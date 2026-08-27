import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/sync/player_sync_coordinator.dart';
import 'package:vpc/src/application/sync/sync_contracts.dart';
import 'package:vpc/src/application/sync/sync_models.dart';
import 'package:vpc/src/application/sync/sync_runtime.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/players/permanent_player.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';
import 'package:vpc/src/infrastructure/sync/drift_player_sync_store.dart';
import 'package:vpc/src/infrastructure/sync/drift_syncing_player_repository.dart';

import 'sync_test_fakes.dart';

const playerId = '40000000-0000-4000-8000-000000000001';
const operationId = '50000000-0000-4000-8000-000000000001';
const operationIdTwo = '50000000-0000-4000-8000-000000000002';
const conflictId = '60000000-0000-4000-8000-000000000001';
final now = DateTime.utc(2026, 8, 28, 4);

PermanentPlayer player({String name = 'Queued Player', int version = 0}) =>
    PermanentPlayer(
      id: PlayerId(playerId),
      displayName: name,
      metadata: RecordMetadata(
        createdAt: now,
        updatedAt: now.add(Duration(minutes: version)),
        recordVersion: version,
      ),
    );

final class FakeRemoteGateway implements SyncRemoteGateway {
  FakeRemoteGateway({
    required this.applyResult,
    RemotePullResult? pullResult,
    this.applyBlocker,
  }) : pullResult =
           pullResult ??
           const RemotePullSuccess(RemotePullPage(players: [], hasMore: false));

  RemoteApplyResult applyResult;
  RemotePullResult pullResult;
  Completer<void>? applyBlocker;
  int applyCalls = 0;
  int pullCalls = 0;

  @override
  Future<RemoteApplyResult> applyPlayerOperation(
    SyncOperation operation,
  ) async {
    applyCalls++;
    await applyBlocker?.future;
    return applyResult;
  }

  @override
  Future<RemotePullResult> pullPlayers({
    SyncCheckpoint? after,
    required int limit,
  }) async {
    pullCalls++;
    return pullResult;
  }
}

void main() {
  late AppDatabase database;
  late FakeSyncClock clock;
  late QueueSyncIdFactory ids;
  late DriftPlayerSyncStore store;

  setUp(() async {
    database = AppDatabase.inMemory();
    clock = FakeSyncClock(now);
    ids = QueueSyncIdFactory(
      operationIds: [operationId, operationIdTwo],
      conflictIds: [conflictId],
    );
    store = DriftPlayerSyncStore(database);
    final repository = DriftSyncingPlayerRepository(
      database: database,
      idFactory: ids,
      clock: clock,
    );
    await repository.save(player());
  });

  tearDown(() => database.close());

  PlayerSyncCoordinator coordinator(FakeRemoteGateway remote) =>
      PlayerSyncCoordinator(
        store: store,
        remote: remote,
        clock: clock,
        jitter: const FixedSyncJitter(125),
        idFactory: ids,
      );

  test('uploads once, accepts authoritative player, and pulls', () async {
    final remote = FakeRemoteGateway(
      applyResult: RemoteApplyAccepted(player: player(), replayed: false),
    );
    final report = await coordinator(remote).synchronize();

    expect(report.status, SyncRunStatus.completed);
    expect(report.uploaded, 1);
    expect(remote.applyCalls, 1);
    expect(remote.pullCalls, 1);
    expect(await database.select(database.syncOutboxOperations).get(), isEmpty);
  });

  test(
    'idempotent replay confirmation completes without a duplicate local write',
    () async {
      final remote = FakeRemoteGateway(
        applyResult: RemoteApplyAccepted(player: player(), replayed: true),
      );
      final report = await coordinator(remote).synchronize();

      expect(report.uploaded, 1);
      expect(await database.select(database.players).get(), hasLength(1));
      expect(
        await database.select(database.syncOutboxOperations).get(),
        isEmpty,
      );
    },
  );

  test(
    'authorization block leaves operation pending without pulling',
    () async {
      final repository = DriftSyncingPlayerRepository(
        database: database,
        idFactory: ids,
        clock: clock,
      );
      await repository.save(player(name: 'Second local edit', version: 1));
      final remote = FakeRemoteGateway(
        applyResult: const RemoteApplyFailure(
          kind: SyncFailureKind.authorizationBlocked,
          safeMessage: 'redacted',
        ),
      );
      final report = await coordinator(remote).synchronize();

      expect(report.status, SyncRunStatus.authorizationBlocked);
      final rows = await database.select(database.syncOutboxOperations).get();
      expect(rows, hasLength(2));
      expect(rows.every((row) => row.status == 'pending'), isTrue);
      final attempted = rows.singleWhere((row) => row.id == operationId);
      expect(attempted.attemptCount, 1);
      expect(attempted.nextEligibleAt, now.add(const Duration(minutes: 5)));
      expect(
        rows.singleWhere((row) => row.id == operationIdTwo).attemptCount,
        0,
      );
      expect(remote.pullCalls, 0);
    },
  );

  test('retryable failure applies bounded deterministic backoff', () async {
    final remote = FakeRemoteGateway(
      applyResult: const RemoteApplyFailure(
        kind: SyncFailureKind.retryable,
        safeMessage: 'network unavailable',
      ),
    );
    final report = await coordinator(remote).synchronize();

    expect(report.status, SyncRunStatus.failed);
    final row = await database
        .select(database.syncOutboxOperations)
        .getSingle();
    expect(row.status, 'pending');
    expect(
      row.nextEligibleAt,
      now.add(const Duration(seconds: 5, milliseconds: 125)),
    );
    expect(row.failureMessage, 'network unavailable');
  });

  test(
    'stale base-version result becomes an explicit preserved conflict',
    () async {
      final repository = DriftSyncingPlayerRepository(
        database: database,
        idFactory: ids,
        clock: clock,
      );
      await repository.save(player(name: 'Later local edit', version: 1));
      final remote = FakeRemoteGateway(
        applyResult: RemoteApplyConflict(
          remotePlayer: player(name: 'Cloud', version: 1),
        ),
      );
      final report = await coordinator(remote).synchronize();

      expect(report.conflicts, 1);
      expect(
        (await store.readUnresolvedConflicts())
            .single
            .remoteRecord
            ?.displayName,
        'Cloud',
      );
      expect(
        (await database.select(database.players).getSingle()).displayName,
        'Later local edit',
      );
      await coordinator(remote).synchronize();
      expect(
        remote.applyCalls,
        1,
        reason: 'later operations for a conflicted entity stay blocked',
      );
    },
  );

  test('only one synchronization run is active', () async {
    final blocker = Completer<void>();
    final remote = FakeRemoteGateway(
      applyResult: RemoteApplyAccepted(player: player(), replayed: false),
      applyBlocker: blocker,
    );
    final instance = coordinator(remote);
    final first = instance.synchronize();
    await Future<void>.delayed(Duration.zero);
    final second = await instance.synchronize();
    expect(second.status, SyncRunStatus.alreadyRunning);
    blocker.complete();
    expect((await first).status, SyncRunStatus.completed);
  });

  test(
    'runtime starts once, responds to hints, and disposes subscriptions',
    () async {
      final fakeCoordinator = FakeCoordinator();
      final realtime = FakeRealtimeRefreshSource();
      final runtime = SyncRuntime(
        coordinator: fakeCoordinator,
        realtimeSource: realtime,
      );

      await runtime.start();
      await runtime.start();
      await Future<void>.delayed(Duration.zero);
      expect(realtime.started, isTrue);
      expect(fakeCoordinator.runs, 1);

      realtime.emit();
      await Future<void>.delayed(Duration.zero);
      expect(fakeCoordinator.runs, 2);

      await runtime.dispose();
      expect(realtime.disposed, isTrue);
      expect(fakeCoordinator.disposed, isTrue);
    },
  );
}
