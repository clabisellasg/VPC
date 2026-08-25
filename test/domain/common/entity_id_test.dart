import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';

import '../fixtures.dart';

void main() {
  group('typed entity IDs', () {
    test('accept a valid fixed canonical UUID', () {
      expect(PlayerId(playerOneUuid).value, playerOneUuid);
    });

    test(
      'reject blank and malformed values with typed validation failures',
      () {
        expect(() => PlayerId('  '), throwsA(isA<ValidationFailure>()));
        expect(() => PlayerId('not-a-uuid'), throwsA(isA<ValidationFailure>()));
        expect(
          () => PlayerId('AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA'),
          throwsA(isA<ValidationFailure>()),
        );
      },
    );

    test('compare by nominal type and value', () {
      expect(PlayerId(playerOneUuid), PlayerId(playerOneUuid));
      expect(
        PlayerId(playerOneUuid).hashCode,
        PlayerId(playerOneUuid).hashCode,
      );
      expect(PlayerId(playerOneUuid), isNot(PlayerId(playerTwoUuid)));
      expect(PlayerId(playerOneUuid), isNot(TeamId(playerOneUuid)));
    });

    test('provides every approved typed identifier', () {
      expect(AccountId(accountUuid).value, accountUuid);
      expect(EventId(eventUuid).value, eventUuid);
      expect(DivisionId(divisionUuid).value, divisionUuid);
      expect(
        EventParticipantId(eventParticipantUuid).value,
        eventParticipantUuid,
      );
      expect(
        DivisionParticipantId(divisionParticipantUuid).value,
        divisionParticipantUuid,
      );
      expect(ParticipantPaymentId(paymentUuid).value, paymentUuid);
      expect(MatchId(matchOneUuid).value, matchOneUuid);
      expect(CourtQueueEntryId(queueUuid).value, queueUuid);
      expect(DivisionPlacementId(placementUuid).value, placementUuid);
    });
  });
}
