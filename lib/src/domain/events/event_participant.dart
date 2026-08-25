import '../common/domain_enums.dart';
import '../common/entity_id.dart';
import '../common/record_metadata.dart';

final class EventParticipant {
  const EventParticipant({
    required this.id,
    required this.eventId,
    required this.playerId,
    required this.checkInStatus,
    required this.metadata,
  });

  final EventParticipantId id;
  final EventId eventId;
  final PlayerId playerId;
  final CheckInStatus checkInStatus;
  final RecordMetadata metadata;
}
