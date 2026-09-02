import '../../application/participation/participation_contracts.dart';
import '../../application/participation/participation_models.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import 'drift_participation_store.dart';

final class ParticipationSynchronizer {
  ParticipationSynchronizer({
    required this.store,
    required this.remote,
    required this.ids,
    required this.clock,
  });
  final DriftParticipationStore store;
  final ParticipationRemoteGateway remote;
  final ParticipationIdFactory ids;
  final ParticipationClock clock;
  bool _running = false;

  Future<void> synchronize() async {
    if (_running) return;
    _running = true;
    try {
      for (final operation in await store.pendingOperations()) {
        switch (await remote.apply(operation)) {
          case ParticipationRemoteAccepted(:final record):
            await store.accept(operation, record);
          case ParticipationRemoteConflict(:final remote):
            await store.preserveConflict(
              operation,
              remote,
              SyncConflictId(ids.operationId().value),
              clock.nowUtc(),
            );
          case ParticipationRemoteFailure(failure: UnauthorizedFailure()):
            await store.markBlocked(
              operation,
              'Organizer authorization is required.',
            );
          case ParticipationRemoteFailure(:final failure):
            await store.markFailed(operation, failure.message);
        }
      }
      final checkpoint = await store.checkpoint();
      final pulled = await remote.pull(
        afterUpdatedAt: checkpoint.$1,
        afterId: checkpoint.$2,
      );
      if (pulled case RepositorySuccess(:final value)) {
        await store.reconcile(value.records, clock.nowUtc());
      }
    } finally {
      _running = false;
    }
  }
}

final class AndroidParticipationWriter implements ParticipationWriter {
  const AndroidParticipationWriter({required this.store, required this.ids});
  final ParticipationStore store;
  final ParticipationIdFactory ids;
  @override
  Future<RepositoryResult<ParticipationSaved>> save(
    ParticipationRecord record, {
    int? expectedVersion,
  }) => store.save(
    record,
    operationId: ids.operationId(),
    expectedVersion: expectedVersion,
  );
}

final class WebParticipationWriter implements ParticipationWriter {
  const WebParticipationWriter({required this.remote, required this.ids});
  final ParticipationRemoteGateway remote;
  final ParticipationIdFactory ids;
  @override
  Future<RepositoryResult<ParticipationSaved>> save(
    ParticipationRecord record, {
    int? expectedVersion,
  }) async => switch (await remote.apply(
    ParticipationOperation(
      operationId: ids.operationId(),
      record: record,
      baseVersion: expectedVersion,
    ),
  )) {
    ParticipationRemoteAccepted(:final record) => RepositorySuccess(
      ParticipationSaved(
        record: record,
        disposition: ParticipationMutationDisposition.synchronized,
      ),
    ),
    ParticipationRemoteConflict() => const RepositoryFailure(
      ConflictFailure(
        message: 'Cloud participation changed. Refresh before retrying.',
      ),
    ),
    ParticipationRemoteFailure(:final failure) => RepositoryFailure(failure),
  };
}

final class UnavailableParticipationWriter implements ParticipationWriter {
  const UnavailableParticipationWriter();
  @override
  Future<RepositoryResult<ParticipationSaved>> save(
    ParticipationRecord record, {
    int? expectedVersion,
  }) async => const RepositoryFailure(
    PersistenceUnavailableFailure(
      message: 'Participation is unavailable in this build.',
    ),
  );
}
