import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/teams/team_formation_contracts.dart';
import 'package:vpc/src/application/teams/team_formation_models.dart';
import 'package:vpc/src/application/teams/team_formation_service.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/players/player_skill.dart';

void main() {
  final ids = _Ids();
  final service = TeamFormationService(
    store: _Store(),
    ids: ids,
    random: const _ReverseRandom(),
  );
  TeamFormationSnapshot snapshot(List<int?> skills) => TeamFormationSnapshot(
    eventId: EventId('00000000-0000-4000-8000-000000000101'),
    divisionId: DivisionId('00000000-0000-4000-8000-000000000102'),
    eventStatus: EventStatus.registration,
    eligiblePlayers: [
      for (var i = 0; i < skills.length; i++)
        EligibleTeamPlayer(
          playerId: PlayerId(
            '00000000-0000-4000-8000-${(i + 1).toString().padLeft(12, '0')}',
          ),
          displayName: 'Player ${i + 1}',
          skill: skills[i] == null ? null : PlayerSkill(skills[i]!),
          paid: i.isEven,
        ),
    ],
    teams: const [],
  );

  test('skill scale preserves null and validates 1 through 5', () {
    expect(PlayerSkill(1).label, 'Beginner');
    expect(PlayerSkill(5).label, 'Competitive');
    expect(playerSkillLabel(null), 'Unrated');
    expect(() => PlayerSkill(0), throwsException);
    expect(() => PlayerSkill(6), throwsException);
  });
  test('random preview is deterministic and leaves odd player unassigned', () {
    final first = service.randomPreview(snapshot([1, 2, 3, 4, 5]));
    final second = service.randomPreview(snapshot([1, 2, 3, 4, 5]));
    expect(
      first.teams
          .map((t) => t.players.map((p) => p.playerId.value).toList())
          .toList(),
      second.teams
          .map((t) => t.players.map((p) => p.playerId.value).toList())
          .toList(),
    );
    expect(first.unassigned, hasLength(1));
  });
  test('balanced pairs strongest with weakest and calculates spread', () {
    final preview = service.balancedPreview(snapshot([5, 4, 3, 2, 1]));
    expect(preview.teams[0].strength, 6);
    expect(preview.teams[1].strength, 6);
    expect(preview.spread, 0);
    expect(preview.unassigned.single.skill!.value, 3);
  });
  test('balanced preview blocks and lists unrated players', () {
    final preview = service.balancedPreview(snapshot([5, null, 1, 2]));
    expect(preview.teams, isEmpty);
    expect(preview.unrated.single.displayName, 'Player 2');
  });
  test('preview does not persist before explicit confirmation', () {
    final store = _Store();
    final local = TeamFormationService(
      store: store,
      ids: _Ids(),
      random: const _ReverseRandom(),
    );
    final preview = local.randomPreview(snapshot([1, 2]));
    expect(store.replacements, 0);
    local.confirm(snapshot([1, 2]), preview);
    expect(store.replacements, 1);
  });
  test('releasing a confirmed team returns both players to unassigned', () {
    final initial = snapshot([5, 1, 4, 2]);
    final confirmed = TeamFormationSnapshot(
      eventId: initial.eventId,
      divisionId: initial.divisionId,
      eventStatus: initial.eventStatus,
      eligiblePlayers: initial.eligiblePlayers,
      teams: [
        TeamDraft(
          id: TeamId('00000000-0000-4000-8000-000000000150'),
          players: initial.eligiblePlayers.take(2),
          method: TeamFormationMethod.manual,
          recordVersion: 2,
        ),
      ],
    );
    final preview = service.releaseTeam(confirmed, confirmed.teams.single.id);
    expect(preview.teams, isEmpty);
    expect(preview.unassigned, hasLength(4));
    expect(preview.baseTeamVersions[confirmed.teams.single.id], 2);
  });
  test('manual pairing accumulates teams in the active preview', () {
    final initial = snapshot([5, 1, 4, 2, 3, 2]);
    final first = service.manual(
      initial,
      initial.eligiblePlayers[0],
      initial.eligiblePlayers[1],
    );
    final second = service.manual(
      initial,
      initial.eligiblePlayers[2],
      initial.eligiblePlayers[3],
      currentPreview: first,
    );

    expect(second.teams, hasLength(2));
    expect(second.teams[0].players, first.teams[0].players);
    expect(second.unassigned, hasLength(2));
    expect(
      second.unassigned.map((player) => player.playerId),
      containsAll([
        initial.eligiblePlayers[4].playerId,
        initial.eligiblePlayers[5].playerId,
      ]),
    );
  });
  test('mistaken manual pair can be removed before confirmation', () {
    final initial = snapshot([5, 1, 4, 2]);
    final preview = service.manual(
      initial,
      initial.eligiblePlayers[1],
      initial.eligiblePlayers[2],
    );

    final corrected = service.removePreviewTeam(
      initial,
      preview,
      preview.teams.single.id,
    );

    expect(corrected.teams, isEmpty);
    expect(corrected.unassigned, hasLength(4));
    expect(corrected.baseTeamVersions, preview.baseTeamVersions);
  });
}

final class _Ids implements TeamIdFactory {
  var value = 200;
  String next() =>
      '00000000-0000-4000-8000-${(value++).toString().padLeft(12, '0')}';
  @override
  TeamId nextTeamId() => TeamId(next());
  @override
  SyncOperationId nextOperationId() => SyncOperationId(next());
}

final class _ReverseRandom implements TeamRandomSource {
  const _ReverseRandom();
  @override
  List<T> shuffled<T>(List<T> values) => values.reversed.toList();
}

final class _Store implements TeamFormationStore {
  var replacements = 0;
  @override
  Future<RepositoryResult<TeamFormationSnapshot>> load(
    EventId eventId,
    DivisionId divisionId,
  ) => throw UnimplementedError();
  @override
  Future<RepositoryResult<TeamFormationSnapshot>> replace({
    required TeamFormationSnapshot current,
    required TeamFormationPreview preview,
    required SyncOperationId operationId,
  }) async {
    replacements++;
    return RepositorySuccess(current);
  }
}
