import 'dart:convert';

import '../../application/tournament/single_elimination_service.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/matches/match.dart';
import '../../domain/matches/validated_score.dart';
import '../../domain/teams/temporary_team.dart';
import '../../domain/tournament/single_elimination_bracket.dart';
import '../../domain/tournament/tournament_contracts.dart';
import '../events/event_setup_codec.dart';

Map<String, Object?> commandJson(BracketCommand c) => {
  'placement_ids': {
    for (final e in c.placementIds.entries) e.key.toString(): e.value.value,
  },
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
};
BracketCommand decodeBracketCommand(Object? value) {
  final m = object(value);
  return BracketCommand(
    placementIds: object(
      m['placement_ids'],
    ).map((k, v) => MapEntry(int.parse(k), DivisionPlacementId(v as String))),
    operationId: SyncOperationId(text(m, 'operation_id')),
    eventId: EventId(text(m, 'event_id')),
    divisionId: DivisionId(text(m, 'division_id')),
    action: enumValue(BracketAction.values, text(m, 'action')),
    expectedVersion: integer(m, 'expected_version'),
    expectedEventVersion: integer(m, 'event_version'),
    expectedDivisionVersion: integer(m, 'division_version'),
    createdAt: time(m, 'created_at'),
    seedOrder: list(m, 'seed_order').map((v) => TeamId(v as String)),
    teamVersions: object(m['team_versions'])
        .map((k, v) => MapEntry(TeamId(k), v as int)),
    matchIds: object(m['match_ids'])
        .map((k, v) => MapEntry(PlannedMatchKey(k), MatchId(v as String))),
    matchKey: m['match_key'] == null
        ? null
        : PlannedMatchKey(text(m, 'match_key')),
    score: m['score_one'] == null && m['score_two'] == null
        ? null
        : ValidatedScore(integer(m, 'score_one'), integer(m, 'score_two')),
    reason: m['reason'] as String?,
  );
}

Map<String, Object?> metadataJson(RecordMetadata m) => {
  'created_at': m.createdAt.toIso8601String(),
  'updated_at': m.updatedAt.toIso8601String(),
  'version': m.recordVersion,
  'deleted_at': m.deletedAt?.toIso8601String(),
};
Map<String, Object?> matchJson(Match m) => {
  'id': m.id.value,
  'division_id': m.divisionId.value,
  'status': m.status.name,
  'side_one_team_id': m.sideOneTeamId?.value,
  'side_two_team_id': m.sideTwoTeamId?.value,
  'side_one_score': m.sideOneScore,
  'side_two_score': m.sideTwoScore,
  'winner_team_id': m.winnerTeamId?.value,
  'round_number': m.roundNumber,
  'sequence_number': m.sequenceNumber,
  ...metadataJson(m.metadata),
};
Match decodeMatch(Object? value) {
  final m = object(value);
  TeamId? id(String k) => m[k] == null ? null : TeamId(text(m, k));
  return Match(
    id: MatchId(text(m, 'id')),
    divisionId: DivisionId(text(m, 'division_id')),
    status: enumValue(MatchStatus.values, text(m, 'status')),
    metadata: metadata(m),
    sideOneTeamId: id('side_one_team_id'),
    sideTwoTeamId: id('side_two_team_id'),
    winnerTeamId: id('winner_team_id'),
    sideOneScore: m['side_one_score'] as int?,
    sideTwoScore: m['side_two_score'] as int?,
    roundNumber: m['round_number'] as int?,
    sequenceNumber: m['sequence_number'] as int?,
  );
}

Map<String, Object?> bracketJson(SingleEliminationBracket b) => {
  'plan': jsonDecode(b.plan.canonicalJson),
  ...metadataJson(b.metadata),
  'matches': [
    for (final e in b.matches.entries)
      {'planned_key': e.key.value, ...matchJson(e.value)},
  ],
  'revisions': [
    for (final r in b.revisions)
      {
        'operation_id': r.operationId.value,
        'previous': matchJson(r.previous),
        'reason': r.reason,
        'recorded_at': r.recordedAt.toIso8601String(),
      },
  ],
};
SingleEliminationBracket decodeBracket(Object? value) {
  final m = object(value), p = object(m['plan']);
  PlannedParticipantSource source(Object? value) {
    final s = object(value);
    return s['teamId'] != null
        ? DirectTeamSource(TeamId(text(s, 'teamId')))
        : MatchOutcomeSource(
            PlannedMatchKey(text(s, 'matchKey')),
            enumValue(MatchDependencySource.values, text(s, 'outcome')),
          );
  }

  final plan = TournamentPlan(
    eventId: EventId(text(p, 'eventId')),
    divisionId: DivisionId(text(p, 'divisionId')),
    format: enumValue(TournamentFormat.values, text(p, 'format')),
    metadata: object(p['metadata']).map((k, v) => MapEntry(k, v as String)),
    matches: list(p, 'matches').map((v) {
      final row = object(v);
      return PlannedMatch(
        key: PlannedMatchKey(text(row, 'key')),
        eventId: EventId(text(row, 'eventId')),
        divisionId: DivisionId(text(row, 'divisionId')),
        sideOne: source(row['sideOne']),
        sideTwo: source(row['sideTwo']),
        round: integer(row, 'round'),
        section: text(row, 'section'),
        status: enumValue(MatchStatus.values, text(row, 'status')),
      );
    }),
  );
  final rows = <PlannedMatchKey, Match>{};
  for (final value in list(m, 'matches')) {
    final row = object(value), key = PlannedMatchKey(text(row, 'planned_key'));
    if (rows.containsKey(key)) throw invalid();
    rows[key] = decodeMatch(row);
  }
  return SingleEliminationBracket(
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

BracketContext decodeBracketContext(Object? value) {
  try {
    final m = object(value);
    final setup = decodeEventSetup({
      'event': m['event'],
      'divisions': [m['division']],
    });
    final labels = <TeamId, String>{}, teams = <TournamentTeam>[];
    for (final value in list(m, 'teams')) {
      final row = object(value), id = TeamId(text(row, 'id'));
      final members = <PlayerId, RecordMetadata>{};
      for (final value in list(row, 'members')) {
        final member = object(value),
            player = PlayerId(text(member, 'player_id'));
        if (members.containsKey(player)) throw invalid();
        members[player] = metadata(member);
      }
      if (labels.containsKey(id)) throw invalid();
      labels[id] = text(row, 'label');
      teams.add(
        TournamentTeam(
          team: TemporaryTeam(
            id: id,
            divisionId: DivisionId(text(row, 'division_id')),
            memberIds: members.keys,
            formationMethod: enumValue(
              TeamFormationMethod.values,
              text(row, 'formation_method'),
            ),
            metadata: metadata(row),
          ),
          members: members,
        ),
      );
    }
    return BracketContext(
      event: setup.event,
      division: setup.divisions.single,
      teams: teams,
      teamLabels: labels,
      bracket: m['bracket'] == null ? null : decodeBracket(m['bracket']),
    );
  } on TypeError {
    throw invalid();
  } on FormatException {
    throw invalid();
  }
}

ValidationFailure invalid() => const ValidationFailure(
  field: 'bracketData',
  message: 'Tournament data could not be validated safely.',
);
Map<String, Object?> object(Object? v) {
  if (v is! Map) throw invalid();
  return Map<String, Object?>.from(v);
}

String text(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v is! String) throw invalid();
  return v;
}

int integer(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v is! int) throw invalid();
  return v;
}

List<Object?> list(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v is! List) throw invalid();
  return v;
}

DateTime time(Map<String, Object?> m, String k) {
  final v = text(m, k);
  final t = DateTime.tryParse(v);
  if (t == null || !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(v)) throw invalid();
  return t.toUtc();
}

RecordMetadata metadata(Map<String, Object?> m) => RecordMetadata(
  createdAt: time(m, 'created_at'),
  updatedAt: time(m, 'updated_at'),
  recordVersion: integer(m, 'version'),
  deletedAt: m['deleted_at'] == null ? null : time(m, 'deleted_at'),
);
T enumValue<T extends Enum>(List<T> values, String name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw invalid();
}
