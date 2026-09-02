import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/events/event_division.dart';
import 'package:vpc/src/domain/teams/temporary_team.dart';
import 'package:vpc/src/domain/tournament/tournament_contracts.dart';

String fixtureId(int n) =>
    '12000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
RecordMetadata fixtureMetadata({bool deleted = false}) => RecordMetadata(
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 2),
  recordVersion: 3,
  deletedAt: deleted ? DateTime.utc(2026, 9, 2) : null,
);
final fixtureEvent = EventId(fixtureId(1));
final fixtureDivision = DivisionId(fixtureId(2));
TournamentTeam fixtureTeam(
  int n, {
  bool deleted = false,
  bool deletedMember = false,
  bool incomplete = false,
  DivisionId? division,
}) {
  final players = [
    PlayerId(fixtureId(n * 10)),
    PlayerId(fixtureId(n * 10 + 1)),
  ];
  return TournamentTeam(
    team: TemporaryTeam(
      id: TeamId(fixtureId(n)),
      divisionId: division ?? fixtureDivision,
      memberIds: players,
      formationMethod: TeamFormationMethod.manual,
      metadata: fixtureMetadata(deleted: deleted),
    ),
    members: {
      for (final player in incomplete ? players.take(1) : players)
        player: fixtureMetadata(deleted: deletedMember),
    },
  );
}

TournamentGenerationRequest fixtureRequest({
  List<TournamentTeam>? teams,
  TournamentFormat? format = TournamentFormat.singleElimination,
  List<TeamId>? order,
}) => TournamentGenerationRequest(
  eventId: fixtureEvent,
  division: EventDivision(
    id: fixtureDivision,
    eventId: fixtureEvent,
    name: 'VPC Test Open',
    format: format,
    metadata: fixtureMetadata(),
  ),
  teams: teams ?? [fixtureTeam(3), fixtureTeam(4)],
  organizerOrder: order,
);
PlannedMatch fixtureMatch(
  String key, {
  PlannedParticipantSource? one,
  PlannedParticipantSource? two,
  EventId? event,
  MatchStatus status = MatchStatus.scheduled,
  TeamId? winner,
}) => PlannedMatch(
  key: PlannedMatchKey(key),
  eventId: event ?? fixtureEvent,
  divisionId: fixtureDivision,
  sideOne: one ?? DirectTeamSource(TeamId(fixtureId(3))),
  sideTwo: two ?? DirectTeamSource(TeamId(fixtureId(4))),
  status: status,
  winner: winner,
);
TournamentPlan fixturePlan(List<PlannedMatch> matches) => TournamentPlan(
  eventId: fixtureEvent,
  divisionId: fixtureDivision,
  format: TournamentFormat.singleElimination,
  matches: matches,
);

/// A single fixture match, NOT a format implementation.
final class FixtureOnlyGenerator implements TournamentGenerator {
  @override
  RepositoryResult<TournamentPlan> generate(
    TournamentGenerationRequest request,
  ) {
    final teams = request.canonicalTeams;
    return RepositorySuccess(
      TournamentPlan(
        eventId: request.eventId,
        divisionId: request.division.id,
        format: request.division.format!,
        matches: [
          fixtureMatch(
            'fixture/1',
            one: DirectTeamSource(teams[0].team.id),
            two: DirectTeamSource(teams[1].team.id),
          ),
        ],
      ),
    );
  }
}
