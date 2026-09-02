import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/events/event.dart';
import '../../domain/events/event_division.dart';
import 'event_setup_contracts.dart';
import 'event_setup_models.dart';
import '../accounts/account_models.dart';

final class EventSetupService {
  const EventSetupService({
    required this.writer,
    required this.idFactory,
    required this.clock,
  });

  final EventSetupWriter writer;
  final EventSetupIdFactory idFactory;
  final EventSetupClock clock;

  Future<EventSetupMutationResult> selectFormat({
    required EventSetup current,
    required DivisionId divisionId,
    required TournamentFormat format,
    required AuthorizationState authorization,
  }) async {
    try {
      if (authorization != AuthorizationState.organizer) {
        throw const UnauthorizedFailure(
          message: 'Organizer authorization is required.',
        );
      }
      final selected = current.divisions
          .where((d) => d.id == divisionId && !d.metadata.isDeleted)
          .firstOrNull;
      if (current.event.status != EventStatus.registration ||
          current.event.metadata.isDeleted ||
          selected == null ||
          current.readiness[divisionId] == null ||
          current.readiness[divisionId]!.generatedMatches != 0) {
        throw const ValidationFailure(
          field: 'format',
          message: 'Formats may be selected during Registration only, before any match structure exists. Refresh if readiness is unavailable.',
        );
      }
      final now = clock.nowUtc();
      final event = current.event;
      final setup = EventSetup(
        event: Event(
          id: event.id,
          name: event.name,
          scheduledAt: event.scheduledAt,
          type: event.type,
          status: event.status,
          courtLabel: event.courtLabel,
          entryFee: event.entryFee,
          metadata: RecordMetadata(
            createdAt: event.metadata.createdAt,
            updatedAt: now,
            recordVersion: event.metadata.recordVersion + 1,
          ),
        ),
        divisions: current.divisions.map(
          (d) => d.id != divisionId
              ? d
              : EventDivision(
                  id: d.id,
                  eventId: d.eventId,
                  name: d.name,
                  format: format,
                  metadata: RecordMetadata(
                    createdAt: d.metadata.createdAt,
                    updatedAt: now,
                    recordVersion: d.metadata.recordVersion + 1,
                  ),
                ),
        ),
        readiness: current.readiness,
      );
      final saved = await writer.save(
        setup,
        expectedVersion: event.metadata.recordVersion,
      );
      return saved.when<EventSetupMutationResult>(
        success: (value) => value,
        failure: EventSetupMutationFailed.new,
      );
    } on DomainFailure catch (failure) {
      return EventSetupMutationFailed(failure);
    }
  }

  Future<EventSetupMutationResult> createQuickCasual({
    required String name,
    required DateTime scheduledAt,
    required String venue,
  }) => _create(
    name: name,
    scheduledAt: scheduledAt,
    venue: venue,
    type: EventType.casual,
    divisionNames: const ['Open'],
  );

  Future<EventSetupMutationResult> createFormal({
    required String name,
    required DateTime scheduledAt,
    required String venue,
    required Iterable<String> divisionNames,
  }) => _create(
    name: name,
    scheduledAt: scheduledAt,
    venue: venue,
    type: EventType.formal,
    divisionNames: divisionNames,
  );

  Future<EventSetupMutationResult> _create({
    required String name,
    required DateTime scheduledAt,
    required String venue,
    required EventType type,
    required Iterable<String> divisionNames,
  }) async {
    try {
      final now = clock.nowUtc();
      if (!now.isUtc || !scheduledAt.isUtc) {
        throw const ValidationFailure(
          field: 'scheduledAt',
          message: 'Event timestamps must use UTC.',
        );
      }
      final eventId = idFactory.eventId();
      final metadata = RecordMetadata(
        createdAt: now,
        updatedAt: now,
        recordVersion: 0,
      );
      final setup = EventSetup(
        event: Event(
          id: eventId,
          name: prepareSetupText(name, field: 'name'),
          scheduledAt: scheduledAt,
          type: type,
          status: EventStatus.upcoming,
          courtLabel: prepareSetupText(venue, field: 'venue'),
          metadata: metadata,
        ),
        divisions: divisionNames.map(
          (divisionName) => EventDivision(
            id: idFactory.divisionId(),
            eventId: eventId,
            name: prepareSetupText(divisionName, field: 'divisionName'),
            format: null,
            metadata: metadata,
          ),
        ),
      );
      final result = await writer.save(setup);
      return result.when<EventSetupMutationResult>(
        success: (saved) => saved,
        failure: EventSetupMutationFailed.new,
      );
    } on DomainFailure catch (failure) {
      return EventSetupMutationFailed(failure);
    }
  }

  Future<EventSetupMutationResult> updateUpcoming({
    required EventSetup current,
    required String name,
    required DateTime scheduledAt,
    required String venue,
    required Iterable<String> divisionNames,
  }) async {
    if (current.event.status != EventStatus.upcoming) {
      return const EventSetupMutationFailed(
        InvalidStateTransitionFailure(
          entity: 'Event setup',
          from: 'locked',
          to: 'edited',
        ),
      );
    }
    try {
      final now = clock.nowUtc();
      final version = current.event.metadata.recordVersion + 1;
      final requestedNames = divisionNames
          .map((name) => prepareSetupText(name, field: 'divisionName'))
          .toList();
      final existingByName = {
        for (final division in current.divisions)
          normalizeDivisionName(division.name): division,
      };
      final retained = <EventDivision>[];
      for (final requested in requestedNames) {
        final existing = existingByName.remove(
          normalizeDivisionName(requested),
        );
        retained.add(
          existing == null
              ? EventDivision(
                  id: idFactory.divisionId(),
                  eventId: current.event.id,
                  name: requested,
                  format: null,
                  metadata: RecordMetadata(
                    createdAt: now,
                    updatedAt: now,
                    recordVersion: 0,
                  ),
                )
              : EventDivision(
                  id: existing.id,
                  eventId: existing.eventId,
                  name: requested,
                  format: existing.format,
                  metadata: existing.metadata,
                ),
        );
      }
      for (final removed in existingByName.values) {
        retained.add(
          EventDivision(
            id: removed.id,
            eventId: removed.eventId,
            name: removed.name,
            format: removed.format,
            metadata: RecordMetadata(
              createdAt: removed.metadata.createdAt,
              updatedAt: now,
              recordVersion: removed.metadata.recordVersion + 1,
              deletedAt: now,
            ),
          ),
        );
      }
      final setup = EventSetup(
        event: Event(
          id: current.event.id,
          name: prepareSetupText(name, field: 'name'),
          scheduledAt: scheduledAt,
          type: current.event.type,
          status: current.event.status,
          courtLabel: prepareSetupText(venue, field: 'venue'),
          metadata: RecordMetadata(
            createdAt: current.event.metadata.createdAt,
            updatedAt: now,
            recordVersion: version,
          ),
        ),
        divisions: retained,
      );
      final result = await writer.save(
        setup,
        expectedVersion: current.event.metadata.recordVersion,
      );
      return result.when<EventSetupMutationResult>(
        success: (saved) => saved,
        failure: EventSetupMutationFailed.new,
      );
    } on DomainFailure catch (failure) {
      return EventSetupMutationFailed(failure);
    }
  }

  Future<EventSetupMutationResult> advance(EventSetup current) async {
    final target = nextEventStatus(current.event.status);
    if (target == null) {
      return EventSetupMutationFailed(
        InvalidStateTransitionFailure(
          entity: 'Event',
          from: current.event.status.name,
          to: current.event.status.name,
        ),
      );
    }
    if (target == EventStatus.inProgress && current.hasUnconfiguredFormats) {
      return const EventSetupMutationFailed(TournamentFormatRequiredFailure());
    }
    if (target == EventStatus.inProgress && !current.canBegin) {
      return const EventSetupMutationFailed(
        TournamentStructureRequiredFailure(),
      );
    }
    final now = clock.nowUtc();
    try {
      final transitioned = current.event.transitionTo(
        target,
        metadata: RecordMetadata(
          createdAt: current.event.metadata.createdAt,
          updatedAt: now,
          recordVersion: current.event.metadata.recordVersion + 1,
          deletedAt: current.event.metadata.deletedAt,
        ),
      );
      final result = await writer.save(
        EventSetup(event: transitioned, divisions: current.divisions),
        expectedVersion: current.event.metadata.recordVersion,
      );
      return result.when<EventSetupMutationResult>(
        success: (saved) => saved,
        failure: EventSetupMutationFailed.new,
      );
    } on DomainFailure catch (failure) {
      return EventSetupMutationFailed(failure);
    }
  }
}
