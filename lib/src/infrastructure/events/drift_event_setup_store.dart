import 'package:drift/drift.dart';

import '../../application/events/event_setup_contracts.dart';
import '../../application/events/event_setup_models.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../persistence/local/app_database.dart';
import '../persistence/local/drift_mapping.dart';
import '../persistence/local/sqlite_failure_mapper.dart';
import 'event_setup_codec.dart';

final class DriftEventSetupStore implements EventSetupStore {
  const DriftEventSetupStore(this.database);

  final AppDatabase database;

  @override
  Future<RepositoryResult<List<EventSetup>>> listSetups() async {
    try {
      final rows =
          await (database.select(database.events)
                ..where((row) => row.deletedAt.isNull())
                ..orderBy([
                  (row) => OrderingTerm.desc(row.scheduledAt),
                  (row) => OrderingTerm.asc(row.id),
                ]))
              .get();
      final setups = <EventSetup>[];
      for (final row in rows) {
        setups.add(await _setupFor(row));
      }
      return RepositorySuccess(setups);
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }

  @override
  Future<RepositoryResult<EventSetup>> getSetup(EventId id) async {
    try {
      final row =
          await (database.select(database.events)..where(
                (table) => table.id.equals(id.value) & table.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      return row == null
          ? RepositoryFailure(
              NotFoundFailure(entity: 'Event', identifier: id.value),
            )
          : RepositorySuccess(await _setupFor(row));
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }

  Future<EventSetup> _setupFor(LocalEventRow row) async {
    final divisions =
        await (database.select(database.eventDivisions)
              ..where((table) => table.eventId.equals(row.id))
              ..orderBy([
                (table) => OrderingTerm.asc(table.name),
                (table) => OrderingTerm.asc(table.id),
              ]))
            .get();
    return EventSetup(
      event: eventFromRow(row),
      divisions: divisions.map(eventDivisionFromRow),
      readiness: await _readiness(row.id),
    );
  }

  Future<Map<DivisionId, DivisionTournamentReadiness>> _readiness(
    String eventId,
  ) async {
    final rows = await database
        .customSelect(
          '''
SELECT d.id, (SELECT count(*) FROM teams t WHERE t.division_id=d.id AND t.deleted_at IS NULL
  AND (SELECT count(*) FROM team_members tm JOIN players p ON p.id=tm.player_id
       WHERE tm.team_id=t.id AND tm.deleted_at IS NULL AND p.deleted_at IS NULL)=2) AS complete_teams,
  (SELECT count(*) FROM matches m WHERE m.division_id=d.id AND m.deleted_at IS NULL) AS active_matches,
  (SELECT count(*) FROM matches m WHERE m.division_id=d.id) AS generated_matches
FROM event_divisions d WHERE d.event_id=? AND d.deleted_at IS NULL
''',
          variables: [Variable(eventId)],
        )
        .get();
    return {
      for (final row in rows)
        DivisionId(row.read<String>('id')): DivisionTournamentReadiness(
          completeTeams: row.read<int>('complete_teams'),
          activeMatches: row.read<int>('active_matches'),
          generatedMatches: row.read<int>('generated_matches'),
        ),
    };
  }

  @override
  Future<RepositoryResult<EventSetupSaved>> save(
    EventSetup setup, {
    required SyncOperationId operationId,
    int? expectedVersion,
  }) async {
    try {
      return await database.transaction(() async {
        final existing =
            await (database.select(database.events)
                  ..where((row) => row.id.equals(setup.event.id.value)))
                .getSingleOrNull();
        if (expectedVersion != null && existing?.version != expectedVersion) {
          return RepositoryFailure<EventSetupSaved>(
            existing == null
                ? NotFoundFailure(
                    entity: 'Event',
                    identifier: setup.event.id.value,
                  )
                : ConflictFailure(
                    message: 'Event setup version changed.',
                    expectedVersion: expectedVersion,
                    actualVersion: existing.version,
                  ),
          );
        }
        if (existing == null && setup.event.metadata.recordVersion != 0) {
          return const RepositoryFailure(
            ConflictFailure(message: 'A new event must begin at version zero.'),
          );
        }
        if (existing != null &&
            existing.status != setup.event.status.name &&
            setup.event.status == EventStatus.inProgress) {
          final checked = EventSetup(
            event: setup.event,
            divisions: setup.divisions,
            readiness: await _readiness(existing.id),
          );
          if (!checked.canBegin) {
            throw const TournamentStructureRequiredFailure();
          }
        }
        await database
            .into(database.events)
            .insertOnConflictUpdate(eventToCompanion(setup.event));
        for (final division in setup.divisions) {
          await database
              .into(database.eventDivisions)
              .insertOnConflictUpdate(eventDivisionToCompanion(division));
        }
        await database
            .into(database.eventSetupOutboxOperations)
            .insert(
              EventSetupOutboxOperationsCompanion.insert(
                id: operationId.value,
                eventId: setup.event.id.value,
                baseVersion: Value(expectedVersion),
                payloadJson: encodeEventSetup(setup),
                createdAt: setup.event.metadata.updatedAt,
                status: 'pending',
              ),
            );
        return RepositorySuccess(
          EventSetupSaved(
            setup: await _setupFor(
              (await (database.select(
                database.events,
              )..where((e) => e.id.equals(setup.event.id.value))).getSingle()),
            ),
            disposition: EventMutationDisposition.pending,
          ),
        );
      });
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } catch (error, stackTrace) {
      final failure = mapExpectedSqliteFailure(
        error,
        operation: 'Saving event setup',
      );
      if (failure != null) return RepositoryFailure(failure);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<RepositoryResult<EventSetupSyncStatus>> syncStatus(EventId id) async {
    final conflict =
        await (database.select(database.eventSetupConflicts)
              ..where(
                (row) =>
                    row.eventId.equals(id.value) &
                    row.status.equals('unresolved'),
              )
              ..limit(1))
            .getSingleOrNull();
    if (conflict != null) {
      return const RepositorySuccess(
        EventSetupSyncStatus(disposition: EventMutationDisposition.conflicted),
      );
    }
    final outbox =
        await (database.select(database.eventSetupOutboxOperations)
              ..where((row) => row.eventId.equals(id.value))
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    final disposition = switch (outbox?.status) {
      'blocked' => EventMutationDisposition.blocked,
      'conflicted' => EventMutationDisposition.conflicted,
      null => EventMutationDisposition.synchronized,
      _ => EventMutationDisposition.pending,
    };
    return RepositorySuccess(
      EventSetupSyncStatus(
        disposition: disposition,
        message: outbox?.failureMessage,
      ),
    );
  }

  Future<List<EventSetupOperation>> pendingOperations() async {
    final rows =
        await (database.select(database.eventSetupOutboxOperations)
              ..where((row) => row.status.equals('pending'))
              ..orderBy([
                (row) => OrderingTerm.asc(row.createdAt),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    return rows
        .map(
          (row) => EventSetupOperation(
            operationId: SyncOperationId(row.id),
            setup: decodeEventSetup(row.payloadJson),
            baseVersion: row.baseVersion,
          ),
        )
        .toList();
  }

  Future<void> accept(
    EventSetupOperation operation,
    EventSetup authoritative,
  ) => database.transaction(() async {
    await (database.delete(
      database.eventSetupOutboxOperations,
    )..where((row) => row.id.equals(operation.operationId.value))).go();
    final later =
        await (database.select(database.eventSetupOutboxOperations)
              ..where((r) => r.eventId.equals(operation.setup.event.id.value))
              ..limit(1))
            .getSingleOrNull();
    if (later == null) await _replaceAuthoritative(authoritative);
  });

  Future<void> markBlocked(EventSetupOperation operation, String message) =>
      (database.update(
        database.eventSetupOutboxOperations,
      )..where((row) => row.id.equals(operation.operationId.value))).write(
        EventSetupOutboxOperationsCompanion(
          status: const Value('blocked'),
          failureMessage: Value(message),
        ),
      );

  Future<void> markFailed(EventSetupOperation operation, String message) =>
      (database.update(
        database.eventSetupOutboxOperations,
      )..where((row) => row.id.equals(operation.operationId.value))).write(
        EventSetupOutboxOperationsCompanion(
          status: const Value('failed'),
          failureMessage: Value(message),
        ),
      );

  Future<void> preserveConflict(
    EventSetupOperation operation,
    EventSetup? remote,
    SyncConflictId conflictId,
    DateTime now,
  ) => database.transaction(() async {
    await (database.update(
      database.eventSetupOutboxOperations,
    )..where((row) => row.id.equals(operation.operationId.value))).write(
      const EventSetupOutboxOperationsCompanion(status: Value('conflicted')),
    );
    await database
        .into(database.eventSetupConflicts)
        .insert(
          EventSetupConflictsCompanion.insert(
            id: conflictId.value,
            operationId: operation.operationId.value,
            eventId: operation.setup.event.id.value,
            localPayloadJson: encodeEventSetup(operation.setup),
            remotePayloadJson: Value(
              remote == null ? null : encodeEventSetup(remote),
            ),
            detectedAt: now,
            status: 'unresolved',
          ),
        );
  });

  Future<int> reconcile(List<EventSetup> setups, DateTime now) =>
      database.transaction(() async {
        var count = 0;
        for (final setup in setups) {
          final pending =
              await (database.select(database.eventSetupOutboxOperations)
                    ..where(
                      (row) =>
                          row.eventId.equals(setup.event.id.value) &
                          row.status.isIn([
                            'pending',
                            'blocked',
                            'conflicted',
                            'failed',
                          ]),
                    )
                    ..limit(1))
                  .getSingleOrNull();
          if (pending != null) return 0;
        }
        for (final setup in setups) {
          await _replaceAuthoritative(setup);
          count++;
        }
        if (setups.isNotEmpty) {
          final last = setups.last.event;
          await database
              .into(database.eventSetupPullCheckpoints)
              .insertOnConflictUpdate(
                EventSetupPullCheckpointsCompanion.insert(
                  singleton: const Value(1),
                  cursorUpdatedAt: last.metadata.updatedAt,
                  cursorEventId: last.id.value,
                  updatedAt: now,
                ),
              );
        }
        return count;
      });

  Future<(DateTime?, EventId?)> checkpoint() async {
    final row = await database
        .select(database.eventSetupPullCheckpoints)
        .getSingleOrNull();
    return row == null
        ? (null, null)
        : (row.cursorUpdatedAt.toUtc(), EventId(row.cursorEventId));
  }

  Future<void> _replaceAuthoritative(EventSetup setup) async {
    final existing = await (database.select(
      database.events,
    )..where((row) => row.id.equals(setup.event.id.value))).getSingleOrNull();
    if (existing != null) {
      final from = EventStatus.values.indexWhere(
        (status) => status.name == existing.status,
      );
      final to = EventStatus.values.indexOf(setup.event.status);
      for (var index = from + 1; index <= to; index++) {
        await (database.update(
          database.events,
        )..where((row) => row.id.equals(existing.id))).write(
          EventsCompanion(status: Value(EventStatus.values[index].name)),
        );
      }
    }
    await database
        .into(database.events)
        .insertOnConflictUpdate(eventToCompanion(setup.event));
    for (final division in setup.divisions) {
      await database
          .into(database.eventDivisions)
          .insertOnConflictUpdate(eventDivisionToCompanion(division));
    }
  }
}
