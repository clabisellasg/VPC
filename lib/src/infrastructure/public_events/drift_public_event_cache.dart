import 'package:drift/drift.dart';

import '../../application/public_events/public_event_models.dart';
import '../../application/public_events/public_event_reader.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/events/event_division.dart';
import '../persistence/local/app_database.dart';
import '../persistence/local/drift_mapping.dart';

typedef PublicCacheClock = DateTime Function();

final class DriftPublicEventCache implements PublicEventCache {
  DriftPublicEventCache(this.database, {this.clock = _utcNow});

  final AppDatabase database;
  final PublicCacheClock clock;

  @override
  Future<RepositoryResult<PublicEventCatalog?>> readCatalog() async {
    try {
      final eventRows =
          await (database.select(database.events)
                ..where((table) => table.deletedAt.isNull())
                ..orderBy([
                  (table) => OrderingTerm.asc(table.scheduledAt),
                  (table) => OrderingTerm.asc(table.id),
                ]))
              .get();
      if (eventRows.isEmpty) {
        return const RepositorySuccess(null);
      }
      final divisionRows =
          await (database.select(database.eventDivisions)
                ..where((table) => table.deletedAt.isNull())
                ..orderBy([
                  (table) => OrderingTerm.asc(table.name),
                  (table) => OrderingTerm.asc(table.id),
                ]))
              .get();
      final divisionsByEvent = <String, List<EventDivision>>{};
      for (final row in divisionRows) {
        final division = eventDivisionFromRow(row);
        divisionsByEvent.putIfAbsent(row.eventId, () => []).add(division);
      }
      final refreshedAt = eventRows
          .map((row) => row.updatedAt.toUtc())
          .reduce((left, right) => left.isAfter(right) ? left : right);
      return RepositorySuccess(
        PublicEventCatalog(
          events: eventRows.map((row) {
            final event = eventFromRow(row);
            return PublicEventItem(
              event: event,
              divisions: divisionsByEvent[row.id] ?? const [],
            );
          }),
          origin: PublicCatalogOrigin.androidCache,
          refreshedAt: refreshedAt,
        ),
      );
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } catch (error) {
      if (error is Error) {
        rethrow;
      }
      return const RepositoryFailure(
        PersistenceUnavailableFailure(
          message: 'Saved public event data is unavailable.',
        ),
      );
    }
  }

  @override
  Future<RepositoryResult<PublicEventCatalog>> reconcile(
    PublicEventCatalog authoritativeCatalog,
  ) async {
    try {
      final reconciledAt = clock().toUtc();
      await database.transaction(() async {
        final remoteEventIds = <String>{};
        final remoteDivisionIds = <String>{};
        final preservedEventIds = <String>{};
        for (final item in authoritativeCatalog.events) {
          remoteEventIds.add(item.event.id.value);
          if (await _hasPendingSetup(item.event.id.value)) {
            preservedEventIds.add(item.event.id.value);
            continue;
          }
          await _guardAndAdvanceStatus(item);
          await database
              .into(database.events)
              .insertOnConflictUpdate(eventToCompanion(item.event));
        }
        for (final item in authoritativeCatalog.events) {
          if (preservedEventIds.contains(item.event.id.value)) {
            continue;
          }
          for (final division in item.divisions) {
            remoteDivisionIds.add(division.id.value);
            await _guardDivisionVersion(division);
            await database
                .into(database.eventDivisions)
                .insertOnConflictUpdate(eventDivisionToCompanion(division));
          }
        }
        await _tombstoneMissingEvents(remoteEventIds, reconciledAt);
        await _tombstoneMissingDivisions(remoteDivisionIds, reconciledAt);
      });
      final cached = await readCatalog();
      final result = cached.when(
        success: (catalog) => RepositorySuccess(
          PublicEventCatalog(
            events: catalog?.events ?? const [],
            origin: PublicCatalogOrigin.remote,
            refreshedAt: authoritativeCatalog.refreshedAt,
          ),
        ),
        failure: RepositoryFailure<PublicEventCatalog>.new,
      );
      return result;
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } catch (error) {
      if (error is Error) {
        rethrow;
      }
      return const RepositoryFailure(
        PersistenceUnavailableFailure(
          message: 'Public event cache could not be refreshed.',
        ),
      );
    }
  }

  Future<void> _guardAndAdvanceStatus(PublicEventItem item) async {
    final existing =
        await (database.select(database.events)
              ..where((table) => table.id.equals(item.event.id.value)))
            .getSingleOrNull();
    if (existing == null) {
      return;
    }
    if (existing.version > item.event.metadata.recordVersion ||
        (existing.version == item.event.metadata.recordVersion &&
            existing.updatedAt.toUtc().isAfter(
              item.event.metadata.updatedAt,
            ))) {
      throw ConflictFailure(
        message: 'A newer local event version was preserved.',
        expectedVersion: existing.version,
        actualVersion: item.event.metadata.recordVersion,
      );
    }
    final existingStatus = _eventStatus(existing.status);
    final targetStatus = item.event.status;
    final from = EventStatus.values.indexOf(existingStatus);
    final to = EventStatus.values.indexOf(targetStatus);
    if (to < from) {
      throw ConflictFailure(
        message: 'A backward public event transition was rejected.',
        expectedVersion: existing.version,
        actualVersion: item.event.metadata.recordVersion,
      );
    }
    for (var index = from + 1; index <= to; index++) {
      await (database.update(
        database.events,
      )..where((table) => table.id.equals(item.event.id.value))).write(
        EventsCompanion(status: Value(EventStatus.values[index].name)),
      );
    }
  }

  Future<void> _guardDivisionVersion(EventDivision division) async {
    final existing = await (database.select(
      database.eventDivisions,
    )..where((table) => table.id.equals(division.id.value))).getSingleOrNull();
    if (existing != null &&
        (existing.version > division.metadata.recordVersion ||
            (existing.version == division.metadata.recordVersion &&
                existing.updatedAt.toUtc().isAfter(
                  division.metadata.updatedAt,
                )))) {
      throw ConflictFailure(
        message: 'A newer local division version was preserved.',
        expectedVersion: existing.version,
        actualVersion: division.metadata.recordVersion,
      );
    }
  }

  Future<void> _tombstoneMissingEvents(
    Set<String> authoritativeIds,
    DateTime reconciledAt,
  ) async {
    final activeRows = await (database.select(
      database.events,
    )..where((table) => table.deletedAt.isNull())).get();
    for (final row in activeRows) {
      if (!authoritativeIds.contains(row.id)) {
        if (await _hasPendingSetup(row.id)) {
          continue;
        }
        final timestamp = row.updatedAt.isAfter(reconciledAt)
            ? row.updatedAt.toUtc()
            : reconciledAt;
        await (database.update(
          database.events,
        )..where((table) => table.id.equals(row.id))).write(
          EventsCompanion(
            updatedAt: Value(timestamp),
            deletedAt: Value(timestamp),
          ),
        );
      }
    }
  }

  Future<void> _tombstoneMissingDivisions(
    Set<String> authoritativeIds,
    DateTime reconciledAt,
  ) async {
    final activeRows = await (database.select(
      database.eventDivisions,
    )..where((table) => table.deletedAt.isNull())).get();
    for (final row in activeRows) {
      if (!authoritativeIds.contains(row.id)) {
        if (await _hasPendingSetup(row.eventId)) {
          continue;
        }
        final timestamp = row.updatedAt.isAfter(reconciledAt)
            ? row.updatedAt.toUtc()
            : reconciledAt;
        await (database.update(
          database.eventDivisions,
        )..where((table) => table.id.equals(row.id))).write(
          EventDivisionsCompanion(
            updatedAt: Value(timestamp),
            deletedAt: Value(timestamp),
          ),
        );
      }
    }
  }

  Future<bool> _hasPendingSetup(String eventId) async {
    final row =
        await (database.select(database.eventSetupOutboxOperations)..where(
              (table) =>
                  table.eventId.equals(eventId) &
                  table.status.isIn(['pending', 'blocked', 'conflicted']),
            ))
            .getSingleOrNull();
    return row != null;
  }
}

EventStatus _eventStatus(String value) {
  for (final status in EventStatus.values) {
    if (status.name == value) {
      return status;
    }
  }
  throw ValidationFailure(
    field: 'status',
    message: 'Cached event status is unsupported.',
  );
}

DateTime _utcNow() => DateTime.now().toUtc();
