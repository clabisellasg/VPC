import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/matches/validated_score.dart';
import 'package:vpc/src/domain/tournament/tournament_contracts.dart';
import 'package:vpc/src/domain/tournament/tournament_invariant_validator.dart';

import 'generator_conformance.dart';
import 'tournament_fixtures.dart';

void main() {
  for (final scores in [(11, 0), (11, 9), (12, 10), (15, 13), (1002, 1000)]) {
    test('valid final score $scores derives both winner orientations', () {
      for (final pair in [scores, (scores.$2, scores.$1)]) {
        final score = ValidatedScore(pair.$1, pair.$2);
        expect(score, ValidatedScore(pair.$1, pair.$2));
        expect(
          MatchResult(
            sideOne: TeamId(fixtureId(3)),
            sideTwo: TeamId(fixtureId(4)),
            score: score,
          ).winner,
          TeamId(fixtureId(pair.$1 > pair.$2 ? 3 : 4)),
        );
      }
    });
  }
  for (final scores in [
    (10, 8),
    (11, 10),
    (12, 9),
    (13, 10),
    (0, 0),
    (11, 11),
    (-1, 11),
    (11, -1),
  ]) {
    test(
      'invalid score $scores is typed',
      () => expect(
        () => ValidatedScore(scores.$1, scores.$2),
        throwsA(isA<ValidationFailure>()),
      ),
    );
  }
  test('canonical input, explicit order and fixture conformance', () {
    verifyGeneratorConformance(FixtureOnlyGenerator(), fixtureRequest());
    verifyGeneratorConformance(
      FixtureOnlyGenerator(),
      fixtureRequest(order: [TeamId(fixtureId(4)), TeamId(fixtureId(3))]),
    );
    expect(() => fixtureRequest().teams.clear(), throwsUnsupportedError);
    expect(
      () => fixturePlan([fixtureMatch('1')]).matches.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => PlannedMatchKey(''),
      throwsA(isA<TournamentGenerationFailure>()),
    );
  });
  test('all four formats deliberately return unimplemented failures', () {
    expect(TournamentFormat.values, hasLength(4));
    for (final format in TournamentFormat.values) {
      final result = const UnimplementedTournamentGenerator().generate(
        fixtureRequest(format: format),
      );
      expect(
        (result as RepositoryFailure<TournamentPlan>).failure,
        isA<TournamentGenerationFailure>(),
      );
    }
  });
  final invalidInputs = <String, TournamentGenerationRequest>{
    'insufficient_teams': fixtureRequest(teams: []),
    'invalid_format': fixtureRequest(format: null),
    'invalid_order': fixtureRequest(order: [TeamId(fixtureId(3))]),
    'duplicate_team': fixtureRequest(teams: [fixtureTeam(3), fixtureTeam(3)]),
    'tombstoned_team': fixtureRequest(
      teams: [fixtureTeam(3, deleted: true), fixtureTeam(4)],
    ),
    'tombstoned_member': fixtureRequest(
      teams: [fixtureTeam(3, deletedMember: true), fixtureTeam(4)],
    ),
    'incomplete_team': fixtureRequest(
      teams: [fixtureTeam(3, incomplete: true), fixtureTeam(4)],
    ),
    'team_outside_division': fixtureRequest(
      teams: [
        fixtureTeam(3, division: DivisionId(fixtureId(99))),
        fixtureTeam(4),
      ],
    ),
  };
  for (final entry in invalidInputs.entries) {
    test('input invariant ${entry.key}', () {
      expect(
        const TournamentInvariantValidator()
            .validate(entry.value, fixturePlan([fixtureMatch('1')]))
            .map((e) => e.code),
        contains(entry.key),
      );
    });
  }
  final invalidPlans = <String, List<PlannedMatch>>{
    'empty_plan': [],
    'duplicate_match_key': [fixtureMatch('1'), fixtureMatch('1')],
    'duplicate_direct_team': [fixtureMatch('1'), fixtureMatch('2')],
    'self_play': [
      fixtureMatch('1', two: DirectTeamSource(TeamId(fixtureId(3)))),
    ],
    'unknown_team': [
      fixtureMatch('1', one: DirectTeamSource(TeamId(fixtureId(99)))),
    ],
    'incompatible_scope': [fixtureMatch('1', event: EventId(fixtureId(99)))],
    'invalid_result': [fixtureMatch('1', status: MatchStatus.completed)],
    'self_dependency': [
      fixtureMatch(
        '1',
        one: MatchOutcomeSource(
          PlannedMatchKey('1'),
          MatchDependencySource.winner,
        ),
      ),
    ],
    'missing_match': [
      fixtureMatch(
        '1',
        one: MatchOutcomeSource(
          PlannedMatchKey('absent'),
          MatchDependencySource.loser,
        ),
      ),
    ],
    'cyclic_dependencies': [
      fixtureMatch(
        '1',
        one: MatchOutcomeSource(
          PlannedMatchKey('2'),
          MatchDependencySource.winner,
        ),
      ),
      fixtureMatch(
        '2',
        one: MatchOutcomeSource(
          PlannedMatchKey('1'),
          MatchDependencySource.loser,
        ),
      ),
    ],
    'duplicate_outcome': [
      fixtureMatch(
        '1',
        one: MatchOutcomeSource(
          PlannedMatchKey('2'),
          MatchDependencySource.winner,
        ),
        two: MatchOutcomeSource(
          PlannedMatchKey('2'),
          MatchDependencySource.winner,
        ),
      ),
      fixtureMatch('2'),
    ],
  };
  for (final entry in invalidPlans.entries) {
    test(
      'plan invariant ${entry.key}',
      () => expect(
        const TournamentInvariantValidator()
            .validate(fixtureRequest(), fixturePlan(entry.value))
            .map((e) => e.code),
        contains(entry.key),
      ),
    );
  }
  test(
    'winner and loser references validate without executing progression',
    () {
      final plan = fixturePlan([
        fixtureMatch('1'),
        fixtureMatch(
          '2',
          one: MatchOutcomeSource(
            PlannedMatchKey('1'),
            MatchDependencySource.winner,
          ),
          two: MatchOutcomeSource(
            PlannedMatchKey('1'),
            MatchDependencySource.loser,
          ),
        ),
      ]);
      expect(
        const TournamentInvariantValidator().validate(fixtureRequest(), plan),
        isEmpty,
      );
      expect(plan.matches.last.sideOne, isA<MatchOutcomeSource>());
    },
  );
}
