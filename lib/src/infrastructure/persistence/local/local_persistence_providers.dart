import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/events/event_repository.dart';
import '../../../domain/matches/match_repository.dart';
import '../../../domain/players/player_repository.dart';
import 'android_host.dart';
import 'app_database.dart';
import 'drift_event_repository.dart';
import 'drift_match_repository.dart';
import 'drift_player_repository.dart';

enum LocalPersistencePlatform { android, web, unsupported }

typedef LocalDatabaseFactory = AppDatabase? Function(
  LocalPersistencePlatform platform,
);

LocalPersistencePlatform resolveLocalPersistencePlatform() {
  if (kIsWeb) {
    return LocalPersistencePlatform.web;
  }
  return isAndroidHost
      ? LocalPersistencePlatform.android
      : LocalPersistencePlatform.unsupported;
}

AppDatabase? createLocalDatabase(LocalPersistencePlatform platform) =>
    platform == LocalPersistencePlatform.android
    ? AppDatabase.forAndroid()
    : null;

final localPersistencePlatformProvider = Provider<LocalPersistencePlatform>(
  (ref) => resolveLocalPersistencePlatform(),
);

final localDatabaseFactoryProvider = Provider<LocalDatabaseFactory>(
  (ref) => createLocalDatabase,
);

final localDatabaseProvider = Provider<AppDatabase?>((ref) {
  final factory = ref.watch(localDatabaseFactoryProvider);
  final platform = ref.watch(localPersistencePlatformProvider);
  final database = factory(platform);
  if (database != null) {
    ref.onDispose(database.close);
  }
  return database;
});

final playerRepositoryProvider = Provider<PlayerRepository?>((ref) {
  final database = ref.watch(localDatabaseProvider);
  return database == null ? null : DriftPlayerRepository(database);
});

final eventRepositoryProvider = Provider<EventRepository?>((ref) {
  final database = ref.watch(localDatabaseProvider);
  return database == null ? null : DriftEventRepository(database);
});

final matchRepositoryProvider = Provider<MatchRepository?>((ref) {
  final database = ref.watch(localDatabaseProvider);
  return database == null ? null : DriftMatchRepository(database);
});
