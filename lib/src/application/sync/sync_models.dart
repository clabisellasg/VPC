import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/players/permanent_player.dart';
import '../../domain/players/player_skill.dart';

enum SyncEntityType { player }

enum SyncOperationKind { upsert, tombstone }

enum SyncOperationStatus { pending, inFlight, conflicted, failed }

enum SyncConflictStatus { unresolved, resolved }

enum SyncFailureKind {
  authorizationBlocked,
  retryable,
  permanent,
  conflict,
  invalidRemoteData,
}

final class PlayerSyncPayload {
  factory PlayerSyncPayload.fromPlayer(PermanentPlayer player) {
    if (player.accountId != null) {
      throw const ValidationFailure(
        field: 'accountId',
        message: 'Account links are outside the player synchronization slice.',
      );
    }
    return PlayerSyncPayload._(
      id: player.id,
      displayName: player.displayName,
      metadata: player.metadata,
      skill: player.skill,
    );
  }

  const PlayerSyncPayload._({
    required this.id,
    required this.displayName,
    required this.metadata,
    required this.skill,
  });

  final PlayerId id;
  final String displayName;
  final RecordMetadata metadata;
  final PlayerSkill? skill;

  PermanentPlayer toPlayer() => PermanentPlayer(
    id: id,
    displayName: displayName,
    metadata: metadata,
    skill: skill,
  );
}

final class SyncOperation {
  SyncOperation({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.kind,
    required this.payload,
    required this.createdAt,
    required this.attemptCount,
    required this.nextEligibleAt,
    required this.status,
    this.baseVersion,
  }) {
    if (entityType != SyncEntityType.player || entityId != payload.id) {
      throw const ValidationFailure(
        field: 'entityId',
        message: 'The operation entity must match its player payload.',
      );
    }
    if (baseVersion != null && baseVersion! < 0) {
      throw const ValidationFailure(
        field: 'baseVersion',
        message: 'Base version cannot be negative.',
      );
    }
    if (attemptCount < 0) {
      throw const ValidationFailure(
        field: 'attemptCount',
        message: 'Attempt count cannot be negative.',
      );
    }
    _requireUtc(createdAt, 'createdAt');
    _requireUtc(nextEligibleAt, 'nextEligibleAt');
    if (kind == SyncOperationKind.tombstone && !payload.metadata.isDeleted) {
      throw const ValidationFailure(
        field: 'kind',
        message: 'A tombstone operation requires deleted metadata.',
      );
    }
  }

  final SyncOperationId id;
  final SyncEntityType entityType;
  final PlayerId entityId;
  final SyncOperationKind kind;
  final int? baseVersion;
  final PlayerSyncPayload payload;
  final DateTime createdAt;
  final int attemptCount;
  final DateTime nextEligibleAt;
  final SyncOperationStatus status;
}

final class SyncCheckpoint {
  SyncCheckpoint({
    required this.entityType,
    required this.updatedAt,
    required this.entityId,
  }) {
    _requireUtc(updatedAt, 'updatedAt');
  }

  final SyncEntityType entityType;
  final DateTime updatedAt;
  final PlayerId entityId;
}

final class SyncConflict {
  SyncConflict({
    required this.id,
    required this.operationId,
    required this.entityType,
    required this.entityId,
    required this.localProposal,
    required this.detectedAt,
    required this.status,
    this.expectedVersion,
    this.remoteRecord,
    this.remoteVersion,
  }) {
    _requireUtc(detectedAt, 'detectedAt');
  }

  final SyncConflictId id;
  final SyncOperationId operationId;
  final SyncEntityType entityType;
  final PlayerId entityId;
  final int? expectedVersion;
  final PlayerSyncPayload localProposal;
  final PermanentPlayer? remoteRecord;
  final int? remoteVersion;
  final DateTime detectedAt;
  final SyncConflictStatus status;
}

sealed class RemoteApplyResult {
  const RemoteApplyResult();
}

final class RemoteApplyAccepted extends RemoteApplyResult {
  const RemoteApplyAccepted({required this.player, required this.replayed});

  final PermanentPlayer player;
  final bool replayed;
}

final class RemoteApplyConflict extends RemoteApplyResult {
  const RemoteApplyConflict({required this.remotePlayer});

  final PermanentPlayer? remotePlayer;
}

final class RemoteApplyFailure extends RemoteApplyResult {
  const RemoteApplyFailure({required this.kind, required this.safeMessage});

  final SyncFailureKind kind;
  final String safeMessage;
}

final class RemotePullPage {
  const RemotePullPage({required this.players, required this.hasMore});

  final List<PermanentPlayer> players;
  final bool hasMore;
}

sealed class RemotePullResult {
  const RemotePullResult();
}

final class RemotePullSuccess extends RemotePullResult {
  const RemotePullSuccess(this.page);

  final RemotePullPage page;
}

final class RemotePullFailure extends RemotePullResult {
  const RemotePullFailure({required this.kind, required this.safeMessage});

  final SyncFailureKind kind;
  final String safeMessage;
}

enum SyncRunStatus { completed, alreadyRunning, authorizationBlocked, failed }

final class SyncReport {
  const SyncReport({
    required this.status,
    this.uploaded = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.safeMessage,
  });

  final SyncRunStatus status;
  final int uploaded;
  final int pulled;
  final int conflicts;
  final String? safeMessage;
}

void _requireUtc(DateTime value, String field) {
  if (!value.isUtc) {
    throw ValidationFailure(field: field, message: '$field must use UTC.');
  }
}
