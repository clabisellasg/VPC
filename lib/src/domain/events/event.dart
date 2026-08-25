import '../common/domain_enums.dart';
import '../common/domain_failure.dart';
import '../common/domain_validation.dart';
import '../common/entity_id.dart';
import '../common/money.dart';
import '../common/record_metadata.dart';

final class Event {
  factory Event({
    required EventId id,
    required String name,
    required DateTime scheduledAt,
    required EventType type,
    required EventStatus status,
    required String courtLabel,
    required RecordMetadata metadata,
    Money? entryFee,
  }) {
    requireUtc(scheduledAt, field: 'scheduledAt');
    return Event._(
      id: id,
      name: requireNonBlank(name, field: 'name'),
      scheduledAt: scheduledAt,
      type: type,
      status: status,
      entryFee: entryFee,
      courtLabel: requireNonBlank(courtLabel, field: 'courtLabel'),
      metadata: metadata,
    );
  }

  const Event._({
    required this.id,
    required this.name,
    required this.scheduledAt,
    required this.type,
    required this.status,
    required this.entryFee,
    required this.courtLabel,
    required this.metadata,
  });

  final EventId id;
  final String name;
  final DateTime scheduledAt;
  final EventType type;
  final EventStatus status;
  final Money? entryFee;
  final String courtLabel;
  final RecordMetadata metadata;

  Event transitionTo(
    EventStatus nextStatus, {
    required RecordMetadata metadata,
  }) {
    final expected = switch (status) {
      EventStatus.upcoming => EventStatus.registration,
      EventStatus.registration => EventStatus.inProgress,
      EventStatus.inProgress => EventStatus.completed,
      EventStatus.completed => EventStatus.archived,
      EventStatus.archived => null,
    };

    if (nextStatus != expected) {
      throw InvalidStateTransitionFailure(
        entity: 'Event',
        from: status.name,
        to: nextStatus.name,
      );
    }

    return Event(
      id: id,
      name: name,
      scheduledAt: scheduledAt,
      type: type,
      status: nextStatus,
      entryFee: entryFee,
      courtLabel: courtLabel,
      metadata: metadata,
    );
  }
}
