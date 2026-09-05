import 'package:drift/drift.dart';

import '../../application/participation/participation_contracts.dart';
import '../../application/participation/participation_models.dart';
import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/events/division_participant.dart';
import '../../domain/events/event_participant.dart';
import '../../domain/events/participant_payment.dart';
import '../persistence/local/app_database.dart';
import '../persistence/local/drift_mapping.dart';
import '../persistence/local/sqlite_failure_mapper.dart';
import 'participation_codec.dart';

final class DriftParticipationStore implements ParticipationStore {
  const DriftParticipationStore(this.database);
  final AppDatabase database;

  @override
  Future<RepositoryResult<List<ParticipationRecord>>> listForEvent(
    EventId eventId,
  ) async {
    try {
      final rows =
          await (database.select(database.eventParticipants)
                ..where(
                  (row) =>
                      row.eventId.equals(eventId.value) &
                      row.deletedAt.isNull(),
                )
                ..orderBy([(row) => OrderingTerm.asc(row.id)]))
              .get();
      final records = <ParticipationRecord>[];
      for (final row in rows) {
        records.add(await _recordFor(row));
      }
      records.sort((a, b) {
        final byName = a.playerDisplayName.toLowerCase().compareTo(
          b.playerDisplayName.toLowerCase(),
        );
        return byName != 0
            ? byName
            : a.participant.id.value.compareTo(b.participant.id.value);
      });
      return RepositorySuccess(records);
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }

  @override
  Future<RepositoryResult<ParticipationRecord>> get(
    EventParticipantId id,
  ) async {
    try {
      final row = await (database.select(
        database.eventParticipants,
      )..where((table) => table.id.equals(id.value))).getSingleOrNull();
      return row == null
          ? RepositoryFailure(
              NotFoundFailure(
                entity: 'Event participant',
                identifier: id.value,
              ),
            )
          : RepositorySuccess(await _recordFor(row));
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    }
  }

  Future<ParticipationRecord> _recordFor(LocalEventParticipantRow row) async {
    final player = await (database.select(
      database.players,
    )..where((table) => table.id.equals(row.playerId))).getSingle();
    final assignments =
        await (database.select(database.divisionParticipants)
              ..where((table) => table.eventParticipantId.equals(row.id))
              ..orderBy([(table) => OrderingTerm.asc(table.id)]))
            .get();
    final payment =
        await (database.select(database.participantPayments)..where(
              (table) =>
                  table.eventParticipantId.equals(row.id) &
                  table.divisionId.isNull(),
            ))
            .getSingleOrNull();
    if (payment == null) {
      throw const ValidationFailure(
        field: 'payment',
        message: 'Stored participant payment record is missing.',
      );
    }
    return ParticipationRecord(
      participant: EventParticipant(
        id: EventParticipantId(row.id),
        eventId: EventId(row.eventId),
        playerId: PlayerId(row.playerId),
        checkInStatus: enumValue(
          CheckInStatus.values,
          row.checkInStatus,
          field: 'checkInStatus',
        ),
        metadata: metadataFromValues(
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
          version: row.version,
          deletedAt: row.deletedAt,
        ),
      ),
      playerDisplayName: player.displayName,
      divisions: assignments.map(
        (item) => DivisionParticipant(
          id: DivisionParticipantId(item.id),
          divisionId: DivisionId(item.divisionId),
          eventParticipantId: EventParticipantId(item.eventParticipantId),
          metadata: metadataFromValues(
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            version: item.version,
            deletedAt: item.deletedAt,
          ),
        ),
      ),
      payment: ParticipantPayment(
        id: ParticipantPaymentId(payment.id),
        eventParticipantId: EventParticipantId(payment.eventParticipantId),
        divisionId: payment.divisionId == null
            ? null
            : DivisionId(payment.divisionId!),
        status: enumValue(
          PaymentStatus.values,
          payment.status,
          field: 'paymentStatus',
        ),
        metadata: metadataFromValues(
          createdAt: payment.createdAt,
          updatedAt: payment.updatedAt,
          version: payment.version,
          deletedAt: payment.deletedAt,
        ),
      ),
    );
  }

  @override
  Future<RepositoryResult<ParticipationSaved>> save(
    ParticipationRecord record, {
    required SyncOperationId operationId,
    int? expectedVersion,
  }) async {
    try {
      return await database.transaction(() async {
        final existing =
            await (database.select(database.eventParticipants)
                  ..where((row) => row.id.equals(record.participant.id.value)))
                .getSingleOrNull();
        if (expectedVersion != null && existing?.version != expectedVersion) {
          return RepositoryFailure<ParticipationSaved>(
            ConflictFailure(
              message: 'Participant version changed.',
              expectedVersion: expectedVersion,
              actualVersion: existing?.version,
            ),
          );
        }
        if (existing == null) {
          final duplicate =
              await (database.select(database.eventParticipants)..where(
                    (row) =>
                        row.eventId.equals(record.participant.eventId.value) &
                        row.playerId.equals(record.participant.playerId.value) &
                        row.deletedAt.isNull(),
                  ))
                  .getSingleOrNull();
          if (duplicate != null) {
            return const RepositoryFailure(
              ConflictFailure(
                message: 'Player is already registered for this event.',
              ),
            );
          }
        }
        await database
            .into(database.eventParticipants)
            .insertOnConflictUpdate(_participantCompanion(record.participant));
        for (final assignment in record.divisions) {
          await database
              .into(database.divisionParticipants)
              .insertOnConflictUpdate(_divisionCompanion(assignment));
        }
        await database
            .into(database.participantPayments)
            .insertOnConflictUpdate(_paymentCompanion(record.payment));
        await database
            .into(database.participationOutboxOperations)
            .insert(
              ParticipationOutboxOperationsCompanion.insert(
                id: operationId.value,
                eventParticipantId: record.participant.id.value,
                baseVersion: Value(expectedVersion),
                payloadJson: encodeParticipation(record),
                createdAt: record.participant.metadata.updatedAt,
                status: 'pending',
              ),
            );
        return RepositorySuccess(
          ParticipationSaved(
            record: record,
            disposition: ParticipationMutationDisposition.pending,
          ),
        );
      });
    } catch (error, stackTrace) {
      final failure = mapExpectedSqliteFailure(
        error,
        operation: 'Saving participation',
      );
      if (failure != null) return RepositoryFailure(failure);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<RepositoryResult<ParticipationSyncStatus>> syncStatus(
    EventParticipantId id,
  ) async {
    final conflicts =
        await (database.select(database.participationConflicts)..where(
              (row) =>
                  row.eventParticipantId.equals(id.value) &
                  row.status.equals('unresolved'),
            ))
            .get();
    if (conflicts.isNotEmpty) {
      return const RepositorySuccess(
        ParticipationSyncStatus(
          disposition: ParticipationMutationDisposition.conflicted,
        ),
      );
    }
    final outboxRows =
        await (database.select(database.participationOutboxOperations)
              ..where((row) => row.eventParticipantId.equals(id.value))
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
            .get();
    final outbox = outboxRows.isEmpty ? null : outboxRows.first;
    return RepositorySuccess(
      ParticipationSyncStatus(
        disposition: switch (outbox?.status) {
          'blocked' => ParticipationMutationDisposition.blocked,
          'failed' => ParticipationMutationDisposition.failed,
          'conflicted' => ParticipationMutationDisposition.conflicted,
          null => ParticipationMutationDisposition.synchronized,
          _ => ParticipationMutationDisposition.pending,
        },
        message: outbox?.failureMessage,
      ),
    );
  }

  Future<List<ParticipationOperation>> pendingOperations() async {
    final rows =
        await (database.select(database.participationOutboxOperations)
              ..where((row) => row.status.equals('pending'))
              ..orderBy([
                (row) => OrderingTerm.asc(row.createdAt),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    return rows
        .map(
          (row) => ParticipationOperation(
            operationId: SyncOperationId(row.id),
            record: decodeParticipation(row.payloadJson),
            baseVersion: row.baseVersion,
          ),
        )
        .toList();
  }

  Future<void> accept(
    ParticipationOperation operation,
    ParticipationRecord remote,
  ) => database.transaction(() async {
    await _replaceAuthoritative(remote);
    await (database.delete(
      database.participationOutboxOperations,
    )..where((row) => row.id.equals(operation.operationId.value))).go();
  });

  Future<void> markBlocked(ParticipationOperation operation, String message) =>
      (database.update(
        database.participationOutboxOperations,
      )..where((row) => row.id.equals(operation.operationId.value))).write(
        ParticipationOutboxOperationsCompanion(
          status: const Value('blocked'),
          failureMessage: Value(message),
        ),
      );

  Future<void> markFailed(ParticipationOperation operation, String message) =>
      (database.update(
        database.participationOutboxOperations,
      )..where((row) => row.id.equals(operation.operationId.value))).write(
        ParticipationOutboxOperationsCompanion(
          status: const Value('failed'),
          failureMessage: Value(message),
        ),
      );

  Future<void> preserveConflict(
    ParticipationOperation operation,
    ParticipationRecord? remote,
    SyncConflictId conflictId,
    DateTime now,
  ) => database.transaction(() async {
    await (database.update(
      database.participationOutboxOperations,
    )..where((row) => row.id.equals(operation.operationId.value))).write(
      const ParticipationOutboxOperationsCompanion(status: Value('conflicted')),
    );
    await database
        .into(database.participationConflicts)
        .insert(
          ParticipationConflictsCompanion.insert(
            id: conflictId.value,
            operationId: operation.operationId.value,
            eventParticipantId: operation.record.participant.id.value,
            localPayloadJson: encodeParticipation(operation.record),
            remotePayloadJson: Value(
              remote == null ? null : encodeParticipation(remote),
            ),
            detectedAt: now,
            status: 'unresolved',
          ),
        );
  });

  /// Clears only conflicts whose cloud aggregate already represents the exact
  /// same business state as the queued mutation. Server-assigned updated-at
  /// values are deliberately ignored; IDs, versions, tombstones, statuses and
  /// relationships must all agree. Genuine divergent conflicts remain intact.
  Future<int> acknowledgeEquivalentConflicts() async =>
      database.transaction(() async {
        final rows = await (database.select(
          database.participationConflicts,
        )..where((row) => row.status.equals('unresolved'))).get();
        var acknowledged = 0;
        for (final row in rows) {
          if (row.remotePayloadJson == null) continue;
          final local = decodeParticipation(row.localPayloadJson);
          final remote = decodeParticipation(row.remotePayloadJson!);
          if (!participationRecordsHaveEquivalentState(local, remote)) {
            continue;
          }
          await _replaceAuthoritative(remote);
          await (database.delete(
            database.participationConflicts,
          )..where((table) => table.id.equals(row.id))).go();
          await (database.delete(
            database.participationOutboxOperations,
          )..where((table) => table.id.equals(row.operationId))).go();
          acknowledged++;
        }
        return acknowledged;
      });

  Future<(DateTime?, EventParticipantId?)> checkpoint() async {
    final row = await database
        .select(database.participationPullCheckpoints)
        .getSingleOrNull();
    return row == null
        ? (null, null)
        : (
            row.cursorUpdatedAt.toUtc(),
            EventParticipantId(row.cursorParticipantId),
          );
  }

  Future<void> reconcile(List<ParticipationRecord> records, DateTime now) =>
      database.transaction(() async {
        for (final record in records) {
          final pendingRows =
              await (database.select(database.participationOutboxOperations)
                    ..where(
                      (row) =>
                          row.eventParticipantId.equals(
                            record.participant.id.value,
                          ) &
                          row.status.isIn(['pending', 'blocked', 'conflicted']),
                    ))
                  .get();
          if (pendingRows.isEmpty) await _replaceAuthoritative(record);
        }
        if (records.isNotEmpty) {
          final last = records.last.participant;
          await database
              .into(database.participationPullCheckpoints)
              .insertOnConflictUpdate(
                ParticipationPullCheckpointsCompanion.insert(
                  singleton: const Value(1),
                  cursorUpdatedAt: last.metadata.updatedAt,
                  cursorParticipantId: last.id.value,
                  updatedAt: now,
                ),
              );
        }
      });

  Future<void> _replaceAuthoritative(ParticipationRecord record) async {
    await database
        .into(database.eventParticipants)
        .insertOnConflictUpdate(_participantCompanion(record.participant));
    for (final assignment in record.divisions) {
      await database
          .into(database.divisionParticipants)
          .insertOnConflictUpdate(_divisionCompanion(assignment));
    }
    await database
        .into(database.participantPayments)
        .insertOnConflictUpdate(_paymentCompanion(record.payment));
  }
}

bool participationRecordsHaveEquivalentState(
  ParticipationRecord local,
  ParticipationRecord remote,
) {
  bool sameMetadata(RecordMetadata left, RecordMetadata right) =>
      left.createdAt == right.createdAt &&
      left.recordVersion == right.recordVersion &&
      left.deletedAt == right.deletedAt;
  final leftParticipant = local.participant;
  final rightParticipant = remote.participant;
  if (leftParticipant.id != rightParticipant.id ||
      leftParticipant.eventId != rightParticipant.eventId ||
      leftParticipant.playerId != rightParticipant.playerId ||
      leftParticipant.checkInStatus != rightParticipant.checkInStatus ||
      !sameMetadata(leftParticipant.metadata, rightParticipant.metadata)) {
    return false;
  }
  final leftPayment = local.payment;
  final rightPayment = remote.payment;
  if (leftPayment.id != rightPayment.id ||
      leftPayment.eventParticipantId != rightPayment.eventParticipantId ||
      leftPayment.divisionId != rightPayment.divisionId ||
      leftPayment.status != rightPayment.status ||
      !sameMetadata(leftPayment.metadata, rightPayment.metadata)) {
    return false;
  }
  if (local.divisions.length != remote.divisions.length) return false;
  final remoteDivisions = {
    for (final division in remote.divisions) division.id: division,
  };
  for (final left in local.divisions) {
    final right = remoteDivisions[left.id];
    if (right == null ||
        left.divisionId != right.divisionId ||
        left.eventParticipantId != right.eventParticipantId ||
        !sameMetadata(left.metadata, right.metadata)) {
      return false;
    }
  }
  return true;
}

EventParticipantsCompanion _participantCompanion(EventParticipant value) =>
    EventParticipantsCompanion(
      id: Value(value.id.value),
      eventId: Value(value.eventId.value),
      playerId: Value(value.playerId.value),
      checkInStatus: Value(value.checkInStatus.name),
      createdAt: Value(value.metadata.createdAt),
      updatedAt: Value(value.metadata.updatedAt),
      version: Value(value.metadata.recordVersion),
      deletedAt: Value(value.metadata.deletedAt),
    );

DivisionParticipantsCompanion _divisionCompanion(DivisionParticipant value) =>
    DivisionParticipantsCompanion(
      id: Value(value.id.value),
      divisionId: Value(value.divisionId.value),
      eventParticipantId: Value(value.eventParticipantId.value),
      createdAt: Value(value.metadata.createdAt),
      updatedAt: Value(value.metadata.updatedAt),
      version: Value(value.metadata.recordVersion),
      deletedAt: Value(value.metadata.deletedAt),
    );

ParticipantPaymentsCompanion _paymentCompanion(ParticipantPayment value) =>
    ParticipantPaymentsCompanion(
      id: Value(value.id.value),
      eventParticipantId: Value(value.eventParticipantId.value),
      divisionId: Value(value.divisionId?.value),
      status: Value(value.status.name),
      createdAt: Value(value.metadata.createdAt),
      updatedAt: Value(value.metadata.updatedAt),
      version: Value(value.metadata.recordVersion),
      deletedAt: Value(value.metadata.deletedAt),
    );
