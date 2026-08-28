import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/public_events/public_event_models.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';

import 'public_event_fixtures.dart';

void main() {
  test('groups approved lifecycle statuses into public sections', () {
    final catalog = publicCatalog(
      events: EventStatus.values.map(
        (status) => PublicEventItem(
          event: publicEvent(
            id: '71000000-0000-4000-8000-00000000000${status.index + 1}',
            status: status,
          ),
        ),
      ),
    );

    expect(catalog.eventsIn(PublicEventGroup.upcoming), hasLength(1));
    expect(catalog.eventsIn(PublicEventGroup.current), hasLength(2));
    expect(catalog.eventsIn(PublicEventGroup.completed), hasLength(2));
  });

  test('orders active upcoming ascending and completed descending', () {
    final catalog = publicCatalog(
      events: [
        PublicEventItem(
          event: publicEvent(
            id: upcomingEventId,
            status: EventStatus.upcoming,
            scheduledAt: DateTime.utc(2026, 10),
          ),
        ),
        PublicEventItem(
          event: publicEvent(
            id: currentEventId,
            status: EventStatus.upcoming,
            scheduledAt: DateTime.utc(2026, 9),
          ),
        ),
        PublicEventItem(
          event: publicEvent(
            id: completedEventId,
            status: EventStatus.completed,
            scheduledAt: DateTime.utc(2026, 7),
          ),
        ),
        PublicEventItem(
          event: publicEvent(
            id: '71000000-0000-4000-8000-000000000004',
            status: EventStatus.completed,
            scheduledAt: DateTime.utc(2026, 8),
          ),
        ),
      ],
    );

    expect(
      catalog
          .eventsIn(PublicEventGroup.upcoming)
          .map((item) => item.event.id.value),
      [currentEventId, upcomingEventId],
    );
    expect(
      catalog
          .eventsIn(PublicEventGroup.completed)
          .map((item) => item.event.id.value),
      ['71000000-0000-4000-8000-000000000004', completedEventId],
    );
  });

  test('excludes tombstoned events and divisions', () {
    final deletedAt = DateTime.utc(2026, 8, 21);
    final catalog = publicCatalog(
      events: [
        PublicEventItem(
          event: publicEvent(metadata: publicMetadata(deletedAt: deletedAt)),
        ),
        PublicEventItem(
          event: publicEvent(id: upcomingEventId),
          divisions: [
            publicDivision(metadata: publicMetadata(deletedAt: deletedAt)),
          ],
        ),
      ],
    );

    expect(catalog.events, hasLength(1));
    expect(catalog.events.single.divisions, isEmpty);
  });

  test('division collection cannot be mutated externally', () {
    final divisions = [publicDivision()];
    final item = PublicEventItem(event: publicEvent(), divisions: divisions);
    divisions.clear();

    expect(item.divisions, hasLength(1));
    expect(() => item.divisions.clear(), throwsUnsupportedError);
  });

  test('catalog refresh timestamps must be UTC', () {
    expect(
      () => PublicEventCatalog(
        events: const [],
        origin: PublicCatalogOrigin.remote,
        refreshedAt: DateTime(2026, 8, 28),
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });
}
