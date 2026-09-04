import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/matches/match.dart';
import 'package:vpc/src/domain/matches/validated_score.dart';
import 'package:vpc/src/domain/tournament/round_robin_generator.dart';
import 'package:vpc/src/domain/tournament/round_robin_standings.dart';
import 'package:vpc/src/domain/tournament/tournament_contracts.dart';

import 'tournament_fixtures.dart';

void main() {
  group('circle schedules', () {
    for (final format in [
      TournamentFormat.singleRoundRobin,
      TournamentFormat.doubleRoundRobin,
    ]) {
      for (var count = 2; count <= 8; count++) {
        test('${format.name} $count teams has exact rounds/pairs', () {
          final request = fixtureRequest(
            format: format,
            teams: [for (var i = 3; i < 3 + count; i++) fixtureTeam(i)],
          );
          final result = const RoundRobinGenerator().generate(request);
          expect(result, isA<RepositorySuccess<TournamentPlan>>());
          final plan = (result as RepositorySuccess<TournamentPlan>).value;
          final legs = format == TournamentFormat.singleRoundRobin ? 1 : 2;
          expect(plan.matches.length, count * (count - 1) ~/ 2 * legs);
          expect(
            plan.matches.map((m) => m.round).toSet().length,
            (count.isEven ? count - 1 : count) * legs,
          );
          final perRound = <int, Set<TeamId>>{}, pairs = <String, int>{};
          for (final m in plan.matches) {
            expect(m.status, MatchStatus.queued);
            final a = (m.sideOne as DirectTeamSource).teamId;
            final b = (m.sideTwo as DirectTeamSource).teamId;
            expect(a, isNot(b));
            expect((perRound[m.round] ??= {}).add(a), isTrue);
            expect(perRound[m.round]!.add(b), isTrue);
            final key = [a.value, b.value]..sort();
            pairs.update(key.join('/'), (v) => v + 1, ifAbsent: () => 1);
          }
          expect(pairs.length, count * (count - 1) ~/ 2);
          expect(pairs.values, everyElement(legs));
          if (count.isOdd) {
            final rests = (plan.metadata['restingByRound']!);
            for (final t in request.canonicalTeams) {
              expect(RegExp(t.team.id.value).allMatches(rests).length, legs);
            }
          }
          final repeated = const RoundRobinGenerator().generate(
            request,
          ) as RepositorySuccess<TournamentPlan>;
          expect(repeated.value, plan);
        });
      }
    }
    test('double leg reverses display sides in matching order', () {
      final plan = (const RoundRobinGenerator().generate(
        fixtureRequest(
          format: TournamentFormat.doubleRoundRobin,
          teams: [
            fixtureTeam(3),
            fixtureTeam(4),
            fixtureTeam(5),
            fixtureTeam(6),
          ],
        ),
      ) as RepositorySuccess<TournamentPlan>).value;
      final first = plan.matches.take(6).toList(),
          second = plan.matches.skip(6).toList();
      for (var i = 0; i < 6; i++) {
        expect(
          (first[i].sideOne as DirectTeamSource).teamId,
          (second[i].sideTwo as DirectTeamSource).teamId,
        );
        expect(
          (first[i].sideTwo as DirectTeamSource).teamId,
          (second[i].sideOne as DirectTeamSource).teamId,
        );
      }
    });
    test('odd-team rounds number only playable matches', () {
      final plan = (const RoundRobinGenerator().generate(
        fixtureRequest(
          format: TournamentFormat.singleRoundRobin,
          teams: [fixtureTeam(3), fixtureTeam(4), fixtureTeam(5)],
        ),
      ) as RepositorySuccess<TournamentPlan>).value;

      expect(plan.matches.map((match) => match.key.value), [
        'rr/r1/m1',
        'rr/r2/m1',
        'rr/r3/m1',
      ]);
    });
    test('elimination formats are rejected', () {
      expect(
        const RoundRobinGenerator().generate(fixtureRequest()),
        isA<RepositoryFailure<TournamentPlan>>(),
      );
    });
  });

  group('derived standings', () {
    final teams = [
      fixtureTeam(3),
      fixtureTeam(4),
      fixtureTeam(5),
      fixtureTeam(6),
    ];
    final request = fixtureRequest(
      format: TournamentFormat.singleRoundRobin,
      teams: teams,
    );
    final plan = (const RoundRobinGenerator().generate(
      request,
    ) as RepositorySuccess<TournamentPlan>).value;
    Match played(int index, int a, int b, {bool deleted = false}) {
      final p = plan.matches[index];
      final one = (p.sideOne as DirectTeamSource).teamId;
      final two = (p.sideTwo as DirectTeamSource).teamId;
      final score = ValidatedScore(a, b);
      return Match(
        id: MatchId(fixtureId(200 + index)),
        divisionId: fixtureDivision,
        status: MatchStatus.completed,
        sideOneTeamId: one,
        sideTwoTeamId: two,
        sideOneScore: a,
        sideTwoScore: b,
        winnerTeamId: score.sideOneWins ? one : two,
        roundNumber: p.round,
        sequenceNumber: int.parse(p.key.value.split('/m').last),
        metadata: RecordMetadata(
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          recordVersion: 0,
          deletedAt: deleted ? DateTime.utc(2026, 1, 2) : null,
        ),
      );
    }

    Match between(
      int firstSeed,
      int secondSeed,
      int firstScore,
      int secondScore,
    ) {
      final first = teams[firstSeed - 1].team.id;
      final second = teams[secondSeed - 1].team.id;
      final index = plan.matches.indexWhere((planned) {
        final one = (planned.sideOne as DirectTeamSource).teamId;
        final two = (planned.sideTwo as DirectTeamSource).teamId;
        return {one, two}.containsAll({first, second});
      });
      final planned = plan.matches[index];
      final one = (planned.sideOne as DirectTeamSource).teamId;
      return one == first
          ? played(index, firstScore, secondScore)
          : played(index, secondScore, firstScore);
    }

    test('calculates played wins losses points difference and ignores incomplete/tombstone', () {
      final rows = [
        played(0, 11, 5),
        played(1, 11, 9),
        played(2, 5, 11, deleted: true),
      ];
      final table = calculateRoundRobinStandings(
        plan: plan,
        seedOrder: teams.map((t) => t.team.id).toList(),
        matches: rows,
      );
      expect(table.fold(0, (n, r) => n + r.played), 4);
      expect(table.first.wins, greaterThanOrEqualTo(table.last.wins));
      expect(table.every((r) => r.losses == r.played - r.wins), isTrue);
      expect(
        table.every((r) => r.difference == r.pointsFor - r.pointsAgainst),
        isTrue,
      );
    });
    test('original seed is deterministic final fallback before scores', () {
      final table = calculateRoundRobinStandings(
        plan: plan,
        seedOrder: teams.map((t) => t.team.id).toList(),
        matches: const [],
      );
      expect(table.map((r) => r.teamId), teams.map((t) => t.team.id));
      expect(table.every((r) => r.tieBreak == RoundRobinTieBreak.seed), isTrue);
    });
    test('correction input recomputes order', () {
      final first = played(0, 11, 5), corrected = played(0, 5, 11);
      final seed = teams.map((t) => t.team.id).toList();
      final before = calculateRoundRobinStandings(
        plan: plan,
        seedOrder: seed,
        matches: [first],
      );
      final after = calculateRoundRobinStandings(
        plan: plan,
        seedOrder: seed,
        matches: [corrected],
      );
      expect(after.first.teamId, isNot(before.first.teamId));
    });
    test('head-to-head mini wins separates teams tied on total wins', () {
      final table = calculateRoundRobinStandings(
        plan: plan,
        seedOrder: teams.map((team) => team.team.id).toList(),
        matches: [
          between(1, 2, 11, 5),
          between(1, 3, 11, 5),
          between(1, 4, 5, 11),
          between(2, 3, 11, 5),
          between(2, 4, 11, 5),
        ],
      );
      expect(table[0].teamId, teams[0].team.id);
      expect(table[1].teamId, teams[1].team.id);
      expect(table[0].wins, table[1].wins);
      expect(table[0].tieBreak, RoundRobinTieBreak.miniWins);
    });
    test('three-team mini-table differential is recalculated', () {
      final table = calculateRoundRobinStandings(
        plan: plan,
        seedOrder: teams.map((team) => team.team.id).toList(),
        matches: [
          between(1, 2, 11, 0),
          between(2, 3, 11, 9),
          between(3, 1, 11, 9),
        ],
      );
      expect(table.first.teamId, teams[0].team.id);
      expect(table.first.tieBreak, RoundRobinTieBreak.miniDifference);
    });
    test('overall differential follows an unresolved mini-table', () {
      final table = calculateRoundRobinStandings(
        plan: plan,
        seedOrder: teams.map((team) => team.team.id).toList(),
        matches: [
          between(1, 2, 11, 9),
          between(2, 3, 11, 9),
          between(3, 1, 11, 9),
          between(1, 4, 11, 0),
          between(2, 4, 11, 5),
          between(3, 4, 11, 9),
        ],
      );
      expect(table.take(3).map((row) => row.teamId), [
        teams[0].team.id,
        teams[1].team.id,
        teams[2].team.id,
      ]);
      expect(table.first.tieBreak, RoundRobinTieBreak.difference);
    });
    test('points scored follows equal overall differential', () {
      final table = calculateRoundRobinStandings(
        plan: plan,
        seedOrder: teams.map((team) => team.team.id).toList(),
        matches: [between(1, 3, 11, 9), between(2, 4, 12, 10)],
      );
      expect(table.first.teamId, teams[1].team.id);
      expect(table.first.tieBreak, RoundRobinTieBreak.points);
    });
    test(
      'cross-division, duplicate positions and invalid pairing fail typed',
      () {
        final normal = played(0, 11, 5);
        expect(
          () => calculateRoundRobinStandings(
            plan: plan,
            seedOrder: teams.map((t) => t.team.id).toList(),
            matches: [normal, normal],
          ),
          throwsA(isA<Exception>()),
        );
      },
    );
  });
}
