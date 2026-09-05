import 'dart:convert';

import '../common/domain_enums.dart';
import '../common/domain_failure.dart';
import '../common/entity_id.dart';
import '../common/repository_result.dart';
import 'single_elimination_generator.dart';
import 'tournament_contracts.dart';
import 'tournament_invariant_validator.dart';

/// Deterministic two-loss structure. The winners bracket is seeded using M13's
/// recursive positions. Its real losers become the seeded entrants of a second
/// elimination bracket. Grand Final 2 is a structural, conditional placeholder.
final class DoubleEliminationGenerator implements TournamentGenerator {
  const DoubleEliminationGenerator();

  static final resetKey = PlannedMatchKey('de/finals/gf2');
  static final grandFinalOneKey = PlannedMatchKey('de/finals/gf1');

  @override
  RepositoryResult<TournamentPlan> generate(
    TournamentGenerationRequest request,
  ) {
    try {
      if (request.division.format != TournamentFormat.doubleElimination) {
        throw const TournamentGenerationFailure(
          code: 'unsupported_format',
          message: 'This generator supports Double Elimination only.',
        );
      }
      final teams = request.canonicalTeams;
      if (teams.length < 2) {
        throw const TournamentGenerationFailure(
          code: 'insufficient_teams',
          message: 'Double Elimination requires at least two complete teams.',
        );
      }
      final winners = _elimination(
        eventId: request.eventId,
        divisionId: request.division.id,
        sources: [for (final team in teams) DirectTeamSource(team.team.id)],
        section: 'winners',
        prefix: 'de/wb',
      );
      final winnerFinal = winners.matches.last.key;
      final losers = _losersBracket(
        eventId: request.eventId,
        divisionId: request.division.id,
        winners: winners,
      );
      final gf1 = PlannedMatch(
        key: grandFinalOneKey,
        eventId: request.eventId,
        divisionId: request.division.id,
        sideOne: MatchOutcomeSource(winnerFinal, MatchDependencySource.winner),
        sideTwo: losers.champion,
        section: 'grandFinal',
        round: 1,
      );
      final gf2 = PlannedMatch(
        key: resetKey,
        eventId: request.eventId,
        divisionId: request.division.id,
        sideOne: MatchOutcomeSource(
          grandFinalOneKey,
          MatchDependencySource.winner,
        ),
        sideTwo: MatchOutcomeSource(
          grandFinalOneKey,
          MatchDependencySource.loser,
        ),
        section: 'resetFinal',
        round: 2,
      );
      final plan = TournamentPlan(
        eventId: request.eventId,
        divisionId: request.division.id,
        format: TournamentFormat.doubleElimination,
        matches: [...winners.matches, ...losers.matches, gf1, gf2],
        metadata: {
          'bracketSize':
              '${SingleEliminationGenerator.seedPositions(teams.length).length}',
          'seedOrder': jsonEncode(teams.map((t) => t.team.id.value).toList()),
          'resetKey': resetKey.value,
        },
      );
      final failures = const TournamentInvariantValidator().validate(
        request,
        plan,
      );
      if (failures.isNotEmpty) return RepositoryFailure(failures.first);
      if (plan.matches.length != 2 * teams.length - 1) {
        throw const TournamentGenerationFailure(
          code: 'double_elimination_cardinality',
          message: 'The reset-capable plan must contain 2N-1 match slots.',
        );
      }
      return RepositorySuccess(plan);
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }

  _EliminationResult _elimination({
    required EventId eventId,
    required DivisionId divisionId,
    required List<PlannedParticipantSource> sources,
    required String section,
    required String prefix,
  }) {
    final positions = SingleEliminationGenerator.seedPositions(sources.length);
    var current = <PlannedParticipantSource?>[
      for (final seed in positions)
        seed <= sources.length ? sources[seed - 1] : null,
    ];
    final matches = <PlannedMatch>[];
    final matchesByRound = <List<PlannedMatch>>[];
    var round = 1;
    while (current.length > 1) {
      final next = <PlannedParticipantSource?>[];
      final roundMatches = <PlannedMatch>[];
      var playable = 0;
      for (var index = 0; index < current.length; index += 2) {
        final one = current[index], two = current[index + 1];
        if (one == null || two == null) {
          next.add(one ?? two);
          continue;
        }
        final key = PlannedMatchKey('$prefix/r$round/m${++playable}');
        final match = PlannedMatch(
          key: key,
          eventId: eventId,
          divisionId: divisionId,
          sideOne: one,
          sideTwo: two,
          round: round,
          section: section,
          status: one is DirectTeamSource && two is DirectTeamSource
              ? MatchStatus.queued
              : MatchStatus.scheduled,
        );
        matches.add(match);
        roundMatches.add(match);
        next.add(MatchOutcomeSource(key, MatchDependencySource.winner));
      }
      current = next;
      matchesByRound.add(roundMatches);
      round++;
    }
    return _EliminationResult(matches, current.single!, matchesByRound);
  }

  _EliminationResult _losersBracket({
    required EventId eventId,
    required DivisionId divisionId,
    required _EliminationResult winners,
  }) {
    final output = <PlannedMatch>[];
    var losersRound = 0;

    List<PlannedParticipantSource> pair(
      List<PlannedParticipantSource> sources,
    ) {
      losersRound++;
      final next = <PlannedParticipantSource>[];
      var position = 0;
      for (var index = 0; index < sources.length; index += 2) {
        if (index + 1 == sources.length) {
          next.add(sources[index]);
          continue;
        }
        final key = PlannedMatchKey('de/lb/r$losersRound/m${++position}');
        output.add(
          PlannedMatch(
            key: key,
            eventId: eventId,
            divisionId: divisionId,
            sideOne: sources[index],
            sideTwo: sources[index + 1],
            round: losersRound,
            section: 'losers',
          ),
        );
        next.add(MatchOutcomeSource(key, MatchDependencySource.winner));
      }
      return next;
    }

    List<PlannedParticipantSource> drop(
      List<PlannedParticipantSource> survivors,
      List<PlannedParticipantSource> incoming,
    ) {
      final sources = <PlannedParticipantSource>[];
      final count = survivors.length > incoming.length
          ? survivors.length
          : incoming.length;
      for (var index = 0; index < count; index++) {
        if (index < survivors.length) sources.add(survivors[index]);
        if (index < incoming.length) sources.add(incoming[index]);
      }
      return pair(sources);
    }

    final winnerRounds = winners.matchesByRound;
    if (winnerRounds.length == 1) {
      return _EliminationResult(
        const [],
        MatchOutcomeSource(
          winnerRounds.single.single.key,
          MatchDependencySource.loser,
        ),
        const [],
      );
    }
    var survivors = pair([
      for (final match in winnerRounds.first)
        MatchOutcomeSource(match.key, MatchDependencySource.loser),
    ]);
    for (var round = 1; round < winnerRounds.length - 1; round++) {
      final incoming = [
        for (final match in winnerRounds[round])
          MatchOutcomeSource(match.key, MatchDependencySource.loser),
      ];
      survivors = drop(survivors, incoming);
      if (survivors.length > 1) survivors = pair(survivors);
    }
    final finalLoser = MatchOutcomeSource(
      winnerRounds.last.single.key,
      MatchDependencySource.loser,
    );
    survivors = drop(survivors, [finalLoser]);
    return _EliminationResult(output, survivors.single, const []);
  }
}

final class _EliminationResult {
  const _EliminationResult(this.matches, this.champion, this.matchesByRound);
  final List<PlannedMatch> matches;
  final PlannedParticipantSource champion;
  final List<List<PlannedMatch>> matchesByRound;
}
