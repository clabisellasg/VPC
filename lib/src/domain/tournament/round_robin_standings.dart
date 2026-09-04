import '../common/domain_enums.dart';
import '../common/domain_failure.dart';
import '../common/entity_id.dart';
import '../matches/match.dart';
import 'round_robin_generator.dart';
import 'tournament_contracts.dart';

enum RoundRobinTieBreak {
  wins('Match wins'),
  miniWins('Tied-team match wins'),
  miniDifference('Tied-team point differential'),
  difference('Overall point differential'),
  points('Overall points scored'),
  seed('Original seed order');

  const RoundRobinTieBreak(this.label);
  final String label;
}

final class RoundRobinStanding {
  const RoundRobinStanding({
    required this.teamId,
    required this.seed,
    required this.rank,
    required this.played,
    required this.wins,
    required this.pointsFor,
    required this.pointsAgainst,
    required this.tieBreak,
  });
  final TeamId teamId;
  final int seed, rank, played, wins, pointsFor, pointsAgainst;
  final RoundRobinTieBreak tieBreak;
  int get losses => played - wins;
  int get difference => pointsFor - pointsAgainst;
}

/// Only actual completed active matches contribute. Each criterion partitions
/// its current subgroup; the next mini-table uses only that remaining subgroup.
List<RoundRobinStanding> calculateRoundRobinStandings({
  required TournamentPlan plan,
  required List<TeamId> seedOrder,
  required Iterable<Match> matches,
}) {
  void invalid() => throw const TournamentGenerationFailure(
    code: 'invalid_standings',
    message: 'Round-robin results do not match this schedule.',
  );
  if (!isRoundRobin(plan.format) ||
      seedOrder.length < 2 ||
      seedOrder.toSet().length != seedOrder.length) {
    invalid();
  }
  final expected = <String, PlannedMatch>{};
  for (final planned in plan.matches) {
    final key = '${planned.round}/${planned.key.value.split('/m').last}';
    if (expected.containsKey(key) ||
        planned.eventId != plan.eventId ||
        planned.divisionId != plan.divisionId ||
        planned.sideOne is! DirectTeamSource ||
        planned.sideTwo is! DirectTeamSource) {
      invalid();
    }
    expected[key] = planned;
  }
  final completed = <Match>[], ids = <MatchId>{}, positions = <String>{};
  for (final match in matches) {
    if (match.metadata.isDeleted) continue;
    final position = '${match.roundNumber}/${match.sequenceNumber}';
    final planned = expected[position];
    if (!ids.add(match.id) ||
        !positions.add(position) ||
        match.divisionId != plan.divisionId ||
        planned == null ||
        match.sideOneTeamId != (planned.sideOne as DirectTeamSource).teamId ||
        match.sideTwoTeamId != (planned.sideTwo as DirectTeamSource).teamId ||
        !seedOrder.contains(match.sideOneTeamId) ||
        !seedOrder.contains(match.sideTwoTeamId)) {
      invalid();
    }
    if (match.status == MatchStatus.completed) completed.add(match);
  }
  (int, int, int, int) totals(TeamId team, Set<TeamId> group) {
    var played = 0, wins = 0, scored = 0, allowed = 0;
    for (final m in completed) {
      if (!group.contains(m.sideOneTeamId) ||
          !group.contains(m.sideTwoTeamId)) {
        continue;
      }
      final first = m.sideOneTeamId == team;
      if (!first && m.sideTwoTeamId != team) continue;
      played++;
      if (m.winnerTeamId == team) wins++;
      scored += first ? m.sideOneScore! : m.sideTwoScore!;
      allowed += first ? m.sideTwoScore! : m.sideOneScore!;
    }
    return (played, wins, scored, allowed);
  }

  final all = seedOrder.toSet();
  final overall = {for (final t in seedOrder) t: totals(t, all)};
  final explanations = <TeamId, RoundRobinTieBreak>{};
  List<TeamId> rank(List<TeamId> group, int stage) {
    if (group.length <= 1) return group;
    final criterion = RoundRobinTieBreak.values[stage];
    int value(TeamId team) {
      final total = overall[team]!;
      final mini = (stage == 1 || stage == 2)
          ? totals(team, group.toSet())
          : total;
      return switch (criterion) {
        RoundRobinTieBreak.wins => total.$2,
        RoundRobinTieBreak.miniWins => mini.$2,
        RoundRobinTieBreak.miniDifference => mini.$3 - mini.$4,
        RoundRobinTieBreak.difference => total.$3 - total.$4,
        RoundRobinTieBreak.points => total.$3,
        RoundRobinTieBreak.seed => -seedOrder.indexOf(team),
      };
    }

    final buckets = <int, List<TeamId>>{};
    for (final t in group) {
      (buckets[value(t)] ??= []).add(t);
    }
    final keys = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    if (keys.length > 1) {
      for (final t in group) {
        explanations[t] = criterion;
      }
    }
    return [for (final k in keys) ...rank(buckets[k]!, stage + 1)];
  }

  final ordered = rank(seedOrder.toList(), 0);
  return List.unmodifiable([
    for (var i = 0; i < ordered.length; i++)
      RoundRobinStanding(
        teamId: ordered[i],
        seed: seedOrder.indexOf(ordered[i]) + 1,
        rank: i + 1,
        played: overall[ordered[i]]!.$1,
        wins: overall[ordered[i]]!.$2,
        pointsFor: overall[ordered[i]]!.$3,
        pointsAgainst: overall[ordered[i]]!.$4,
        tieBreak: explanations[ordered[i]] ?? RoundRobinTieBreak.seed,
      ),
  ]);
}
