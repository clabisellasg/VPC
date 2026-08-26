import 'dart:async';

import 'package:drift/drift.dart';

import '../../../domain/common/domain_failure.dart';
import '../../../domain/common/entity_id.dart';
import '../../../domain/common/repository_result.dart';
import '../../../domain/matches/match.dart' as domain;
import '../../../domain/matches/match_repository.dart';
import 'app_database.dart';
import 'drift_mapping.dart';
import 'sqlite_failure_mapper.dart';

final class DriftMatchRepository implements MatchRepository {
  const DriftMatchRepository(this.database);

  final AppDatabase database;

  @override
  Future<RepositoryResult<domain.Match>> getById(MatchId id) async {
    final statement = database.select(database.matches)
      ..where((table) => table.id.equals(id.value) & table.deletedAt.isNull());
    final row = await statement.getSingleOrNull();
    if (row == null) {
      return RepositoryFailure(
        NotFoundFailure(entity: 'Match', identifier: id.value),
      );
    }
    return _mapMatch(row);
  }

  @override
  Stream<RepositoryResult<List<domain.Match>>> observeForDivision(
    DivisionId divisionId,
  ) {
    final statement = database.select(database.matches)
      ..where(
        (table) =>
            table.divisionId.equals(divisionId.value) &
            table.deletedAt.isNull(),
      )
      ..orderBy([
        (table) => OrderingTerm.asc(table.roundNumber),
        (table) => OrderingTerm.asc(table.sequenceNumber),
      ]);

    return statement.watch().map((rows) {
      try {
        return RepositorySuccess<List<domain.Match>>(
          rows.map(matchFromRow).toList(growable: false),
        );
      } on DomainFailure catch (failure) {
        return RepositoryFailure<List<domain.Match>>(failure);
      }
    });
  }

  @override
  Future<RepositoryResult<domain.Match>> save(
    domain.Match match, {
    int? expectedVersion,
  }) async {
    try {
      return await database.transaction(() async {
        final existing = await (database.select(
          database.matches,
        )..where((table) => table.id.equals(match.id.value))).getSingleOrNull();
        if (expectedVersion != null && existing == null) {
          return RepositoryFailure<domain.Match>(
            NotFoundFailure(entity: 'Match', identifier: match.id.value),
          );
        }
        if (expectedVersion != null && existing!.version != expectedVersion) {
          return RepositoryFailure<domain.Match>(
            ConflictFailure(
              message:
                  'Match version does not match the expected local version.',
              expectedVersion: expectedVersion,
              actualVersion: existing.version,
            ),
          );
        }

        await database
            .into(database.matches)
            .insertOnConflictUpdate(matchToCompanion(match));
        return RepositorySuccess(match);
      });
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } catch (error, stackTrace) {
      final failure = mapExpectedSqliteFailure(
        error,
        operation: 'Saving match',
      );
      if (failure != null) {
        return RepositoryFailure(failure);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  RepositoryResult<domain.Match> _mapMatch(LocalMatchRow row) {
    try {
      return RepositorySuccess(matchFromRow(row));
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }
}
