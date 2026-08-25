import '../common/domain_enums.dart';
import '../common/entity_id.dart';
import '../common/record_metadata.dart';

/// Paid/Unpaid status only; a null [divisionId] represents event-level scope.
final class ParticipantPayment {
  const ParticipantPayment({
    required this.id,
    required this.eventParticipantId,
    required this.status,
    required this.metadata,
    this.divisionId,
  });

  final ParticipantPaymentId id;
  final EventParticipantId eventParticipantId;
  final DivisionId? divisionId;
  final PaymentStatus status;
  final RecordMetadata metadata;
}
