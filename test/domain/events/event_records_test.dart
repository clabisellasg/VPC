import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/events/division_participant.dart';
import 'package:vpc/src/domain/events/event_division.dart';
import 'package:vpc/src/domain/events/event_participant.dart';
import 'package:vpc/src/domain/events/participant_payment.dart';

import '../fixtures.dart';

void main() {
  test(
    'event records reference permanent identity without copying a player',
    () {
      final eventParticipant = EventParticipant(
        id: EventParticipantId(eventParticipantUuid),
        eventId: EventId(eventUuid),
        playerId: PlayerId(playerOneUuid),
        checkInStatus: CheckInStatus.checkedIn,
        metadata: metadata(),
      );
      final division = EventDivision(
        id: DivisionId(divisionUuid),
        eventId: EventId(eventUuid),
        name: 'Community Invitational',
        format: TournamentFormat.singleRoundRobin,
        metadata: metadata(),
      );
      final divisionParticipant = DivisionParticipant(
        id: DivisionParticipantId(divisionParticipantUuid),
        divisionId: division.id,
        eventParticipantId: eventParticipant.id,
        metadata: metadata(),
      );

      expect(eventParticipant.playerId, PlayerId(playerOneUuid));
      expect(division.name, 'Community Invitational');
      expect(divisionParticipant.eventParticipantId, eventParticipant.id);
    },
  );

  test('payment scope can remain event-level or be division-specific', () {
    final eventLevel = ParticipantPayment(
      id: ParticipantPaymentId(paymentUuid),
      eventParticipantId: EventParticipantId(eventParticipantUuid),
      status: PaymentStatus.unpaid,
      metadata: metadata(),
    );
    final divisionLevel = ParticipantPayment(
      id: ParticipantPaymentId('00000000-0000-4000-8000-000000000010'),
      eventParticipantId: EventParticipantId(eventParticipantUuid),
      divisionId: DivisionId(divisionUuid),
      status: PaymentStatus.paid,
      metadata: metadata(),
    );

    expect(eventLevel.divisionId, isNull);
    expect(divisionLevel.divisionId, DivisionId(divisionUuid));
  });
}
