import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sync/operational_sync.dart';
import '../court/court_queue_providers.dart';
import '../events/event_setup_providers.dart';
import '../participation/participation_providers.dart';
import '../persistence/local/local_persistence_providers.dart';
import '../teams/team_formation_providers.dart';
import '../tournament/bracket_providers.dart';
import '../tournament/double_elimination_providers.dart';
import '../tournament/round_robin_providers.dart';
import 'drift_operational_sync_store.dart';
import 'sync_providers.dart';

final operationalSyncStoreProvider = Provider<OperationalSyncStore?>((ref) {
  final database = ref.watch(localDatabaseProvider);
  return database == null ? null : DriftOperationalSyncStore(database);
});

final operationalSyncCoordinatorProvider =
    Provider<OperationalSyncCoordinator?>((ref) {
      final store = ref.watch(operationalSyncStoreProvider);
      if (store == null) return null;
      final runners = <OperationalSyncRunner>[
        if (ref.watch(playerSyncCoordinatorProvider) case final runner?)
          _Runner(runner.synchronize),
        if (ref.watch(eventSetupSynchronizerProvider) case final runner?)
          _Runner(runner.synchronize),
        if (ref.watch(participationSynchronizerProvider) case final runner?)
          _Runner(runner.synchronize),
        if (ref.watch(teamFormationSynchronizerProvider) case final runner?)
          _Runner(runner.synchronize),
        if (ref.watch(bracketSynchronizerProvider) case final runner?)
          _Runner(runner.synchronize),
        if (ref.watch(roundRobinSynchronizerProvider) case final runner?)
          _Runner(runner.synchronize),
        if (ref.watch(doubleEliminationSynchronizerProvider) case final runner?)
          _Runner(runner.synchronize),
        if (ref.watch(courtQueueSynchronizerProvider) case final runner?)
          _Runner(runner.synchronize),
      ];
      final coordinator = OperationalSyncCoordinator(
        store: store,
        runners: runners,
        nowUtc: DateTime.now,
      );
      ref.onDispose(coordinator.dispose);
      return coordinator;
    });

final class _Runner implements OperationalSyncRunner {
  const _Runner(this._run);
  final Future<void> Function() _run;
  @override
  Future<void> synchronize() => _run();
}
