import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/events/event_setup_contracts.dart';
import '../../application/events/event_setup_models.dart';
import '../../application/events/event_setup_service.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../core/supabase/supabase_client_provider.dart';
import '../persistence/local/local_persistence_providers.dart';
import 'drift_event_setup_store.dart';
import 'event_setup_primitives.dart';
import 'event_setup_realtime_runtime.dart';
import 'event_setup_writers.dart';
import 'supabase_event_setup_gateway.dart';

final eventSetupClockProvider = Provider<EventSetupClock>(
  (ref) => const SystemEventSetupClock(),
);
final eventSetupIdFactoryProvider = Provider<EventSetupIdFactory>(
  (ref) => SecureEventSetupIdFactory(),
);

final eventSetupRemoteProvider = Provider<EventSetupRemoteGateway?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseEventSetupGateway(client);
});

final driftEventSetupStoreProvider = Provider<DriftEventSetupStore?>((ref) {
  final database = ref.watch(localDatabaseProvider);
  return database == null ? null : DriftEventSetupStore(database);
});

final eventSetupSynchronizerProvider = Provider<EventSetupSynchronizer?>((ref) {
  final store = ref.watch(driftEventSetupStoreProvider);
  final remote = ref.watch(eventSetupRemoteProvider);
  if (store == null || remote == null) return null;
  return EventSetupSynchronizer(
    store: store,
    remote: remote,
    idFactory: ref.watch(eventSetupIdFactoryProvider),
    clock: ref.watch(eventSetupClockProvider),
  );
});

final eventSetupRealtimeRuntimeProvider = Provider<EventSetupRealtimeRuntime?>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  final synchronizer = ref.watch(eventSetupSynchronizerProvider);
  if (client == null || synchronizer == null) return null;
  final runtime = EventSetupRealtimeRuntime(
    client: client,
    synchronizer: synchronizer,
  );
  ref.onDispose(() => unawaited(runtime.dispose()));
  return runtime;
});

final eventSetupStoreProvider = Provider<EventSetupStore?>((ref) {
  final local = ref.watch(driftEventSetupStoreProvider);
  if (local != null) return local;
  final remote = ref.watch(eventSetupRemoteProvider);
  return remote == null ? null : _RemoteEventSetupStore(remote);
});

final eventSetupWriterProvider = Provider<EventSetupWriter>((ref) {
  final local = ref.watch(driftEventSetupStoreProvider);
  final ids = ref.watch(eventSetupIdFactoryProvider);
  if (local != null) {
    return AndroidEventSetupWriter(store: local, idFactory: ids);
  }
  final remote = ref.watch(eventSetupRemoteProvider);
  return remote == null
      ? const UnavailableEventSetupWriter()
      : WebEventSetupWriter(remote: remote, idFactory: ids);
});

final eventSetupServiceProvider = Provider<EventSetupService>(
  (ref) => EventSetupService(
    writer: ref.watch(eventSetupWriterProvider),
    idFactory: ref.watch(eventSetupIdFactoryProvider),
    clock: ref.watch(eventSetupClockProvider),
  ),
);

final class _RemoteEventSetupStore implements EventSetupStore {
  const _RemoteEventSetupStore(this.remote);
  final EventSetupRemoteGateway remote;
  @override
  Future<RepositoryResult<List<EventSetup>>> listSetups() async {
    final result = await remote.pull();
    return result.when(
      success: (page) => RepositorySuccess(page.setups),
      failure: RepositoryFailure.new,
    );
  }

  @override
  Future<RepositoryResult<EventSetup>> getSetup(EventId id) async {
    final result = await listSetups();
    return result.when(
      success: (setups) {
        for (final setup in setups) {
          if (setup.event.id == id) return RepositorySuccess(setup);
        }
        return RepositoryFailure(
          NotFoundFailure(entity: 'Event', identifier: id.value),
        );
      },
      failure: RepositoryFailure.new,
    );
  }

  @override
  Future<RepositoryResult<EventSetupSaved>> save(
    EventSetup setup, {
    required SyncOperationId operationId,
    int? expectedVersion,
  }) async => const RepositoryFailure(
    PersistenceUnavailableFailure(
      message: 'Web setup writes use the cloud command path.',
    ),
  );
  @override
  Future<RepositoryResult<EventSetupSyncStatus>> syncStatus(EventId id) async =>
      const RepositorySuccess(
        EventSetupSyncStatus(
          disposition: EventMutationDisposition.synchronized,
        ),
      );
}
