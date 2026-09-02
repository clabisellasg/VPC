import '../common/domain_enums.dart';
import '../common/domain_failure.dart';
import '../common/entity_id.dart';
import 'tournament_contracts.dart';

final class TournamentInvariantValidator {
  const TournamentInvariantValidator();
  List<TournamentGenerationFailure> validate(
    TournamentGenerationRequest request,
    TournamentPlan plan, {
    bool forbidRepeatedDirectTeams = true,
  }) {
    final errors = <TournamentGenerationFailure>[];
    void fail(String code) => errors.add(
      TournamentGenerationFailure(
        code: code,
        message: 'Tournament invariant failed: $code.',
      ),
    );
    if (request.eventId != request.division.eventId ||
        request.division.metadata.isDeleted ||
        plan.eventId != request.eventId ||
        plan.divisionId != request.division.id) {
      fail('incompatible_scope');
    }
    if (request.division.format == null ||
        request.division.format != plan.format) {
      fail('invalid_format');
    }
    if (request.teams.length < 2) fail('insufficient_teams');
    try {
      request.canonicalTeams;
    } on TournamentGenerationFailure {
      fail('invalid_order');
    }
    final teams = <TeamId>{};
    final players = <PlayerId>{};
    for (final entry in request.teams) {
      final team = entry.team;
      if (!teams.add(team.id)) fail('duplicate_team');
      if (team.divisionId != request.division.id) fail('team_outside_division');
      if (team.metadata.isDeleted) fail('tombstoned_team');
      if (entry.members.length != 2 ||
          !entry.members.keys.toSet().containsAll(team.memberIds)) {
        fail('incomplete_team');
      }
      for (final member in entry.members.entries) {
        if (member.value.isDeleted) fail('tombstoned_member');
        if (!players.add(member.key)) fail('duplicate_membership');
      }
    }
    final byKey = <PlannedMatchKey, PlannedMatch>{};
    if (plan.matches.isEmpty) fail('empty_plan');
    for (final match in plan.matches) {
      if (byKey.containsKey(match.key)) fail('duplicate_match_key');
      byKey[match.key] = match;
    }
    final placed = <TeamId>{};
    for (final match in plan.matches) {
      if (match.eventId != request.eventId ||
          match.divisionId != request.division.id) {
        fail('incompatible_scope');
      }
      if (match.round < 1 || match.section.trim().isEmpty) {
        fail('invalid_round');
      }
      for (final source in [match.sideOne, match.sideTwo]) {
        switch (source) {
          case DirectTeamSource(:final teamId):
            if (!teams.contains(teamId)) fail('unknown_team');
            if (!placed.add(teamId) && forbidRepeatedDirectTeams) {
              fail('duplicate_direct_team');
            }
          case MatchOutcomeSource(:final matchKey):
            if (matchKey == match.key) fail('self_dependency');
            if (!byKey.containsKey(matchKey)) fail('missing_match');
        }
      }
      if (match.sideOne is MatchOutcomeSource &&
          match.sideTwo is MatchOutcomeSource) {
        final one = match.sideOne as MatchOutcomeSource;
        final two = match.sideTwo as MatchOutcomeSource;
        if (one.matchKey == two.matchKey && one.outcome == two.outcome) {
          fail('duplicate_outcome');
        }
      }
      final one = match.sideOne;
      final two = match.sideTwo;
      if (one is DirectTeamSource &&
          two is DirectTeamSource &&
          one.teamId == two.teamId) {
        fail('self_play');
      }
      if (match.status == MatchStatus.completed) {
        if (one is! DirectTeamSource ||
            two is! DirectTeamSource ||
            match.finalScore == null ||
            match.winner !=
                (match.finalScore!.sideOneWins ? one.teamId : two.teamId)) {
          fail('invalid_result');
        }
      } else if (match.winner != null || match.finalScore != null) {
        fail('invalid_result');
      }
    }
    // Iterative topological traversal avoids recursion limits and never advances outcomes.
    final remaining = byKey.keys.toSet();
    while (remaining.isNotEmpty) {
      final ready = remaining
          .where(
            (key) => [byKey[key]!.sideOne, byKey[key]!.sideTwo]
                .whereType<MatchOutcomeSource>()
                .every((s) => !remaining.contains(s.matchKey)),
          )
          .toList();
      if (ready.isEmpty) {
        fail('cyclic_dependencies');
        break;
      }
      remaining.removeAll(ready);
    }
    return List.unmodifiable(errors);
  }
}
