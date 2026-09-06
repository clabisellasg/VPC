import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/infrastructure/sync/outbox_ordering.dart';

void main() {
  group('cross-outbox timestamp ordering', () {
    test('accepts the ISO-8601 text returned by raw Drift rows', () {
      const timestamp = '2026-09-06T04:09:24.019387Z';

      expect(outboxCreatedAt({'created_at': timestamp}), same(timestamp));
    });

    test('also accepts typed DateTime rows', () {
      final timestamp = DateTime.utc(2026, 9, 6, 4, 9, 24);

      expect(outboxCreatedAt({'created_at': timestamp}), same(timestamp));
    });

    test('rejects missing or malformed values explicitly', () {
      expect(
        () => outboxCreatedAt({'created_at': 42}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
