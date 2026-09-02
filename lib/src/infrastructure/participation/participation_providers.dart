import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/participation/participation_contracts.dart';
import '../../application/participation/participation_models.dart';
import '../../application/participation/participation_service.dart';
import '../../core/supabase/supabase_client_provider.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../persistence/local/local_persistence_providers.dart';
import 'drift_participation_store.dart';
import 'participation_primitives.dart';
import 'participation_realtime_runtime.dart';
import 'participation_writers.dart';
import 'supabase_participation_gateway.dart';

final participationClockProvider = Provider<ParticipationClock>(
  (ref) => const SystemParticipationClock(),
);
final participationIdFactoryProvider = Provider<ParticipationIdFactory>(
  (ref) => SecureParticipationIdFactory(),
);
final participationRemoteProvider = Provider<ParticipationRemoteGateway?>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseParticipationGateway(client);
});
final driftParticipationStoreProvider = Provider<DriftParticipationStore?>((
  ref,
) {
  final database = ref.watch(localDatabaseProvider);
  return database == null ? null : DriftParticipationStore(database);
});
final participationSynchronizerProvider = Provider<ParticipationSynchronizer?>((
  ref,
) {
  final store = ref.watch(driftParticipationStoreProvider);
  final remote = ref.watch(participationRemoteProvider);
  if (store == null || remote == null) return null;
  return ParticipationSynchronizer(
    store: store,
    remote: remote,
    ids: ref.watch(participationIdFactoryProvider),
    clock: ref.watch(participationClockProvider),
  );
});
final participationRealtimeRuntimeProvider =
    Provider<ParticipationRealtimeRuntime?>((ref) {
      final client = ref.watch(supabaseClientProvider);
      final synchronizer = ref.watch(participationSynchronizerProvider);
      if (client == null || synchronizer == null) return null;
      final runtime = ParticipationRealtimeRuntime(
        client: client,
        synchronizer: synchronizer,
      );
      ref.onDispose(() => unawaited(runtime.dispose()));
      return runtime;
    });
final participationStoreProvider = Provider<ParticipationStore?>((ref) {
  final local = ref.watch(driftParticipationStoreProvider);
  if (local != null) return local;
  final remote = ref.watch(participationRemoteProvider);
  return remote == null ? null : _RemoteParticipationStore(remote);
});
final participationWriterProvider = Provider<ParticipationWriter>((ref) {
  final local = ref.watch(driftParticipationStoreProvider);
  final ids = ref.watch(participationIdFactoryProvider);
  if (local != null) return AndroidParticipationWriter(store: local, ids: ids);
  final remote = ref.watch(participationRemoteProvider);
  return remote == null
      ? const UnavailableParticipationWriter()
      : WebParticipationWriter(remote: remote, ids: ids);
});
final participationServiceProvider = Provider<ParticipationService>(
  (ref) => ParticipationService(
    writer: ref.watch(participationWriterProvider),
    ids: ref.watch(participationIdFactoryProvider),
    clock: ref.watch(participationClockProvider),
  ),
);

final class _RemoteParticipationStore implements ParticipationStore {
  const _RemoteParticipationStore(this.remote);
  final ParticipationRemoteGateway remote;
  Future<RepositoryResult<List<ParticipationRecord>>> _all() async {
    final result = await remote.pull();
    return result.when(
      success: (page) => RepositorySuccess(page.records),
      failure: RepositoryFailure.new,
    );
  }

  @override
  Future<RepositoryResult<List<ParticipationRecord>>> listForEvent(
    EventId eventId,
  ) async {
    final result = await _all();
    return result.when(
      success: (records) => RepositorySuccess(
        records
            .where(
              (record) =>
                  record.participant.eventId == eventId &&
                  !record.participant.metadata.isDeleted,
            )
            .toList(),
      ),
      failure: RepositoryFailure.new,
    );
  }

  @override
  Future<RepositoryResult<ParticipationRecord>> get(
    EventParticipantId id,
  ) async {
    final result = await _all();
    return result.when(
      success: (records) {
        for (final record in records) {
          if (record.participant.id == id) return RepositorySuccess(record);
        }
        return RepositoryFailure(
          NotFoundFailure(entity: 'Event participant', identifier: id.value),
        );
      },
      failure: RepositoryFailure.new,
    );
  }

  @override
  Future<RepositoryResult<ParticipationSaved>> save(
    ParticipationRecord record, {
    required SyncOperationId operationId,
    int? expectedVersion,
  }) async => const RepositoryFailure(
    PersistenceUnavailableFailure(
      message: 'Web writes use the cloud command path.',
    ),
  );
  @override
  Future<RepositoryResult<ParticipationSyncStatus>> syncStatus(
    EventParticipantId id,
  ) async => const RepositorySuccess(
    ParticipationSyncStatus(
      disposition: ParticipationMutationDisposition.synchronized,
    ),
  );
}
