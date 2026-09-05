import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/events/division_participant.dart';
import '../../domain/events/event_participant.dart';
import '../../domain/events/participant_payment.dart';
import '../events/event_setup_models.dart';
import 'participation_contracts.dart';
import 'participation_models.dart';

final class ParticipationService {
  const ParticipationService({
    required this.writer,
    required this.ids,
    required this.clock,
  });
  final ParticipationWriter writer;
  final ParticipationIdFactory ids;
  final ParticipationClock clock;

  Future<RepositoryResult<ParticipationSaved>> register({
    required EventSetup setup,
    required PlayerId playerId,
    required String playerDisplayName,
    required Iterable<DivisionId> divisionIds,
  }) async {
    if (setup.event.status != EventStatus.registration) {
      return const RepositoryFailure(
        InvalidStateTransitionFailure(
          entity: 'Event roster',
          from: 'locked',
          to: 'registered',
        ),
      );
    }
    final selected = divisionIds.toSet();
    if (selected.isEmpty) {
      return const RepositoryFailure(
        ValidationFailure(
          field: 'divisions',
          message: 'Select at least one active division.',
        ),
      );
    }
    final active = {
      for (final division in setup.divisions)
        if (!division.metadata.isDeleted) division.id,
    };
    if (!active.containsAll(selected)) {
      return const RepositoryFailure(
        ValidationFailure(
          field: 'divisions',
          message: 'Every selected division must be active in this event.',
        ),
      );
    }
    final now = clock.nowUtc();
    final metadata = RecordMetadata(
      createdAt: now,
      updatedAt: now,
      recordVersion: 0,
    );
    final participantId = ids.participantId();
    final record = ParticipationRecord(
      participant: EventParticipant(
        id: participantId,
        eventId: setup.event.id,
        playerId: playerId,
        checkInStatus: CheckInStatus.notPresent,
        metadata: metadata,
      ),
      playerDisplayName: playerDisplayName,
      divisions: selected.map(
        (divisionId) => DivisionParticipant(
          id: ids.divisionParticipantId(),
          divisionId: divisionId,
          eventParticipantId: participantId,
          metadata: metadata,
        ),
      ),
      payment: ParticipantPayment(
        id: ids.paymentId(),
        eventParticipantId: participantId,
        status: PaymentStatus.unpaid,
        metadata: metadata,
      ),
    );
    return writer.save(record);
  }

  Future<RepositoryResult<ParticipationSaved>> updateCheckIn(
    ParticipationRecord current,
    CheckInStatus status,
    EventStatus eventStatus,
  ) {
    if (eventStatus != EventStatus.registration &&
        eventStatus != EventStatus.inProgress) {
      return Future.value(_lifecycleFailure('check-in'));
    }
    return _update(
      current,
      participant: EventParticipant(
        id: current.participant.id,
        eventId: current.participant.eventId,
        playerId: current.participant.playerId,
        checkInStatus: status,
        metadata: _next(current.participant.metadata),
      ),
    );
  }

  Future<RepositoryResult<ParticipationSaved>> updatePayment(
    ParticipationRecord current,
    PaymentStatus status,
    EventStatus eventStatus,
  ) {
    if (eventStatus != EventStatus.registration &&
        eventStatus != EventStatus.inProgress) {
      return Future.value(_lifecycleFailure('payment'));
    }
    return _update(
      current,
      payment: ParticipantPayment(
        id: current.payment.id,
        eventParticipantId: current.payment.eventParticipantId,
        divisionId: current.payment.divisionId,
        status: status,
        metadata: _next(current.payment.metadata),
      ),
    );
  }

  Future<RepositoryResult<ParticipationSaved>> updateDivisions({
    required ParticipationRecord current,
    required EventSetup setup,
    required Iterable<DivisionId> divisionIds,
  }) {
    if (setup.event.status != EventStatus.registration) {
      return Future.value(
        const RepositoryFailure(
          InvalidStateTransitionFailure(
            entity: 'Roster structure',
            from: 'locked',
            to: 'edited',
          ),
        ),
      );
    }
    final selected = divisionIds.toSet();
    if (selected.isEmpty) {
      return Future.value(
        const RepositoryFailure(
          ValidationFailure(
            field: 'divisions',
            message: 'Select at least one active division.',
          ),
        ),
      );
    }
    final active = {
      for (final division in setup.divisions)
        if (!division.metadata.isDeleted) division.id,
    };
    if (!active.containsAll(selected)) {
      return Future.value(
        const RepositoryFailure(
          ValidationFailure(
            field: 'divisions',
            message: 'Every selected division must be active in this event.',
          ),
        ),
      );
    }
    final now = clock.nowUtc();
    final existing = {for (final row in current.divisions) row.divisionId: row};
    final rows = <DivisionParticipant>[];
    for (final divisionId in selected) {
      rows.add(
        existing.remove(divisionId) ??
            DivisionParticipant(
              id: ids.divisionParticipantId(),
              divisionId: divisionId,
              eventParticipantId: current.participant.id,
              metadata: RecordMetadata(
                createdAt: now,
                updatedAt: now,
                recordVersion: 0,
              ),
            ),
      );
    }
    for (final removed in existing.values) {
      rows.add(
        DivisionParticipant(
          id: removed.id,
          divisionId: removed.divisionId,
          eventParticipantId: removed.eventParticipantId,
          metadata: RecordMetadata(
            createdAt: removed.metadata.createdAt,
            updatedAt: now,
            recordVersion: removed.metadata.recordVersion + 1,
            deletedAt: now,
          ),
        ),
      );
    }
    return _update(current, divisions: rows);
  }

  Future<RepositoryResult<ParticipationSaved>> remove(
    ParticipationRecord current,
    EventStatus eventStatus,
  ) {
    if (eventStatus != EventStatus.registration) {
      return Future.value(_lifecycleFailure('removal'));
    }
    final now = clock.nowUtc();
    return writer.save(
      ParticipationRecord(
        participant: EventParticipant(
          id: current.participant.id,
          eventId: current.participant.eventId,
          playerId: current.participant.playerId,
          checkInStatus: current.participant.checkInStatus,
          metadata: _next(current.participant.metadata, deletedAt: now),
        ),
        playerDisplayName: current.playerDisplayName,
        divisions: current.divisions.map(
          (row) => DivisionParticipant(
            id: row.id,
            divisionId: row.divisionId,
            eventParticipantId: row.eventParticipantId,
            metadata: _next(row.metadata, deletedAt: now),
          ),
        ),
        payment: ParticipantPayment(
          id: current.payment.id,
          eventParticipantId: current.payment.eventParticipantId,
          divisionId: current.payment.divisionId,
          status: current.payment.status,
          metadata: _next(current.payment.metadata, deletedAt: now),
        ),
      ),
      expectedVersion: current.participant.metadata.recordVersion,
    );
  }

  RepositoryFailure<ParticipationSaved> _lifecycleFailure(String action) =>
      RepositoryFailure(
        InvalidStateTransitionFailure(
          entity: 'Participation $action',
          from: 'locked',
          to: 'changed',
        ),
      );

  Future<RepositoryResult<ParticipationSaved>> _update(
    ParticipationRecord current, {
    EventParticipant? participant,
    ParticipantPayment? payment,
    Iterable<DivisionParticipant>? divisions,
  }) => writer.save(
    ParticipationRecord(
      participant:
          participant ??
          EventParticipant(
            id: current.participant.id,
            eventId: current.participant.eventId,
            playerId: current.participant.playerId,
            checkInStatus: current.participant.checkInStatus,
            metadata: _next(current.participant.metadata),
          ),
      payment: payment ?? current.payment,
      playerDisplayName: current.playerDisplayName,
      divisions: divisions ?? current.divisions,
    ),
    expectedVersion: current.participant.metadata.recordVersion,
  );

  RecordMetadata _next(RecordMetadata value, {DateTime? deletedAt}) {
    final now = deletedAt ?? clock.nowUtc();
    return RecordMetadata(
      createdAt: value.createdAt,
      updatedAt: now,
      recordVersion: value.recordVersion + 1,
      deletedAt: deletedAt,
    );
  }
}
