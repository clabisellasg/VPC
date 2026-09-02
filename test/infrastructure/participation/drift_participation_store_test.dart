import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/participation/participation_models.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/events/division_participant.dart';
import 'package:vpc/src/domain/events/event_participant.dart';
import 'package:vpc/src/domain/events/participant_payment.dart';
import 'package:vpc/src/infrastructure/participation/drift_participation_store.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';

void main() {
  late AppDatabase database;
  late DriftParticipationStore store;
  final now = DateTime.utc(2026, 9, 1, 12);
  setUp(() async {
    database = AppDatabase.inMemory();
    store = DriftParticipationStore(database);
    await database
        .into(database.players)
        .insert(
          PlayersCompanion.insert(
            id: _playerId,
            displayName: 'VPC Sample Player',
            createdAt: now,
            updatedAt: now,
            version: 0,
          ),
        );
    await database
        .into(database.events)
        .insert(
          EventsCompanion.insert(
            id: _eventId,
            name: 'VPC M10 Test',
            scheduledAt: now.add(const Duration(days: 1)),
            eventType: 'formal',
            status: 'registration',
            courtLabel: 'Sample Court',
            createdAt: now,
            updatedAt: now,
            version: 0,
          ),
        );
    await database
        .into(database.eventDivisions)
        .insert(
          EventDivisionsCompanion.insert(
            id: _divisionId,
            eventId: _eventId,
            name: 'Open',
            tournamentFormat: const Value(null),
            createdAt: now,
            updatedAt: now,
            version: 0,
          ),
        );
  });
  tearDown(() => database.close());

  test('aggregate and outbox commit atomically and round-trip', () async {
    final result = await store.save(
      _record(now),
      operationId: SyncOperationId(_operationId),
    );
    expect(result, isA<RepositorySuccess<ParticipationSaved>>());
    expect(
      await database.select(database.eventParticipants).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.divisionParticipants).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.participantPayments).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.participationOutboxOperations).get(),
      hasLength(1),
    );
    final loaded = await store.listForEvent(EventId(_eventId));
    final record =
        (loaded as RepositorySuccess<List<ParticipationRecord>>).value.single;
    expect(record.playerDisplayName, 'VPC Sample Player');
    expect(record.payment.status, PaymentStatus.unpaid);
    expect(record.participant.metadata.createdAt, now);
  });

  test('duplicate active player registration is rejected', () async {
    await store.save(_record(now), operationId: SyncOperationId(_operationId));
    final duplicate = _record(now, participantId: _otherParticipantId);
    expect(
      await store.save(
        duplicate,
        operationId: SyncOperationId(_otherOperationId),
      ),
      isA<RepositoryFailure<ParticipationSaved>>(),
    );
  });

  test('outbox failure rolls back the complete aggregate', () async {
    await database.customStatement('''
      CREATE TRIGGER reject_participation_outbox
      BEFORE INSERT ON participation_outbox_operations
      BEGIN SELECT RAISE(ABORT, 'forced outbox failure'); END
    ''');
    final result = await store.save(
      _record(now),
      operationId: SyncOperationId(_operationId),
    );
    expect(result, isA<RepositoryFailure<ParticipationSaved>>());
    expect(await database.select(database.eventParticipants).get(), isEmpty);
  });
}

ParticipationRecord _record(
  DateTime now, {
  String participantId = _participantId,
}) {
  final metadata = RecordMetadata(
    createdAt: now,
    updatedAt: now,
    recordVersion: 0,
  );
  final id = EventParticipantId(participantId);
  return ParticipationRecord(
    participant: EventParticipant(
      id: id,
      eventId: EventId(_eventId),
      playerId: PlayerId(_playerId),
      checkInStatus: CheckInStatus.notPresent,
      metadata: metadata,
    ),
    playerDisplayName: 'VPC Sample Player',
    divisions: [
      DivisionParticipant(
        id: DivisionParticipantId(
          participantId == _participantId ? _assignmentId : _otherAssignmentId,
        ),
        divisionId: DivisionId(_divisionId),
        eventParticipantId: id,
        metadata: metadata,
      ),
    ],
    payment: ParticipantPayment(
      id: ParticipantPaymentId(
        participantId == _participantId ? _paymentId : _otherPaymentId,
      ),
      eventParticipantId: id,
      status: PaymentStatus.unpaid,
      metadata: metadata,
    ),
  );
}

const _eventId = '00000000-0000-4000-8000-000000000201';
const _divisionId = '00000000-0000-4000-8000-000000000202';
const _playerId = '00000000-0000-4000-8000-000000000203';
const _participantId = '00000000-0000-4000-8000-000000000204';
const _assignmentId = '00000000-0000-4000-8000-000000000205';
const _paymentId = '00000000-0000-4000-8000-000000000206';
const _operationId = '00000000-0000-4000-8000-000000000207';
const _otherParticipantId = '00000000-0000-4000-8000-000000000208';
const _otherAssignmentId = '00000000-0000-4000-8000-000000000209';
const _otherPaymentId = '00000000-0000-4000-8000-000000000210';
const _otherOperationId = '00000000-0000-4000-8000-000000000211';
