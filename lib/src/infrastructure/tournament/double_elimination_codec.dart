import 'dart:convert';

import '../../application/tournament/double_elimination_service.dart';
import '../../application/tournament/single_elimination_service.dart'
    show BracketAction, BracketDisposition;
import '../../domain/common/domain_enums.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/matches/match.dart';
import '../../domain/matches/validated_score.dart';
import '../../domain/teams/temporary_team.dart';
import '../../domain/tournament/double_elimination_bracket.dart';
import '../../domain/tournament/double_elimination_generator.dart';
import '../../domain/tournament/single_elimination_bracket.dart'
    show ResultRevision;
import '../../domain/tournament/tournament_contracts.dart';
import '../events/event_setup_codec.dart';
import 'bracket_codec.dart'
    show
        decodeMatch,
        enumValue,
        integer,
        invalid,
        list,
        matchJson,
        metadata,
        metadataJson,
        object,
        text,
        time;

Map<String, Object?> doubleCommandJson(DoubleEliminationCommand command) => {
  'operation_id': command.operationId.value,
  'event_id': command.eventId.value,
  'division_id': command.divisionId.value,
  'action': command.action.name,
  'expected_version': command.expectedVersion,
  'event_version': command.expectedEventVersion,
  'division_version': command.expectedDivisionVersion,
  'created_at': command.createdAt.toIso8601String(),
  'seed_order': command.seedOrder.map((id) => id.value).toList(),
  'team_versions': {
    for (final row in command.teamVersions.entries) row.key.value: row.value,
  },
  'match_ids': {
    for (final row in command.matchIds.entries) row.key.value: row.value.value,
  },
  'placement_ids': {
    for (final row in command.placementIds.entries)
      row.key.toString(): row.value.value,
  },
  'match_key': command.matchKey?.value,
  'score_one': command.score?.sideOne,
  'score_two': command.score?.sideTwo,
  'reason': command.reason,
  'proposed': command.proposed == null
      ? null
      : doubleBracketJson(command.proposed!),
};

DoubleEliminationCommand decodeDoubleCommand(Object? value) {
  final row = object(value);
  return DoubleEliminationCommand(
    operationId: SyncOperationId(text(row, 'operation_id')),
    eventId: EventId(text(row, 'event_id')),
    divisionId: DivisionId(text(row, 'division_id')),
    action: enumValue(BracketAction.values, text(row, 'action')),
    expectedVersion: integer(row, 'expected_version'),
    expectedEventVersion: integer(row, 'event_version'),
    expectedDivisionVersion: integer(row, 'division_version'),
    createdAt: time(row, 'created_at'),
    seedOrder: list(row, 'seed_order').map((v) => TeamId(v as String)),
    teamVersions: object(row['team_versions'])
        .map((key, value) => MapEntry(TeamId(key), value as int)),
    matchIds: object(row['match_ids']).map(
      (key, value) => MapEntry(PlannedMatchKey(key), MatchId(value as String)),
    ),
    placementIds: object(row['placement_ids']).map(
      (key, value) =>
          MapEntry(int.parse(key), DivisionPlacementId(value as String)),
    ),
    matchKey: row['match_key'] == null
        ? null
        : PlannedMatchKey(text(row, 'match_key')),
    score: row['score_one'] == null && row['score_two'] == null
        ? null
        : ValidatedScore(integer(row, 'score_one'), integer(row, 'score_two')),
    reason: row['reason'] as String?,
    proposed: row['proposed'] == null
        ? null
        : decodeDoubleBracket(row['proposed']),
  );
}

Map<String, Object?> doubleBracketJson(DoubleEliminationBracket bracket) => {
  'plan': jsonDecode(bracket.plan.canonicalJson),
  'reset_match_id': bracket.reservedResetMatchId.value,
  ...metadataJson(bracket.metadata),
  'matches': [
    for (final row in bracket.matches.entries)
      {'planned_key': row.key.value, ...matchJson(row.value)},
  ],
  'revisions': [
    for (final revision in bracket.revisions)
      {
        'operation_id': revision.operationId.value,
        'previous': matchJson(revision.previous),
        'reason': revision.reason,
        'recorded_at': revision.recordedAt.toIso8601String(),
      },
  ],
};

/// Upgrades an M15 bracket payload written before the reset-final identity was
/// projected into every local snapshot and queued command.
///
/// The generation command always reserved this identity. Reusing that exact
/// value keeps an already queued reset final idempotent across app upgrades.
Map<String, Object?> normalizeDoubleBracketResetIdentity(
  Object? value,
  String reservedResetMatchId,
) {
  final row = Map<String, Object?>.from(object(value));
  row['reset_match_id'] = reservedResetMatchId;
  final rawMatches = row['matches'];
  if (rawMatches is List) {
    row['matches'] = [
      for (final rawMatch in rawMatches)
        if (rawMatch is Map)
          (() {
            final match = Map<String, Object?>.from(rawMatch);
            if (match['planned_key'] ==
                DoubleEliminationGenerator.resetKey.value) {
              match['id'] = reservedResetMatchId;
            }
            return match;
          })()
        else
          rawMatch,
    ];
  }
  return row;
}

DoubleEliminationBracket decodeDoubleBracket(Object? value) {
  final row = object(value), rawPlan = object(row['plan']);
  PlannedParticipantSource source(Object? value) {
    final raw = object(value);
    return raw['teamId'] != null
        ? DirectTeamSource(TeamId(text(raw, 'teamId')))
        : MatchOutcomeSource(
            PlannedMatchKey(text(raw, 'matchKey')),
            enumValue(MatchDependencySource.values, text(raw, 'outcome')),
          );
  }

  final plan = TournamentPlan(
    eventId: EventId(text(rawPlan, 'eventId')),
    divisionId: DivisionId(text(rawPlan, 'divisionId')),
    format: enumValue(TournamentFormat.values, text(rawPlan, 'format')),
    metadata: object(rawPlan['metadata'])
        .map((key, value) => MapEntry(key, value as String)),
    matches: list(rawPlan, 'matches').map((value) {
      final planned = object(value);
      return PlannedMatch(
        key: PlannedMatchKey(text(planned, 'key')),
        eventId: EventId(text(planned, 'eventId')),
        divisionId: DivisionId(text(planned, 'divisionId')),
        sideOne: source(planned['sideOne']),
        sideTwo: source(planned['sideTwo']),
        round: integer(planned, 'round'),
        section: text(planned, 'section'),
        status: enumValue(MatchStatus.values, text(planned, 'status')),
      );
    }),
  );
  final matches = <PlannedMatchKey, Match>{};
  for (final value in list(row, 'matches')) {
    final match = object(value);
    final key = PlannedMatchKey(text(match, 'planned_key'));
    if (matches.containsKey(key)) throw invalid();
    matches[key] = decodeMatch(match);
  }
  return DoubleEliminationBracket(
    plan: plan,
    reservedResetMatchId: MatchId(text(row, 'reset_match_id')),
    matches: Map.from(matches),
    metadata: metadata(row),
    revisions: list(row, 'revisions').map((value) {
      final revision = object(value);
      return ResultRevision(
        operationId: SyncOperationId(text(revision, 'operation_id')),
        previous: decodeMatch(revision['previous']),
        reason: text(revision, 'reason'),
        recordedAt: time(revision, 'recorded_at'),
      );
    }),
  );
}

DoubleEliminationContext decodeDoubleContext(Object? value) {
  try {
    final row = object(value);
    final setup = decodeEventSetup({
      'event': row['event'],
      'divisions': [row['division']],
    });
    final teams = <TournamentTeam>[], labels = <TeamId, String>{};
    for (final value in list(row, 'teams')) {
      final teamRow = object(value), id = TeamId(text(teamRow, 'id'));
      final members = <PlayerId, RecordMetadata>{};
      for (final rawMember in list(teamRow, 'members')) {
        final member = object(rawMember),
            playerId = PlayerId(text(member, 'player_id'));
        members[playerId] = metadata(member);
      }
      labels[id] = text(teamRow, 'label');
      teams.add(
        TournamentTeam(
          team: TemporaryTeam(
            id: id,
            divisionId: DivisionId(text(teamRow, 'division_id')),
            memberIds: members.keys,
            formationMethod: enumValue(
              TeamFormationMethod.values,
              text(teamRow, 'formation_method'),
            ),
            metadata: metadata(teamRow),
          ),
          members: members,
        ),
      );
    }
    return DoubleEliminationContext(
      event: setup.event,
      division: setup.divisions.single,
      teams: teams,
      teamLabels: labels,
      bracket: row['bracket'] == null
          ? null
          : decodeDoubleBracket(row['bracket']),
      disposition: row['disposition'] == null
          ? BracketDisposition.synchronized
          : enumValue(BracketDisposition.values, text(row, 'disposition')),
    );
  } on TypeError {
    throw invalid();
  } on FormatException {
    throw invalid();
  }
}
