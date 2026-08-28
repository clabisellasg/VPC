import 'dart:collection';

import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_validation.dart';
import '../../domain/events/event.dart';
import '../../domain/events/event_division.dart';

enum PublicEventGroup { current, upcoming, completed }

enum PublicCatalogOrigin { remote, androidCache }

final class PublicEventItem {
  PublicEventItem({
    required this.event,
    Iterable<EventDivision> divisions = const [],
  }) : divisions = UnmodifiableListView<EventDivision>(
         _orderedDivisions(divisions),
       );

  final Event event;
  final UnmodifiableListView<EventDivision> divisions;

  PublicEventGroup get group => switch (event.status) {
    EventStatus.upcoming => PublicEventGroup.upcoming,
    EventStatus.registration ||
    EventStatus.inProgress => PublicEventGroup.current,
    EventStatus.completed || EventStatus.archived => PublicEventGroup.completed,
  };

  static List<EventDivision> _orderedDivisions(
    Iterable<EventDivision> divisions,
  ) {
    final result = divisions
        .where((division) => !division.metadata.isDeleted)
        .toList();
    result.sort((left, right) {
      final byName = left.name.toLowerCase().compareTo(
        right.name.toLowerCase(),
      );
      return byName != 0 ? byName : left.id.value.compareTo(right.id.value);
    });
    return result;
  }
}

final class PublicEventCatalog {
  PublicEventCatalog({
    required Iterable<PublicEventItem> events,
    required this.origin,
    required this.refreshedAt,
  }) : events = UnmodifiableListView<PublicEventItem>(
         _orderedEvents(events.where((item) => !item.event.metadata.isDeleted)),
       ) {
    requireUtc(refreshedAt, field: 'refreshedAt');
  }

  final UnmodifiableListView<PublicEventItem> events;
  final PublicCatalogOrigin origin;
  final DateTime refreshedAt;

  List<PublicEventItem> eventsIn(PublicEventGroup group) =>
      UnmodifiableListView<PublicEventItem>(
        events.where((item) => item.group == group),
      );

  PublicEventItem? eventById(String id) {
    for (final item in events) {
      if (item.event.id.value == id) {
        return item;
      }
    }
    return null;
  }

  static List<PublicEventItem> _orderedEvents(
    Iterable<PublicEventItem> events,
  ) {
    final result = events.toList();
    result.sort((left, right) {
      final leftCompleted = left.group == PublicEventGroup.completed;
      final rightCompleted = right.group == PublicEventGroup.completed;
      if (leftCompleted && rightCompleted) {
        final byDate = right.event.scheduledAt.compareTo(
          left.event.scheduledAt,
        );
        return byDate != 0
            ? byDate
            : left.event.id.value.compareTo(right.event.id.value);
      }
      final byDate = left.event.scheduledAt.compareTo(right.event.scheduledAt);
      return byDate != 0
          ? byDate
          : left.event.id.value.compareTo(right.event.id.value);
    });
    return result;
  }
}
