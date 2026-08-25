import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/events/event.dart';

import '../fixtures.dart';

Event makeEvent(EventStatus status) => Event(
  id: EventId(eventUuid),
  name: 'Community Day',
  scheduledAt: DateTime.utc(2026, 2, 1),
  type: EventType.casual,
  status: status,
  courtLabel: 'Community Court',
  metadata: metadata(),
);

void main() {
  group('Event lifecycle', () {
    test('allows every adjacent forward transition', () {
      var event = makeEvent(EventStatus.upcoming);

      for (final next in const [
        EventStatus.registration,
        EventStatus.inProgress,
        EventStatus.completed,
        EventStatus.archived,
      ]) {
        event = event.transitionTo(next, metadata: metadata(version: 1));
        expect(event.status, next);
      }
    });

    test('rejects skipped transitions', () {
      expect(
        () =>
            makeEvent(EventStatus.upcoming)
                .transitionTo(EventStatus.inProgress, metadata: metadata()),
        throwsA(isA<InvalidStateTransitionFailure>()),
      );
    });

    test('rejects backward transitions', () {
      expect(
        () =>
            makeEvent(EventStatus.completed)
                .transitionTo(EventStatus.inProgress, metadata: metadata()),
        throwsA(isA<InvalidStateTransitionFailure>()),
      );
    });

    test('rejects transitions from archived', () {
      expect(
        () =>
            makeEvent(EventStatus.archived)
                .transitionTo(EventStatus.upcoming, metadata: metadata()),
        throwsA(isA<InvalidStateTransitionFailure>()),
      );
    });

    test('treats a same-state transition as an explicit failure', () {
      expect(
        () =>
            makeEvent(EventStatus.registration)
                .transitionTo(EventStatus.registration, metadata: metadata()),
        throwsA(isA<InvalidStateTransitionFailure>()),
      );
    });
  });

  test('only approved enum values are present', () {
    expect(EventType.values.map((value) => value.name), ['casual', 'formal']);
    expect(EventStatus.values.map((value) => value.name), [
      'upcoming',
      'registration',
      'inProgress',
      'completed',
      'archived',
    ]);
    expect(TournamentFormat.values.map((value) => value.name), [
      'singleElimination',
      'doubleElimination',
      'singleRoundRobin',
      'doubleRoundRobin',
    ]);
    expect(CheckInStatus.values.map((value) => value.name), [
      'notPresent',
      'checkedIn',
    ]);
    expect(PaymentStatus.values.map((value) => value.name), ['unpaid', 'paid']);
    expect(TeamFormationMethod.values.map((value) => value.name), [
      'manual',
      'random',
      'balanced',
    ]);
  });
}
