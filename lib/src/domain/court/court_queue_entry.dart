import '../common/domain_validation.dart';
import '../common/entity_id.dart';
import '../common/record_metadata.dart';

/// A zero-based structural position in the single-court queue.
final class CourtQueueEntry {
  CourtQueueEntry({
    required this.id,
    required this.eventId,
    required this.matchId,
    required this.queuePosition,
    required this.metadata,
    this.divisionId,
  }) {
    requireNonNegative(queuePosition, field: 'queuePosition');
  }

  final CourtQueueEntryId id;
  final EventId eventId;
  final DivisionId? divisionId;
  final MatchId matchId;
  final int queuePosition;
  final RecordMetadata metadata;
}
