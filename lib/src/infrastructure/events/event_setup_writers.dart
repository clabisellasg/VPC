import '../../application/events/event_setup_contracts.dart';
import '../../application/events/event_setup_models.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'drift_event_setup_store.dart';

final class EventSetupSynchronizer {
  EventSetupSynchronizer({
    required this.store,
    required this.remote,
    required this.idFactory,
    required this.clock,
  });
  final DriftEventSetupStore store;
  final EventSetupRemoteGateway remote;
  final EventSetupIdFactory idFactory;
  final EventSetupClock clock;
  bool _running = false;

  Future<void> synchronize() async {
    if (_running) return;
    _running = true;
    try {
      for (final operation in await store.pendingOperations()) {
        final result = await remote.apply(operation);
        switch (result) {
          case EventSetupRemoteAccepted(:final setup):
            await store.accept(operation, setup);
          case EventSetupRemoteConflict(:final remote):
            await store.preserveConflict(
              operation,
              remote,
              SyncConflictId(idFactory.operationId().value),
              clock.nowUtc(),
            );
          case EventSetupRemoteFailure(failure: UnauthorizedFailure()):
            await store.markBlocked(
              operation,
              'Organizer authorization is required.',
            );
          case EventSetupRemoteFailure(:final failure):
            await store.markFailed(operation, failure.message);
        }
      }
      final checkpoint = await store.checkpoint();
      final pulled = await remote.pull(
        afterUpdatedAt: checkpoint.$1,
        afterId: checkpoint.$2,
      );
      if (pulled case RepositorySuccess(:final value)) {
        await store.reconcile(value.setups, clock.nowUtc());
      }
    } finally {
      _running = false;
    }
  }
}

final class AndroidEventSetupWriter implements EventSetupWriter {
  const AndroidEventSetupWriter({required this.store, required this.idFactory});
  final EventSetupStore store;
  final EventSetupIdFactory idFactory;

  @override
  Future<RepositoryResult<EventSetupSaved>> save(
    EventSetup setup, {
    int? expectedVersion,
  }) async {
    return store.save(
      setup,
      operationId: idFactory.operationId(),
      expectedVersion: expectedVersion,
    );
  }
}

final class WebEventSetupWriter implements EventSetupWriter {
  const WebEventSetupWriter({required this.remote, required this.idFactory});
  final EventSetupRemoteGateway remote;
  final EventSetupIdFactory idFactory;

  @override
  Future<RepositoryResult<EventSetupSaved>> save(
    EventSetup setup, {
    int? expectedVersion,
  }) async {
    final result = await remote.apply(
      EventSetupOperation(
        operationId: idFactory.operationId(),
        setup: setup,
        baseVersion: expectedVersion,
      ),
    );
    return switch (result) {
      EventSetupRemoteAccepted(:final setup) => RepositorySuccess(
        EventSetupSaved(
          setup: setup,
          disposition: EventMutationDisposition.synchronized,
        ),
      ),
      EventSetupRemoteConflict() => const RepositoryFailure(
        ConflictFailure(
          message: 'Cloud event data changed. Refresh before retrying.',
        ),
      ),
      EventSetupRemoteFailure(:final failure) => RepositoryFailure(failure),
    };
  }
}

final class UnavailableEventSetupWriter implements EventSetupWriter {
  const UnavailableEventSetupWriter();
  @override
  Future<RepositoryResult<EventSetupSaved>> save(
    EventSetup setup, {
    int? expectedVersion,
  }) async => const RepositoryFailure(
    PersistenceUnavailableFailure(
      message: 'Event setup is unavailable in this build.',
    ),
  );
}
