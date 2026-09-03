import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/matches/match.dart';
import 'package:vpc/src/domain/matches/validated_score.dart';
import 'package:vpc/src/domain/tournament/single_elimination_bracket.dart';
import 'package:vpc/src/domain/tournament/single_elimination_generator.dart';
import 'package:vpc/src/domain/tournament/tournament_contracts.dart';
import 'package:vpc/src/domain/tournament/tournament_invariant_validator.dart';

import 'tournament_fixtures.dart';

void main() {
  const generator = SingleEliminationGenerator();
  for (final n in [2, 3, 4, 5, 6, 7, 8, 9, 13, 17, 33]) {
    test(
      '$n teams: deterministic, N-1 playable matches, byes and invariants',
      () {
        final request = fixtureRequest(
          teams: [for (var i = 0; i < n; i++) fixtureTeam(i + 3)],
        );
        final plan = (generator.generate(
          request,
        ) as RepositorySuccess<TournamentPlan>).value;
        expect(plan.matches, hasLength(n - 1));
        expect(
          generator
              .generate(request)
              .when(success: (p) => p, failure: (f) => f),
          plan,
        );
        expect(
          const TournamentInvariantValidator().validate(request, plan),
          isEmpty,
        );
        final direct = plan.matches
            .expand((m) => [m.sideOne, m.sideTwo])
            .whereType<DirectTeamSource>()
            .map((s) => s.teamId)
            .toList();
        expect(direct.toSet(), request.teams.map((t) => t.team.id).toSet());
        expect(direct.length, n);
        final outgoing = <PlannedMatchKey, int>{};
        for (final m in plan.matches) {
          for (final s in [
            m.sideOne,
            m.sideTwo,
          ].whereType<MatchOutcomeSource>()) {
            expect(s.outcome, MatchDependencySource.winner);
            outgoing.update(s.matchKey, (v) => v + 1, ifAbsent: () => 1);
          }
        }
        expect(outgoing[plan.matches.last.key], isNull);
        for (final m in plan.matches.take(plan.matches.length - 1)) {
          expect(outgoing[m.key], 1);
        }
      },
    );
  }
  test('standard recursive seeds and highest seed byes', () {
    expect(SingleEliminationGenerator.seedPositions(4), [1, 4, 2, 3]);
    expect(SingleEliminationGenerator.seedPositions(5), [
      1,
      8,
      4,
      5,
      2,
      7,
      3,
      6,
    ]);
    final p = (generator.generate(
      fixtureRequest(teams: [for (var i = 3; i < 8; i++) fixtureTeam(i)]),
    ) as RepositorySuccess<TournamentPlan>).value;
    expect(p.matches.where((m) => m.round == 1).length, 1);
    expect(p.matches.first.sideOne.toJson(), {'teamId': fixtureId(6)});
    expect(p.matches.first.sideTwo.toJson(), {'teamId': fixtureId(7)});
  });
  test('unsupported formats and invalid input fail explicitly', () {
    expect(
      generator.generate(
        fixtureRequest(format: TournamentFormat.singleRoundRobin),
      ),
      isA<RepositoryFailure<TournamentPlan>>(),
    );
    expect(
      generator.generate(fixtureRequest(teams: [])),
      isA<RepositoryFailure<TournamentPlan>>(),
    );
    expect(
      generator.generate(
        fixtureRequest(
          teams: [fixtureTeam(3), fixtureTeam(4, deletedMember: true)],
        ),
      ),
      isA<RepositoryFailure<TournamentPlan>>(),
    );
  });
  test('progression, final placements and immutable correction audit', () {
    var bracket = makeBracket(4);
    final old = bracket;
    final keys = bracket.plan.matches.map((m) => m.key).toList();
    bracket = play(bracket, keys[0]);
    expect(old.matches[keys[0]]!.winnerTeamId, isNull);
    bracket = bracket.result(
      key: keys[0],
      score: ValidatedScore(9, 11),
      eventStatus: EventStatus.inProgress,
      expectedVersion: bracket.metadata.recordVersion,
      now: tick,
      operationId: SyncOperationId(fixtureId(900)),
      correctionReason: 'VPC test score correction',
    );
    expect(bracket.revisions, hasLength(1));
    expect(bracket.revisions.single.previous.sideOneScore, 11);
    expect(
      bracket.matches[keys[2]]!.sideOneTeamId,
      bracket.matches[keys[0]]!.sideTwoTeamId,
    );
    bracket = play(bracket, keys[1]);
    expect(bracket.matches[keys[2]]!.status, MatchStatus.queued);
    bracket = play(bracket, keys[2]);
    expect(bracket.champion, bracket.finalMatch.sideOneTeamId);
    expect(bracket.runnerUp, bracket.finalMatch.sideTwoTeamId);
    final completed = bracket;
    expect(
      () => completed.result(
        key: keys[0],
        score: ValidatedScore(11, 9),
        eventStatus: EventStatus.inProgress,
        expectedVersion: completed.metadata.recordVersion,
        now: tick,
        operationId: SyncOperationId(fixtureId(901)),
        correctionReason: 'test',
      ),
      throwsA(isA<TournamentGenerationFailure>()),
    );
    bracket = bracket.result(
      key: keys[2],
      score: ValidatedScore(8, 11),
      eventStatus: EventStatus.inProgress,
      expectedVersion: bracket.metadata.recordVersion,
      now: tick,
      operationId: SyncOperationId(fixtureId(902)),
      correctionReason: 'VPC final correction',
    );
    expect(bracket.champion, bracket.finalMatch.sideTwoTeamId);
    expect(bracket.revisions.length, 2);
  });
  test('lifecycle, reason, optimistic versions and explicit start guards', () {
    var bracket = makeBracket(2);
    final key = bracket.plan.matches.single.key;
    expect(
      () => bracket.result(
        key: key,
        score: ValidatedScore(11, 0),
        eventStatus: EventStatus.inProgress,
        expectedVersion: 0,
        now: tick,
        operationId: SyncOperationId(fixtureId(900)),
      ),
      throwsA(isA<TournamentGenerationFailure>()),
    );
    expect(bracket.mayRegenerate, isTrue);
    bracket = play(bracket, key);
    expect(bracket.mayRegenerate, isFalse);
    for (final status in [
      EventStatus.completed,
      EventStatus.archived,
      EventStatus.registration,
    ]) {
      expect(
        () => bracket.result(
          key: key,
          score: ValidatedScore(11, 2),
          eventStatus: status,
          expectedVersion: bracket.metadata.recordVersion,
          now: tick,
          operationId: SyncOperationId(fixtureId(900)),
          correctionReason: 'test',
        ),
        throwsA(isA<TournamentGenerationFailure>()),
      );
    }
    expect(
      () => bracket.result(
        key: key,
        score: ValidatedScore(11, 2),
        eventStatus: EventStatus.inProgress,
        expectedVersion: bracket.metadata.recordVersion,
        now: tick,
        operationId: SyncOperationId(fixtureId(900)),
        correctionReason: '  ',
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => bracket.start(key, EventStatus.inProgress, -1, tick),
      throwsA(isA<ConflictFailure>()),
    );
  });
}

final tick = DateTime.utc(2026, 9, 3);
SingleEliminationBracket makeBracket(int count) {
  final plan = (const SingleEliminationGenerator().generate(
    fixtureRequest(teams: [for (var i = 3; i < count + 3; i++) fixtureTeam(i)]),
  ) as RepositorySuccess<TournamentPlan>).value;
  final meta = RecordMetadata(
    createdAt: tick,
    updatedAt: tick,
    recordVersion: 0,
  );
  return SingleEliminationBracket(
    plan: plan,
    metadata: meta,
    matches: {
      for (var i = 0; i < plan.matches.length; i++)
        plan.matches[i].key: Match(
          id: MatchId(fixtureId(500 + i)),
          divisionId: fixtureDivision,
          status: plan.matches[i].status,
          metadata: meta,
          sideOneTeamId: plan.matches[i].sideOne is DirectTeamSource
              ? (plan.matches[i].sideOne as DirectTeamSource).teamId
              : null,
          sideTwoTeamId: plan.matches[i].sideTwo is DirectTeamSource
              ? (plan.matches[i].sideTwo as DirectTeamSource).teamId
              : null,
          roundNumber: plan.matches[i].round,
          sequenceNumber: i + 1,
        ),
    },
  );
}

SingleEliminationBracket play(SingleEliminationBracket b, PlannedMatchKey key) {
  final started = b.start(
    key,
    EventStatus.inProgress,
    b.metadata.recordVersion,
    tick,
  );
  return started.result(
    key: key,
    score: ValidatedScore(11, 0),
    eventStatus: EventStatus.inProgress,
    expectedVersion: started.metadata.recordVersion,
    now: tick,
    operationId: SyncOperationId(fixtureId(990)),
  );
}
