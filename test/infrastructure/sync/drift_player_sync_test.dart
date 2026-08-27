import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/sync/sync_models.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/players/permanent_player.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';
import 'package:vpc/src/infrastructure/persistence/local/drift_mapping.dart';
import 'package:vpc/src/infrastructure/sync/drift_player_sync_store.dart';
import 'package:vpc/src/infrastructure/sync/drift_syncing_player_repository.dart';
import 'package:vpc/src/infrastructure/sync/player_sync_codec.dart';

import '../../application/sync/sync_test_fakes.dart';

const playerId = '10000000-0000-4000-8000-000000000001';
const operationOne = '20000000-0000-4000-8000-000000000001';
const operationTwo = '20000000-0000-4000-8000-000000000002';
const conflictOne = '30000000-0000-4000-8000-000000000001';
final createdAt = DateTime.utc(2026, 8, 28, 1);

PermanentPlayer player({
  String name = 'Player One',
  int version = 0,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) => PermanentPlayer(
  id: PlayerId(playerId),
  displayName: name,
  metadata: RecordMetadata(
    createdAt: createdAt,
    updatedAt: updatedAt ?? createdAt.add(Duration(minutes: version)),
    recordVersion: version,
    deletedAt: deletedAt,
  ),
);

void main() {
  late AppDatabase database;
  late FakeSyncClock clock;

  setUp(() {
    database = AppDatabase.inMemory();
    clock = FakeSyncClock(DateTime.utc(2026, 8, 28, 2));
  });

  tearDown(() => database.close());

  test(
    'fresh v2 schema has constrained outbox, checkpoint, and conflict tables',
    () async {
      final tables = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'sync_%'",
          )
          .get();
      expect(tables, hasLength(3));
      await expectLater(
        database
            .into(database.syncOutboxOperations)
            .insert(
              SyncOutboxOperationsCompanion.insert(
                id: operationOne,
                entityType: 'event',
                entityId: playerId,
                operationKind: 'upsert',
                payloadJson: '{}',
                createdAt: clock.current,
                nextEligibleAt: clock.current,
                status: 'pending',
              ),
            ),
        throwsA(anything),
      );
    },
  );

  test('player mutation and outbox operation commit atomically', () async {
    final repository = DriftSyncingPlayerRepository(
      database: database,
      idFactory: QueueSyncIdFactory(operationIds: [operationOne]),
      clock: clock,
    );

    final result = await repository.save(player());
    expect(result, isA<RepositorySuccess<PermanentPlayer>>());
    expect(await database.select(database.players).get(), hasLength(1));
    final outbox = await database
        .select(database.syncOutboxOperations)
        .getSingle();
    expect(outbox.id, operationOne);
    expect(outbox.entityId, playerId);
    expect(outbox.baseVersion, isNull);
    expect(
      decodePlayerPayload(outbox.payloadJson).toPlayer().id.value,
      playerId,
    );
  });

  test('outbox insertion failure rolls back the player mutation', () async {
    await database.into(database.players).insert(playerToCompanion(player()));
    await database
        .into(database.syncOutboxOperations)
        .insert(
          SyncOutboxOperationsCompanion.insert(
            id: operationOne,
            entityType: 'player',
            entityId: playerId,
            operationKind: 'upsert',
            payloadJson: encodePlayerPayload(
              PlayerSyncPayload.fromPlayer(player()),
            ),
            createdAt: clock.current,
            nextEligibleAt: clock.current,
            status: 'pending',
          ),
        );
    final repository = DriftSyncingPlayerRepository(
      database: database,
      idFactory: QueueSyncIdFactory(operationIds: [operationOne]),
      clock: clock,
    );

    final result = await repository.save(
      player(name: 'Changed', version: 1),
      expectedVersion: 0,
    );
    expect(result.isSuccess, isFalse);
    expect(
      (await database.select(database.players).getSingle()).displayName,
      'Player One',
    );
  });

  test(
    'queue claims deterministically and recovers interrupted work',
    () async {
      await database.into(database.players).insert(playerToCompanion(player()));
      for (final entry in [(operationTwo, 2), (operationOne, 1)]) {
        await database
            .into(database.syncOutboxOperations)
            .insert(
              SyncOutboxOperationsCompanion.insert(
                id: entry.$1,
                entityType: 'player',
                entityId: playerId,
                operationKind: 'upsert',
                payloadJson: encodePlayerPayload(
                  PlayerSyncPayload.fromPlayer(player()),
                ),
                createdAt: clock.current.add(Duration(minutes: entry.$2)),
                nextEligibleAt: clock.current,
                status: 'pending',
              ),
            );
      }
      final store = DriftPlayerSyncStore(database);
      final claimed = await store.claimEligibleOperations(
        now: clock.current,
        limit: 1,
      );
      expect(claimed.single.id.value, operationOne);
      await store.recoverInterruptedOperations(
        staleBefore: clock.current.add(const Duration(minutes: 1)),
      );
      final row = await (database.select(
        database.syncOutboxOperations,
      )..where((row) => row.id.equals(operationOne))).getSingle();
      expect(row.status, 'pending');
      expect(row.claimedAt, isNull);
    },
  );

  test(
    'conflict preserves local and remote payloads and stops retrying',
    () async {
      final repository = DriftSyncingPlayerRepository(
        database: database,
        idFactory: QueueSyncIdFactory(operationIds: [operationOne]),
        clock: clock,
      );
      await repository.save(player());
      final store = DriftPlayerSyncStore(database);
      final operation = (await store.claimEligibleOperations(
        now: clock.current,
        limit: 1,
      )).single;
      final remote = player(name: 'Remote', version: 1);
      await store.preserveConflict(
        operation,
        remotePlayer: remote,
        detectedAt: clock.current,
        conflictId: SyncConflictId(conflictOne),
      );

      final conflicts = await store.readUnresolvedConflicts();
      expect(conflicts.single.localProposal.displayName, 'Player One');
      expect(conflicts.single.remoteRecord?.displayName, 'Remote');
      expect(
        (await database.select(database.syncOutboxOperations).getSingle())
            .status,
        'conflicted',
      );
    },
  );

  test(
    'pull reconciles newer records and advances checkpoint atomically',
    () async {
      await database.into(database.players).insert(playerToCompanion(player()));
      final store = DriftPlayerSyncStore(database);
      final remote = player(name: 'Remote', version: 1);
      final applied = await store.reconcilePullPage(
        RemotePullPage(players: [remote], hasMore: false),
        previousCheckpoint: null,
        detectedAt: clock.current,
        conflictIdFactory: () => SyncConflictId(conflictOne),
      );

      expect(applied, 1);
      expect(
        (await database.select(database.players).getSingle()).displayName,
        'Remote',
      );
      final checkpoint = await store.readCheckpoint();
      expect(checkpoint?.entityId.value, playerId);
      expect(checkpoint?.updatedAt, remote.metadata.updatedAt);
    },
  );

  test('equal-version pull is idempotent and tombstones round-trip', () async {
    final deletedAt = createdAt.add(const Duration(minutes: 2));
    final tombstone = player(
      version: 1,
      updatedAt: createdAt.add(const Duration(minutes: 1)),
      deletedAt: deletedAt,
    );
    await database.into(database.players).insert(playerToCompanion(tombstone));
    final store = DriftPlayerSyncStore(database);
    expect(
      await store.reconcilePullPage(
        RemotePullPage(players: [tombstone], hasMore: false),
        previousCheckpoint: null,
        detectedAt: clock.current,
        conflictIdFactory: () => SyncConflictId(conflictOne),
      ),
      0,
    );
    expect(
      (await database.select(database.players).getSingle()).deletedAt,
      deletedAt,
    );
  });

  test(
    'pending local mutation wins neither side and becomes a conflict',
    () async {
      final repository = DriftSyncingPlayerRepository(
        database: database,
        idFactory: QueueSyncIdFactory(operationIds: [operationOne]),
        clock: clock,
      );
      await repository.save(player(name: 'Local'));
      final store = DriftPlayerSyncStore(database);
      final remote = player(name: 'Remote', version: 1);

      final applied = await store.reconcilePullPage(
        RemotePullPage(players: [remote], hasMore: false),
        previousCheckpoint: null,
        detectedAt: clock.current,
        conflictIdFactory: () => SyncConflictId(conflictOne),
      );

      expect(applied, 0);
      expect(
        (await database.select(database.players).getSingle()).displayName,
        'Local',
      );
      expect(
        (await store.readUnresolvedConflicts())
            .single
            .remoteRecord
            ?.displayName,
        'Remote',
      );
    },
  );
}
