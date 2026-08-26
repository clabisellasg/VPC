import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';
import 'package:vpc/src/infrastructure/persistence/local/local_persistence_providers.dart';

void main() {
  test('Web and unsupported platforms never create a SQLite database', () {
    expect(createLocalDatabase(LocalPersistencePlatform.web), isNull);
    expect(createLocalDatabase(LocalPersistencePlatform.unsupported), isNull);
  });

  test('repository providers remain unavailable without a local database', () {
    final container = ProviderContainer(
      overrides: [localDatabaseProvider.overrideWithValue(null)],
    );
    addTearDown(container.dispose);

    expect(container.read(playerRepositoryProvider), isNull);
    expect(container.read(eventRepositoryProvider), isNull);
    expect(container.read(matchRepositoryProvider), isNull);
  });

  test('disposing the Riverpod owner closes its database', () async {
    final database = AppDatabase.inMemory();
    final container = ProviderContainer(
      overrides: [
        localPersistencePlatformProvider.overrideWithValue(
          LocalPersistencePlatform.android,
        ),
        localDatabaseFactoryProvider.overrideWithValue((_) => database),
      ],
    );

    expect(container.read(localDatabaseProvider), same(database));
    await database.customSelect('SELECT 1').get();
    container.dispose();
    await Future<void>.delayed(Duration.zero);

    await expectLater(
      database.customSelect('SELECT 1').get(),
      throwsA(anything),
    );
  });
}
