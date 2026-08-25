import '../common/domain_enums.dart';
import '../common/domain_failure.dart';
import '../common/domain_validation.dart';
import '../common/entity_id.dart';
import '../common/record_metadata.dart';

/// A division-scoped team that never becomes a permanent community identity.
final class TemporaryTeam {
  factory TemporaryTeam({
    required TeamId id,
    required DivisionId divisionId,
    required Iterable<PlayerId> memberIds,
    required TeamFormationMethod formationMethod,
    required RecordMetadata metadata,
    String? displayLabel,
  }) {
    final immutableMembers = List<PlayerId>.unmodifiable(memberIds);
    if (immutableMembers.isEmpty) {
      throw const ValidationFailure(
        field: 'memberIds',
        message: 'A team must contain at least one player.',
      );
    }
    if (immutableMembers.toSet().length != immutableMembers.length) {
      throw const ValidationFailure(
        field: 'memberIds',
        message: 'A player cannot appear more than once on the same team.',
      );
    }

    return TemporaryTeam._(
      id: id,
      divisionId: divisionId,
      memberIds: immutableMembers,
      formationMethod: formationMethod,
      displayLabel: displayLabel == null
          ? null
          : requireNonBlank(displayLabel, field: 'displayLabel'),
      metadata: metadata,
    );
  }

  const TemporaryTeam._({
    required this.id,
    required this.divisionId,
    required this.memberIds,
    required this.formationMethod,
    required this.displayLabel,
    required this.metadata,
  });

  final TeamId id;
  final DivisionId divisionId;
  final List<PlayerId> memberIds;
  final TeamFormationMethod formationMethod;
  final String? displayLabel;
  final RecordMetadata metadata;
}
