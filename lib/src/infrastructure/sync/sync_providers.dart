import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sync/player_sync_coordinator.dart';
import '../../application/sync/sync_contracts.dart';
import '../../application/sync/sync_runtime.dart';
import '../../core/supabase/supabase_client_provider.dart';
import '../persistence/local/local_persistence_providers.dart';
import 'drift_player_sync_store.dart';
import 'supabase_player_realtime_source.dart';
import 'supabase_player_sync_gateway.dart';
import 'sync_dependency_providers.dart';

final playerSyncStoreProvider = Provider<PlayerSyncStore?>((ref) {
  final database = ref.watch(localDatabaseProvider);
  return database == null ? null : DriftPlayerSyncStore(database);
});

final syncRemoteGatewayProvider = Provider<SyncRemoteGateway?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabasePlayerSyncGateway(client);
});

final playerSyncCoordinatorProvider = Provider<SyncCoordinator?>((ref) {
  final store = ref.watch(playerSyncStoreProvider);
  final remote = ref.watch(syncRemoteGatewayProvider);
  if (store == null || remote == null) {
    return null;
  }
  final coordinator = PlayerSyncCoordinator(
    store: store,
    remote: remote,
    clock: ref.watch(syncClockProvider),
    jitter: ref.watch(syncJitterProvider),
    idFactory: ref.watch(syncIdFactoryProvider),
  );
  ref.onDispose(() => unawaited(coordinator.dispose()));
  return coordinator;
});

final syncRuntimeProvider = Provider<SyncRuntime?>((ref) {
  final coordinator = ref.watch(playerSyncCoordinatorProvider);
  final client = ref.watch(supabaseClientProvider);
  if (coordinator == null || client == null) {
    return null;
  }
  final runtime = SyncRuntime(
    coordinator: coordinator,
    realtimeSource: SupabasePlayerRealtimeSource(client),
  );
  ref.onDispose(() => unawaited(runtime.dispose()));
  return runtime;
});
