import 'package:drift/drift.dart';

import '../../application/sync/sync_contracts.dart';
import '../../application/sync/sync_models.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/players/permanent_player.dart';
import '../persistence/local/app_database.dart';
import '../persistence/local/drift_mapping.dart';
import 'player_sync_codec.dart';

final class DriftPlayerSyncStore implements PlayerSyncStore {
  const DriftPlayerSyncStore(this.database);

  final AppDatabase database;

  @override
  Future<void> recoverInterruptedOperations({required DateTime staleBefore}) =>
      (database.update(database.syncOutboxOperations)..where(
            (row) =>
                row.status.equals(SyncOperationStatus.inFlight.name) &
                row.claimedAt.isSmallerOrEqualValue(staleBefore),
          ))
          .write(
            const SyncOutboxOperationsCompanion(
              status: Value('pending'),
              claimedAt: Value(null),
            ),
          );

  @override
  Future<List<SyncOperation>> claimEligibleOperations({
    required DateTime now,
    required int limit,
  }) => database.transaction(() async {
    final unresolved = database.alias(
      database.syncConflicts,
      'unresolved_conflicts',
    );
    final query = database.select(database.syncOutboxOperations)
      ..where((row) {
        final hasNoConflict = notExistsQuery(
          database.selectOnly(unresolved)
            ..addColumns([unresolved.id])
            ..where(
              unresolved.entityType.equalsExp(row.entityType) &
                  unresolved.entityId.equalsExp(row.entityId) &
                  unresolved.status.equals(SyncConflictStatus.unresolved.name),
            ),
        );
        return row.status.equals(SyncOperationStatus.pending.name) &
            row.nextEligibleAt.isSmallerOrEqualValue(now) &
            hasNoConflict;
      })
      ..orderBy([
        (row) => OrderingTerm.asc(row.createdAt),
        (row) => OrderingTerm.asc(row.id),
      ])
      ..limit(limit);
    final rows = await query.get();
    for (final row in rows) {
      await (database.update(
        database.syncOutboxOperations,
      )..where((candidate) => candidate.id.equals(row.id))).write(
        SyncOutboxOperationsCompanion(
          status: const Value('inFlight'),
          claimedAt: Value(now),
        ),
      );
    }
    return rows.map(_operationFromRow).toList(growable: false);
  });

  @override
  Future<void> releaseClaims(Iterable<SyncOperation> operations) async {
    final ids = operations.map((operation) => operation.id.value).toList();
    if (ids.isEmpty) {
      return;
    }
    await (database.update(database.syncOutboxOperations)..where(
          (row) =>
              row.id.isIn(ids) &
              row.status.equals(SyncOperationStatus.inFlight.name),
        ))
        .write(
          const SyncOutboxOperationsCompanion(
            status: Value('pending'),
            claimedAt: Value(null),
          ),
        );
  }

  @override
  Future<void> acceptRemoteOperation(
    SyncOperation operation,
    PermanentPlayer authoritativePlayer,
  ) => database.transaction(() async {
    final laterLocal =
        await (database.select(database.syncOutboxOperations)
              ..where(
                (row) =>
                    row.entityType.equals(SyncEntityType.player.name) &
                    row.entityId.equals(operation.entityId.value) &
                    row.id.equals(operation.id.value).not() &
                    row.status.isIn([
                      SyncOperationStatus.pending.name,
                      SyncOperationStatus.inFlight.name,
                    ]),
              )
              ..limit(1))
            .getSingleOrNull();
    if (laterLocal == null) {
      await database
          .into(database.players)
          .insertOnConflictUpdate(playerToCompanion(authoritativePlayer));
    }
    await (database.delete(
      database.syncOutboxOperations,
    )..where((row) => row.id.equals(operation.id.value))).go();
  });

  @override
  Future<void> markRetryable(
    SyncOperation operation, {
    required DateTime nextEligibleAt,
    required String safeMessage,
  }) => _returnToPending(
    operation,
    nextEligibleAt: nextEligibleAt,
    failureCode: 'retryable',
    failureMessage: safeMessage,
  );

  @override
  Future<void> markAuthorizationBlocked(
    SyncOperation operation, {
    required DateTime nextEligibleAt,
  }) => _returnToPending(
    operation,
    nextEligibleAt: nextEligibleAt,
    failureCode: 'authorization_blocked',
    failureMessage: 'An authenticated organizer session is required.',
  );

  @override
  Future<void> markPermanentFailure(
    SyncOperation operation, {
    required String safeMessage,
  }) =>
      (database.update(
        database.syncOutboxOperations,
      )..where((row) => row.id.equals(operation.id.value))).write(
        SyncOutboxOperationsCompanion(
          status: const Value('failed'),
          claimedAt: const Value(null),
          attemptCount: Value(operation.attemptCount + 1),
          failureCode: const Value('permanent'),
          failureMessage: Value(_truncate(safeMessage)),
        ),
      );

  Future<void> _returnToPending(
    SyncOperation operation, {
    required DateTime nextEligibleAt,
    required String failureCode,
    required String failureMessage,
  }) =>
      (database.update(
        database.syncOutboxOperations,
      )..where((row) => row.id.equals(operation.id.value))).write(
        SyncOutboxOperationsCompanion(
          status: const Value('pending'),
          claimedAt: const Value(null),
          attemptCount: Value(operation.attemptCount + 1),
          nextEligibleAt: Value(nextEligibleAt),
          failureCode: Value(failureCode),
          failureMessage: Value(_truncate(failureMessage)),
        ),
      );

  @override
  Future<void> preserveConflict(
    SyncOperation operation, {
    required PermanentPlayer? remotePlayer,
    required DateTime detectedAt,
    required SyncConflictId conflictId,
  }) => database.transaction(() async {
    await (database.update(
      database.syncOutboxOperations,
    )..where((row) => row.id.equals(operation.id.value))).write(
      const SyncOutboxOperationsCompanion(
        status: Value('conflicted'),
        claimedAt: Value(null),
        failureCode: Value('conflict'),
        failureMessage: Value(
          'Remote version conflicts with the pending local mutation.',
        ),
      ),
    );
    await database
        .into(database.syncConflicts)
        .insert(
          SyncConflictsCompanion.insert(
            id: conflictId.value,
            operationId: operation.id.value,
            entityType: operation.entityType.name,
            entityId: operation.entityId.value,
            expectedVersion: Value(operation.baseVersion),
            localPayloadJson: encodePlayerPayload(operation.payload),
            remotePayloadJson: Value(
              remotePlayer == null
                  ? null
                  : encodePlayerPayload(
                      PlayerSyncPayload.fromPlayer(remotePlayer),
                    ),
            ),
            remoteVersion: Value(remotePlayer?.metadata.recordVersion),
            detectedAt: detectedAt,
            status: SyncConflictStatus.unresolved.name,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  });

  @override
  Future<SyncCheckpoint?> readCheckpoint() async {
    final row =
        await (database.select(database.syncPullCheckpoints)..where(
              (row) => row.entityType.equals(SyncEntityType.player.name),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : SyncCheckpoint(
            entityType: SyncEntityType.player,
            updatedAt: row.cursorUpdatedAt.toUtc(),
            entityId: PlayerId(row.cursorEntityId),
          );
  }

  @override
  Future<int> reconcilePullPage(
    RemotePullPage page, {
    required SyncCheckpoint? previousCheckpoint,
    required DateTime detectedAt,
    required SyncConflictId Function() conflictIdFactory,
  }) => database.transaction(() async {
    var applied = 0;
    PermanentPlayer? last;
    for (final remote in page.players) {
      last = remote;
      final pending =
          await (database.select(database.syncOutboxOperations)
                ..where(
                  (row) =>
                      row.entityType.equals(SyncEntityType.player.name) &
                      row.entityId.equals(remote.id.value) &
                      row.status.isIn([
                        SyncOperationStatus.pending.name,
                        SyncOperationStatus.inFlight.name,
                      ]),
                )
                ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
                ..limit(1))
              .getSingleOrNull();
      final local = await (database.select(
        database.players,
      )..where((row) => row.id.equals(remote.id.value))).getSingleOrNull();

      if (pending != null && !_samePlayerPayload(pending.payloadJson, remote)) {
        await preserveConflict(
          _operationFromRow(pending),
          remotePlayer: remote,
          detectedAt: detectedAt,
          conflictId: conflictIdFactory(),
        );
        continue;
      }
      if (local == null || remote.metadata.recordVersion > local.version) {
        await database
            .into(database.players)
            .insertOnConflictUpdate(playerToCompanion(remote));
        applied++;
      }
    }
    if (last != null) {
      await database
          .into(database.syncPullCheckpoints)
          .insertOnConflictUpdate(
            SyncPullCheckpointsCompanion.insert(
              entityType: SyncEntityType.player.name,
              cursorUpdatedAt: last.metadata.updatedAt,
              cursorEntityId: last.id.value,
              updatedAt: detectedAt,
            ),
          );
    }
    return applied;
  });

  @override
  Future<List<SyncConflict>> readUnresolvedConflicts() async {
    final rows =
        await (database.select(database.syncConflicts)
              ..where(
                (row) => row.status.equals(SyncConflictStatus.unresolved.name),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.detectedAt)]))
            .get();
    return rows
        .map((row) {
          final local = decodePlayerPayload(row.localPayloadJson);
          final remote = row.remotePayloadJson == null
              ? null
              : decodePlayerPayload(row.remotePayloadJson!).toPlayer();
          return SyncConflict(
            id: SyncConflictId(row.id),
            operationId: SyncOperationId(row.operationId),
            entityType: SyncEntityType.player,
            entityId: PlayerId(row.entityId),
            expectedVersion: row.expectedVersion,
            localProposal: local,
            remoteRecord: remote,
            remoteVersion: row.remoteVersion,
            detectedAt: row.detectedAt.toUtc(),
            status: SyncConflictStatus.unresolved,
          );
        })
        .toList(growable: false);
  }

  SyncOperation _operationFromRow(LocalSyncOutboxRow row) => SyncOperation(
    id: SyncOperationId(row.id),
    entityType: SyncEntityType.values.byName(row.entityType),
    entityId: PlayerId(row.entityId),
    kind: SyncOperationKind.values.byName(row.operationKind),
    baseVersion: row.baseVersion,
    payload: decodePlayerPayload(row.payloadJson),
    createdAt: row.createdAt.toUtc(),
    attemptCount: row.attemptCount,
    nextEligibleAt: row.nextEligibleAt.toUtc(),
    status: SyncOperationStatus.inFlight,
  );
}

bool _samePlayerPayload(String encoded, PermanentPlayer player) =>
    encoded == encodePlayerPayload(PlayerSyncPayload.fromPlayer(player));

String _truncate(String value) =>
    value.length <= 240 ? value : value.substring(0, 240);
