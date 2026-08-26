import 'dart:async';

import 'package:drift/drift.dart';

import '../../../domain/common/domain_failure.dart';
import '../../../domain/common/entity_id.dart';
import '../../../domain/common/repository_result.dart';
import '../../../domain/players/permanent_player.dart';
import '../../../domain/players/player_repository.dart';
import 'app_database.dart';
import 'drift_mapping.dart';
import 'sqlite_failure_mapper.dart';

final class DriftPlayerRepository implements PlayerRepository {
  const DriftPlayerRepository(this.database);

  final AppDatabase database;

  @override
  Future<RepositoryResult<PermanentPlayer>> getById(PlayerId id) async {
    final statement = database.select(database.players)
      ..where((table) => table.id.equals(id.value) & table.deletedAt.isNull());
    final row = await statement.getSingleOrNull();
    if (row == null) {
      return RepositoryFailure(
        NotFoundFailure(entity: 'Player', identifier: id.value),
      );
    }
    return _mapPlayer(row);
  }

  @override
  Stream<RepositoryResult<List<PermanentPlayer>>> observe(
    PlayerSearchQuery query,
  ) {
    final statement = database.select(database.players)
      ..where((table) {
        var predicate = table.deletedAt.isNull();
        if (query.nameContains case final term?) {
          predicate =
              predicate &
              table.displayName.lower().like('%${term.toLowerCase()}%');
        }
        return predicate;
      })
      ..orderBy([(table) => OrderingTerm.asc(table.displayName)])
      ..limit(query.limit);

    return statement.watch().map((rows) {
      try {
        return RepositorySuccess<List<PermanentPlayer>>(
          rows.map(playerFromRow).toList(growable: false),
        );
      } on DomainFailure catch (failure) {
        return RepositoryFailure<List<PermanentPlayer>>(failure);
      }
    });
  }

  @override
  Future<RepositoryResult<PermanentPlayer>> save(
    PermanentPlayer player, {
    int? expectedVersion,
  }) async {
    if (player.accountId != null) {
      return const RepositoryFailure(
        ValidationFailure(
          field: 'accountId',
          message: 'Player account links are not persisted before the approved claim workflow.',
        ),
      );
    }
    try {
      return await database.transaction(() async {
        final existing =
            await (database.select(database.players)
                  ..where((table) => table.id.equals(player.id.value)))
                .getSingleOrNull();
        final conflict = _versionFailure(
          existing?.version,
          expectedVersion,
          entity: 'Player',
          identifier: player.id.value,
        );
        if (conflict != null) {
          return RepositoryFailure<PermanentPlayer>(conflict);
        }

        await database
            .into(database.players)
            .insertOnConflictUpdate(playerToCompanion(player));
        return RepositorySuccess(player);
      });
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } catch (error, stackTrace) {
      final failure = mapExpectedSqliteFailure(
        error,
        operation: 'Saving player',
      );
      if (failure != null) {
        return RepositoryFailure(failure);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  RepositoryResult<PermanentPlayer> _mapPlayer(LocalPlayerRow row) {
    try {
      return RepositorySuccess(playerFromRow(row));
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }
}

DomainFailure? _versionFailure(
  int? actualVersion,
  int? expectedVersion, {
  required String entity,
  required String identifier,
}) {
  if (expectedVersion == null) {
    return null;
  }
  if (actualVersion == null) {
    return NotFoundFailure(entity: entity, identifier: identifier);
  }
  if (actualVersion != expectedVersion) {
    return ConflictFailure(
      message: '$entity version does not match the expected local version.',
      expectedVersion: expectedVersion,
      actualVersion: actualVersion,
    );
  }
  return null;
}
