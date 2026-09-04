import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/tournament/round_robin_service.dart';
import '../../core/supabase/supabase_client_provider.dart';
import '../persistence/local/local_persistence_providers.dart';
import '../sync/supabase_player_realtime_source.dart';
import 'bracket_providers.dart' show bracketPrimitivesProvider;
import 'drift_round_robin_repository.dart';
import 'round_robin_synchronizer.dart';
import 'supabase_round_robin_repository.dart';

final localRoundRobinRepositoryProvider = Provider<DriftRoundRobinRepository?>((
  ref,
) {
  final db = ref.watch(localDatabaseProvider);
  return db == null ? null : DriftRoundRobinRepository(db);
});
final remoteRoundRobinRepositoryProvider =
    Provider<SupabaseRoundRobinRepository?>((ref) {
      final client = ref.watch(supabaseClientProvider);
      return client == null ? null : SupabaseRoundRobinRepository(client);
    });
final roundRobinRepositoryProvider = Provider<RoundRobinRepository?>(
  (ref) =>
      ref.watch(localRoundRobinRepositoryProvider) ??
      ref.watch(remoteRoundRobinRepositoryProvider),
);
final roundRobinServiceProvider = Provider<RoundRobinService?>((ref) {
  final repo = ref.watch(roundRobinRepositoryProvider),
      p = ref.watch(bracketPrimitivesProvider);
  return repo == null
      ? null
      : RoundRobinService(repository: repo, ids: p, clock: p);
});
final roundRobinSynchronizerProvider =
    Provider.autoDispose<RoundRobinSynchronizer?>((ref) {
      final local = ref.watch(localRoundRobinRepositoryProvider),
          remote = ref.watch(remoteRoundRobinRepositoryProvider);
      if (local == null || remote == null) return null;
      final sync = RoundRobinSynchronizer(local: local, remote: remote);
      ref.onDispose(sync.dispose);
      return sync;
    });
final roundRobinRefreshHintsProvider = StreamProvider.autoDispose<void>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const Stream.empty();
  final hints = StreamController<void>(),
      debounce = RefreshHintDebouncer(const Duration(milliseconds: 300));
  final channel = client.channel('vpc-round-robin-hints');
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'round_robin_tournaments',
        callback: (_) => debounce.add(() {
          if (!hints.isClosed) hints.add(null);
        }),
      )
      .subscribe();
  ref.onDispose(() {
    debounce.dispose();
    unawaited(client.removeChannel(channel));
    unawaited(hints.close());
  });
  return hints.stream;
});
