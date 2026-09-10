import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/core/config/supabase_configuration.dart';
import 'package:vpc/src/core/supabase/supabase_client_provider.dart';

void main() {
  test('public client is absent when cloud configuration is absent', () {
    final client = createPublicSupabaseClient(
      SupabaseConfiguration.fromValues(),
    );

    expect(client, isNull);
  });

  test('public client starts without an authenticated session', () async {
    final client = createPublicSupabaseClient(
      SupabaseConfiguration.fromValues(
        url: 'https://project.example.invalid',
        publishableKey: 'publishable-test-value',
      ),
    );

    expect(client, isNotNull);
    expect(client!.auth.currentSession, isNull);
    await client.dispose();
  });
}
