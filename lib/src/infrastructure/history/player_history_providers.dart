import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/history/player_history_models.dart';
import '../../core/supabase/supabase_client_provider.dart';
import '../persistence/local/local_persistence_providers.dart';
import 'drift_player_history_reader.dart';
import 'supabase_player_history_reader.dart';

final playerHistoryReaderProvider = Provider<PlayerHistoryReader?>((ref) {
  if (ref.watch(localPersistencePlatformProvider) ==
      LocalPersistencePlatform.android) {
    final database = ref.watch(localDatabaseProvider);
    if (database != null) return DriftPlayerHistoryReader(database);
  }
  if (ref.watch(localPersistencePlatformProvider) ==
      LocalPersistencePlatform.web) {
    final client = ref.watch(supabaseClientProvider);
    return client == null ? null : SupabasePlayerHistoryReader(client);
  }
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabasePlayerHistoryReader(client);
});
