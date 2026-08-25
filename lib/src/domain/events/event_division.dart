import '../common/domain_enums.dart';
import '../common/domain_validation.dart';
import '../common/entity_id.dart';
import '../common/record_metadata.dart';

final class EventDivision {
  factory EventDivision({
    required DivisionId id,
    required EventId eventId,
    required String name,
    required TournamentFormat format,
    required RecordMetadata metadata,
  }) => EventDivision._(
    id: id,
    eventId: eventId,
    name: requireNonBlank(name, field: 'name'),
    format: format,
    metadata: metadata,
  );

  const EventDivision._({
    required this.id,
    required this.eventId,
    required this.name,
    required this.format,
    required this.metadata,
  });

  final DivisionId id;
  final EventId eventId;
  final String name;
  final TournamentFormat format;
  final RecordMetadata metadata;
}
