import 'dart:collection';

import '../../domain/common/domain_enums.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/events/event.dart';
import '../../domain/events/event_division.dart';

enum EventMutationDisposition { pending, synchronized, blocked, conflicted }

final class EventSetup {
  EventSetup({required this.event, required Iterable<EventDivision> divisions})
    : divisions = UnmodifiableListView(divisions.toList(growable: false)) {
    final active = this.divisions.where(
      (division) => !division.metadata.isDeleted,
    );
    if (active.isEmpty) {
      throw const ValidationFailure(
        field: 'divisions',
        message: 'At least one active division is required.',
      );
    }
    final names = <String>{};
    for (final division in active) {
      if (division.eventId != event.id) {
        throw const ValidationFailure(
          field: 'divisions',
          message: 'Every division must belong to the event.',
        );
      }
      if (!names.add(normalizeDivisionName(division.name))) {
        throw const ValidationFailure(
          field: 'divisions',
          message: 'Division names must be unique within an event.',
        );
      }
    }
  }

  final Event event;
  final UnmodifiableListView<EventDivision> divisions;

  bool get hasUnconfiguredFormats => divisions.any(
    (division) => !division.metadata.isDeleted && division.format == null,
  );
}

String prepareSetupText(String value, {required String field}) {
  final prepared = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (prepared.isEmpty) {
    throw ValidationFailure(field: field, message: '$field cannot be blank.');
  }
  return prepared;
}

String normalizeDivisionName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

sealed class EventSetupMutationResult {
  const EventSetupMutationResult();
}

final class EventSetupSaved extends EventSetupMutationResult {
  const EventSetupSaved({required this.setup, required this.disposition});

  final EventSetup setup;
  final EventMutationDisposition disposition;
}

final class EventSetupMutationFailed extends EventSetupMutationResult {
  const EventSetupMutationFailed(this.failure);

  final DomainFailure failure;
}

final class EventSetupSyncStatus {
  const EventSetupSyncStatus({required this.disposition, this.message});

  final EventMutationDisposition disposition;
  final String? message;
}

final class EventSetupOperation {
  const EventSetupOperation({
    required this.operationId,
    required this.setup,
    required this.baseVersion,
  });

  final SyncOperationId operationId;
  final EventSetup setup;
  final int? baseVersion;
}

final class EventSetupPullPage {
  const EventSetupPullPage({required this.setups, required this.hasMore});

  final List<EventSetup> setups;
  final bool hasMore;
}

sealed class EventSetupRemoteResult {
  const EventSetupRemoteResult();
}

final class EventSetupRemoteAccepted extends EventSetupRemoteResult {
  const EventSetupRemoteAccepted({required this.setup, required this.replayed});
  final EventSetup setup;
  final bool replayed;
}

final class EventSetupRemoteConflict extends EventSetupRemoteResult {
  const EventSetupRemoteConflict(this.remote);
  final EventSetup? remote;
}

final class EventSetupRemoteFailure extends EventSetupRemoteResult {
  const EventSetupRemoteFailure(this.failure);
  final DomainFailure failure;
}

EventStatus? nextEventStatus(EventStatus status) => switch (status) {
  EventStatus.upcoming => EventStatus.registration,
  EventStatus.registration => EventStatus.inProgress,
  EventStatus.inProgress => EventStatus.completed,
  EventStatus.completed => EventStatus.archived,
  EventStatus.archived => null,
};
