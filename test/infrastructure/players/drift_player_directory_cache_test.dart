import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/players/player_directory_models.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/players/permanent_player.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';
import 'package:vpc/src/infrastructure/persistence/local/drift_player_repository.dart';
import 'package:vpc/src/infrastructure/players/drift_player_directory_cache.dart';

void main() {
  late AppDatabase database;
  late DriftPlayerDirectoryCache cache;
  late DriftPlayerRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    cache = DriftPlayerDirectoryCache(database);
    repository = DriftPlayerRepository(database);
  });
  tearDown(() => database.close());

  test(
    'local directory normalizes search and orders by name then ID',
    () async {
      await repository.save(player(id: playerTwo, name: '  bravo  Player '));
      await repository.save(player(id: playerOne, name: 'Alpha Player'));
      final result = await cache.readPage(
        PlayerDirectoryQuery(searchText: 'PLAYER'),
      );
      result.when(
        success: (page) {
          expect(page.entries.map((e) => e.profile.displayName), [
            'Alpha Player',
            'bravo Player',
          ]);
          expect(page.origin, PlayerDirectoryOrigin.androidLocal);
        },
        failure: (failure) => fail(failure.message),
      );
    },
  );

  test('tombstoned players are excluded from list and detail', () async {
    await repository.save(
      player(id: playerOne, name: 'Deleted', deleted: true),
    );
    final page = await cache.readPage(PlayerDirectoryQuery());
    page.when(
      success: (value) => expect(value.entries, isEmpty),
      failure: (failure) => fail(failure.message),
    );
    final detail = await cache.getById(PlayerId(playerOne));
    expect(detail.isSuccess, isFalse);
  });

  test('remote public reconciliation creates no outbox operation', () async {
    final remote = PlayerDirectoryPage(
      entries: [
        PlayerDirectoryEntry(
          profile: PublicPlayerProfile(
            id: PlayerId(playerOne),
            displayName: 'VPC Remote Player',
            metadata: metadata(),
          ),
        ),
      ],
      hasMore: false,
      origin: PlayerDirectoryOrigin.remote,
    );
    final result = await cache.reconcile(remote);
    expect(result.isSuccess, isTrue);
    expect(await database.select(database.syncOutboxOperations).get(), isEmpty);
    expect((await repository.getById(PlayerId(playerOne))).isSuccess, isTrue);
  });

  test('remote reconciliation does not overwrite a pending local operation', () async {
    await repository.save(player(id: playerOne, name: 'Local Proposal'));
    await database.customStatement(
      "INSERT INTO sync_outbox_operations "
      "(id, entity_type, entity_id, operation_kind, payload_json, created_at, "
      "attempt_count, next_eligible_at, status) VALUES "
      "('83000000-0000-4000-8000-000000000001','player',?, 'upsert','{}',?,0,?,'pending')",
      [playerOne, testNow.toIso8601String(), testNow.toIso8601String()],
    );
    final remote = PlayerDirectoryPage(
      entries: [
        PlayerDirectoryEntry(
          profile: PublicPlayerProfile(
            id: PlayerId(playerOne),
            displayName: 'Remote Replacement',
            metadata: metadata(version: 2),
          ),
        ),
      ],
      hasMore: false,
      origin: PlayerDirectoryOrigin.remote,
    );
    await cache.reconcile(remote);
    final result = await repository.getById(PlayerId(playerOne));
    result.when(
      success: (value) => expect(value.displayName, 'Local Proposal'),
      failure: (failure) => fail(failure.message),
    );
  });

  test('an unresolved conflict is visible and never auto-resolved', () async {
    await repository.save(player(id: playerOne, name: 'Local Conflict'));
    const operationId = '83000000-0000-4000-8000-000000000002';
    await database.customStatement(
      "INSERT INTO sync_outbox_operations "
      "(id, entity_type, entity_id, operation_kind, payload_json, created_at, "
      "attempt_count, next_eligible_at, status) VALUES "
      "(?,'player',?, 'upsert','{}',?,0,?,'conflicted')",
      [
        operationId,
        playerOne,
        testNow.toIso8601String(),
        testNow.toIso8601String(),
      ],
    );
    await database
        .into(database.syncConflicts)
        .insert(
          SyncConflictsCompanion.insert(
            id: '83000000-0000-4000-8000-000000000003',
            operationId: operationId,
            entityType: 'player',
            entityId: playerOne,
            localPayloadJson: '{}',
            detectedAt: testNow,
            status: 'unresolved',
          ),
        );

    final before = await cache.readPage(PlayerDirectoryQuery());
    before.when(
      success: (page) => expect(
        page.entries.single.syncState,
        PlayerSyncPresentation.conflicted,
      ),
      failure: (failure) => fail(failure.message),
    );
    await cache.reconcile(
      PlayerDirectoryPage(
        entries: [
          PlayerDirectoryEntry(
            profile: PublicPlayerProfile(
              id: PlayerId(playerOne),
              displayName: 'Remote Conflict',
              metadata: metadata(version: 3),
            ),
          ),
        ],
        hasMore: false,
        origin: PlayerDirectoryOrigin.remote,
      ),
    );
    final after = await repository.getById(PlayerId(playerOne));
    after.when(
      success: (value) => expect(value.displayName, 'Local Conflict'),
      failure: (failure) => fail(failure.message),
    );
    expect(await database.select(database.syncConflicts).get(), hasLength(1));
  });
}

const playerOne = '83000000-0000-4000-8000-000000000011';
const playerTwo = '83000000-0000-4000-8000-000000000012';
final testNow = DateTime.utc(2026, 8, 29, 2);

RecordMetadata metadata({int version = 0, DateTime? deletedAt}) =>
    RecordMetadata(
      createdAt: testNow,
      updatedAt: testNow.add(Duration(minutes: version)),
      recordVersion: version,
      deletedAt: deletedAt,
    );

PermanentPlayer player({
  required String id,
  required String name,
  bool deleted = false,
}) => PermanentPlayer(
  id: PlayerId(id),
  displayName: name,
  metadata: metadata(deletedAt: deleted ? testNow : null),
);
