import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/public_events/public_event_reader.dart';
import '../../application/public_events/public_event_readers.dart';
import '../../core/supabase/supabase_client_provider.dart';
import '../persistence/local/local_persistence_providers.dart';
import 'drift_public_event_cache.dart';
import 'supabase_public_event_source.dart';

final publicEventClockProvider = Provider<PublicEventClock>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

final publicEventRemoteSourceProvider = Provider<PublicEventRemoteSource?>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? null
      : SupabasePublicEventSource(
          SupabasePublicRowsGateway(client),
          clock: ref.watch(publicEventClockProvider),
        );
});

final publicEventCacheProvider = Provider<PublicEventCache?>((ref) {
  final database = ref.watch(localDatabaseProvider);
  return database == null
      ? null
      : DriftPublicEventCache(
          database,
          clock: ref.watch(publicEventClockProvider),
        );
});

final publicEventReaderProvider = Provider<PublicEventReader>((ref) {
  final platform = ref.watch(localPersistencePlatformProvider);
  final remote = ref.watch(publicEventRemoteSourceProvider);
  if (platform == LocalPersistencePlatform.android) {
    final cache = ref.watch(publicEventCacheProvider);
    if (cache != null) {
      return AndroidCachedPublicEventReader(cache: cache, remote: remote);
    }
  }
  return remote == null
      ? const UnconfiguredPublicEventReader()
      : OnlinePublicEventReader(remote);
});
