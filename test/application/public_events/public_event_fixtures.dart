import 'package:vpc/src/application/public_events/public_event_models.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/events/event.dart';
import 'package:vpc/src/domain/events/event_division.dart';

const currentEventId = '71000000-0000-4000-8000-000000000001';
const upcomingEventId = '71000000-0000-4000-8000-000000000002';
const completedEventId = '71000000-0000-4000-8000-000000000003';
const divisionId = '72000000-0000-4000-8000-000000000001';

final fixtureCreatedAt = DateTime.utc(2026, 8, 1);
final fixtureUpdatedAt = DateTime.utc(2026, 8, 20);
final fixtureRefreshAt = DateTime.utc(2026, 8, 28, 3);

RecordMetadata publicMetadata({
  int version = 0,
  DateTime? deletedAt,
  DateTime? updatedAt,
}) => RecordMetadata(
  createdAt: fixtureCreatedAt,
  updatedAt: updatedAt ?? fixtureUpdatedAt,
  recordVersion: version,
  deletedAt: deletedAt,
);

Event publicEvent({
  String id = currentEventId,
  String name = 'VPC Demo Current',
  EventStatus status = EventStatus.inProgress,
  DateTime? scheduledAt,
  RecordMetadata? metadata,
}) => Event(
  id: EventId(id),
  name: name,
  scheduledAt: scheduledAt ?? DateTime.utc(2026, 8, 28, 2),
  type: EventType.formal,
  status: status,
  courtLabel: 'VPC Sample Court',
  metadata: metadata ?? publicMetadata(),
);

EventDivision publicDivision({
  String id = divisionId,
  String eventId = currentEventId,
  String name = 'Sample Open',
  RecordMetadata? metadata,
}) => EventDivision(
  id: DivisionId(id),
  eventId: EventId(eventId),
  name: name,
  format: TournamentFormat.singleRoundRobin,
  metadata: metadata ?? publicMetadata(),
);

PublicEventCatalog publicCatalog({
  PublicCatalogOrigin origin = PublicCatalogOrigin.remote,
  Iterable<PublicEventItem>? events,
}) => PublicEventCatalog(
  events:
      events ??
      [
        PublicEventItem(event: publicEvent(), divisions: [publicDivision()]),
        PublicEventItem(
          event: publicEvent(
            id: upcomingEventId,
            name: 'VPC Demo Upcoming',
            status: EventStatus.upcoming,
            scheduledAt: DateTime.utc(2026, 9, 20, 1),
          ),
        ),
        PublicEventItem(
          event: publicEvent(
            id: completedEventId,
            name: 'VPC Demo Completed',
            status: EventStatus.completed,
            scheduledAt: DateTime.utc(2026, 8, 16, 1),
          ),
        ),
      ],
  origin: origin,
  refreshedAt: fixtureRefreshAt,
);
