import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/players/permanent_player.dart';
import 'package:vpc/src/domain/teams/temporary_team.dart';

import '../fixtures.dart';

void main() {
  test('a permanent player has typed identity and optional account link', () {
    final player = PermanentPlayer(
      id: PlayerId(playerOneUuid),
      displayName: '  Ana Cruz  ',
      accountId: AccountId(accountUuid),
      metadata: metadata(),
    );

    expect(player.id, PlayerId(playerOneUuid));
    expect(player.displayName, 'Ana Cruz');
    expect(player.accountId, AccountId(accountUuid));
  });

  group('TemporaryTeam', () {
    TemporaryTeam makeTeam(Iterable<PlayerId> members) => TemporaryTeam(
      id: TeamId(teamOneUuid),
      divisionId: DivisionId(divisionUuid),
      memberIds: members,
      formationMethod: TeamFormationMethod.manual,
      metadata: metadata(),
    );

    test('references immutable PlayerId membership', () {
      final source = [PlayerId(playerOneUuid), PlayerId(playerTwoUuid)];
      final team = makeTeam(source);
      source.add(PlayerId(playerThreeUuid));

      expect(team.memberIds, [
        PlayerId(playerOneUuid),
        PlayerId(playerTwoUuid),
      ]);
      expect(
        () => team.memberIds.add(PlayerId(playerThreeUuid)),
        throwsUnsupportedError,
      );
    });

    test('rejects empty membership', () {
      expect(() => makeTeam([]), throwsA(isA<ValidationFailure>()));
    });

    test('rejects duplicate players', () {
      expect(
        () => makeTeam([PlayerId(playerOneUuid), PlayerId(playerOneUuid)]),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('does not impose a fixed two-player team size', () {
      expect(makeTeam([PlayerId(playerOneUuid)]).memberIds, hasLength(1));
      expect(
        makeTeam([
          PlayerId(playerOneUuid),
          PlayerId(playerTwoUuid),
          PlayerId(playerThreeUuid),
        ]).memberIds,
        hasLength(3),
      );
    });
  });
}
