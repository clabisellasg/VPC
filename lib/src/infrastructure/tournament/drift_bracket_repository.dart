import 'dart:convert';

import 'package:drift/drift.dart';

import '../../application/tournament/single_elimination_service.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/tournament/single_elimination_bracket.dart';
import '../../domain/tournament/tournament_contracts.dart';
import '../persistence/local/app_database.dart';
import '../persistence/local/sqlite_failure_mapper.dart';
import 'bracket_codec.dart';

final class DriftBracketRepository implements BracketRepository {
  const DriftBracketRepository(this.database);
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
  Future<RepositoryResult<BracketContext>> load(
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
      final teams = await rows(
        'SELECT * FROM teams WHERE division_id=? AND deleted_at IS NULL ORDER BY id',
        [divisionId.value],
      );
      final enriched = <Map<String, Object?>>[];
      for (final team in teams) {
        final members = await rows(
          'SELECT tm.*,p.display_name FROM team_members tm JOIN players p ON p.id=tm.player_id WHERE tm.team_id=? AND tm.deleted_at IS NULL ORDER BY tm.player_id',
          [team['id'] as String],
        );
        enriched.add({
          ...team,
          'members': members,
          'label':
              team['display_label'] ??
              members.map((m) => m['display_name']).join(' / '),
        });
      }
      final stored = await rows(
        'SELECT bracket_json FROM single_elimination_snapshots WHERE division_id=?',
        [divisionId.value],
      );
      final context = decodeBracketContext({
        'event': events.single,
        'division': divisions.single,
        'teams': enriched,
        'bracket': stored.isEmpty
            ? null
            : jsonDecode(stored.single['bracket_json'] as String),
      });
      final pending = await rows(
        "SELECT status FROM single_elimination_outbox WHERE division_id=? AND status<>'accepted' ORDER BY CASE status WHEN 'conflicted' THEN 0 WHEN 'blocked' THEN 1 WHEN 'failed' THEN 2 ELSE 3 END LIMIT 1",
        [divisionId.value],
      );
      final conflict = await rows(
        "SELECT id FROM team_formation_outbox_operations WHERE division_id=? AND status='conflicted' LIMIT 1",
        [divisionId.value],
      );
      return RepositorySuccess(
        BracketContext(
          event: context.event,
          division: context.division,
          teams: context.teams,
          teamLabels: context.teamLabels,
          bracket: context.bracket,
          teamConflict: conflict.isNotEmpty,
          disposition: pending.isEmpty
              ? BracketDisposition.synchronized
              : enumValue(
                  BracketDisposition.values,
                  pending.single['status'] as String,
                ),
        ),
      );
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }

  @override
  Future<RepositoryResult<BracketContext>> apply(BracketCommand command) async {
    try {
      return await database.transaction(() async {
        final old = await rows(
          'SELECT payload_json FROM single_elimination_outbox WHERE id=?',
          [command.operationId.value],
        );
        if (old.isNotEmpty) {
          if (old.single['payload_json'] != jsonEncode(commandJson(command))) {
            throw const ConflictFailure(
              message: 'Operation identity was reused with a changed command.',
            );
          }
          return load(command.eventId, command.divisionId);
        }
        final context = (await load(
          command.eventId,
          command.divisionId,
        )).when(success: (v) => v, failure: (f) => throw f);
        if (context.disposition == BracketDisposition.conflicted ||
            context.disposition == BracketDisposition.blocked) {
          throw const ConflictFailure(
            message: 'Resolve the existing blocked or conflicted work before changing this bracket.',
          );
        }
        final next = applyBracketCommand(context, command);
        await persist(next, command: command);
        await write(
          'INSERT INTO single_elimination_outbox(id,division_id,payload_json,status,created_at) VALUES(?,?,?,?,?)',
          [
            command.operationId.value,
            command.divisionId.value,
            jsonEncode(commandJson(command)),
            'pending',
            command.createdAt.toIso8601String(),
          ],
        );
        return load(command.eventId, command.divisionId);
      });
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } catch (error, stack) {
      final failure = mapExpectedSqliteFailure(
        error,
        operation: 'Bracket operation',
      );
      if (failure != null) return RepositoryFailure(failure);
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// Caller owns a transaction. Remote reads must never call apply/enqueue.
  Future<void> persist(
    SingleEliminationBracket bracket, {
    BracketCommand? command,
  }) async {
    final stamp = bracket.metadata.updatedAt.toIso8601String(),
        division = bracket.plan.divisionId.value;
    for (final revision in bracket.revisions) {
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
    final ids = bracket.matches.values.map((m) => m.id.value).toList();
    final prior = await rows(
      'SELECT id FROM matches WHERE division_id=? AND deleted_at IS NULL',
      [division],
    );
    for (final row in prior) {
      if (!ids.contains(row['id'])) {
        await write(
          'UPDATE match_dependencies SET deleted_at=?,updated_at=?,version=version+1 WHERE source_match_id=? AND deleted_at IS NULL',
          [stamp, stamp, row['id']],
        );
        await write(
          'UPDATE matches SET deleted_at=?,updated_at=?,version=version+1 WHERE id=?',
          [stamp, stamp, row['id']],
        );
      }
    }
    for (final match in bracket.matches.values) {
      final m = matchJson(match),
          existing = await rows(
            'SELECT status,version FROM matches WHERE id=?',
            [match.id.value],
          );
      if (existing.isNotEmpty) {
        // Authoritative reconciliation can have missed intermediate forward states.
        final old = enumValue(
          MatchStatus.values,
          existing.single['status'] as String,
        );
        for (var step = old.index + 1; step < match.status.index; step++) {
          await write('UPDATE matches SET status=? WHERE id=?', [
            MatchStatus.values[step].name,
            match.id.value,
          ]);
        }
      }
      await write(
        '''INSERT INTO matches(id,division_id,side_one_team_id,side_two_team_id,status,side_one_score,side_two_score,winner_team_id,round_number,sequence_number,created_at,updated_at,version,deleted_at)
VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET side_one_team_id=excluded.side_one_team_id,side_two_team_id=excluded.side_two_team_id,status=excluded.status,
side_one_score=excluded.side_one_score,side_two_score=excluded.side_two_score,winner_team_id=excluded.winner_team_id,updated_at=excluded.updated_at,version=excluded.version,deleted_at=excluded.deleted_at''',
        [
          for (final key in [
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
            m[key],
        ],
      );
    }
    for (final match in bracket.plan.matches) {
      final sources = [match.sideOne, match.sideTwo];
      for (var i = 0; i < sources.length; i++) {
        if (sources[i] case MatchOutcomeSource(
          :final matchKey,
          :final outcome,
        )) {
          await write(
            '''INSERT INTO match_dependencies(source_match_id,source_outcome,destination_match_id,destination_slot,created_at,updated_at,version)
VALUES(?,?,?,?,?,?,0) ON CONFLICT(source_match_id,source_outcome,destination_match_id,destination_slot) DO NOTHING''',
            [
              bracket.matches[matchKey]!.id.value,
              outcome.name,
              bracket.matches[match.key]!.id.value,
              i == 0 ? 'sideOne' : 'sideTwo',
              bracket.metadata.createdAt.toIso8601String(),
              stamp,
            ],
          );
        }
      }
    }
    if (bracket.champion != null &&
        command != null &&
        (command.action == BracketAction.result ||
            command.action == BracketAction.correct)) {
      if (command.placementIds.length != 2 ||
          command.placementIds[1] == null ||
          command.placementIds[2] == null ||
          command.placementIds[1] == command.placementIds[2]) {
        throw const ValidationFailure(
          field: 'placements',
          message: 'Final placements require two distinct identities.',
        );
      }
      await write(
        'UPDATE division_placements SET deleted_at=?,updated_at=?,version=version+1 WHERE division_id=? AND deleted_at IS NULL',
        [stamp, stamp, division],
      );
      for (final pos in [1, 2]) {
        await write(
          'INSERT INTO division_placements(id,division_id,team_id,position,created_at,updated_at,version) VALUES(?,?,?,?,?,?,0)',
          [
            command.placementIds[pos]!.value,
            division,
            pos == 1 ? bracket.champion!.value : bracket.runnerUp!.value,
            pos,
            stamp,
            stamp,
          ],
        );
      }
    }
    await write(
      'INSERT INTO single_elimination_snapshots(division_id,bracket_json) VALUES(?,?) ON CONFLICT(division_id) DO UPDATE SET bracket_json=excluded.bracket_json',
      [division, jsonEncode(bracketJson(bracket))],
    );
  }
}
