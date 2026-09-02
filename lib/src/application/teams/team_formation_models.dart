import 'dart:collection';

import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/players/player_skill.dart';

final class EligibleTeamPlayer {
  const EligibleTeamPlayer({
    required this.playerId,
    required this.displayName,
    required this.skill,
    required this.paid,
  });

  final PlayerId playerId;
  final String displayName;
  final PlayerSkill? skill;
  final bool paid;
}

final class TeamDraft {
  TeamDraft({
    required this.id,
    required Iterable<EligibleTeamPlayer> players,
    required this.method,
    this.recordVersion = 0,
  }) : players = UnmodifiableListView(players.toList(growable: false)) {
    if (this.players.length != 2 ||
        this.players[0].playerId == this.players[1].playerId) {
      throw const ValidationFailure(
        field: 'players',
        message: 'A draft team requires two different eligible players.',
      );
    }
  }

  final TeamId id;
  final UnmodifiableListView<EligibleTeamPlayer> players;
  final TeamFormationMethod method;
  final int recordVersion;

  int? get strength {
    final first = players[0].skill;
    final second = players[1].skill;
    return first == null || second == null ? null : first.value + second.value;
  }
}

final class TeamFormationPreview {
  TeamFormationPreview({
    required Iterable<TeamDraft> teams,
    required Iterable<EligibleTeamPlayer> unassigned,
    required Iterable<EligibleTeamPlayer> unrated,
    required this.method,
    Map<TeamId, int> baseTeamVersions = const {},
  }) : teams = UnmodifiableListView(teams.toList(growable: false)),
       unassigned = UnmodifiableListView(unassigned.toList(growable: false)),
       unrated = UnmodifiableListView(unrated.toList(growable: false)),
       baseTeamVersions = UnmodifiableMapView(baseTeamVersions);

  final UnmodifiableListView<TeamDraft> teams;
  final UnmodifiableListView<EligibleTeamPlayer> unassigned;
  final UnmodifiableListView<EligibleTeamPlayer> unrated;
  final TeamFormationMethod method;
  final UnmodifiableMapView<TeamId, int> baseTeamVersions;

  int? get spread {
    final strengths = teams.map((team) => team.strength).toList();
    if (strengths.isEmpty || strengths.any((value) => value == null)) {
      return null;
    }
    final values = strengths.cast<int>();
    return values.reduce((a, b) => a > b ? a : b) -
        values.reduce((a, b) => a < b ? a : b);
  }
}

enum TeamMutationDisposition { pending, synchronized, blocked, conflicted }

final class TeamFormationSnapshot {
  TeamFormationSnapshot({
    required this.eventId,
    required this.divisionId,
    required this.eventStatus,
    required Iterable<EligibleTeamPlayer> eligiblePlayers,
    required Iterable<TeamDraft> teams,
    this.disposition = TeamMutationDisposition.synchronized,
  }) : eligiblePlayers = UnmodifiableListView(eligiblePlayers.toList()),
       teams = UnmodifiableListView(teams.toList());

  final EventId eventId;
  final DivisionId divisionId;
  final EventStatus eventStatus;
  final UnmodifiableListView<EligibleTeamPlayer> eligiblePlayers;
  final UnmodifiableListView<TeamDraft> teams;
  final TeamMutationDisposition disposition;
}
