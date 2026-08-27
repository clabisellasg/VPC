import 'dart:async';

import 'package:vpc/src/application/sync/sync_contracts.dart';
import 'package:vpc/src/application/sync/sync_models.dart';
import 'package:vpc/src/domain/common/entity_id.dart';

final class FakeSyncClock implements SyncClock {
  FakeSyncClock(this.current);

  DateTime current;
  final List<Duration> delays = [];

  @override
  Future<void> delay(Duration duration) async {
    delays.add(duration);
    current = current.add(duration);
  }

  @override
  DateTime nowUtc() => current;
}

final class FixedSyncJitter implements SyncJitter {
  const FixedSyncJitter([this.value = 0]);

  final int value;

  @override
  int milliseconds(int upperExclusive) => value;
}

final class QueueSyncIdFactory implements SyncIdFactory {
  QueueSyncIdFactory({
    Iterable<String> operationIds = const [],
    Iterable<String> conflictIds = const [],
  }) : _operationIds = operationIds.toList(),
       _conflictIds = conflictIds.toList();

  final List<String> _operationIds;
  final List<String> _conflictIds;

  @override
  SyncConflictId conflictId() => SyncConflictId(_conflictIds.removeAt(0));

  @override
  SyncOperationId operationId() => SyncOperationId(_operationIds.removeAt(0));
}

final class FakeRealtimeRefreshSource implements RealtimeRefreshSource {
  final StreamController<void> controller = StreamController<void>.broadcast();
  bool started = false;
  bool disposed = false;

  @override
  Stream<void> get hints => controller.stream;

  void emit() => controller.add(null);

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> dispose() async {
    disposed = true;
    await controller.close();
  }
}

final class FakeCoordinator implements SyncCoordinator {
  int runs = 0;
  bool disposed = false;
  Completer<void>? blocker;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  Future<SyncReport> synchronize() async {
    runs++;
    await blocker?.future;
    return const SyncReport(status: SyncRunStatus.completed);
  }
}
