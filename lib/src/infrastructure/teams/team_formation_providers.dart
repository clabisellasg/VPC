import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/teams/team_formation_contracts.dart';
import '../../application/teams/team_formation_service.dart';
import '../../core/supabase/supabase_client_provider.dart';
import '../persistence/local/local_persistence_providers.dart';
import 'drift_team_formation_store.dart';
import 'supabase_team_formation_store.dart';
import 'team_formation_realtime_runtime.dart';
import 'team_formation_primitives.dart';
import 'team_formation_synchronizer.dart';

final teamIdFactoryProvider = Provider<TeamIdFactory>(
  (ref) => SecureTeamIdFactory(),
);
final teamRandomSourceProvider = Provider<TeamRandomSource>(
  (ref) => SeededTeamRandom(),
);
final teamFormationStoreProvider = Provider<TeamFormationStore?>((ref) {
  final database = ref.watch(localDatabaseProvider);
  if (database != null) return DriftTeamFormationStore(database);
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseTeamFormationStore(client);
});
final teamFormationServiceProvider = Provider<TeamFormationService?>((ref) {
  final store = ref.watch(teamFormationStoreProvider);
  return store == null
      ? null
      : TeamFormationService(
          store: store,
          ids: ref.watch(teamIdFactoryProvider),
          random: ref.watch(teamRandomSourceProvider),
        );
});

final teamFormationSynchronizerProvider = Provider<TeamFormationSynchronizer?>((
  ref,
) {
  final local = ref.watch(localDatabaseProvider);
  final client = ref.watch(supabaseClientProvider);
  if (local == null || client == null) return null;
  return TeamFormationSynchronizer(
    local: DriftTeamFormationStore(local),
    remote: SupabaseTeamFormationStore(client),
  );
});

final teamFormationRealtimeRuntimeProvider =
    Provider<TeamFormationRealtimeRuntime?>((ref) {
      final synchronizer = ref.watch(teamFormationSynchronizerProvider);
      final client = ref.watch(supabaseClientProvider);
      if (synchronizer == null || client == null) return null;
      final runtime = TeamFormationRealtimeRuntime(
        client: client,
        synchronizer: synchronizer,
      );
      ref.onDispose(() => unawaited(runtime.dispose()));
      return runtime;
    });
