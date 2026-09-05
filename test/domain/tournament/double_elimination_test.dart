import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/matches/match.dart';
import 'package:vpc/src/domain/matches/validated_score.dart';
import 'package:vpc/src/domain/tournament/double_elimination_bracket.dart';
import 'package:vpc/src/domain/tournament/double_elimination_generator.dart';
import 'package:vpc/src/domain/tournament/tournament_contracts.dart';
import 'package:vpc/src/domain/tournament/tournament_invariant_validator.dart';

import 'tournament_fixtures.dart';

void main() {
  const generator = DoubleEliminationGenerator();
  for (final count in [2, 3, 4, 5, 8]) {
    test(
      '$count teams generate stable winners, losers and reset structure',
      () {
        final request = fixtureRequest(
          format: TournamentFormat.doubleElimination,
          teams: [for (var i = 0; i < count; i++) fixtureTeam(i + 3)],
        );
        final first = (generator.generate(
          request,
        ) as RepositorySuccess<TournamentPlan>).value;
        final second = (generator.generate(
          request,
        ) as RepositorySuccess<TournamentPlan>).value;
        expect(first, second);
        expect(first.matches, hasLength(2 * count - 1));
        expect(
          first.matches.where((m) => m.section == 'winners'),
          hasLength(count - 1),
        );
        expect(
          first.matches.where((m) => m.section == 'losers'),
          hasLength(count - 2),
        );
        expect(
          first.matches.where((m) => m.section == 'grandFinal'),
          hasLength(1),
        );
        expect(
          first.matches.where((m) => m.section == 'resetFinal'),
          hasLength(1),
        );
        expect(
          const TournamentInvariantValidator().validate(request, first),
          isEmpty,
        );
        final keys = first.matches.map((m) => m.key).toSet();
        for (final match in first.matches) {
          for (final source in [
            match.sideOne,
            match.sideTwo,
          ].whereType<MatchOutcomeSource>()) {
            expect(keys, contains(source.matchKey));
            expect(source.matchKey, isNot(match.key));
          }
        }
      },
    );
  }

  test('non-power-of-two teams have no fake bye matches or losses', () {
    final plan = planFor(5);
    expect(plan.matches.where((m) => m.section == 'winners'), hasLength(4));
    expect(
      plan.matches
          .expand((m) => [m.sideOne, m.sideTwo])
          .whereType<DirectTeamSource>(),
      hasLength(5),
    );
    expect(
      plan.matches.any((m) => m.key.value.toLowerCase().contains('bye')),
      isFalse,
    );
  });

  test('four-team loser routing is staged and deterministic', () {
    final plan = planFor(4);
    PlannedMatch match(String key) =>
        plan.matches.singleWhere((match) => match.key.value == key);

    final losersRoundOne = match('de/lb/r1/m1');
    expect(
      [losersRoundOne.sideOne, losersRoundOne.sideTwo]
          .whereType<MatchOutcomeSource>()
          .map((source) => (source.matchKey.value, source.outcome))
          .toSet(),
      {
        ('de/wb/r1/m1', MatchDependencySource.loser),
        ('de/wb/r1/m2', MatchDependencySource.loser),
      },
    );

    final losersFinal = match('de/lb/r2/m1');
    expect(
      [losersFinal.sideOne, losersFinal.sideTwo]
          .whereType<MatchOutcomeSource>()
          .map((source) => (source.matchKey.value, source.outcome))
          .toSet(),
      {
        ('de/lb/r1/m1', MatchDependencySource.winner),
        ('de/wb/r2/m1', MatchDependencySource.loser),
      },
    );
  });

  test('winners finalist victory ends without persisting reset', () {
    var bracket = bracketFor(4);
    bracket = completeUntilFinal(bracket);
    final gf1 = DoubleEliminationGenerator.grandFinalOneKey;
    bracket = play(bracket, gf1, sideOneWins: true);
    expect(bracket.decided, isTrue);
    expect(bracket.grandFinalTwo, isNull);
    expect(bracket.matches, hasLength(2 * 4 - 2));
    expect(bracket.champion, bracket.grandFinalOne.sideOneTeamId);
  });

  test(
    'losers finalist victory activates one reset and reset decides placements',
    () {
      var bracket = completeUntilFinal(bracketFor(4));
      final gf1 = DoubleEliminationGenerator.grandFinalOneKey;
      bracket = play(bracket, gf1, sideOneWins: false);
      expect(bracket.resetRequired, isTrue);
      expect(bracket.decided, isFalse);
      expect(bracket.grandFinalTwo?.status, MatchStatus.queued);
      expect(bracket.matches, hasLength(2 * 4 - 1));
      bracket = play(
        bracket,
        DoubleEliminationGenerator.resetKey,
        sideOneWins: true,
      );
      expect(bracket.decided, isTrue);
      expect(bracket.champion, bracket.grandFinalTwo!.sideOneTeamId);
      expect(bracket.runnerUp, bracket.grandFinalTwo!.sideTwoTeamId);
    },
  );

  test('correction audits and is blocked after affected downstream starts', () {
    var bracket = bracketFor(3);
    final first = bracket.matches.entries
        .firstWhere((entry) => entry.value.status == MatchStatus.queued)
        .key;
    bracket = play(bracket, first, sideOneWins: true);
    final corrected = bracket.result(
      key: first,
      score: ValidatedScore(5, 11),
      eventStatus: EventStatus.inProgress,
      expectedVersion: bracket.metadata.recordVersion,
      now: tick,
      operationId: SyncOperationId(fixtureId(920)),
      correctionReason: 'Synthetic correction',
    );
    expect(corrected.revisions, hasLength(1));
    final downstream = corrected.matches.entries
        .firstWhere(
          (entry) =>
              entry.value.status == MatchStatus.queued && entry.key != first,
        )
        .key;
    final started = corrected.start(
      downstream,
      EventStatus.inProgress,
      corrected.metadata.recordVersion,
      tick,
    );
    expect(
      () => started.result(
        key: first,
        score: ValidatedScore(11, 5),
        eventStatus: EventStatus.inProgress,
        expectedVersion: started.metadata.recordVersion,
        now: tick,
        operationId: SyncOperationId(fixtureId(921)),
        correctionReason: 'Blocked correction',
      ),
      throwsA(isA<TournamentGenerationFailure>()),
    );
  });

  test('other formats are rejected', () {
    expect(
      generator.generate(fixtureRequest()),
      isA<RepositoryFailure<TournamentPlan>>(),
    );
  });
}

final tick = DateTime.utc(2026, 9, 5);

TournamentPlan planFor(int count) =>
    (const DoubleEliminationGenerator().generate(
      fixtureRequest(
        format: TournamentFormat.doubleElimination,
        teams: [for (var i = 0; i < count; i++) fixtureTeam(i + 3)],
      ),
    ) as RepositorySuccess<TournamentPlan>).value;

DoubleEliminationBracket bracketFor(int count) {
  final plan = planFor(count);
  final meta = RecordMetadata(
    createdAt: tick,
    updatedAt: tick,
    recordVersion: 0,
  );
  var id = 500;
  return DoubleEliminationBracket(
    plan: plan,
    reservedResetMatchId: MatchId(fixtureId(899)),
    metadata: meta,
    matches: {
      for (final planned in plan.matches)
        if (planned.key != DoubleEliminationGenerator.resetKey)
          planned.key: Match(
            id: MatchId(fixtureId(id++)),
            divisionId: fixtureDivision,
            status: planned.status,
            metadata: meta,
            sideOneTeamId: planned.sideOne is DirectTeamSource
                ? (planned.sideOne as DirectTeamSource).teamId
                : null,
            sideTwoTeamId: planned.sideTwo is DirectTeamSource
                ? (planned.sideTwo as DirectTeamSource).teamId
                : null,
            roundNumber: planned.round,
            sequenceNumber: id,
          ),
    },
  );
}

DoubleEliminationBracket completeUntilFinal(DoubleEliminationBracket bracket) {
  while (bracket.grandFinalOne.status != MatchStatus.queued) {
    final ready = bracket.matches.entries
        .where(
          (entry) =>
              entry.key != DoubleEliminationGenerator.grandFinalOneKey &&
              entry.value.status == MatchStatus.queued,
        )
        .first;
    bracket = play(bracket, ready.key, sideOneWins: true);
  }
  return bracket;
}

DoubleEliminationBracket play(
  DoubleEliminationBracket bracket,
  PlannedMatchKey key, {
  required bool sideOneWins,
}) {
  final started = bracket.start(
    key,
    EventStatus.inProgress,
    bracket.metadata.recordVersion,
    tick,
  );
  return started.result(
    key: key,
    score: sideOneWins ? ValidatedScore(11, 5) : ValidatedScore(5, 11),
    eventStatus: EventStatus.inProgress,
    expectedVersion: started.metadata.recordVersion,
    now: tick,
    operationId: SyncOperationId(fixtureId(990)),
  );
}
