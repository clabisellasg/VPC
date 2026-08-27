import 'package:drift/drift.dart';

import '../../application/sync/sync_contracts.dart';
import '../../application/sync/sync_models.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/players/permanent_player.dart';
import '../../domain/players/player_repository.dart';
import '../persistence/local/app_database.dart';
import '../persistence/local/drift_mapping.dart';
import '../persistence/local/drift_player_repository.dart';
import '../persistence/local/sqlite_failure_mapper.dart';
import 'player_sync_codec.dart';

final class DriftSyncingPlayerRepository implements PlayerRepository {
  DriftSyncingPlayerRepository({
    required this.database,
    required this.idFactory,
    required this.clock,
  }) : _reads = DriftPlayerRepository(database);

  final AppDatabase database;
  final SyncIdFactory idFactory;
  final SyncClock clock;
  final DriftPlayerRepository _reads;

  @override
  Future<RepositoryResult<PermanentPlayer>> getById(PlayerId id) =>
      _reads.getById(id);

  @override
  Stream<RepositoryResult<List<PermanentPlayer>>> observe(
    PlayerSearchQuery query,
  ) => _reads.observe(query);

  @override
  Future<RepositoryResult<PermanentPlayer>> save(
    PermanentPlayer player, {
    int? expectedVersion,
  }) async {
    if (player.accountId != null) {
      return const RepositoryFailure(
        ValidationFailure(
          field: 'accountId',
          message:
              'Player account links remain outside the synchronization slice.',
        ),
      );
    }
    try {
      return await database.transaction(() async {
        final existing = await (database.select(
          database.players,
        )..where((row) => row.id.equals(player.id.value))).getSingleOrNull();
        if (expectedVersion != null && existing?.version != expectedVersion) {
          return RepositoryFailure<PermanentPlayer>(
            existing == null
                ? NotFoundFailure(entity: 'Player', identifier: player.id.value)
                : ConflictFailure(
                    message: 'Player version does not match the expected local version.',
                    expectedVersion: expectedVersion,
                    actualVersion: existing.version,
                  ),
          );
        }
        final baseVersion = existing?.version;
        final requiredVersion = baseVersion == null ? 0 : baseVersion + 1;
        if (player.metadata.recordVersion != requiredVersion) {
          return RepositoryFailure<PermanentPlayer>(
            ConflictFailure(
              message: 'A synchronized player mutation must advance exactly one version.',
              expectedVersion: requiredVersion,
              actualVersion: player.metadata.recordVersion,
            ),
          );
        }

        final operationId = idFactory.operationId();
        final now = clock.nowUtc();
        final payload = PlayerSyncPayload.fromPlayer(player);
        await database
            .into(database.players)
            .insertOnConflictUpdate(playerToCompanion(player));
        await database
            .into(database.syncOutboxOperations)
            .insert(
              SyncOutboxOperationsCompanion.insert(
                id: operationId.value,
                entityType: SyncEntityType.player.name,
                entityId: player.id.value,
                operationKind: player.metadata.isDeleted
                    ? SyncOperationKind.tombstone.name
                    : SyncOperationKind.upsert.name,
                baseVersion: Value(baseVersion),
                payloadJson: encodePlayerPayload(payload),
                createdAt: now,
                nextEligibleAt: now,
                status: SyncOperationStatus.pending.name,
              ),
            );
        return RepositorySuccess(player);
      });
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } catch (error, stackTrace) {
      final failure = mapExpectedSqliteFailure(
        error,
        operation: 'Saving and queueing player',
      );
      if (failure != null) {
        return RepositoryFailure(failure);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
