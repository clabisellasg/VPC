import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/players/player_directory_readers.dart';
import 'package:vpc/src/infrastructure/persistence/local/local_persistence_providers.dart';
import 'package:vpc/src/infrastructure/players/player_creation_writers.dart';
import 'package:vpc/src/infrastructure/players/player_directory_providers.dart';

void main() {
  test('Web directory never initializes SQLite', () {
    var databaseFactoryCalls = 0;
    final container = ProviderContainer(
      overrides: [
        localPersistencePlatformProvider.overrideWithValue(
          LocalPersistencePlatform.web,
        ),
        localDatabaseFactoryProvider.overrideWithValue((platform) {
          databaseFactoryCalls++;
          fail('Web must not request a local database.');
        }),
      ],
    );
    addTearDown(container.dispose);
    expect(
      container.read(playerDirectoryReaderProvider),
      isA<UnconfiguredPlayerDirectoryReader>(),
    );
    expect(
      container.read(playerCreationWriterProvider),
      isA<UnavailablePlayerCreationWriter>(),
    );
    expect(databaseFactoryCalls, 0);
  });

  test('unsupported platform exposes no persistence implementation', () {
    final container = ProviderContainer(
      overrides: [
        localPersistencePlatformProvider.overrideWithValue(
          LocalPersistencePlatform.unsupported,
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(
      container.read(playerCreationWriterProvider),
      isA<UnavailablePlayerCreationWriter>(),
    );
  });
}
