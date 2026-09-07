import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/infrastructure/persistence/local/local_persistence_providers.dart';
import 'package:vpc/src/infrastructure/sync/operational_sync_providers.dart';

void main() {
  test('Web constructs neither SQLite nor an offline coordinator', () {
    var databaseFactoryCalls = 0;
    final container = ProviderContainer(
      overrides: [
        localPersistencePlatformProvider.overrideWithValue(
          LocalPersistencePlatform.web,
        ),
        localDatabaseFactoryProvider.overrideWithValue((platform) {
          databaseFactoryCalls++;
          expect(platform, LocalPersistencePlatform.web);
          return null;
        }),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(operationalSyncStoreProvider), isNull);
    expect(container.read(operationalSyncCoordinatorProvider), isNull);
    expect(databaseFactoryCalls, 1);
  });
}
