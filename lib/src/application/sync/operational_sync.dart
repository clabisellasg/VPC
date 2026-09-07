enum OperationalSyncStream {
  players,
  events,
  participation,
  teams,
  singleElimination,
  roundRobin,
  doubleElimination,
  courtQueue,
}

enum OperationalSyncState {
  pending,
  uploading,
  failed,
  authorizationBlocked,
  conflicted,
}

enum ConflictResolutionAction { useCloud, reapplyLocal }

final class OperationalSyncItem {
  const OperationalSyncItem({
    required this.operationId,
    required this.stream,
    required this.aggregateId,
    required this.label,
    required this.state,
    required this.createdAt,
    this.message,
  });
  final String operationId;
  final OperationalSyncStream stream;
  final String aggregateId;
  final String label;
  final OperationalSyncState state;
  final DateTime createdAt;
  final String? message;
  bool get isConflict => state == OperationalSyncState.conflicted;
}

final class OperationalSyncSnapshot {
  const OperationalSyncSnapshot({
    this.items = const [],
    this.lastSuccessfulSync,
    this.isSynchronizing = false,
    this.isOffline = false,
  });
  final List<OperationalSyncItem> items;
  final DateTime? lastSuccessfulSync;
  final bool isSynchronizing;
  final bool isOffline;
  int get pendingCount =>
      items.where((e) => e.state == OperationalSyncState.pending).length;
  int get conflictCount => items.where((e) => e.isConflict).length;
}

abstract interface class OperationalSyncStore {
  Future<OperationalSyncSnapshot> snapshot();
  Future<void> retryFailures();
  Future<void> useCloudVersion(String operationId);
  Future<void> stageLocalReapplication(
    String operationId,
    String replacementOperationId,
  );
  Future<void> enqueueStagedReapplication(
    String operationId,
    String replacementOperationId,
  );
  Future<void> recordSuccessfulSync(DateTime atUtc);
}

abstract interface class OperationalSyncRunner {
  Future<void> synchronize();
}

/// Runs existing bounded slices in parent-before-child order and coalesces
/// concurrent refresh/realtime requests into one follow-up pass.
final class OperationalSyncCoordinator {
  OperationalSyncCoordinator({
    required this.store,
    required this.runners,
    required this.nowUtc,
  });
  final OperationalSyncStore store;
  final List<OperationalSyncRunner> runners;
  final DateTime Function() nowUtc;
  Future<void>? _active;
  bool _rerun = false;
  bool _disposed = false;

  Future<void> synchronize() {
    if (_disposed) return Future.value();
    if (_active != null) {
      _rerun = true;
      return _active!;
    }
    final future = _drain();
    _active = future;
    return future.whenComplete(() => _active = null);
  }

  Future<void> _drain() async {
    do {
      _rerun = false;
      for (final runner in runners) {
        if (_disposed) return;
        await runner.synchronize();
      }
      await store.recordSuccessfulSync(nowUtc().toUtc());
    } while (_rerun);
  }

  void dispose() {
    _disposed = true;
    _rerun = false;
  }

  Future<void> retryNow() async {
    await store.retryFailures();
    await synchronize();
  }

  Future<void> useCloudVersion(String operationId) async {
    await store.useCloudVersion(operationId);
    await synchronize();
  }

  Future<void> reapplyLocalChange(
    String operationId,
    String replacementId,
  ) async {
    await store.stageLocalReapplication(operationId, replacementId);
    try {
      await synchronize();
    } finally {
      // Even if refresh is interrupted, preserve the organizer's intent as a
      // new pending operation. Cloud version checks can safely conflict again.
      await store.enqueueStagedReapplication(operationId, replacementId);
    }
    await synchronize();
  }
}
