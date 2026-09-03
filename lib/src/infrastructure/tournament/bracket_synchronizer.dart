import 'dart:convert';

import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'bracket_codec.dart';
import 'drift_bracket_repository.dart';
import 'supabase_bracket_repository.dart';

final class BracketSynchronizer {
  BracketSynchronizer({required this.local, required this.remote});
  final DriftBracketRepository local;
  final SupabaseBracketRepository remote;
  bool _running = false, _disposed = false;
  void dispose() => _disposed = true;

  Future<void> synchronize() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      final pending = await local.rows(
        "SELECT * FROM single_elimination_outbox WHERE status IN ('pending','blocked','failed') ORDER BY created_at,id LIMIT 50",
      );
      final blocked = <String>{};
      for (final row in pending) {
        if (_disposed) return;
        final division = row['division_id'] as String;
        if (blocked.contains(division)) continue;
        final conflicts = await local.rows(
          "SELECT id FROM single_elimination_outbox WHERE division_id=? AND status='conflicted' LIMIT 1",
          [division],
        );
        if (conflicts.isNotEmpty) continue;
        final command = decodeBracketCommand(
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
            'UPDATE single_elimination_outbox SET status=?,failure=? WHERE id=?',
            [status, failure.message, row['id']],
          );
          continue;
        }
        // Receipt acknowledgement is durable. Pull reconciles authoritative rows;
        // never replace a later locally pending bracket with this earlier receipt.
        await local.write(
          "UPDATE single_elimination_outbox SET status='accepted',failure=NULL WHERE id=?",
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
      final checkpoint = await local.rows(
        "SELECT * FROM single_elimination_checkpoints WHERE scope='organizer'",
      );
      final cursor = checkpoint.isEmpty ? null : checkpoint.single;
      final response = await remote.client
          .rpc<Object?>(
            'pull_single_elimination_changes',
            params: {
              'p_after_updated_at': cursor?['updated_at'],
              'p_after_id': cursor?['bracket_id'],
              'p_limit': 50,
            },
          )
          .timeout(const Duration(seconds: 20));
      if (_disposed) return;
      if (response is! List || response.length > 50) throw invalid();
      if (response.isEmpty) return;
      final pageRows = response.map(object).toList();
      var priorTime = cursor == null ? null : time(cursor, 'updated_at');
      var priorId = cursor?['bracket_id'] as String?;
      for (final row in pageRows) {
        final stamp = time(row, 'updated_at'),
            id = SyncOperationId(text(row, 'id')).value;
        if (priorTime != null &&
            (stamp.isBefore(priorTime) ||
                (stamp == priorTime && id.compareTo(priorId!) <= 0))) {
          throw invalid();
        }
        priorTime = stamp;
        priorId = id;
        DivisionId(text(row, 'division_id'));
        EventId(text(row, 'event_id'));
      }
      final applied = await local.database.transaction(() async {
        for (final row in pageRows) {
          final protected = await local.rows(
            "SELECT id FROM single_elimination_outbox WHERE division_id=? AND status<>'accepted' LIMIT 1",
            [text(row, 'division_id')],
          );
          if (protected.isNotEmpty) return false;
        }
        await local.database.importBracketHistory(() async {
          for (final row in pageRows) {
            final division = DivisionId(text(row, 'division_id'));
            for (final raw in list(row, 'matches')) {
              final match = decodeMatch(raw);
              if (match.divisionId != division) throw invalid();
              await _upsert('matches', matchJson(match), ['id']);
            }
            final deps = list(row, 'dependencies').map(object).toList()
              ..sort(_tombstonesFirst);
            for (final dep in deps) {
              MatchId(text(dep, 'source_match_id'));
              MatchId(text(dep, 'destination_match_id'));
              if (dep['source_outcome'] != 'winner' ||
                  !['sideOne', 'sideTwo'].contains(dep['destination_slot']) ||
                  dep['source_match_id'] == dep['destination_match_id']) {
                throw invalid();
              }
              await _upsert(
                'match_dependencies',
                {
                  for (final key in [
                    'source_match_id',
                    'source_outcome',
                    'destination_match_id',
                    'destination_slot',
                  ])
                    key: dep[key],
                  ...metadataJson(metadata(dep)),
                },
                [
                  'source_match_id',
                  'source_outcome',
                  'destination_match_id',
                  'destination_slot',
                ],
              );
            }
            final placements = list(row, 'placements').map(object).toList()
              ..sort(_tombstonesFirst);
            for (final p in placements) {
              DivisionPlacementId(text(p, 'id'));
              TeamId(text(p, 'team_id'));
              if (p['division_id'] != division.value ||
                  ![1, 2].contains(integer(p, 'position'))) {
                throw invalid();
              }
              await _upsert(
                'division_placements',
                {
                  for (final key in [
                    'id',
                    'division_id',
                    'team_id',
                    'position',
                  ])
                    key: p[key],
                  ...metadataJson(metadata(p)),
                },
                ['id'],
              );
            }
            if (row['bracket'] != null) {
              final bracket = decodeBracket(row['bracket']);
              if (bracket.plan.divisionId != division ||
                  bracket.plan.eventId.value != row['event_id']) {
                throw invalid();
              }
              await local.persist(bracket);
            }
          }
        });
        await local.write(
          "INSERT INTO single_elimination_checkpoints(scope,updated_at,bracket_id) VALUES('organizer',?,?) ON CONFLICT(scope) DO UPDATE SET updated_at=excluded.updated_at,bracket_id=excluded.bracket_id",
          [priorTime!.toIso8601String(), priorId],
        );
        return true;
      });
      if (!applied || response.length < 50) return;
    }
  }

  int _tombstonesFirst(Map<String, Object?> a, Map<String, Object?> b) =>
      (a['deleted_at'] == null ? 1 : 0).compareTo(
        b['deleted_at'] == null ? 1 : 0,
      );

  /// Table names/columns originate exclusively in the fixed mapping above, never
  /// command data. Bind every value; retain remote versions and UTC metadata.
  Future<void> _upsert(
    String table,
    Map<String, Object?> row,
    List<String> keys,
  ) async {
    final columns = row.keys.toList();
    await local.write(
      'INSERT INTO $table(${columns.join(',')}) VALUES(${columns.map((_) => '?').join(',')}) '
      'ON CONFLICT(${keys.join(',')}) DO UPDATE SET ${columns.where((c) => !keys.contains(c)).map((c) => '$c=excluded.$c').join(',')} '
      'WHERE excluded.version >= $table.version',
      columns.map((c) => row[c]).toList(),
    );
  }
}
