import 'dart:async';

import 'package:drift/drift.dart';

import '../../../domain/common/domain_failure.dart';
import '../../../domain/common/entity_id.dart';
import '../../../domain/common/repository_result.dart';
import '../../../domain/events/event.dart' as domain;
import '../../../domain/events/event_repository.dart';
import 'app_database.dart';
import 'drift_mapping.dart';
import 'sqlite_failure_mapper.dart';

final class DriftEventRepository implements EventRepository {
  const DriftEventRepository(this.database);

  final AppDatabase database;

  @override
  Future<RepositoryResult<domain.Event>> getById(EventId id) async {
    final statement = database.select(database.events)
      ..where((table) => table.id.equals(id.value) & table.deletedAt.isNull());
    final row = await statement.getSingleOrNull();
    if (row == null) {
      return RepositoryFailure(
        NotFoundFailure(entity: 'Event', identifier: id.value),
      );
    }
    return _mapEvent(row);
  }

  @override
  Stream<RepositoryResult<List<domain.Event>>> observe(EventQuery query) {
    final statement = database.select(database.events)
      ..where((table) {
        var predicate = table.deletedAt.isNull();
        if (query.statuses.isNotEmpty) {
          predicate =
              predicate & table.status.isIn(query.statuses.map((e) => e.name));
        }
        if (query.type case final type?) {
          predicate = predicate & table.eventType.equals(type.name);
        }
        return predicate;
      })
      ..orderBy([(table) => OrderingTerm.asc(table.scheduledAt)])
      ..limit(query.limit);

    return statement.watch().map((rows) {
      try {
        return RepositorySuccess<List<domain.Event>>(
          rows.map(eventFromRow).toList(growable: false),
        );
      } on DomainFailure catch (failure) {
        return RepositoryFailure<List<domain.Event>>(failure);
      }
    });
  }

  @override
  Future<RepositoryResult<domain.Event>> save(
    domain.Event event, {
    int? expectedVersion,
  }) async {
    try {
      return await database.transaction(() async {
        final existing = await (database.select(
          database.events,
        )..where((table) => table.id.equals(event.id.value))).getSingleOrNull();
        if (expectedVersion != null && existing == null) {
          return RepositoryFailure<domain.Event>(
            NotFoundFailure(entity: 'Event', identifier: event.id.value),
          );
        }
        if (expectedVersion != null && existing!.version != expectedVersion) {
          return RepositoryFailure<domain.Event>(
            ConflictFailure(
              message:
                  'Event version does not match the expected local version.',
              expectedVersion: expectedVersion,
              actualVersion: existing.version,
            ),
          );
        }

        await database
            .into(database.events)
            .insertOnConflictUpdate(eventToCompanion(event));
        return RepositorySuccess(event);
      });
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } catch (error, stackTrace) {
      final failure = mapExpectedSqliteFailure(
        error,
        operation: 'Saving event',
      );
      if (failure != null) {
        return RepositoryFailure(failure);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  RepositoryResult<domain.Event> _mapEvent(LocalEventRow row) {
    try {
      return RepositorySuccess(eventFromRow(row));
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }
}
