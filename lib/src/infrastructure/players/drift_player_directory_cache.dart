import 'package:drift/drift.dart';

import '../../application/players/player_directory_models.dart';
import '../../application/players/player_directory_reader.dart';
import '../../application/sync/sync_models.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../persistence/local/app_database.dart';
import '../persistence/local/drift_mapping.dart';
import '../persistence/local/sqlite_failure_mapper.dart';

final class DriftPlayerDirectoryCache implements PlayerDirectoryCache {
  const DriftPlayerDirectoryCache(this.database);

  final AppDatabase database;

  @override
  Future<RepositoryResult<PlayerDirectoryPage>> readPage(
    PlayerDirectoryQuery query,
  ) async {
    try {
      final rows = await (database.select(
        database.players,
      )..where((row) => row.deletedAt.isNull())).get();
      final profiles =
          rows
              .map(playerFromRow)
              .map(PublicPlayerProfile.fromPlayer)
              .where(
                (profile) =>
                    normalizePlayerName(profile.displayName)
                        .contains(query.searchText),
              )
              .toList(growable: false)
            ..sort(_compareProfiles);
      final after = query.after;
      final remaining = after == null
          ? profiles
          : profiles.where((profile) => _isAfter(profile, after)).toList();
      final pageProfiles = remaining.take(query.limit).toList(growable: false);
      final states = await _syncStates(
        pageProfiles.map((profile) => profile.id),
      );
      return RepositorySuccess(
        PlayerDirectoryPage(
          entries: pageProfiles.map(
            (profile) => PlayerDirectoryEntry(
              profile: profile,
              syncState:
                  states[profile.id] ?? PlayerSyncPresentation.synchronized,
            ),
          ),
          hasMore: remaining.length > pageProfiles.length,
          origin: PlayerDirectoryOrigin.androidLocal,
        ),
      );
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }

  @override
  Future<RepositoryResult<PlayerDirectoryEntry>> getById(PlayerId id) async {
    try {
      final row =
          await (database.select(database.players)..where(
                (row) => row.id.equals(id.value) & row.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (row == null) {
        return RepositoryFailure(
          NotFoundFailure(entity: 'Player', identifier: id.value),
        );
      }
      final states = await _syncStates([id]);
      return RepositorySuccess(
        PlayerDirectoryEntry(
          profile: PublicPlayerProfile.fromPlayer(playerFromRow(row)),
          syncState: states[id] ?? PlayerSyncPresentation.synchronized,
        ),
      );
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }

  @override
  Future<RepositoryResult<void>> reconcile(
    PlayerDirectoryPage remotePage,
  ) async {
    try {
      await database.transaction(() async {
        for (final entry in remotePage.entries) {
          final remote = entry.profile;
          final pending =
              await (database.select(database.syncOutboxOperations)
                    ..where(
                      (row) =>
                          row.entityType.equals(SyncEntityType.player.name) &
                          row.entityId.equals(remote.id.value) &
                          row.status.isIn([
                            SyncOperationStatus.pending.name,
                            SyncOperationStatus.inFlight.name,
                            SyncOperationStatus.failed.name,
                            SyncOperationStatus.conflicted.name,
                          ]),
                    )
                    ..limit(1))
                  .getSingleOrNull();
          final conflict =
              await (database.select(database.syncConflicts)
                    ..where(
                      (row) =>
                          row.entityType.equals(SyncEntityType.player.name) &
                          row.entityId.equals(remote.id.value) &
                          row.status.equals(SyncConflictStatus.unresolved.name),
                    )
                    ..limit(1))
                  .getSingleOrNull();
          if (pending != null || conflict != null) {
            continue;
          }
          final local = await (database.select(
            database.players,
          )..where((row) => row.id.equals(remote.id.value))).getSingleOrNull();
          if (local == null || remote.metadata.recordVersion > local.version) {
            await database
                .into(database.players)
                .insertOnConflictUpdate(playerToCompanion(remote.toPlayer()));
          }
        }
      });
      return const RepositorySuccess<void>(null);
    } catch (error, stackTrace) {
      if (error is DomainFailure) {
        return RepositoryFailure(error);
      }
      final failure = mapExpectedSqliteFailure(
        error,
        operation: 'Reconciling public players',
      );
      if (failure != null) {
        return RepositoryFailure(failure);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<Map<PlayerId, PlayerSyncPresentation>> _syncStates(
    Iterable<PlayerId> ids,
  ) async {
    final values = ids.map((id) => id.value).toList(growable: false);
    if (values.isEmpty) {
      return const {};
    }
    final states = <PlayerId, PlayerSyncPresentation>{};
    final conflicts =
        await (database.select(database.syncConflicts)..where(
              (row) =>
                  row.entityType.equals(SyncEntityType.player.name) &
                  row.entityId.isIn(values) &
                  row.status.equals(SyncConflictStatus.unresolved.name),
            ))
            .get();
    for (final row in conflicts) {
      states[PlayerId(row.entityId)] = PlayerSyncPresentation.conflicted;
    }
    final operations =
        await (database.select(database.syncOutboxOperations)
              ..where(
                (row) =>
                    row.entityType.equals(SyncEntityType.player.name) &
                    row.entityId.isIn(values),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
            .get();
    for (final row in operations) {
      final id = PlayerId(row.entityId);
      if (states.containsKey(id)) {
        continue;
      }
      states[id] = switch (row.status) {
        'conflicted' => PlayerSyncPresentation.conflicted,
        'failed' => PlayerSyncPresentation.failed,
        _ when row.failureCode == 'authorization_blocked' =>
          PlayerSyncPresentation.authorizationBlocked,
        _ => PlayerSyncPresentation.pending,
      };
    }
    return states;
  }
}

int _compareProfiles(PublicPlayerProfile left, PublicPlayerProfile right) {
  final name = normalizePlayerName(left.displayName)
      .compareTo(normalizePlayerName(right.displayName));
  return name != 0 ? name : left.id.value.compareTo(right.id.value);
}

bool _isAfter(PublicPlayerProfile profile, PlayerDirectoryCursor cursor) {
  final name = normalizePlayerName(profile.displayName);
  final comparison = name.compareTo(cursor.normalizedName);
  return comparison > 0 ||
      (comparison == 0 && profile.id.value.compareTo(cursor.id.value) > 0);
}
