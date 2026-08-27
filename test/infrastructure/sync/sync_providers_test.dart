import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/core/supabase/supabase_client_provider.dart';
import 'package:vpc/src/infrastructure/persistence/local/local_persistence_providers.dart';
import 'package:vpc/src/infrastructure/sync/sync_providers.dart';

void main() {
  test('Web-style composition creates neither SQLite sync nor Realtime', () {
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(null),
        supabaseClientProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(playerSyncStoreProvider), isNull);
    expect(container.read(syncRemoteGatewayProvider), isNull);
    expect(container.read(playerSyncCoordinatorProvider), isNull);
    expect(container.read(syncRuntimeProvider), isNull);
  });
}
