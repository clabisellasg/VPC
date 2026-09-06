import 'dart:convert';

import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'court_queue_codec.dart';
import 'drift_court_queue_repository.dart';
import 'supabase_court_queue_repository.dart';

final class CourtQueueSynchronizer {
  CourtQueueSynchronizer({required this.local, required this.remote});
  final DriftCourtQueueRepository local;
  final SupabaseCourtQueueRepository remote;
  Future<void>? _active;
  bool _rerunRequested = false, _disposed = false;
  void dispose() => _disposed = true;

  Future<void> synchronize() {
    if (_disposed) return Future.value();
    final active = _active;
    if (active != null) {
      _rerunRequested = true;
      return active;
    }
    final operation = _drain();
    _active = operation;
    return operation.whenComplete(() => _active = null);
  }

  Future<void> _drain() async {
    do {
      _rerunRequested = false;
      await _synchronizeOnce();
    } while (_rerunRequested && !_disposed);
  }

  Future<void> _synchronizeOnce() async {
    if (_disposed) return;
    final pending = await local.rows(
      "SELECT * FROM court_queue_outbox WHERE status IN ('pending','blocked','failed') ORDER BY created_at,id LIMIT 50",
    );
    for (final row in pending) {
      if (_disposed) return;
      final earlierTournament = await local.rows(
        '''
SELECT 1 FROM event_divisions d WHERE d.event_id=? AND (
  EXISTS(SELECT 1 FROM single_elimination_outbox o WHERE o.division_id=d.id AND o.status<>'accepted' AND o.created_at<?) OR
  EXISTS(SELECT 1 FROM round_robin_outbox o WHERE o.division_id=d.id AND o.status<>'accepted' AND o.created_at<?) OR
  EXISTS(SELECT 1 FROM double_elimination_outbox o WHERE o.division_id=d.id AND o.status<>'accepted' AND o.created_at<?)
) LIMIT 1
''',
        [
          row['event_id'],
          row['created_at'],
          row['created_at'],
          row['created_at'],
        ],
      );
      if (earlierTournament.isNotEmpty) return;
      final command = decodeCourtCommand(
        jsonDecode(row['payload_json'] as String),
      );
      final result = command.action == 'start'
          ? await remote.start(command)
          : await remote.reconcile(command);
      if (result case RepositoryFailure(:final failure)) {
        final status = failure is UnauthorizedFailure
            ? 'blocked'
            : failure is ConflictFailure
            ? 'conflicted'
            : 'failed';
        await local.database.customStatement(
          'UPDATE court_queue_outbox SET status=?,failure=? WHERE id=?',
          [status, failure.message, row['id']],
        );
      } else {
        await local.database.customStatement(
          "UPDATE court_queue_outbox SET status='accepted',failure=NULL WHERE id=?",
          [row['id']],
        );
      }
    }
    // Queue entry pull is bounded by the event scopes present locally. Match
    // snapshots continue to converge through their format synchronizers.
    final events = await local.rows(
      'SELECT DISTINCT event_id FROM court_queue_entries UNION SELECT DISTINCT event_id FROM court_queue_outbox',
    );
    for (final row in events) {
      if (_disposed) return;
      final eventId = EventId(row['event_id'] as String);
      final remoteResult = await remote.load(eventId);
      if (remoteResult case RepositorySuccess(:final value)) {
        final protected = await local.rows(
          "SELECT id FROM court_queue_outbox WHERE event_id=? AND status<>'accepted' LIMIT 1",
          [eventId.value],
        );
        if (protected.isNotEmpty) continue;
        final protectedTournament = await local.rows(
          '''
SELECT 1 FROM event_divisions d WHERE d.event_id=? AND (
  EXISTS(SELECT 1 FROM single_elimination_outbox o WHERE o.division_id=d.id AND o.status<>'accepted') OR
  EXISTS(SELECT 1 FROM round_robin_outbox o WHERE o.division_id=d.id AND o.status<>'accepted') OR
  EXISTS(SELECT 1 FROM double_elimination_outbox o WHERE o.division_id=d.id AND o.status<>'accepted')
) LIMIT 1
''',
          [eventId.value],
        );
        final synchronizedAt = DateTime.now().toUtc();
        await local.database.transaction(() async {
          final current = value.current;
          if (current != null && protectedTournament.isEmpty) {
            await local.database.customStatement(
              "UPDATE matches SET status='inProgress',updated_at=?,version=? WHERE id=? AND version<=? AND deleted_at IS NULL",
              [
                current.match.metadata.updatedAt.toIso8601String(),
                current.match.metadata.recordVersion,
                current.match.id.value,
                current.match.metadata.recordVersion,
              ],
            );
          }
          await local.tombstoneEntriesForAuthoritativeReplace(
            eventId,
            synchronizedAt,
          );
          final authoritativeEntries = [
            if (value.currentEntry != null) value.currentEntry!,
            ...value.queue.map((queued) => queued.entry),
          ];
          for (final e in authoritativeEntries) {
            await local.database.customStatement(
              'INSERT INTO court_queue_entries(id,event_id,division_id,match_id,queue_position,created_at,updated_at,version,deleted_at) VALUES(?,?,?,?,?,?,?,?,NULL) ON CONFLICT(id) DO UPDATE SET queue_position=excluded.queue_position,updated_at=excluded.updated_at,version=excluded.version,deleted_at=NULL',
              [
                e.id.value,
                e.eventId.value,
                e.divisionId?.value,
                e.matchId.value,
                e.queuePosition,
                e.metadata.createdAt.toIso8601String(),
                e.metadata.updatedAt.toIso8601String(),
                e.metadata.recordVersion,
              ],
            );
          }
          if (authoritativeEntries.isNotEmpty) {
            await local.database.customStatement(
              'INSERT INTO court_queue_checkpoints(scope,updated_at,queue_entry_id) VALUES(?,?,?) ON CONFLICT(scope) DO UPDATE SET updated_at=excluded.updated_at,queue_entry_id=excluded.queue_entry_id',
              [
                eventId.value,
                DateTime.now().toUtc().toIso8601String(),
                authoritativeEntries.last.id.value,
              ],
            );
          }
        });
      }
    }
  }
}
