import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/core/config/production_web_configuration.dart';

void main() {
  test('requires complete production configuration', () {
    expect(
      () => ProductionWebConfiguration.fromEnvironment(const {}),
      throwsFormatException,
    );
    expect(
      () => ProductionWebConfiguration.fromEnvironment(const {
        'SUPABASE_URL': 'https://project.example.invalid',
      }),
      throwsFormatException,
    );
  });

  test('configuration errors do not reveal provided values', () {
    const privateValue = 'private-test-value';
    Object? failure;
    try {
      ProductionWebConfiguration.fromEnvironment(const {
        'SUPABASE_URL': privateValue,
        'SUPABASE_PUBLISHABLE_KEY': 'publishable-test-value',
      });
    } on Object catch (error) {
      failure = error;
    }
    expect(failure, isA<FormatException>());
    expect(failure.toString(), isNot(contains(privateValue)));
  });

  test('production rejects non-HTTPS endpoints without exposing them', () {
    const insecureUrl = 'http://production.example.invalid';
    Object? failure;
    try {
      ProductionWebConfiguration.fromEnvironment(const {
        'SUPABASE_URL': insecureUrl,
        'SUPABASE_PUBLISHABLE_KEY': 'publishable-test-value',
      });
    } on Object catch (error) {
      failure = error;
    }
    expect(failure, isA<FormatException>());
    expect(failure.toString(), isNot(contains(insecureUrl)));
  });

  test('creates release defines for complete configuration', () {
    final configuration = ProductionWebConfiguration.fromEnvironment(const {
      'SUPABASE_URL': 'https://project.example.invalid',
      'SUPABASE_PUBLISHABLE_KEY': 'publishable-test-value',
    });
    expect(configuration.toDartDefineJson(), <String, Object>{
      'APP_ENV': 'production',
      'SUPABASE_URL': 'https://project.example.invalid',
      'SUPABASE_PUBLISHABLE_KEY': 'publishable-test-value',
    });
  });
}
