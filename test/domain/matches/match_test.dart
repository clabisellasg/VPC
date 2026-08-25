import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/matches/match.dart';
import 'package:vpc/src/domain/matches/match_dependency.dart';

import '../fixtures.dart';

Match makeMatch(MatchStatus status) => Match(
  id: MatchId(matchOneUuid),
  divisionId: DivisionId(divisionUuid),
  sideOneTeamId: TeamId(teamOneUuid),
  sideTwoTeamId: TeamId(teamTwoUuid),
  status: status,
  sideOneScore: status == MatchStatus.completed ? 11 : null,
  sideTwoScore: status == MatchStatus.completed ? 8 : null,
  winnerTeamId: status == MatchStatus.completed ? TeamId(teamOneUuid) : null,
  roundNumber: 1,
  sequenceNumber: 1,
  metadata: metadata(),
);

void main() {
  group('Match structural state', () {
    test('contains exactly the approved statuses', () {
      expect(MatchStatus.values.map((value) => value.name), [
        'scheduled',
        'queued',
        'inProgress',
        'completed',
      ]);
    });

    test('allows each adjacent forward transition', () {
      var match = makeMatch(MatchStatus.scheduled);
      match = match.transitionTo(MatchStatus.queued, metadata: metadata());
      match = match.transitionTo(MatchStatus.inProgress, metadata: metadata());
      match = match.transitionTo(
        MatchStatus.completed,
        sideOneScore: 11,
        sideTwoScore: 8,
        winnerTeamId: TeamId(teamOneUuid),
        metadata: metadata(version: 1),
      );

      expect(match.status, MatchStatus.completed);
      expect(match.winnerTeamId, TeamId(teamOneUuid));
    });

    test('rejects skipped, backward, same-state, and terminal transitions', () {
      expect(
        () =>
            makeMatch(MatchStatus.scheduled)
                .transitionTo(MatchStatus.inProgress, metadata: metadata()),
        throwsA(isA<InvalidStateTransitionFailure>()),
      );
      expect(
        () =>
            makeMatch(MatchStatus.inProgress)
                .transitionTo(MatchStatus.queued, metadata: metadata()),
        throwsA(isA<InvalidStateTransitionFailure>()),
      );
      expect(
        () =>
            makeMatch(MatchStatus.queued)
                .transitionTo(MatchStatus.queued, metadata: metadata()),
        throwsA(isA<InvalidStateTransitionFailure>()),
      );
      expect(
        () =>
            makeMatch(MatchStatus.completed)
                .transitionTo(MatchStatus.scheduled, metadata: metadata()),
        throwsA(isA<InvalidStateTransitionFailure>()),
      );
    });

    test('rejects negative structural scores', () {
      expect(
        () => Match(
          id: MatchId(matchOneUuid),
          divisionId: DivisionId(divisionUuid),
          status: MatchStatus.inProgress,
          sideOneScore: -1,
          metadata: metadata(),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('requires internally consistent completed state', () {
      expect(
        () => Match(
          id: MatchId(matchOneUuid),
          divisionId: DivisionId(divisionUuid),
          sideOneTeamId: TeamId(teamOneUuid),
          sideTwoTeamId: TeamId(teamTwoUuid),
          status: MatchStatus.completed,
          sideOneScore: 11,
          sideTwoScore: 8,
          metadata: metadata(),
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => Match(
          id: MatchId(matchOneUuid),
          divisionId: DivisionId(divisionUuid),
          sideOneTeamId: TeamId(teamOneUuid),
          sideTwoTeamId: TeamId(teamTwoUuid),
          status: MatchStatus.completed,
          sideOneScore: 11,
          sideTwoScore: 8,
          winnerTeamId: TeamId('00000000-0000-4000-8000-000000000011'),
          metadata: metadata(),
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => Match(
          id: MatchId(matchOneUuid),
          divisionId: DivisionId(divisionUuid),
          status: MatchStatus.scheduled,
          winnerTeamId: TeamId(teamOneUuid),
          metadata: metadata(),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  test(
    'dependency represents winner/loser routing to either destination side',
    () {
      for (final source in MatchDependencySource.values) {
        for (final slot in MatchDestinationSlot.values) {
          final dependency = MatchDependency(
            sourceMatchId: MatchId(matchOneUuid),
            source: source,
            destinationMatchId: MatchId(matchTwoUuid),
            destinationSlot: slot,
          );

          expect(dependency.source, source);
          expect(dependency.destinationSlot, slot);
        }
      }
      expect(MatchDependencySource.values.map((value) => value.name), [
        'winner',
        'loser',
      ]);
      expect(MatchDestinationSlot.values.map((value) => value.name), [
        'sideOne',
        'sideTwo',
      ]);
    },
  );
}
