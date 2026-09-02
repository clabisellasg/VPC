import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/players/player_creation_service.dart';
import '../../application/players/player_directory_reader.dart';
import '../../application/players/player_directory_readers.dart';
import '../persistence/local/local_persistence_providers.dart';
import '../sync/sync_dependency_providers.dart';
import '../sync/sync_providers.dart';
import '../../core/supabase/supabase_client_provider.dart';
import 'drift_player_directory_cache.dart';
import 'player_creation_writers.dart';
import 'player_directory_primitives.dart';
import 'supabase_public_player_source.dart';
import '../../application/players/player_skill_editor.dart';
import 'player_skill_editors.dart';

final playerDirectoryClockProvider = Provider<PlayerDirectoryClock>(
  (ref) => const SystemPlayerDirectoryClock(),
);

final playerIdFactoryProvider = Provider<PlayerIdFactory>(
  (ref) => SecurePlayerIdFactory(),
);

final playerDirectoryRemoteSourceProvider =
    Provider<PlayerDirectoryRemoteSource?>((ref) {
      final client = ref.watch(supabaseClientProvider);
      return client == null
          ? null
          : SupabasePublicPlayerSource(SupabasePublicPlayerRowsGateway(client));
    });

final playerDirectoryCacheProvider = Provider<PlayerDirectoryCache?>((ref) {
  final database = ref.watch(localDatabaseProvider);
  return database == null ? null : DriftPlayerDirectoryCache(database);
});

final playerDirectoryReaderProvider = Provider<PlayerDirectoryReader>((ref) {
  final platform = ref.watch(localPersistencePlatformProvider);
  final remote = ref.watch(playerDirectoryRemoteSourceProvider);
  if (platform == LocalPersistencePlatform.android) {
    final cache = ref.watch(playerDirectoryCacheProvider);
    if (cache != null) {
      return AndroidCachedPlayerDirectoryReader(cache: cache, remote: remote);
    }
  }
  return remote == null
      ? const UnconfiguredPlayerDirectoryReader()
      : OnlinePlayerDirectoryReader(remote);
});

final playerCreationWriterProvider = Provider<PlayerCreationWriter>((ref) {
  final platform = ref.watch(localPersistencePlatformProvider);
  if (platform == LocalPersistencePlatform.android) {
    final repository = ref.watch(playerRepositoryProvider);
    if (repository != null) {
      return AndroidPlayerCreationWriter(
        repository: repository,
        coordinator: ref.watch(playerSyncCoordinatorProvider),
      );
    }
  } else if (platform == LocalPersistencePlatform.web) {
    final remote = ref.watch(syncRemoteGatewayProvider);
    if (remote != null) {
      return WebPlayerCreationWriter(
        remote: remote,
        idFactory: ref.watch(syncIdFactoryProvider),
        clock: ref.watch(syncClockProvider),
      );
    }
  }
  return const UnavailablePlayerCreationWriter();
});

final playerCreationServiceProvider = Provider<PlayerCreationService>((ref) {
  return PlayerCreationService(
    reader: ref.watch(playerDirectoryReaderProvider),
    writer: ref.watch(playerCreationWriterProvider),
    idFactory: ref.watch(playerIdFactoryProvider),
    clock: ref.watch(playerDirectoryClockProvider),
  );
});

final playerSkillEditorProvider = Provider<PlayerSkillEditor>((ref) {
  final platform = ref.watch(localPersistencePlatformProvider);
  if (platform == LocalPersistencePlatform.android) {
    final repository = ref.watch(playerRepositoryProvider);
    if (repository != null) {
      return AndroidPlayerSkillEditor(
        repository,
        ref.watch(playerSyncCoordinatorProvider),
      );
    }
  }
  if (platform == LocalPersistencePlatform.web) {
    final remote = ref.watch(syncRemoteGatewayProvider);
    if (remote != null) {
      return WebPlayerSkillEditor(
        ref.watch(playerDirectoryReaderProvider),
        remote,
        ref.watch(syncIdFactoryProvider),
        ref.watch(syncClockProvider),
      );
    }
  }
  return const UnavailablePlayerSkillEditor();
});
