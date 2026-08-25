import '../common/domain_enums.dart';
import '../common/domain_failure.dart';
import '../common/entity_id.dart';

/// A bracket-routing description. It never executes advancement.
final class MatchDependency {
  MatchDependency({
    required this.sourceMatchId,
    required this.source,
    required this.destinationMatchId,
    required this.destinationSlot,
  }) {
    if (sourceMatchId == destinationMatchId) {
      throw const ValidationFailure(
        field: 'destinationMatchId',
        message: 'A match cannot depend on its own outcome.',
      );
    }
  }

  final MatchId sourceMatchId;
  final MatchDependencySource source;
  final MatchId destinationMatchId;
  final MatchDestinationSlot destinationSlot;
}
