import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/tournament/double_elimination_service.dart';
import '../../core/supabase/supabase_client_provider.dart';
import '../persistence/local/local_persistence_providers.dart';
import '../sync/supabase_player_realtime_source.dart';
import 'bracket_providers.dart' show bracketPrimitivesProvider;
import 'double_elimination_synchronizer.dart';
import 'drift_double_elimination_repository.dart';
import 'supabase_double_elimination_repository.dart';

final localDoubleEliminationRepositoryProvider =
    Provider<DriftDoubleEliminationRepository?>((ref) {
      final database = ref.watch(localDatabaseProvider);
      return database == null
          ? null
          : DriftDoubleEliminationRepository(database);
    });
final remoteDoubleEliminationRepositoryProvider =
    Provider<SupabaseDoubleEliminationRepository?>((ref) {
      final client = ref.watch(supabaseClientProvider);
      return client == null
          ? null
          : SupabaseDoubleEliminationRepository(client);
    });
final doubleEliminationRepositoryProvider =
    Provider<DoubleEliminationRepository?>(
      (ref) =>
          ref.watch(localDoubleEliminationRepositoryProvider) ??
          ref.watch(remoteDoubleEliminationRepositoryProvider),
    );
final doubleEliminationServiceProvider = Provider<DoubleEliminationService?>((
  ref,
) {
  final repository = ref.watch(doubleEliminationRepositoryProvider);
  final primitives = ref.watch(bracketPrimitivesProvider);
  return repository == null
      ? null
      : DoubleEliminationService(
          repository: repository,
          ids: primitives,
          clock: primitives,
        );
});
final doubleEliminationSynchronizerProvider =
    Provider.autoDispose<DoubleEliminationSynchronizer?>((ref) {
      final local = ref.watch(localDoubleEliminationRepositoryProvider);
      final remote = ref.watch(remoteDoubleEliminationRepositoryProvider);
      if (local == null || remote == null) return null;
      final synchronizer = DoubleEliminationSynchronizer(
        local: local,
        remote: remote,
      );
      ref.onDispose(synchronizer.dispose);
      return synchronizer;
    });
final doubleEliminationRefreshHintsProvider = StreamProvider.autoDispose<void>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const Stream<void>.empty();
  final hints = StreamController<void>();
  final debounce = RefreshHintDebouncer(const Duration(milliseconds: 300));
  final channel = client.channel('vpc-double-elimination-hints');
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'double_elimination_brackets',
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
