import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/public_events/public_event_readers.dart';
import 'package:vpc/src/infrastructure/persistence/local/app_database.dart';
import 'package:vpc/src/infrastructure/persistence/local/local_persistence_providers.dart';
import 'package:vpc/src/infrastructure/public_events/public_event_providers.dart';

void main() {
  test('Web public reading never initializes SQLite', () {
    var databaseFactoryCalls = 0;
    final container = ProviderContainer(
      overrides: [
        localPersistencePlatformProvider.overrideWithValue(
          LocalPersistencePlatform.web,
        ),
        localDatabaseFactoryProvider.overrideWithValue((platform) {
          databaseFactoryCalls++;
          throw StateError('Web must not request a local database.');
        }),
      ],
    );
    addTearDown(container.dispose);

    final reader = container.read(publicEventReaderProvider);

    expect(reader, isA<UnconfiguredPublicEventReader>());
    expect(databaseFactoryCalls, 0);
  });

  test('Android composes the real cache boundary without a cloud client', () {
    final database = AppDatabase.inMemory();
    final container = ProviderContainer(
      overrides: [
        localPersistencePlatformProvider.overrideWithValue(
          LocalPersistencePlatform.android,
        ),
        localDatabaseFactoryProvider.overrideWithValue((platform) => database),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(publicEventReaderProvider),
      isA<AndroidCachedPublicEventReader>(),
    );
  });
}
