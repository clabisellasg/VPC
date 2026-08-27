import 'dart:math' as math;

import 'sync_contracts.dart';
import 'sync_models.dart';

final class PlayerSyncCoordinator implements SyncCoordinator {
  PlayerSyncCoordinator({
    required this.store,
    required this.remote,
    required this.clock,
    required this.jitter,
    required this.idFactory,
    this.batchSize = 25,
  }) : assert(batchSize > 0);

  final PlayerSyncStore store;
  final SyncRemoteGateway remote;
  final SyncClock clock;
  final SyncJitter jitter;
  final SyncIdFactory idFactory;
  final int batchSize;

  bool _running = false;
  bool _disposed = false;

  @override
  Future<SyncReport> synchronize() async {
    if (_disposed) {
      return const SyncReport(
        status: SyncRunStatus.failed,
        safeMessage: 'Synchronization coordinator is disposed.',
      );
    }
    if (_running) {
      return const SyncReport(status: SyncRunStatus.alreadyRunning);
    }
    _running = true;
    try {
      return await _run();
    } finally {
      _running = false;
    }
  }

  Future<SyncReport> _run() async {
    var uploaded = 0;
    var pulled = 0;
    var conflicts = 0;
    final now = clock.nowUtc();
    await store.recoverInterruptedOperations(
      staleBefore: now.subtract(const Duration(minutes: 15)),
    );
    final operations = await store.claimEligibleOperations(
      now: now,
      limit: batchSize,
    );

    for (var index = 0; index < operations.length; index++) {
      final operation = operations[index];
      if (_disposed) {
        await store.releaseClaims(operations.skip(index));
        break;
      }
      final result = await remote.applyPlayerOperation(operation);
      switch (result) {
        case RemoteApplyAccepted(:final player):
          await store.acceptRemoteOperation(operation, player);
          uploaded++;
        case RemoteApplyConflict(:final remotePlayer):
          await store.preserveConflict(
            operation,
            remotePlayer: remotePlayer,
            detectedAt: clock.nowUtc(),
            conflictId: idFactory.conflictId(),
          );
          conflicts++;
          await store.releaseClaims(operations.skip(index + 1));
          return SyncReport(
            status: SyncRunStatus.completed,
            uploaded: uploaded,
            conflicts: conflicts,
          );
        case RemoteApplyFailure(kind: SyncFailureKind.authorizationBlocked):
          await store.markAuthorizationBlocked(
            operation,
            nextEligibleAt: clock.nowUtc().add(const Duration(minutes: 5)),
          );
          await store.releaseClaims(operations.skip(index + 1));
          return SyncReport(
            status: SyncRunStatus.authorizationBlocked,
            uploaded: uploaded,
            conflicts: conflicts,
            safeMessage:
                'Queued writes require an authenticated organizer session.',
          );
        case RemoteApplyFailure(
          kind: SyncFailureKind.retryable,
          :final safeMessage,
        ):
          await store.markRetryable(
            operation,
            nextEligibleAt: clock.nowUtc().add(
              _backoff(operation.attemptCount),
            ),
            safeMessage: safeMessage,
          );
          await store.releaseClaims(operations.skip(index + 1));
          return SyncReport(
            status: SyncRunStatus.failed,
            uploaded: uploaded,
            conflicts: conflicts,
            safeMessage: 'Synchronization is temporarily unavailable.',
          );
        case RemoteApplyFailure(:final safeMessage):
          await store.markPermanentFailure(operation, safeMessage: safeMessage);
      }
    }

    var checkpoint = await store.readCheckpoint();
    while (!_disposed) {
      final pull = await remote.pullPlayers(
        after: checkpoint,
        limit: batchSize,
      );
      switch (pull) {
        case RemotePullFailure(:final kind, :final safeMessage):
          return SyncReport(
            status: kind == SyncFailureKind.authorizationBlocked
                ? SyncRunStatus.authorizationBlocked
                : SyncRunStatus.failed,
            uploaded: uploaded,
            pulled: pulled,
            conflicts: conflicts,
            safeMessage: safeMessage,
          );
        case RemotePullSuccess(:final page):
          final before = await store.readUnresolvedConflicts();
          pulled += await store.reconcilePullPage(
            page,
            previousCheckpoint: checkpoint,
            detectedAt: clock.nowUtc(),
            conflictIdFactory: idFactory.conflictId,
          );
          final after = await store.readUnresolvedConflicts();
          conflicts += after.length - before.length;
          checkpoint = await store.readCheckpoint();
          if (!page.hasMore || page.players.isEmpty) {
            return SyncReport(
              status: SyncRunStatus.completed,
              uploaded: uploaded,
              pulled: pulled,
              conflicts: conflicts,
            );
          }
      }
    }
    return SyncReport(
      status: SyncRunStatus.failed,
      uploaded: uploaded,
      pulled: pulled,
      conflicts: conflicts,
      safeMessage: 'Synchronization stopped during disposal.',
    );
  }

  Duration _backoff(int priorAttempts) {
    final exponent = math.min(priorAttempts, 6);
    final baseSeconds = math.min(5 * (1 << exponent), 300);
    return Duration(
      seconds: baseSeconds,
      milliseconds: jitter.milliseconds(1000),
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}
