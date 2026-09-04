import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'team_formation_contracts.dart';
import 'team_formation_models.dart';

final class TeamFormationService {
  const TeamFormationService({
    required this.store,
    required this.ids,
    required this.random,
  });

  final TeamFormationStore store;
  final TeamIdFactory ids;
  final TeamRandomSource random;

  TeamFormationPreview manual(
    TeamFormationSnapshot snapshot,
    EligibleTeamPlayer first,
    EligibleTeamPlayer second, {
    TeamFormationPreview? currentPreview,
  }) {
    _requireRegistration(snapshot);
    _requireEligible(snapshot, first);
    _requireEligible(snapshot, second);
    final previewTeams = currentPreview?.teams;
    final sourceTeams = previewTeams ?? snapshot.teams;
    final alreadyAssigned = sourceTeams
        .expand((team) => team.players)
        .map((player) => player.playerId)
        .toSet();
    if (alreadyAssigned.contains(first.playerId) ||
        alreadyAssigned.contains(second.playerId)) {
      throw const ConflictFailure(
        message: 'A selected player is already assigned.',
      );
    }
    return TeamFormationPreview(
      teams: [
        ...(previewTeams ?? snapshot.teams.map(_replacementCopy)),
        TeamDraft(
          id: ids.nextTeamId(),
          players: [first, second],
          method: TeamFormationMethod.manual,
        ),
      ],
      unassigned: _unassigned(snapshot.eligiblePlayers, [
        ...sourceTeams.expand((team) => team.players),
        first,
        second,
      ]),
      unrated: const [],
      method: TeamFormationMethod.manual,
      baseTeamVersions:
          currentPreview?.baseTeamVersions ??
          {for (final team in snapshot.teams) team.id: team.recordVersion},
    );
  }

  TeamFormationPreview releaseTeam(
    TeamFormationSnapshot snapshot,
    TeamId teamId,
  ) {
    _requireRegistration(snapshot);
    if (!snapshot.teams.any((team) => team.id == teamId)) {
      throw const ValidationFailure(
        field: 'team',
        message: 'The selected team is not active in this division.',
      );
    }
    final retained = snapshot.teams
        .where((team) => team.id != teamId)
        .map(_replacementCopy)
        .toList();
    return TeamFormationPreview(
      teams: retained,
      unassigned: _unassigned(
        snapshot.eligiblePlayers,
        retained.expand((team) => team.players),
      ),
      unrated: const [],
      method: TeamFormationMethod.manual,
      baseTeamVersions: {
        for (final team in snapshot.teams) team.id: team.recordVersion,
      },
    );
  }

  TeamFormationPreview removePreviewTeam(
    TeamFormationSnapshot snapshot,
    TeamFormationPreview preview,
    TeamId teamId,
  ) {
    _requireRegistration(snapshot);
    if (!preview.teams.any((team) => team.id == teamId)) {
      throw const ValidationFailure(
        field: 'team',
        message: 'The selected preview team is not available.',
      );
    }
    final retained = preview.teams.where((team) => team.id != teamId).toList();
    return TeamFormationPreview(
      teams: retained,
      unassigned: _unassigned(
        snapshot.eligiblePlayers,
        retained.expand((team) => team.players),
      ),
      unrated: const [],
      method: preview.method,
      baseTeamVersions: preview.baseTeamVersions,
    );
  }

  TeamDraft _replacementCopy(TeamDraft team) => TeamDraft(
    id: ids.nextTeamId(),
    players: team.players,
    method: team.method,
  );

  TeamFormationPreview randomPreview(TeamFormationSnapshot snapshot) {
    _requireRegistration(snapshot);
    return _pair(
      random.shuffled(snapshot.eligiblePlayers.toList()),
      TeamFormationMethod.random,
      snapshot,
    );
  }

  TeamFormationPreview balancedPreview(TeamFormationSnapshot snapshot) {
    _requireRegistration(snapshot);
    final unrated = snapshot.eligiblePlayers
        .where((player) => player.skill == null)
        .toList();
    if (unrated.isNotEmpty) {
      return TeamFormationPreview(
        teams: const [],
        unassigned: snapshot.eligiblePlayers,
        unrated: unrated,
        method: TeamFormationMethod.balanced,
      );
    }
    final sorted = snapshot.eligiblePlayers.toList()
      ..sort((a, b) {
        final bySkill = b.skill!.value.compareTo(a.skill!.value);
        return bySkill != 0
            ? bySkill
            : a.playerId.value.compareTo(b.playerId.value);
      });
    final pairedOrder = <EligibleTeamPlayer>[];
    var left = 0;
    var right = sorted.length - 1;
    while (left < right) {
      pairedOrder
        ..add(sorted[left++])
        ..add(sorted[right--]);
    }
    if (left == right) pairedOrder.add(sorted[left]);
    return _pair(pairedOrder, TeamFormationMethod.balanced, snapshot);
  }

  Future<RepositoryResult<TeamFormationSnapshot>> confirm(
    TeamFormationSnapshot current,
    TeamFormationPreview preview,
  ) {
    _requireRegistration(current);
    if (preview.unrated.isNotEmpty) {
      return Future.value(
        const RepositoryFailure(
          ValidationFailure(
            field: 'skillLevel',
            message: 'Every eligible player must be rated before balanced generation.',
          ),
        ),
      );
    }
    return store.replace(
      current: current,
      preview: preview,
      operationId: ids.nextOperationId(),
    );
  }

  TeamFormationPreview _pair(
    List<EligibleTeamPlayer> players,
    TeamFormationMethod method,
    TeamFormationSnapshot snapshot,
  ) {
    final teams = <TeamDraft>[];
    var index = 0;
    while (index + 1 < players.length) {
      teams.add(
        TeamDraft(
          id: ids.nextTeamId(),
          players: [players[index], players[index + 1]],
          method: method,
        ),
      );
      index += 2;
    }
    return TeamFormationPreview(
      teams: teams,
      unassigned: index < players.length ? [players[index]] : const [],
      unrated: const [],
      method: method,
      baseTeamVersions: {
        for (final team in snapshot.teams) team.id: team.recordVersion,
      },
    );
  }

  void _requireRegistration(TeamFormationSnapshot snapshot) {
    if (snapshot.eventStatus != EventStatus.registration) {
      throw const InvalidStateTransitionFailure(
        entity: 'Team formation',
        from: 'locked',
        to: 'change teams',
      );
    }
  }

  void _requireEligible(
    TeamFormationSnapshot snapshot,
    EligibleTeamPlayer player,
  ) {
    if (!snapshot.eligiblePlayers.any(
      (value) => value.playerId == player.playerId,
    )) {
      throw const ValidationFailure(
        field: 'player',
        message: 'The selected player is not eligible for this division.',
      );
    }
  }

  List<EligibleTeamPlayer> _unassigned(
    Iterable<EligibleTeamPlayer> all,
    Iterable<EligibleTeamPlayer> assigned,
  ) {
    final ids = assigned.map((player) => player.playerId).toSet();
    return all.where((player) => !ids.contains(player.playerId)).toList();
  }
}
