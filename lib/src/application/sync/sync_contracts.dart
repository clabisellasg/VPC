import '../../domain/common/entity_id.dart';
import '../../domain/players/permanent_player.dart';
import 'sync_models.dart';

abstract interface class SyncRemoteGateway {
  Future<RemoteApplyResult> applyPlayerOperation(SyncOperation operation);

  Future<RemotePullResult> pullPlayers({
    SyncCheckpoint? after,
    required int limit,
  });
}

abstract interface class PlayerSyncStore {
  Future<void> recoverInterruptedOperations({required DateTime staleBefore});

  Future<List<SyncOperation>> claimEligibleOperations({
    required DateTime now,
    required int limit,
  });

  Future<void> releaseClaims(Iterable<SyncOperation> operations);

  Future<void> acceptRemoteOperation(
    SyncOperation operation,
    PermanentPlayer authoritativePlayer,
  );

  Future<void> markRetryable(
    SyncOperation operation, {
    required DateTime nextEligibleAt,
    required String safeMessage,
  });

  Future<void> markAuthorizationBlocked(
    SyncOperation operation, {
    required DateTime nextEligibleAt,
  });

  Future<void> markPermanentFailure(
    SyncOperation operation, {
    required String safeMessage,
  });

  Future<void> preserveConflict(
    SyncOperation operation, {
    required PermanentPlayer? remotePlayer,
    required DateTime detectedAt,
    required SyncConflictId conflictId,
  });

  Future<SyncCheckpoint?> readCheckpoint();

  Future<int> reconcilePullPage(
    RemotePullPage page, {
    required SyncCheckpoint? previousCheckpoint,
    required DateTime detectedAt,
    required SyncConflictId Function() conflictIdFactory,
  });

  Future<List<SyncConflict>> readUnresolvedConflicts();
}

abstract interface class SyncClock {
  DateTime nowUtc();

  Future<void> delay(Duration duration);
}

abstract interface class SyncJitter {
  int milliseconds(int upperExclusive);
}

abstract interface class SyncIdFactory {
  SyncOperationId operationId();

  SyncConflictId conflictId();
}

abstract interface class RealtimeRefreshSource {
  Stream<void> get hints;

  Future<void> start();

  Future<void> dispose();
}

abstract interface class SyncCoordinator {
  Future<SyncReport> synchronize();

  Future<void> dispose();
}
