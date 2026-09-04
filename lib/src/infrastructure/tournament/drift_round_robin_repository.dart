import 'dart:convert';

import 'package:drift/drift.dart';

import '../../application/tournament/round_robin_service.dart';
import '../../application/tournament/single_elimination_service.dart'
    show BracketDisposition;
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/tournament/round_robin_tournament.dart';
import '../persistence/local/app_database.dart';
import '../persistence/local/sqlite_failure_mapper.dart';
import 'bracket_codec.dart' show enumValue, matchJson;
import 'round_robin_codec.dart';

final class DriftRoundRobinRepository implements RoundRobinRepository {
  const DriftRoundRobinRepository(this.database);
  final AppDatabase database;
  Future<List<Map<String, Object?>>> rows(
    String sql, [
    List<Object> args = const [],
  ]) async =>
      (await database
              .customSelect(sql, variables: [for (final a in args) Variable(a)])
              .get())
          .map((r) => r.data)
          .toList();
  Future<void> write(String sql, [List<Object?> args = const []]) =>
      database.customStatement(sql, args);
  @override
  Future<RepositoryResult<RoundRobinContext>> load(
    EventId eventId,
    DivisionId divisionId,
  ) async {
    try {
      final events = await rows(
        'SELECT * FROM events WHERE id=? AND deleted_at IS NULL',
        [eventId.value],
      );
      final divisions = await rows(
        'SELECT * FROM event_divisions WHERE id=? AND event_id=? AND deleted_at IS NULL',
        [divisionId.value, eventId.value],
      );
      if (events.isEmpty || divisions.isEmpty) {
        return RepositoryFailure(
          NotFoundFailure(entity: 'Division', identifier: divisionId.value),
        );
      }
      final rawTeams = await rows(
            'SELECT * FROM teams WHERE division_id=? AND deleted_at IS NULL ORDER BY id',
            [divisionId.value],
          ),
          teams = <Map<String, Object?>>[];
      for (final t in rawTeams) {
        final members = await rows(
          'SELECT tm.*,p.display_name FROM team_members tm JOIN players p ON p.id=tm.player_id WHERE tm.team_id=? AND tm.deleted_at IS NULL ORDER BY tm.player_id',
          [t['id'] as String],
        );
        teams.add({
          ...t,
          'members': members,
          'label':
              t['display_label'] ??
              members.map((m) => m['display_name']).join(' / '),
        });
      }
      final stored = await rows(
        'SELECT tournament_json FROM round_robin_snapshots WHERE division_id=?',
        [divisionId.value],
      );
      final decoded = decodeRoundRobinContext({
        'event': events.single,
        'division': divisions.single,
        'teams': teams,
        'tournament': stored.isEmpty
            ? null
            : jsonDecode(stored.single['tournament_json'] as String),
      });
      final pending = await rows(
        "SELECT status FROM round_robin_outbox WHERE division_id=? AND status<>'accepted' ORDER BY CASE status WHEN 'conflicted' THEN 0 WHEN 'blocked' THEN 1 WHEN 'failed' THEN 2 ELSE 3 END LIMIT 1",
        [divisionId.value],
      );
      final conflict = await rows(
        "SELECT id FROM team_formation_outbox_operations WHERE division_id=? AND status='conflicted' LIMIT 1",
        [divisionId.value],
      );
      return RepositorySuccess(
        RoundRobinContext(
          event: decoded.event,
          division: decoded.division,
          teams: decoded.teams,
          teamLabels: decoded.teamLabels,
          tournament: decoded.tournament,
          teamConflict: conflict.isNotEmpty,
          disposition: pending.isEmpty
              ? BracketDisposition.synchronized
              : enumValue(
                  BracketDisposition.values,
                  pending.single['status'] as String,
                ),
        ),
      );
    } on DomainFailure catch (f) {
      return RepositoryFailure(f);
    }
  }

  @override
  Future<RepositoryResult<RoundRobinContext>> apply(
    RoundRobinCommand command,
  ) async {
    try {
      return await database.transaction(() async {
        final json = jsonEncode(roundRobinCommandJson(command));
        final old = await rows(
          'SELECT payload_json FROM round_robin_outbox WHERE id=?',
          [command.operationId.value],
        );
        if (old.isNotEmpty) {
          if (old.single['payload_json'] != json) {
            throw const ConflictFailure(
              message: 'Operation identity was reused with changed content.',
            );
          }
          return load(command.eventId, command.divisionId);
        }
        final context = (await load(
          command.eventId,
          command.divisionId,
        )).when(success: (v) => v, failure: (f) => throw f);
        if (context.disposition == BracketDisposition.blocked ||
            context.disposition == BracketDisposition.conflicted) {
          throw const ConflictFailure(
            message: 'Resolve blocked or conflicted schedule work first.',
          );
        }
        if (command.action == RoundRobinAction.generate &&
            context.tournament == null &&
            (await rows(
              'SELECT id FROM matches WHERE division_id=? AND deleted_at IS NULL LIMIT 1',
              [command.divisionId.value],
            )).isNotEmpty) {
          throw const ConflictFailure(
            message: 'Another active tournament structure already exists for this division.',
          );
        }
        final next = applyRoundRobinCommand(context, command);
        await persist(next, command: command);
        await write(
          'INSERT INTO round_robin_outbox(id,division_id,payload_json,status,created_at) VALUES(?,?,?,?,?)',
          [
            command.operationId.value,
            command.divisionId.value,
            json,
            'pending',
            command.createdAt.toIso8601String(),
          ],
        );
        return load(command.eventId, command.divisionId);
      });
    } on DomainFailure catch (f) {
      return RepositoryFailure(f);
    } catch (error, stack) {
      final f = mapExpectedSqliteFailure(
        error,
        operation: 'Round-robin operation',
      );
      if (f != null) return RepositoryFailure(f);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> persist(
    RoundRobinTournament tournament, {
    RoundRobinCommand? command,
  }) async {
    final division = tournament.plan.divisionId.value,
        stamp = tournament.metadata.updatedAt.toIso8601String();
    for (final revision in tournament.revisions) {
      final existing = await rows(
        'SELECT operation_id FROM match_result_revisions WHERE operation_id=?',
        [revision.operationId.value],
      );
      if (existing.isEmpty) {
        await write(
          'INSERT INTO match_result_revisions(operation_id,match_id,previous_result,reason,recorded_at) VALUES(?,?,?,?,?)',
          [
            revision.operationId.value,
            revision.previous.id.value,
            jsonEncode(matchJson(revision.previous)),
            revision.reason,
            revision.recordedAt.toIso8601String(),
          ],
        );
      }
    }
    final ids = tournament.matches.values.map((m) => m.id.value).toList();
    final prior = await rows(
      'SELECT id FROM matches WHERE division_id=? AND deleted_at IS NULL',
      [division],
    );
    for (final row in prior) {
      if (!ids.contains(row['id'])) {
        await write(
          'UPDATE matches SET deleted_at=?,updated_at=?,version=version+1 WHERE id=?',
          [stamp, stamp, row['id']],
        );
      }
    }
    for (final m in tournament.matches.values) {
      final j = matchJson(m);
      await write(
        '''INSERT INTO matches(id,division_id,side_one_team_id,side_two_team_id,status,side_one_score,side_two_score,winner_team_id,round_number,sequence_number,created_at,updated_at,version,deleted_at)
VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET side_one_team_id=excluded.side_one_team_id,side_two_team_id=excluded.side_two_team_id,status=excluded.status,side_one_score=excluded.side_one_score,side_two_score=excluded.side_two_score,winner_team_id=excluded.winner_team_id,updated_at=excluded.updated_at,version=excluded.version,deleted_at=excluded.deleted_at''',
        [
          for (final k in [
            'id',
            'division_id',
            'side_one_team_id',
            'side_two_team_id',
            'status',
            'side_one_score',
            'side_two_score',
            'winner_team_id',
            'round_number',
            'sequence_number',
            'created_at',
            'updated_at',
            'version',
            'deleted_at',
          ])
            j[k],
        ],
      );
    }
    if (tournament.complete &&
        command != null &&
        (command.action == RoundRobinAction.result ||
            command.action == RoundRobinAction.correct)) {
      final standings = tournament.standings;
      if (command.placementIds.length != standings.length) {
        throw const ValidationFailure(
          field: 'placements',
          message: 'Every final standing requires an identity.',
        );
      }
      await write(
        'UPDATE division_placements SET deleted_at=?,updated_at=?,version=version+1 WHERE division_id=? AND deleted_at IS NULL',
        [stamp, stamp, division],
      );
      for (final row in standings) {
        await write(
          'INSERT INTO division_placements(id,division_id,team_id,position,created_at,updated_at,version) VALUES(?,?,?,?,?,?,0)',
          [
            command.placementIds[row.rank]!.value,
            division,
            row.teamId.value,
            row.rank,
            stamp,
            stamp,
          ],
        );
      }
    }
    await write(
      'INSERT INTO round_robin_snapshots(division_id,tournament_json) VALUES(?,?) ON CONFLICT(division_id) DO UPDATE SET tournament_json=excluded.tournament_json',
      [division, jsonEncode(roundRobinJson(tournament))],
    );
  }
}
