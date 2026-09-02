import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/infrastructure/participation/participation_providers.dart';
import 'package:vpc/src/infrastructure/participation/participation_writers.dart';
import 'package:vpc/src/infrastructure/persistence/local/local_persistence_providers.dart';

void main() {
  test('Web participation composition never initializes SQLite', () {
    var databaseFactoryCalls = 0;
    LocalPersistencePlatform? requestedPlatform;
    final container = ProviderContainer(
      overrides: [
        localPersistencePlatformProvider.overrideWithValue(
          LocalPersistencePlatform.web,
        ),
        localDatabaseFactoryProvider.overrideWithValue((platform) {
          databaseFactoryCalls++;
          requestedPlatform = platform;
          return null;
        }),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(driftParticipationStoreProvider), isNull);
    expect(
      container.read(participationWriterProvider),
      isA<UnavailableParticipationWriter>(),
    );
    expect(container.read(participationSynchronizerProvider), isNull);
    expect(container.read(participationRealtimeRuntimeProvider), isNull);
    expect(databaseFactoryCalls, 1);
    expect(requestedPlatform, LocalPersistencePlatform.web);
  });
}
