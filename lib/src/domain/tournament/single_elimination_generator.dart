import 'dart:convert';

import '../common/domain_enums.dart';
import '../common/domain_failure.dart';
import '../common/repository_result.dart';
import 'tournament_contracts.dart';
import 'tournament_invariant_validator.dart';

/// Only real playable matches enter the plan. Empty seed positions remain
/// presentation metadata, never completed matches or statistical wins.
final class SingleEliminationGenerator implements TournamentGenerator {
  const SingleEliminationGenerator();

  static List<int> seedPositions(int teamCount) {
    if (teamCount < 2) {
      throw const TournamentGenerationFailure(
        code: 'insufficient_teams',
        message: 'Single Elimination requires at least two complete teams.',
      );
    }
    var positions = [1, 2];
    while (positions.length < teamCount) {
      final sum = positions.length * 2 + 1;
      positions = [
        for (final seed in positions) ...[seed, sum - seed],
      ];
    }
    return List.unmodifiable(positions);
  }

  @override
  RepositoryResult<TournamentPlan> generate(
    TournamentGenerationRequest request,
  ) {
    try {
      if (request.division.format != TournamentFormat.singleElimination) {
        throw const TournamentGenerationFailure(
          code: 'unsupported_format',
          message: 'This generator supports Single Elimination only.',
        );
      }
      final teams = request.canonicalTeams;
      final positions = seedPositions(teams.length);
      var sources = <PlannedParticipantSource?>[
        for (final seed in positions)
          seed <= teams.length
              ? DirectTeamSource(teams[seed - 1].team.id)
              : null,
      ];
      final matches = <PlannedMatch>[];
      var round = 1;
      while (sources.length > 1) {
        final next = <PlannedParticipantSource?>[];
        for (var index = 0; index < sources.length; index += 2) {
          final one = sources[index];
          final two = sources[index + 1];
          if (one == null || two == null) {
            next.add(one ?? two);
            continue;
          }
          final key = PlannedMatchKey('se/r$round/m${index ~/ 2 + 1}');
          matches.add(
            PlannedMatch(
              key: key,
              eventId: request.eventId,
              divisionId: request.division.id,
              sideOne: one,
              sideTwo: two,
              round: round,
              status: one is DirectTeamSource && two is DirectTeamSource
                  ? MatchStatus.queued
                  : MatchStatus.scheduled,
            ),
          );
          next.add(MatchOutcomeSource(key, MatchDependencySource.winner));
        }
        sources = next;
        round++;
      }
      final plan = TournamentPlan(
        eventId: request.eventId,
        divisionId: request.division.id,
        format: TournamentFormat.singleElimination,
        matches: matches,
        metadata: {
          'bracketSize': '${positions.length}',
          'seedOrder': jsonEncode(teams.map((t) => t.team.id.value).toList()),
          'seedPositions': jsonEncode(positions),
        },
      );
      final failures = const TournamentInvariantValidator().validate(
        request,
        plan,
      );
      if (failures.isNotEmpty) return RepositoryFailure(failures.first);
      if (matches.length != teams.length - 1) {
        throw const TournamentGenerationFailure(
          code: 'single_elimination_cardinality',
          message: 'Every team except the champion must have one elimination.',
        );
      }
      return RepositorySuccess(plan);
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }
}
