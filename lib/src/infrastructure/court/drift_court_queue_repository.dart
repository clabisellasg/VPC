import 'dart:convert';

import 'package:drift/drift.dart';

import '../../application/court/court_queue_service.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/court/court_queue_entry.dart';
import '../../domain/matches/match.dart';
import '../persistence/local/app_database.dart';
import '../persistence/local/sqlite_failure_mapper.dart';
import 'court_queue_codec.dart';

final class DriftCourtQueueRepository implements CourtQueueRepository {
  const DriftCourtQueueRepository(this.database);
  final AppDatabase database;

  Future<List<Map<String, Object?>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) async =>
      (await database
              .customSelect(
                sql,
                variables: [for (final value in args) Variable(value)],
              )
              .get())
          .map((row) => row.data)
          .toList();

  Future<void> tombstoneEntriesForAuthoritativeReplace(
    EventId eventId,
    DateTime synchronizedAt,
  ) async {
    final stamp = synchronizedAt.toUtc().toIso8601String();
    await database.customStatement(
      '''
UPDATE court_queue_entries
SET deleted_at=CASE WHEN created_at>? THEN created_at ELSE ? END,
    updated_at=CASE WHEN created_at>? THEN created_at ELSE ? END,
    version=version+1
WHERE event_id=? AND deleted_at IS NULL
''',
      [stamp, stamp, stamp, stamp, eventId.value],
    );
  }

  @override
  Future<RepositoryResult<CourtQueueSnapshot>> load(EventId eventId) async {
    try {
      final event = await rows(
        'SELECT id,name FROM events WHERE id=? AND deleted_at IS NULL',
        [eventId.value],
      );
      if (event.isEmpty) {
        return RepositoryFailure(
          NotFoundFailure(entity: 'Event', identifier: eventId.value),
        );
      }
      final matchRows = await rows(
        '''
SELECT m.*,d.event_id,d.name AS division_name,d.tournament_format,
       COALESCE(t1.display_label,
         (SELECT group_concat(member_name,' / ') FROM (
           SELECT p.display_name AS member_name
           FROM team_members tm JOIN players p ON p.id=tm.player_id
           WHERE tm.team_id=t1.id AND tm.deleted_at IS NULL AND p.deleted_at IS NULL
           ORDER BY tm.player_id
         )),
         'TBD') AS side_one_label,
       COALESCE(t2.display_label,
         (SELECT group_concat(member_name,' / ') FROM (
           SELECT p.display_name AS member_name
           FROM team_members tm JOIN players p ON p.id=tm.player_id
           WHERE tm.team_id=t2.id AND tm.deleted_at IS NULL AND p.deleted_at IS NULL
           ORDER BY tm.player_id
         )),
         'TBD') AS side_two_label
FROM matches m JOIN event_divisions d ON d.id=m.division_id
JOIN events e ON e.id=d.event_id AND e.status='inProgress' AND e.deleted_at IS NULL
LEFT JOIN teams t1 ON t1.id=m.side_one_team_id
LEFT JOIN teams t2 ON t2.id=m.side_two_team_id
WHERE d.event_id=? AND d.deleted_at IS NULL AND m.deleted_at IS NULL
  AND d.tournament_format IS NOT NULL
ORDER BY m.updated_at,m.division_id,COALESCE(m.round_number,0),COALESCE(m.sequence_number,0),m.id
''',
        [eventId.value],
      );
      final views = <String, CourtMatchView>{};
      for (final row in matchRows) {
        final view = _view(eventId, row);
        views[view.match.id.value] = view;
      }
      await _normalizeQueueOrder(eventId);
      final queueRows = await rows(
        'SELECT * FROM court_queue_entries WHERE event_id=? AND deleted_at IS NULL ORDER BY queue_position,id',
        [eventId.value],
      );
      final historyIds = (await rows(
        'SELECT DISTINCT match_id FROM court_queue_entries WHERE event_id=?',
        [eventId.value],
      )).map((row) => row['match_id']).toSet();
      final queue = <QueuedCourtMatch>[];
      for (final row in queueRows) {
        final view = views[row['match_id']];
        if (view == null ||
            (!view.isReady && view.match.status != MatchStatus.inProgress)) {
          continue;
        }
        queue.add(QueuedCourtMatch(entry: _entry(row), match: view));
      }
      final queuedIds = queue.map((row) => row.match.match.id.value).toSet();
      final pending = await rows(
        "SELECT status FROM court_queue_outbox WHERE event_id=? AND status<>'accepted' ORDER BY CASE status WHEN 'conflicted' THEN 0 WHEN 'blocked' THEN 1 WHEN 'failed' THEN 2 ELSE 3 END LIMIT 1",
        [eventId.value],
      );
      final currentMatches = views.values
          .where((view) => view.match.status == MatchStatus.inProgress)
          .toList();
      if (currentMatches.length > 1) {
        throw const ConflictFailure(
          message: 'More than one match is marked Now Playing. Refresh and reconcile before operating the court.',
        );
      }
      if (currentMatches case [final current]) {
        await _markSnapshotMatchStarted(
          matchId: current.match.id.value,
          divisionId: current.match.divisionId.value,
          tournamentFormat: current.format.name,
          updatedAt: current.match.metadata.updatedAt,
          version: current.match.metadata.recordVersion,
        );
      }
      return RepositorySuccess(
        CourtQueueSnapshot(
          eventId: eventId,
          eventName: event.single['name'] as String,
          current: currentMatches.firstOrNull,
          currentEntry: currentMatches.isEmpty
              ? null
              : queue
                    .where(
                      (row) =>
                          row.match.match.id == currentMatches.single.match.id,
                    )
                    .firstOrNull
                    ?.entry,
          queue: queue.where(
            (row) => row.match.match.status == MatchStatus.queued,
          ),
          unqueuedReady: views.values
              .where(
                (view) =>
                    view.isReady && !queuedIds.contains(view.match.id.value),
              )
              .toList(),
          completedHistory: views.values
              .where(
                (view) =>
                    view.match.status == MatchStatus.completed &&
                    historyIds.contains(view.match.id.value),
              )
              .toList(),
          hasIneligibleEntries: queueRows.length != queue.length,
          disposition: pending.isEmpty
              ? CourtQueueDisposition.synchronized
              : _disposition(pending.single['status'] as String),
        ),
      );
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } on Exception catch (error) {
      final failure = mapExpectedSqliteFailure(
        error,
        operation: 'Court queue read',
      );
      if (failure == null) rethrow;
      return RepositoryFailure(failure);
    }
  }

  @override
  Future<RepositoryResult<CourtQueueSnapshot>> reconcile(
    CourtQueueCommand command,
  ) => _apply(command, start: false);

  @override
  Future<RepositoryResult<CourtQueueSnapshot>> start(
    CourtQueueCommand command,
  ) => _apply(command, start: true);

  Future<RepositoryResult<CourtQueueSnapshot>> _apply(
    CourtQueueCommand command, {
    required bool start,
  }) async {
    try {
      await database.transaction(() async {
        final prior = await rows(
          'SELECT payload_json FROM court_queue_outbox WHERE id=?',
          [command.operationId.value],
        );
        final payload = encodeCourtCommand(command);
        if (prior.isNotEmpty) {
          if (prior.single['payload_json'] != payload) {
            throw const ConflictFailure(
              message: 'Operation identity was reused with changed data.',
            );
          }
          return;
        }
        final current = await rows(
          "SELECT m.id FROM matches m JOIN event_divisions d ON d.id=m.division_id WHERE d.event_id=? AND m.status='inProgress' AND m.deleted_at IS NULL",
          [command.eventId.value],
        );
        if (start) {
          if (current.isNotEmpty) {
            throw const ConflictFailure(
              message: 'Another match is already Now Playing.',
            );
          }
          final matchId = command.matchId;
          if (matchId == null) {
            throw const ValidationFailure(
              field: 'match',
              message: 'A queued match is required.',
            );
          }
          final selected = await rows(
            "SELECT m.version,m.division_id,d.tournament_format FROM matches m JOIN event_divisions d ON d.id=m.division_id JOIN events e ON e.id=d.event_id JOIN court_queue_entries q ON q.match_id=m.id AND q.deleted_at IS NULL WHERE m.id=? AND d.event_id=? AND e.status='inProgress' AND e.deleted_at IS NULL AND m.status='queued' AND m.deleted_at IS NULL",
            [matchId.value, command.eventId.value],
          );
          if (selected.length != 1 ||
              selected.single['version'] != command.expectedMatchVersion) {
            throw const ConflictFailure(
              message: 'The queued match changed. Refresh and retry.',
            );
          }
          await database.customStatement(
            "UPDATE matches SET status='inProgress',updated_at=?,version=version+1 WHERE id=?",
            [command.createdAt.toIso8601String(), matchId.value],
          );
          await _markSnapshotMatchStarted(
            matchId: matchId.value,
            divisionId: selected.single['division_id'] as String,
            tournamentFormat: selected.single['tournament_format'] as String,
            updatedAt: command.createdAt,
            version: (selected.single['version'] as int) + 1,
          );
        } else {
          await database.customStatement(
            '''
UPDATE court_queue_entries SET deleted_at=?,updated_at=?,version=version+1
WHERE event_id=? AND deleted_at IS NULL AND (
  NOT EXISTS(SELECT 1 FROM events e WHERE e.id=? AND e.status='inProgress' AND e.deleted_at IS NULL)
  OR match_id IN (
  SELECT q.match_id FROM court_queue_entries q JOIN matches m ON m.id=q.match_id
  WHERE q.event_id=? AND (m.deleted_at IS NOT NULL OR m.status NOT IN ('queued','inProgress'))
))
''',
            [
              command.createdAt.toIso8601String(),
              command.createdAt.toIso8601String(),
              command.eventId.value,
              command.eventId.value,
              command.eventId.value,
            ],
          );
          final existing = await rows(
            'SELECT match_id,queue_position FROM court_queue_entries WHERE event_id=? AND deleted_at IS NULL',
            [command.eventId.value],
          );
          final existingIds = existing.map((row) => row['match_id']).toSet();
          var position =
              existing.fold<int>(
                -1,
                (value, row) => (row['queue_position'] as int) > value
                    ? row['queue_position'] as int
                    : value,
              ) +
              1;
          final ready = await rows(
            "SELECT m.id FROM matches m JOIN event_divisions d ON d.id=m.division_id JOIN events e ON e.id=d.event_id WHERE d.event_id=? AND e.status='inProgress' AND e.deleted_at IS NULL AND m.status='queued' AND m.deleted_at IS NULL AND m.side_one_team_id IS NOT NULL AND m.side_two_team_id IS NOT NULL ORDER BY d.id,COALESCE(m.round_number,0),COALESCE(m.sequence_number,0),m.id",
            [command.eventId.value],
          );
          for (final row in ready) {
            final id = MatchId(row['id'] as String);
            if (existingIds.contains(id.value)) continue;
            final entryId = command.entryIds[id];
            if (entryId == null) {
              throw const ConflictFailure(
                message: 'Queue candidates changed. Refresh and retry.',
              );
            }
            final division = await rows(
              'SELECT division_id FROM matches WHERE id=?',
              [id.value],
            );
            await database.customStatement(
              'INSERT INTO court_queue_entries(id,event_id,division_id,match_id,queue_position,created_at,updated_at,version,deleted_at) VALUES(?,?,?,?,?,?,?,0,NULL)',
              [
                entryId.value,
                command.eventId.value,
                division.single['division_id'],
                id.value,
                position++,
                command.createdAt.toIso8601String(),
                command.createdAt.toIso8601String(),
              ],
            );
          }
        }
        await database.customStatement(
          "INSERT INTO court_queue_outbox(id,event_id,payload_json,status,created_at) VALUES(?,?,?,'pending',?)",
          [
            command.operationId.value,
            command.eventId.value,
            payload,
            command.createdAt.toIso8601String(),
          ],
        );
      });
      return await load(command.eventId);
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } on Exception catch (error) {
      final failure = mapExpectedSqliteFailure(
        error,
        operation: 'Court queue mutation',
      );
      if (failure == null) rethrow;
      return RepositoryFailure(failure);
    }
  }

  Future<void> _normalizeQueueOrder(EventId eventId) async {
    final active = await rows(
      '''
SELECT q.id FROM court_queue_entries q
JOIN matches m ON m.id=q.match_id
JOIN event_divisions d ON d.id=m.division_id
WHERE q.event_id=? AND q.deleted_at IS NULL
ORDER BY q.created_at,d.id,COALESCE(m.round_number,0),COALESCE(m.sequence_number,0),m.id
''',
      [eventId.value],
    );
    if (active.length < 2) return;
    await database.transaction(() async {
      for (var index = 0; index < active.length; index++) {
        await database.customStatement(
          'UPDATE court_queue_entries SET queue_position=? WHERE id=?',
          [100000000 + index, active[index]['id']],
        );
      }
      for (var index = 0; index < active.length; index++) {
        await database.customStatement(
          'UPDATE court_queue_entries SET queue_position=? WHERE id=?',
          [index, active[index]['id']],
        );
      }
    });
  }

  Future<void> _markSnapshotMatchStarted({
    required String matchId,
    required String divisionId,
    required String tournamentFormat,
    required DateTime updatedAt,
    required int version,
  }) async {
    final (table, column) = switch (tournamentFormat) {
      'singleElimination' => ('single_elimination_snapshots', 'bracket_json'),
      'doubleElimination' => ('double_elimination_snapshots', 'bracket_json'),
      'singleRoundRobin' ||
      'doubleRoundRobin' => ('round_robin_snapshots', 'tournament_json'),
      _ => throw const ValidationFailure(
        field: 'format',
        message: 'The queued match has an unsupported tournament format.',
      ),
    };
    final snapshots = await rows(
      'SELECT $column AS snapshot_json FROM $table WHERE division_id=?',
      [divisionId],
    );
    if (snapshots.isEmpty) return;
    if (snapshots.length != 1) {
      throw const ConflictFailure(
        message: 'The tournament view is unavailable. Refresh before starting.',
      );
    }
    final snapshot = jsonDecode(snapshots.single['snapshot_json'] as String);
    if (snapshot is! Map<String, dynamic> || snapshot['matches'] is! List) {
      throw const ValidationFailure(
        field: 'tournament',
        message: 'Stored tournament data is invalid.',
      );
    }
    var found = false;
    var changed = false;
    for (final value in snapshot['matches'] as List) {
      if (value is Map && value['id'] == matchId) {
        if (value['status'] != MatchStatus.inProgress.name ||
            value['updated_at'] != updatedAt.toIso8601String() ||
            value['version'] != version) {
          value['status'] = MatchStatus.inProgress.name;
          value['updated_at'] = updatedAt.toIso8601String();
          value['version'] = version;
          changed = true;
        }
        found = true;
      }
    }
    if (!found) {
      throw const ConflictFailure(
        message: 'The tournament match changed. Refresh before starting.',
      );
    }
    if (changed) {
      await database.customStatement(
        'UPDATE $table SET $column=? WHERE division_id=?',
        [jsonEncode(snapshot), divisionId],
      );
    }
  }

  CourtMatchView _view(EventId eventId, Map<String, Object?> row) =>
      CourtMatchView(
        eventId: eventId,
        match: Match(
          id: MatchId(row['id'] as String),
          divisionId: DivisionId(row['division_id'] as String),
          status: MatchStatus.values.byName(row['status'] as String),
          metadata: _metadata(row),
          sideOneTeamId: row['side_one_team_id'] == null
              ? null
              : TeamId(row['side_one_team_id'] as String),
          sideTwoTeamId: row['side_two_team_id'] == null
              ? null
              : TeamId(row['side_two_team_id'] as String),
          sideOneScore: row['side_one_score'] as int?,
          sideTwoScore: row['side_two_score'] as int?,
          winnerTeamId: row['winner_team_id'] == null
              ? null
              : TeamId(row['winner_team_id'] as String),
          roundNumber: row['round_number'] as int?,
          sequenceNumber: row['sequence_number'] as int?,
        ),
        format: TournamentFormat.values.byName(
          row['tournament_format'] as String,
        ),
        divisionName: row['division_name'] as String,
        sideOneLabel: row['side_one_label'] as String,
        sideTwoLabel: row['side_two_label'] as String,
      );

  CourtQueueEntry _entry(Map<String, Object?> row) => CourtQueueEntry(
    id: CourtQueueEntryId(row['id'] as String),
    eventId: EventId(row['event_id'] as String),
    divisionId: row['division_id'] == null
        ? null
        : DivisionId(row['division_id'] as String),
    matchId: MatchId(row['match_id'] as String),
    queuePosition: row['queue_position'] as int,
    metadata: _metadata(row),
  );

  RecordMetadata _metadata(Map<String, Object?> row) => RecordMetadata(
    createdAt: _time(row['created_at']),
    updatedAt: _time(row['updated_at']),
    recordVersion: row['version'] as int,
    deletedAt: row['deleted_at'] == null ? null : _time(row['deleted_at']),
  );

  DateTime _time(Object? value) => switch (value) {
    DateTime value => value.toUtc(),
    String value => DateTime.parse(value).toUtc(),
    int value => DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true),
    _ => throw const FormatException('Invalid stored UTC timestamp.'),
  };
}

CourtQueueDisposition _disposition(String value) => switch (value) {
  'pending' => CourtQueueDisposition.pending,
  'blocked' => CourtQueueDisposition.blocked,
  'failed' => CourtQueueDisposition.failed,
  'conflicted' => CourtQueueDisposition.conflicted,
  _ => CourtQueueDisposition.synchronized,
};
