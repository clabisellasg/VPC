import 'dart:convert';

import 'package:drift/drift.dart';

import '../../application/tournament/double_elimination_service.dart';
import '../../application/tournament/single_elimination_service.dart'
    show BracketAction, BracketDisposition;
import '../../domain/common/domain_failure.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/tournament/double_elimination_bracket.dart';
import '../../domain/tournament/double_elimination_generator.dart';
import '../../domain/tournament/tournament_contracts.dart';
import '../persistence/local/app_database.dart';
import '../persistence/local/sqlite_failure_mapper.dart';
import 'bracket_codec.dart' show enumValue, matchJson;
import 'double_elimination_codec.dart';

final class DriftDoubleEliminationRepository
    implements DoubleEliminationRepository {
  const DriftDoubleEliminationRepository(this.database);
  final AppDatabase database;

  Future<List<Map<String, Object?>>> rows(
    String sql, [
    List<Object> args = const [],
  ]) async =>
      (await database
              .customSelect(
                sql,
                variables: [for (final value in args) Variable(value)],
              )
              .get())
          .map((row) => row.data)
          .toList();
  Future<void> write(String sql, [List<Object?> args = const []]) =>
      database.customStatement(sql, args);

  @override
  Future<RepositoryResult<DoubleEliminationContext>> load(
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
      final teamRows = await rows(
        'SELECT * FROM teams WHERE division_id=? AND deleted_at IS NULL ORDER BY id',
        [divisionId.value],
      );
      final teams = <Map<String, Object?>>[];
      for (final team in teamRows) {
        final members = await rows(
          'SELECT tm.*,p.display_name FROM team_members tm JOIN players p ON p.id=tm.player_id WHERE tm.team_id=? AND tm.deleted_at IS NULL ORDER BY tm.player_id',
          [team['id'] as String],
        );
        teams.add({
          ...team,
          'members': members,
          'label':
              team['display_label'] ??
              members.map((member) => member['display_name']).join(' / '),
        });
      }
      final snapshots = await rows(
        'SELECT bracket_json FROM double_elimination_snapshots WHERE division_id=?',
        [divisionId.value],
      );
      Object? bracketValue;
      if (snapshots.isNotEmpty) {
        final decoded = Map<String, Object?>.from(
          jsonDecode(snapshots.single['bracket_json'] as String) as Map,
        );
        if (decoded['reset_match_id'] == null) {
          final operations = await rows(
            'SELECT payload_json FROM double_elimination_outbox WHERE division_id=? ORDER BY created_at,id',
            [divisionId.value],
          );
          for (final operation in operations) {
            final payload = Map<String, Object?>.from(
              jsonDecode(operation['payload_json'] as String) as Map,
            );
            if (payload['action'] == BracketAction.generate.name) {
              final matchIds = Map<String, Object?>.from(
                payload['match_ids'] as Map,
              );
              final reserved =
                  matchIds[DoubleEliminationGenerator.resetKey.value];
              if (reserved is String) {
                bracketValue = normalizeDoubleBracketResetIdentity(
                  decoded,
                  reserved,
                );
              }
              break;
            }
          }
        }
        bracketValue ??= decoded;
      }
      final pending = await rows(
        "SELECT status FROM double_elimination_outbox WHERE division_id=? AND status<>'accepted' ORDER BY CASE status WHEN 'conflicted' THEN 0 WHEN 'blocked' THEN 1 WHEN 'failed' THEN 2 ELSE 3 END LIMIT 1",
        [divisionId.value],
      );
      final context = decodeDoubleContext({
        'event': events.single,
        'division': divisions.single,
        'teams': teams,
        'bracket': bracketValue,
        'disposition': pending.isEmpty
            ? BracketDisposition.synchronized.name
            : pending.single['status'],
      });
      final conflicts = await rows(
        "SELECT id FROM team_formation_outbox_operations WHERE division_id=? AND status='conflicted' LIMIT 1",
        [divisionId.value],
      );
      return RepositorySuccess(
        DoubleEliminationContext(
          event: context.event,
          division: context.division,
          teams: context.teams,
          teamLabels: context.teamLabels,
          bracket: context.bracket,
          disposition: context.disposition,
          teamConflict: conflicts.isNotEmpty,
        ),
      );
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }

  @override
  Future<RepositoryResult<DoubleEliminationContext>> apply(
    DoubleEliminationCommand command,
  ) async {
    try {
      return await database.transaction(() async {
        final old = await rows(
          'SELECT payload_json FROM double_elimination_outbox WHERE id=?',
          [command.operationId.value],
        );
        final payload = jsonEncode(doubleCommandJson(command));
        if (old.isNotEmpty) {
          if (old.single['payload_json'] != payload) {
            throw const ConflictFailure(
              message: 'Operation identity was reused with changed data.',
            );
          }
          return load(command.eventId, command.divisionId);
        }
        final context = (await load(
          command.eventId,
          command.divisionId,
        )).when(success: (value) => value, failure: (failure) => throw failure);
        if (context.disposition == BracketDisposition.blocked ||
            context.disposition == BracketDisposition.conflicted) {
          throw const ConflictFailure(
            message: 'Resolve blocked or conflicted bracket work first.',
          );
        }
        final next = applyDoubleEliminationCommand(context, command);
        if (command.proposed == null ||
            jsonEncode(doubleBracketJson(command.proposed!)) !=
                jsonEncode(doubleBracketJson(next))) {
          throw const ValidationFailure(
            field: 'proposed',
            message:
                'The proposed bracket does not match the validated command.',
          );
        }
        await persist(next, command: command);
        await write(
          'INSERT INTO double_elimination_outbox(id,division_id,payload_json,status,created_at) VALUES(?,?,?,?,?)',
          [
            command.operationId.value,
            command.divisionId.value,
            payload,
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
        operation: 'Double Elimination operation',
      );
      if (failure != null) return RepositoryFailure(failure);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> persist(
    DoubleEliminationBracket bracket, {
    DoubleEliminationCommand? command,
  }) async {
    final stamp = bracket.metadata.updatedAt.toIso8601String();
    final division = bracket.plan.divisionId.value;
    for (final revision in bracket.revisions) {
      final old = await rows(
        'SELECT operation_id FROM match_result_revisions WHERE operation_id=?',
        [revision.operationId.value],
      );
      if (old.isEmpty) {
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
    final activeIds = bracket.matches.values
        .map((match) => match.id.value)
        .toSet();
    final prior = await rows(
      'SELECT id FROM matches WHERE division_id=? AND deleted_at IS NULL',
      [division],
    );
    for (final row in prior) {
      if (!activeIds.contains(row['id'])) {
        await write(
          'UPDATE match_dependencies SET deleted_at=?,updated_at=?,version=version+1 WHERE (source_match_id=? OR destination_match_id=?) AND deleted_at IS NULL',
          [stamp, stamp, row['id'], row['id']],
        );
        await write(
          'UPDATE matches SET deleted_at=?,updated_at=?,version=version+1 WHERE id=?',
          [stamp, stamp, row['id']],
        );
      }
    }
    for (final match in bracket.matches.values) {
      final encoded = matchJson(match);
      final old = await rows('SELECT status FROM matches WHERE id=?', [
        match.id.value,
      ]);
      if (old.isNotEmpty) {
        final previous = enumValue(
          MatchStatus.values,
          old.single['status'] as String,
        );
        for (var step = previous.index + 1; step < match.status.index; step++) {
          await write('UPDATE matches SET status=? WHERE id=?', [
            MatchStatus.values[step].name,
            match.id.value,
          ]);
        }
      }
      await write(
        '''INSERT INTO matches(id,division_id,side_one_team_id,side_two_team_id,status,side_one_score,side_two_score,winner_team_id,round_number,sequence_number,created_at,updated_at,version,deleted_at)
VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET side_one_team_id=excluded.side_one_team_id,side_two_team_id=excluded.side_two_team_id,status=excluded.status,side_one_score=excluded.side_one_score,side_two_score=excluded.side_two_score,winner_team_id=excluded.winner_team_id,updated_at=excluded.updated_at,version=excluded.version,deleted_at=excluded.deleted_at''',
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
            encoded[key],
        ],
      );
    }
    await write(
      'UPDATE match_dependencies SET deleted_at=?,updated_at=?,version=version+1 WHERE destination_match_id IN (SELECT id FROM matches WHERE division_id=?) AND deleted_at IS NULL',
      [stamp, stamp, division],
    );
    for (final planned in bracket.plan.matches) {
      final destination = bracket.matches[planned.key];
      if (destination == null) continue;
      for (var side = 0; side < 2; side++) {
        final source = [planned.sideOne, planned.sideTwo][side];
        if (source is! MatchOutcomeSource) continue;
        final sourceMatch = bracket.matches[source.matchKey];
        if (sourceMatch == null) continue;
        await write(
          '''INSERT INTO match_dependencies(source_match_id,source_outcome,destination_match_id,destination_slot,created_at,updated_at,version)
VALUES(?,?,?,?,?,?,0) ON CONFLICT(source_match_id,source_outcome,destination_match_id,destination_slot) DO UPDATE SET updated_at=excluded.updated_at,deleted_at=NULL''',
          [
            sourceMatch.id.value,
            source.outcome.name,
            destination.id.value,
            side == 0 ? 'sideOne' : 'sideTwo',
            bracket.metadata.createdAt.toIso8601String(),
            stamp,
          ],
        );
      }
    }
    if (bracket.decided &&
        command != null &&
        command.action != BracketAction.start) {
      if (command.placementIds.length != 2 ||
          command.placementIds[1] == command.placementIds[2]) {
        throw const ValidationFailure(
          field: 'placements',
          message: 'Champion and runner-up need distinct identities.',
        );
      }
      await write(
        'UPDATE division_placements SET deleted_at=?,updated_at=?,version=version+1 WHERE division_id=? AND deleted_at IS NULL',
        [stamp, stamp, division],
      );
      for (final position in [1, 2]) {
        await write(
          'INSERT INTO division_placements(id,division_id,team_id,position,created_at,updated_at,version) VALUES(?,?,?,?,?,?,0)',
          [
            command.placementIds[position]!.value,
            division,
            position == 1 ? bracket.champion!.value : bracket.runnerUp!.value,
            position,
            stamp,
            stamp,
          ],
        );
      }
    }
    await write(
      'INSERT INTO double_elimination_snapshots(division_id,bracket_json) VALUES(?,?) ON CONFLICT(division_id) DO UPDATE SET bracket_json=excluded.bracket_json',
      [division, jsonEncode(doubleBracketJson(bracket))],
    );
  }
}
