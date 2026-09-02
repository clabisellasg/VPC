import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/events/event_setup_models.dart';
import 'package:vpc/src/application/participation/participation_contracts.dart';
import 'package:vpc/src/application/participation/participation_models.dart';
import 'package:vpc/src/application/participation/participation_service.dart';
import 'package:vpc/src/domain/common/domain_enums.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/events/event.dart';
import 'package:vpc/src/domain/events/event_division.dart';

void main() {
  final now = DateTime.utc(2026, 9, 1, 12);
  late _Writer writer;
  late ParticipationService service;
  setUp(() {
    writer = _Writer();
    service = ParticipationService(
      writer: writer,
      ids: _Ids(),
      clock: _Clock(now),
    );
  });

  test(
    'registration creates one atomic unpaid and not-present aggregate',
    () async {
      final result = await service.register(
        setup: _setup(now, EventStatus.registration),
        playerId: PlayerId(_playerId),
        playerDisplayName: 'VPC Sample Player',
        divisionIds: [DivisionId(_divisionId)],
      );
      expect(result, isA<RepositorySuccess<ParticipationSaved>>());
      expect(writer.saved!.participant.checkInStatus, CheckInStatus.notPresent);
      expect(writer.saved!.payment.status, PaymentStatus.unpaid);
      expect(writer.saved!.divisions, hasLength(1));
      expect(writer.saved!.participant.metadata.createdAt, now);
    },
  );

  test('registration rejects wrong lifecycle and inactive divisions', () async {
    expect(
      await service.register(
        setup: _setup(now, EventStatus.upcoming),
        playerId: PlayerId(_playerId),
        playerDisplayName: 'Sample',
        divisionIds: [DivisionId(_divisionId)],
      ),
      isA<RepositoryFailure<ParticipationSaved>>(),
    );
    expect(
      await service.register(
        setup: _setup(now, EventStatus.registration),
        playerId: PlayerId(_playerId),
        playerDisplayName: 'Sample',
        divisionIds: [DivisionId(_otherDivisionId)],
      ),
      isA<RepositoryFailure<ParticipationSaved>>(),
    );
  });

  test(
    'check-in and payment corrections increment participant version',
    () async {
      await service.register(
        setup: _setup(now, EventStatus.registration),
        playerId: PlayerId(_playerId),
        playerDisplayName: 'Sample',
        divisionIds: [DivisionId(_divisionId)],
      );
      final initial = writer.saved!;
      await service.updateCheckIn(
        initial,
        CheckInStatus.checkedIn,
        EventStatus.inProgress,
      );
      expect(writer.saved!.participant.checkInStatus, CheckInStatus.checkedIn);
      expect(writer.saved!.participant.metadata.recordVersion, 1);
      await service.updatePayment(
        writer.saved!,
        PaymentStatus.paid,
        EventStatus.inProgress,
      );
      expect(writer.saved!.payment.status, PaymentStatus.paid);
      expect(writer.saved!.participant.metadata.recordVersion, 2);
    },
  );

  test('completed and archived participation is read-only', () async {
    await service.register(
      setup: _setup(now, EventStatus.registration),
      playerId: PlayerId(_playerId),
      playerDisplayName: 'Sample',
      divisionIds: [DivisionId(_divisionId)],
    );
    final record = writer.saved!;
    expect(
      await service.updatePayment(
        record,
        PaymentStatus.paid,
        EventStatus.completed,
      ),
      isA<RepositoryFailure<ParticipationSaved>>(),
    );
    expect(
      await service.remove(record, EventStatus.archived),
      isA<RepositoryFailure<ParticipationSaved>>(),
    );
  });
}

EventSetup _setup(DateTime now, EventStatus status) => EventSetup(
  event: Event(
    id: EventId(_eventId),
    name: 'VPC M10 Test',
    scheduledAt: now.add(const Duration(days: 1)),
    type: EventType.formal,
    status: status,
    courtLabel: 'Sample Court',
    metadata: _metadata(now),
  ),
  divisions: [
    EventDivision(
      id: DivisionId(_divisionId),
      eventId: EventId(_eventId),
      name: 'Open',
      metadata: _metadata(now),
    ),
  ],
);

RecordMetadata _metadata(DateTime now) =>
    RecordMetadata(createdAt: now, updatedAt: now, recordVersion: 0);

final class _Writer implements ParticipationWriter {
  ParticipationRecord? saved;
  @override
  Future<RepositoryResult<ParticipationSaved>> save(
    ParticipationRecord record, {
    int? expectedVersion,
  }) async {
    saved = record;
    return RepositorySuccess(
      ParticipationSaved(
        record: record,
        disposition: ParticipationMutationDisposition.pending,
      ),
    );
  }
}

final class _Clock implements ParticipationClock {
  const _Clock(this.now);
  final DateTime now;
  @override
  DateTime nowUtc() => now;
}

final class _Ids implements ParticipationIdFactory {
  @override
  EventParticipantId participantId() => EventParticipantId(_participantId);
  @override
  DivisionParticipantId divisionParticipantId() =>
      DivisionParticipantId(_assignmentId);
  @override
  ParticipantPaymentId paymentId() => ParticipantPaymentId(_paymentId);
  @override
  SyncOperationId operationId() => SyncOperationId(_operationId);
}

const _eventId = '00000000-0000-4000-8000-000000000101';
const _divisionId = '00000000-0000-4000-8000-000000000102';
const _otherDivisionId = '00000000-0000-4000-8000-000000000103';
const _playerId = '00000000-0000-4000-8000-000000000104';
const _participantId = '00000000-0000-4000-8000-000000000105';
const _assignmentId = '00000000-0000-4000-8000-000000000106';
const _paymentId = '00000000-0000-4000-8000-000000000107';
const _operationId = '00000000-0000-4000-8000-000000000108';
