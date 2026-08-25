import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/court/court_queue_entry.dart';
import 'package:vpc/src/domain/results/division_placement.dart';

import '../fixtures.dart';

void main() {
  test(
    'court queue accepts a zero-based order and rejects negative values',
    () {
      final entry = CourtQueueEntry(
        id: CourtQueueEntryId(queueUuid),
        eventId: EventId(eventUuid),
        divisionId: DivisionId(divisionUuid),
        matchId: MatchId(matchOneUuid),
        queuePosition: 0,
        metadata: metadata(),
      );
      expect(entry.queuePosition, 0);

      expect(
        () => CourtQueueEntry(
          id: CourtQueueEntryId(queueUuid),
          eventId: EventId(eventUuid),
          matchId: MatchId(matchOneUuid),
          queuePosition: -1,
          metadata: metadata(),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    },
  );

  test('division placement requires a positive position', () {
    final placement = DivisionPlacement(
      id: DivisionPlacementId(placementUuid),
      divisionId: DivisionId(divisionUuid),
      teamId: TeamId(teamOneUuid),
      position: 1,
      metadata: metadata(),
    );
    expect(placement.position, 1);

    expect(
      () => DivisionPlacement(
        id: DivisionPlacementId(placementUuid),
        divisionId: DivisionId(divisionUuid),
        teamId: TeamId(teamOneUuid),
        position: 0,
        metadata: metadata(),
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });
}
