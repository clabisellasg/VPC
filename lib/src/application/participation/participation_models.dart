import 'dart:collection';

import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/events/division_participant.dart';
import '../../domain/events/event_participant.dart';
import '../../domain/events/participant_payment.dart';

enum ParticipationMutationDisposition {
  pending,
  synchronized,
  blocked,
  failed,
  conflicted,
}

final class ParticipationRecord {
  ParticipationRecord({
    required this.participant,
    required this.payment,
    required this.playerDisplayName,
    required Iterable<DivisionParticipant> divisions,
  }) : divisions = UnmodifiableListView(divisions.toList(growable: false)) {
    if (payment.eventParticipantId != participant.id ||
        this.divisions.any(
          (assignment) => assignment.eventParticipantId != participant.id,
        )) {
      throw const ValidationFailure(
        field: 'participation',
        message: 'Participation records must reference one participant.',
      );
    }
  }

  final EventParticipant participant;
  final ParticipantPayment payment;
  final String playerDisplayName;
  final UnmodifiableListView<DivisionParticipant> divisions;
}

final class ParticipationSaved {
  const ParticipationSaved({required this.record, required this.disposition});
  final ParticipationRecord record;
  final ParticipationMutationDisposition disposition;
}

final class ParticipationSyncStatus {
  const ParticipationSyncStatus({required this.disposition, this.message});
  final ParticipationMutationDisposition disposition;
  final String? message;
}

final class ParticipationOperation {
  const ParticipationOperation({
    required this.operationId,
    required this.record,
    required this.baseVersion,
  });
  final SyncOperationId operationId;
  final ParticipationRecord record;
  final int? baseVersion;
}

sealed class ParticipationRemoteResult {
  const ParticipationRemoteResult();
}

final class ParticipationRemoteAccepted extends ParticipationRemoteResult {
  const ParticipationRemoteAccepted({
    required this.record,
    required this.replayed,
  });
  final ParticipationRecord record;
  final bool replayed;
}

final class ParticipationRemoteConflict extends ParticipationRemoteResult {
  const ParticipationRemoteConflict(this.remote);
  final ParticipationRecord? remote;
}

final class ParticipationRemoteFailure extends ParticipationRemoteResult {
  const ParticipationRemoteFailure(this.failure);
  final DomainFailure failure;
}

final class ParticipationPullPage {
  const ParticipationPullPage({required this.records, required this.hasMore});
  final List<ParticipationRecord> records;
  final bool hasMore;
}
