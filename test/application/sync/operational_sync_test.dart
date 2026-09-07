import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/sync/operational_sync.dart';

final class _Store implements OperationalSyncStore {
  var retries = 0, successes = 0;
  @override
  Future<OperationalSyncSnapshot> snapshot() async =>
      const OperationalSyncSnapshot();
  @override
  Future<void> retryFailures() async => retries++;
  @override
  Future<void> recordSuccessfulSync(DateTime atUtc) async => successes++;
  @override
  Future<void> stageLocalReapplication(
    String operationId,
    String replacementOperationId,
  ) async {}
  @override
  Future<void> enqueueStagedReapplication(
    String operationId,
    String replacementOperationId,
  ) async {}
  @override
  Future<void> useCloudVersion(String operationId) async {}
}

final class _Runner implements OperationalSyncRunner {
  _Runner(this.name, this.log);
  final String name;
  final List<String> log;
  @override
  Future<void> synchronize() async => log.add(name);
}

void main() {
  test('runs bounded streams in dependency order', () async {
    final store = _Store(), log = <String>[];
    final coordinator = OperationalSyncCoordinator(
      store: store,
      runners: [
        _Runner('player', log),
        _Runner('event', log),
        _Runner('participant', log),
        _Runner('team', log),
        _Runner('tournament', log),
        _Runner('court', log),
      ],
      nowUtc: () => DateTime.utc(2026, 9, 7),
    );
    await coordinator.synchronize();
    expect(log, [
      'player',
      'event',
      'participant',
      'team',
      'tournament',
      'court',
    ]);
    expect(store.successes, 1);
  });

  test('retry resets retryable failures before synchronization', () async {
    final store = _Store(), log = <String>[];
    final coordinator = OperationalSyncCoordinator(
      store: store,
      runners: [_Runner('run', log)],
      nowUtc: DateTime.now,
    );
    await coordinator.retryNow();
    expect(store.retries, 1);
    expect(log, ['run']);
  });
}
