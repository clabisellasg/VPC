import 'dart:convert';

import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'double_elimination_codec.dart';
import 'drift_double_elimination_repository.dart';
import 'supabase_double_elimination_repository.dart';

final class DoubleEliminationSynchronizer {
  DoubleEliminationSynchronizer({required this.local, required this.remote});
  final DriftDoubleEliminationRepository local;
  final SupabaseDoubleEliminationRepository remote;
  bool _running = false, _disposed = false;
  void dispose() => _disposed = true;

  Future<void> synchronize() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      final pending = await local.rows(
        "SELECT * FROM double_elimination_outbox WHERE status IN ('pending','blocked','failed') ORDER BY created_at,id LIMIT 50",
      );
      final blocked = <String>{};
      for (final row in pending) {
        if (_disposed) return;
        final division = row['division_id'] as String;
        if (blocked.contains(division)) continue;
        final history = await local.rows(
          'SELECT payload_json FROM double_elimination_outbox WHERE division_id=? ORDER BY created_at,id',
          [division],
        );
        String? reservedResetMatchId;
        for (final prior in history) {
          final payload = jsonDecode(prior['payload_json'] as String);
          if (payload is Map && payload['action'] == 'generate') {
            final matchIds = payload['match_ids'];
            final reserved = matchIds is Map ? matchIds['de/finals/gf2'] : null;
            if (reserved is String) {
              reservedResetMatchId = reserved;
              break;
            }
          }
        }
        final rawCommand = Map<String, Object?>.from(
          jsonDecode(row['payload_json'] as String) as Map,
        );
        if (reservedResetMatchId != null && rawCommand['proposed'] != null) {
          rawCommand['proposed'] = normalizeDoubleBracketResetIdentity(
            rawCommand['proposed'],
            reservedResetMatchId,
          );
        }
        var command = decodeDoubleCommand(rawCommand);
        if (reservedResetMatchId != null) {
          command = command.withReservedResetMatchId(
            MatchId(reservedResetMatchId),
          );
        }
        final result = await remote.apply(command);
        if (result case RepositoryFailure(:final failure)) {
          blocked.add(division);
          final status = failure is UnauthorizedFailure
              ? 'blocked'
              : failure is ConflictFailure
              ? 'conflicted'
              : 'failed';
          await local.write(
            'UPDATE double_elimination_outbox SET status=?,failure=? WHERE id=?',
            [status, failure.message, row['id']],
          );
        } else {
          await local.write(
            "UPDATE double_elimination_outbox SET status='accepted',failure=NULL WHERE id=?",
            [row['id']],
          );
        }
      }
      if (!_disposed) await pull();
    } finally {
      _running = false;
    }
  }

  Future<void> pull() async {
    for (var page = 0; page < 20 && !_disposed; page++) {
      final checkpoints = await local.rows(
        "SELECT * FROM double_elimination_checkpoints WHERE scope='organizer'",
      );
      final cursor = checkpoints.isEmpty ? null : checkpoints.single;
      final response = await remote.client
          .rpc<Object?>(
            'pull_double_elimination_changes',
            params: {
              'p_after_updated_at': cursor?['updated_at'],
              'p_after_id': cursor?['bracket_id'],
              'p_limit': 50,
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response is! List || response.length > 50) {
        throw const ValidationFailure(
          field: 'doubleEliminationData',
          message: 'Bracket data could not be validated safely.',
        );
      }
      if (response.isEmpty) return;
      final pageRows = response
          .cast<Map>()
          .map((row) => Map<String, Object?>.from(row))
          .toList();
      final applied = await local.database.transaction(() async {
        for (final row in pageRows) {
          final division = row['division_id'] as String;
          final protected = await local.rows(
            "SELECT id FROM double_elimination_outbox WHERE division_id=? AND status<>'accepted' LIMIT 1",
            [division],
          );
          if (protected.isNotEmpty) return false;
          final context = decodeDoubleContext(row['context']);
          if (context.bracket != null) {
            await local.database.importBracketHistory(
              () => local.persist(context.bracket!),
            );
          }
        }
        final last = pageRows.last;
        await local.write(
          "INSERT INTO double_elimination_checkpoints(scope,updated_at,bracket_id) VALUES('organizer',?,?) ON CONFLICT(scope) DO UPDATE SET updated_at=excluded.updated_at,bracket_id=excluded.bracket_id",
          [last['updated_at'], last['id']],
        );
        return true;
      });
      if (!applied || response.length < 50) return;
    }
  }
}
