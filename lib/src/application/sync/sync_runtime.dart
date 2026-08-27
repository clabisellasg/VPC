import 'dart:async';

import 'sync_contracts.dart';

final class SyncRuntime {
  SyncRuntime({required this.coordinator, this.realtimeSource});

  final SyncCoordinator coordinator;
  final RealtimeRefreshSource? realtimeSource;
  StreamSubscription<void>? _subscription;
  bool _disposed = false;

  Future<void> start() async {
    if (_disposed || _subscription != null) {
      return;
    }
    final source = realtimeSource;
    if (source != null) {
      _subscription = source.hints.listen((_) => unawaited(requestSync()));
      await source.start();
    }
    unawaited(requestSync());
  }

  Future<void> requestSync() async {
    if (!_disposed) {
      await coordinator.synchronize();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    await realtimeSource?.dispose();
    await coordinator.dispose();
  }
}
