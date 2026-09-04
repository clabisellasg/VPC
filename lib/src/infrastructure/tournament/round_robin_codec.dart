import 'dart:convert';

import '../../application/tournament/round_robin_service.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/matches/match.dart';
import '../../domain/matches/validated_score.dart';
import '../../domain/teams/temporary_team.dart';
import '../../domain/tournament/round_robin_tournament.dart';
import '../../domain/tournament/single_elimination_bracket.dart'
    show ResultRevision;
import '../../domain/tournament/tournament_contracts.dart';
import '../events/event_setup_codec.dart';
import 'bracket_codec.dart'
    show
        decodeMatch,
        enumValue,
        integer,
        list,
        matchJson,
        metadata,
        metadataJson,
        object,
        text,
        time,
        invalid;

Map<String, Object?> roundRobinCommandJson(RoundRobinCommand c) => {
  'operation_id': c.operationId.value,
  'event_id': c.eventId.value,
  'division_id': c.divisionId.value,
  'action': c.action.name,
  'expected_version': c.expectedVersion,
  'event_version': c.expectedEventVersion,
  'division_version': c.expectedDivisionVersion,
  'created_at': c.createdAt.toIso8601String(),
  'seed_order': c.seedOrder.map((t) => t.value).toList(),
  'team_versions': {
    for (final e in c.teamVersions.entries) e.key.value: e.value,
  },
  'match_ids': {for (final e in c.matchIds.entries) e.key.value: e.value.value},
  'match_key': c.matchKey?.value,
  'score_one': c.score?.sideOne,
  'score_two': c.score?.sideTwo,
  'reason': c.reason,
  'placement_ids': {
    for (final e in c.placementIds.entries) '${e.key}': e.value.value,
  },
};
RoundRobinCommand decodeRoundRobinCommand(Object? value) {
  final m = object(value);
  return RoundRobinCommand(
    operationId: SyncOperationId(text(m, 'operation_id')),
    eventId: EventId(text(m, 'event_id')),
    divisionId: DivisionId(text(m, 'division_id')),
    action: enumValue(RoundRobinAction.values, text(m, 'action')),
    expectedVersion: integer(m, 'expected_version'),
    expectedEventVersion: integer(m, 'event_version'),
    expectedDivisionVersion: integer(m, 'division_version'),
    createdAt: time(m, 'created_at'),
    seedOrder: list(m, 'seed_order').map((v) => TeamId(v as String)).toList(),
    teamVersions: object(m['team_versions'])
        .map((k, v) => MapEntry(TeamId(k), v as int)),
    matchIds: object(m['match_ids'])
        .map((k, v) => MapEntry(PlannedMatchKey(k), MatchId(v as String))),
    matchKey: m['match_key'] == null
        ? null
        : PlannedMatchKey(text(m, 'match_key')),
    score: m['score_one'] == null
        ? null
        : ValidatedScore(integer(m, 'score_one'), integer(m, 'score_two')),
    reason: m['reason'] as String?,
    placementIds: object(
      m['placement_ids'],
    ).map((k, v) => MapEntry(int.parse(k), DivisionPlacementId(v as String))),
  );
}

Map<String, Object?> roundRobinJson(RoundRobinTournament t) => {
  'plan': jsonDecode(t.plan.canonicalJson),
  ...metadataJson(t.metadata),
  'matches': [
    for (final e in t.matches.entries)
      {'planned_key': e.key.value, ...matchJson(e.value)},
  ],
  'revisions': [
    for (final r in t.revisions)
      {
        'operation_id': r.operationId.value,
        'previous': matchJson(r.previous),
        'reason': r.reason,
        'recorded_at': r.recordedAt.toIso8601String(),
      },
  ],
};
RoundRobinTournament decodeRoundRobin(Object? value) {
  final m = object(value), p = object(m['plan']);
  PlannedParticipantSource source(Object? v) {
    final s = object(v);
    return DirectTeamSource(TeamId(text(s, 'teamId')));
  }

  final plan = TournamentPlan(
    eventId: EventId(text(p, 'eventId')),
    divisionId: DivisionId(text(p, 'divisionId')),
    format: enumValue(TournamentFormat.values, text(p, 'format')),
    metadata: object(p['metadata']).map((k, v) => MapEntry(k, v as String)),
    matches: list(p, 'matches').map((v) {
      final r = object(v);
      return PlannedMatch(
        key: PlannedMatchKey(text(r, 'key')),
        eventId: EventId(text(r, 'eventId')),
        divisionId: DivisionId(text(r, 'divisionId')),
        sideOne: source(r['sideOne']),
        sideTwo: source(r['sideTwo']),
        round: integer(r, 'round'),
        section: text(r, 'section'),
        status: enumValue(MatchStatus.values, text(r, 'status')),
      );
    }).toList(),
  );
  final rows = <PlannedMatchKey, Match>{};
  for (final v in list(m, 'matches')) {
    final r = object(v), key = PlannedMatchKey(text(r, 'planned_key'));
    if (rows.containsKey(key)) throw invalid();
    rows[key] = decodeMatch(r);
  }
  return RoundRobinTournament(
    plan: plan,
    matches: rows,
    metadata: metadata(m),
    revisions: list(m, 'revisions').map((v) {
      final r = object(v);
      return ResultRevision(
        operationId: SyncOperationId(text(r, 'operation_id')),
        previous: decodeMatch(r['previous']),
        reason: text(r, 'reason'),
        recordedAt: time(r, 'recorded_at'),
      );
    }),
  );
}

RoundRobinContext decodeRoundRobinContext(Object? value) {
  try {
    final m = object(value);
    final setup = decodeEventSetup({
      'event': m['event'],
      'divisions': [m['division']],
    });
    final labels = <TeamId, String>{}, teams = <TournamentTeam>[];
    for (final v in list(m, 'teams')) {
      final r = object(v),
          id = TeamId(text(r, 'id')),
          members = <PlayerId, RecordMetadata>{};
      for (final raw in list(r, 'members')) {
        final member = object(raw);
        members[PlayerId(text(member, 'player_id'))] = metadata(member);
      }
      labels[id] = text(r, 'label');
      teams.add(
        TournamentTeam(
          team: TemporaryTeam(
            id: id,
            divisionId: DivisionId(text(r, 'division_id')),
            memberIds: members.keys,
            formationMethod: enumValue(
              TeamFormationMethod.values,
              text(r, 'formation_method'),
            ),
            metadata: metadata(r),
          ),
          members: members,
        ),
      );
    }
    return RoundRobinContext(
      event: setup.event,
      division: setup.divisions.single,
      teams: teams,
      teamLabels: labels,
      tournament: m['tournament'] == null
          ? null
          : decodeRoundRobin(m['tournament']),
    );
  } on TypeError {
    throw invalid();
  } on FormatException {
    throw invalid();
  }
}
