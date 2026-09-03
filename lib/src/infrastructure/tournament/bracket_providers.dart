import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/supabase_player_realtime_source.dart';

import '../../application/tournament/single_elimination_service.dart';
import '../../domain/common/entity_id.dart';
import '../../core/supabase/supabase_client_provider.dart';
import '../events/event_setup_primitives.dart';
import '../persistence/local/local_persistence_providers.dart';
import 'drift_bracket_repository.dart';
import 'supabase_bracket_repository.dart';
import 'bracket_synchronizer.dart';

final class SystemBracketPrimitives implements BracketIds, BracketClock {
  final _ids = SecureEventSetupIdFactory();
  @override
  MatchId matchId() => MatchId(_ids.operationId().value);
  @override
  SyncOperationId operationId() => _ids.operationId();
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

final bracketPrimitivesProvider = Provider<SystemBracketPrimitives>(
  (ref) => SystemBracketPrimitives(),
);
final localBracketRepositoryProvider = Provider<DriftBracketRepository?>((ref) {
  final db = ref.watch(localDatabaseProvider);
  return db == null ? null : DriftBracketRepository(db);
});
final remoteBracketRepositoryProvider = Provider<SupabaseBracketRepository?>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseBracketRepository(client);
});
final bracketRepositoryProvider = Provider<BracketRepository?>(
  (ref) =>
      ref.watch(localBracketRepositoryProvider) ??
      ref.watch(remoteBracketRepositoryProvider),
);
final singleEliminationServiceProvider = Provider<SingleEliminationService?>((
  ref,
) {
  final repo = ref.watch(bracketRepositoryProvider),
      primitives = ref.watch(bracketPrimitivesProvider);
  return repo == null
      ? null
      : SingleEliminationService(
          repository: repo,
          ids: primitives,
          clock: primitives,
        );
});
final bracketSynchronizerProvider = Provider.autoDispose<BracketSynchronizer?>((
  ref,
) {
  final local = ref.watch(localBracketRepositoryProvider),
      remote = ref.watch(remoteBracketRepositoryProvider);
  if (local == null || remote == null) return null;
  final sync = BracketSynchronizer(local: local, remote: remote);
  ref.onDispose(sync.dispose);
  return sync;
});

final bracketRefreshHintsProvider = StreamProvider.autoDispose<void>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const Stream<void>.empty();
  final hints = StreamController<void>();
  final debounce = RefreshHintDebouncer(const Duration(milliseconds: 300));
  final channel = client.channel('vpc-single-elimination-hints');
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'single_elimination_brackets',
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
