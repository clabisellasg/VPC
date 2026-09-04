import 'dart:convert';

import '../common/domain_enums.dart';
import '../common/domain_failure.dart';
import '../common/entity_id.dart';
import '../common/repository_result.dart';
import 'tournament_contracts.dart';
import 'tournament_invariant_validator.dart';

bool isRoundRobin(TournamentFormat? format) =>
    format == TournamentFormat.singleRoundRobin ||
    format == TournamentFormat.doubleRoundRobin;

/// Fix the first seed, rotate the last slot into the second slot after each
/// round. Null is an internal resting slot, never a persisted match/team.
final class RoundRobinGenerator implements TournamentGenerator {
  const RoundRobinGenerator();

  @override
  RepositoryResult<TournamentPlan> generate(
    TournamentGenerationRequest request,
  ) {
    try {
      if (!isRoundRobin(request.division.format)) {
        throw const TournamentGenerationFailure(
          code: 'unsupported_format',
          message: 'Choose Single or Double Round Robin.',
        );
      }
      final teams = request.canonicalTeams;
      if (teams.length < 2) {
        throw const TournamentGenerationFailure(
          code: 'insufficient_teams',
          message: 'Round Robin requires at least two complete teams.',
        );
      }
      final order = teams.map((t) => t.team.id).toList();
      final slots = <TeamId?>[...order, if (order.length.isOdd) null];
      final roundsPerLeg = slots.length - 1;
      final legs = request.division.format == TournamentFormat.doubleRoundRobin
          ? 2
          : 1;
      final firstLeg = <List<(TeamId, TeamId)>>[];
      final rests = <TeamId?>[];
      for (var r = 0; r < roundsPerLeg; r++) {
        final pairs = <(TeamId, TeamId)>[];
        TeamId? resting;
        for (var p = 0; p < slots.length ~/ 2; p++) {
          final one = slots[p], two = slots[slots.length - 1 - p];
          if (one == null || two == null) {
            resting = one ?? two;
          } else {
            pairs.add((one, two));
          }
        }
        firstLeg.add(pairs);
        rests.add(resting);
        slots.insert(1, slots.removeLast());
      }
      final matches = <PlannedMatch>[];
      final restingByRound = <String, String>{};
      for (var leg = 1; leg <= legs; leg++) {
        for (var r = 0; r < roundsPerLeg; r++) {
          final round = (leg - 1) * roundsPerLeg + r + 1;
          if (rests[r] != null) restingByRound['$round'] = rests[r]!.value;
          for (var p = 0; p < firstLeg[r].length; p++) {
            final pair = firstLeg[r][p];
            matches.add(
              PlannedMatch(
                key: PlannedMatchKey('rr/r$round/m${p + 1}'),
                eventId: request.eventId,
                divisionId: request.division.id,
                sideOne: DirectTeamSource(leg == 1 ? pair.$1 : pair.$2),
                sideTwo: DirectTeamSource(leg == 1 ? pair.$2 : pair.$1),
                round: round,
                section: 'leg$leg',
                status: MatchStatus.queued,
              ),
            );
          }
        }
      }
      final plan = TournamentPlan(
        eventId: request.eventId,
        divisionId: request.division.id,
        format: request.division.format!,
        matches: matches,
        metadata: {
          'seedOrder': jsonEncode(order.map((t) => t.value).toList()),
          'roundsPerLeg': '$roundsPerLeg',
          'legs': '$legs',
          'restingByRound': jsonEncode(restingByRound),
        },
      );
      final failures = const TournamentInvariantValidator().validate(
        request,
        plan,
        forbidRepeatedDirectTeams: false,
      );
      if (failures.isNotEmpty) return RepositoryFailure(failures.first);
      return RepositorySuccess(plan);
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }
}
