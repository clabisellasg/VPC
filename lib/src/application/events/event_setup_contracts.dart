import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'event_setup_models.dart';

abstract interface class EventSetupStore {
  Future<RepositoryResult<List<EventSetup>>> listSetups();
  Future<RepositoryResult<EventSetup>> getSetup(EventId id);
  Future<RepositoryResult<EventSetupSaved>> save(
    EventSetup setup, {
    required SyncOperationId operationId,
    int? expectedVersion,
  });
  Future<RepositoryResult<EventSetupSyncStatus>> syncStatus(EventId id);
}

abstract interface class EventSetupRemoteGateway {
  Future<EventSetupRemoteResult> apply(EventSetupOperation operation);
  Future<RepositoryResult<EventSetupPullPage>> pull({
    DateTime? afterUpdatedAt,
    EventId? afterId,
    int limit = 50,
  });
}

abstract interface class EventSetupWriter {
  Future<RepositoryResult<EventSetupSaved>> save(
    EventSetup setup, {
    int? expectedVersion,
  });
}

abstract interface class EventSetupIdFactory {
  EventId eventId();
  DivisionId divisionId();
  SyncOperationId operationId();
}

abstract interface class EventSetupClock {
  DateTime nowUtc();
}
