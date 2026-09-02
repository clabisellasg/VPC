import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'participation_models.dart';

abstract interface class ParticipationStore {
  Future<RepositoryResult<List<ParticipationRecord>>> listForEvent(
    EventId eventId,
  );
  Future<RepositoryResult<ParticipationRecord>> get(EventParticipantId id);
  Future<RepositoryResult<ParticipationSaved>> save(
    ParticipationRecord record, {
    required SyncOperationId operationId,
    int? expectedVersion,
  });
  Future<RepositoryResult<ParticipationSyncStatus>> syncStatus(
    EventParticipantId id,
  );
}

abstract interface class ParticipationRemoteGateway {
  Future<ParticipationRemoteResult> apply(ParticipationOperation operation);
  Future<RepositoryResult<ParticipationPullPage>> pull({
    DateTime? afterUpdatedAt,
    EventParticipantId? afterId,
    int limit = 50,
  });
}

abstract interface class ParticipationWriter {
  Future<RepositoryResult<ParticipationSaved>> save(
    ParticipationRecord record, {
    int? expectedVersion,
  });
}

abstract interface class ParticipationIdFactory {
  EventParticipantId participantId();
  DivisionParticipantId divisionParticipantId();
  ParticipantPaymentId paymentId();
  SyncOperationId operationId();
}

abstract interface class ParticipationClock {
  DateTime nowUtc();
}
