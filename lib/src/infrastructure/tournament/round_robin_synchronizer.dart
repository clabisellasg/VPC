import 'dart:convert';

import '../../domain/common/domain_failure.dart';
import '../../domain/common/repository_result.dart';
import 'drift_round_robin_repository.dart';
import 'round_robin_codec.dart';
import 'supabase_round_robin_repository.dart';

final class RoundRobinSynchronizer {
  RoundRobinSynchronizer({required this.local, required this.remote});
  final DriftRoundRobinRepository local;
  final SupabaseRoundRobinRepository remote;
  bool _running = false, _disposed = false;
  void dispose() => _disposed = true;
  Future<void> synchronize() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      final pending = await local.rows(
        "SELECT * FROM round_robin_outbox WHERE status IN ('pending','blocked','failed') ORDER BY created_at,id LIMIT 50",
      );
      final blocked = <String>{};
      for (final row in pending) {
        if (_disposed) return;
        final division = row['division_id'] as String;
        if (blocked.contains(division)) continue;
        final command = decodeRoundRobinCommand(
          jsonDecode(row['payload_json'] as String),
        );
        final result = await remote.apply(command);
        if (_disposed) return;
        if (result case RepositoryFailure(:final failure)) {
          blocked.add(division);
          final status = failure is UnauthorizedFailure
              ? 'blocked'
              : failure is ConflictFailure
              ? 'conflicted'
              : 'failed';
          await local.write(
            'UPDATE round_robin_outbox SET status=?,failure=? WHERE id=?',
            [status, failure.message, row['id']],
          );
          continue;
        }
        await local.write(
          "UPDATE round_robin_outbox SET status='accepted',failure=NULL WHERE id=?",
          [row['id']],
        );
      }
      if (!_disposed) await pull();
    } finally {
      _running = false;
    }
  }

  Future<void> pull() async {
    for (var page = 0; page < 20 && !_disposed; page++) {
      final cp = await local.rows(
            "SELECT * FROM round_robin_checkpoints WHERE scope='organizer'",
          ),
          cursor = cp.isEmpty ? null : cp.single;
      final response = await remote.client
          .rpc<Object?>(
            'pull_round_robin_changes',
            params: {
              'p_after_updated_at': cursor?['updated_at'],
              'p_after_id': cursor?['tournament_id'],
              'p_limit': 50,
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response is! List || response.length > 50) {
        throw const ValidationFailure(
          field: 'roundRobinData',
          message: 'Tournament data could not be validated safely.',
        );
      }
      if (response.isEmpty) return;
      final pageRows = response
          .cast<Map>()
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      var stamp = cursor?['updated_at'] as String?,
          id = cursor?['tournament_id'] as String?;
      final applied = await local.database.transaction(() async {
        for (final row in pageRows) {
          final division = row['division_id'] as String;
          final protected = await local.rows(
            "SELECT id FROM round_robin_outbox WHERE division_id=? AND status<>'accepted' LIMIT 1",
            [division],
          );
          if (protected.isNotEmpty) return false;
          final context = decodeRoundRobinContext(row['context']);
          if (context.tournament != null) {
            await local.database.importBracketHistory(
              () => local.persist(context.tournament!),
            );
          }
          stamp = row['updated_at'] as String;
          id = row['id'] as String;
        }
        await local.write(
          "INSERT INTO round_robin_checkpoints(scope,updated_at,tournament_id) VALUES('organizer',?,?) ON CONFLICT(scope) DO UPDATE SET updated_at=excluded.updated_at,tournament_id=excluded.tournament_id",
          [stamp, id],
        );
        return true;
      });
      if (!applied || response.length < 50) return;
    }
  }
}
