import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/court/court_queue_service.dart';
import '../../core/supabase/supabase_client_provider.dart';
import '../../domain/common/entity_id.dart';
import '../events/event_setup_primitives.dart';
import '../persistence/local/local_persistence_providers.dart';
import '../sync/supabase_player_realtime_source.dart';
import 'court_queue_synchronizer.dart';
import 'drift_court_queue_repository.dart';
import 'supabase_court_queue_repository.dart';

final class SystemCourtQueuePrimitives
    implements CourtQueueIds, CourtQueueClock {
  SystemCourtQueuePrimitives() : _ids = SecureEventSetupIdFactory();
  final SecureEventSetupIdFactory _ids;
  @override
  SyncOperationId operationId() => _ids.operationId();
  @override
  CourtQueueEntryId queueEntryId() =>
      CourtQueueEntryId(_ids.operationId().value);
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

final courtQueuePrimitivesProvider = Provider<SystemCourtQueuePrimitives>(
  (ref) => SystemCourtQueuePrimitives(),
);
final localCourtQueueRepositoryProvider = Provider<DriftCourtQueueRepository?>((
  ref,
) {
  final database = ref.watch(localDatabaseProvider);
  return database == null ? null : DriftCourtQueueRepository(database);
});
final remoteCourtQueueRepositoryProvider =
    Provider<SupabaseCourtQueueRepository?>((ref) {
      final client = ref.watch(supabaseClientProvider);
      return client == null ? null : SupabaseCourtQueueRepository(client);
    });
final courtQueueRepositoryProvider = Provider<CourtQueueRepository?>(
  (ref) =>
      ref.watch(localCourtQueueRepositoryProvider) ??
      ref.watch(remoteCourtQueueRepositoryProvider),
);
final courtQueueServiceProvider = Provider<CourtQueueService?>((ref) {
  final repository = ref.watch(courtQueueRepositoryProvider);
  final primitives = ref.watch(courtQueuePrimitivesProvider);
  return repository == null
      ? null
      : CourtQueueService(
          repository: repository,
          ids: primitives,
          clock: primitives,
        );
});
final courtQueueSynchronizerProvider = Provider<CourtQueueSynchronizer?>((ref) {
  final local = ref.watch(localCourtQueueRepositoryProvider);
  final remote = ref.watch(remoteCourtQueueRepositoryProvider);
  if (local == null || remote == null) return null;
  final sync = CourtQueueSynchronizer(local: local, remote: remote);
  ref.onDispose(sync.dispose);
  return sync;
});
final courtQueueRefreshHintsProvider = StreamProvider.autoDispose<void>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const Stream<void>.empty();
  final hints = StreamController<void>();
  final debounce = RefreshHintDebouncer(const Duration(milliseconds: 300));
  final channel = client.channel('vpc-court-queue-hints');
  for (final table in ['matches', 'court_queue_entries']) {
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: (_) => debounce.add(() {
        if (!hints.isClosed) hints.add(null);
      }),
    );
  }
  channel.subscribe();
  ref.onDispose(() {
    debounce.dispose();
    unawaited(client.removeChannel(channel));
    unawaited(hints.close());
  });
  return hints.stream;
});
