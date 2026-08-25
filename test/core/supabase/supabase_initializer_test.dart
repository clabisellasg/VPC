import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vpc/src/core/config/supabase_configuration.dart';
import 'package:vpc/src/core/supabase/supabase_initializer.dart';

void main() {
  test('does not initialize Supabase when configuration is absent', () async {
    final initializer = _RecordingInitializer();

    final client = await initializeSupabaseIfConfigured(
      SupabaseConfiguration.fromValues(),
      initializer: initializer,
    );

    expect(client, isNull);
    expect(initializer.callCount, 0);
  });

  test('initializes exactly once when configuration is complete', () async {
    final initializer = _RecordingInitializer();
    final configuration = SupabaseConfiguration.fromValues(
      url: 'https://configured.example.invalid',
      publishableKey: 'test-public-value',
    );

    final client = await initializeSupabaseIfConfigured(
      configuration,
      initializer: initializer,
    );

    expect(client, same(initializer.client));
    expect(initializer.callCount, 1);
    expect(initializer.lastConfiguration, same(configuration));
  });
}

final class _RecordingInitializer implements SupabaseInitializer {
  final client = SupabaseClient(
    'https://configured.example.invalid',
    'test-public-value',
  );

  int callCount = 0;
  SupabaseConfiguration? lastConfiguration;

  @override
  Future<SupabaseClient> initialize(SupabaseConfiguration configuration) async {
    callCount += 1;
    lastConfiguration = configuration;
    return client;
  }
}
