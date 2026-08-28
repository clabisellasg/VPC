import 'domain_failure.dart';

/// Base behavior for nominal, UUID-backed entity identifiers.
abstract class EntityId {
  EntityId(String value) : value = _validateCanonicalUuid(value);

  final String value;

  static final RegExp _canonicalUuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  static String _validateCanonicalUuid(String value) {
    if (value.trim().isEmpty) {
      throw const ValidationFailure(
        field: 'id',
        message: 'ID cannot be blank.',
      );
    }
    if (!_canonicalUuid.hasMatch(value)) {
      throw const ValidationFailure(
        field: 'id',
        message: 'ID must be a lowercase canonical UUID string.',
      );
    }
    return value;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is EntityId &&
          other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => value;
}

final class AccountId extends EntityId {
  AccountId(super.value);
}

final class PlayerId extends EntityId {
  PlayerId(super.value);
}

final class EventId extends EntityId {
  EventId(super.value);
}

final class DivisionId extends EntityId {
  DivisionId(super.value);
}

final class EventParticipantId extends EntityId {
  EventParticipantId(super.value);
}

final class DivisionParticipantId extends EntityId {
  DivisionParticipantId(super.value);
}

final class ParticipantPaymentId extends EntityId {
  ParticipantPaymentId(super.value);
}

final class TeamId extends EntityId {
  TeamId(super.value);
}

final class MatchId extends EntityId {
  MatchId(super.value);
}

final class CourtQueueEntryId extends EntityId {
  CourtQueueEntryId(super.value);
}

final class DivisionPlacementId extends EntityId {
  DivisionPlacementId(super.value);
}

/// Stable identity for a durable client synchronization operation.
final class SyncOperationId extends EntityId {
  SyncOperationId(super.value);
}

/// Stable identity for a locally preserved synchronization conflict.
final class SyncConflictId extends EntityId {
  SyncConflictId(super.value);
}

/// Stable identity for an auditable account-to-player claim request.
final class PlayerClaimId extends EntityId {
  PlayerClaimId(super.value);
}
