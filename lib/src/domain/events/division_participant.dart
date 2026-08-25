import '../common/entity_id.dart';
import '../common/record_metadata.dart';

final class DivisionParticipant {
  const DivisionParticipant({
    required this.id,
    required this.divisionId,
    required this.eventParticipantId,
    required this.metadata,
  });

  final DivisionParticipantId id;
  final DivisionId divisionId;
  final EventParticipantId eventParticipantId;
  final RecordMetadata metadata;
}
