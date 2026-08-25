import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/core/config/supabase_configuration.dart';

void main() {
  group('SupabaseConfiguration', () {
    test('is valid and unconfigured when both values are absent', () {
      final configuration = SupabaseConfiguration.fromValues();

      expect(configuration.isConfigured, isFalse);
      expect(configuration.url, isNull);
      expect(configuration.publishableKey, isNull);
    });

    test('is configured when both values are present', () {
      final configuration = SupabaseConfiguration.fromValues(
        url: 'https://configured.example.invalid',
        publishableKey: 'test-public-value',
      );

      expect(configuration.isConfigured, isTrue);
      expect(configuration.url, 'https://configured.example.invalid');
      expect(configuration.publishableKey, 'test-public-value');
    });

    test('rejects either partial configuration without exposing values', () {
      const urlValue = 'https://private-value.example.invalid';
      const keyValue = 'private-test-value';

      for (final values in [
        (url: urlValue, publishableKey: ''),
        (url: '', publishableKey: keyValue),
      ]) {
        Object? failure;
        try {
          SupabaseConfiguration.fromValues(
            url: values.url,
            publishableKey: values.publishableKey,
          );
        } on Object catch (error) {
          failure = error;
        }

        expect(failure, isA<FormatException>());
        expect(failure.toString(), isNot(contains(urlValue)));
        expect(failure.toString(), isNot(contains(keyValue)));
      }
    });

    test('rejects an invalid URL without echoing it', () {
      const invalidUrl = 'not-a-private-url-value';

      expect(
        () => SupabaseConfiguration.fromValues(
          url: invalidUrl,
          publishableKey: 'test-public-value',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.toString(),
            'message',
            isNot(contains(invalidUrl)),
          ),
        ),
      );
    });
  });
}
