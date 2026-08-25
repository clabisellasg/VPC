import '../common/domain_validation.dart';
import '../common/entity_id.dart';
import '../common/record_metadata.dart';

/// A finalized structural finish; no placement is calculated here.
final class DivisionPlacement {
  DivisionPlacement({
    required this.id,
    required this.divisionId,
    required this.teamId,
    required this.position,
    required this.metadata,
  }) {
    requirePositive(position, field: 'position');
  }

  final DivisionPlacementId id;
  final DivisionId divisionId;
  final TeamId teamId;
  final int position;
  final RecordMetadata metadata;
}
