import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/money.dart';

void main() {
  group('Money', () {
    test('allows zero and defaults to PHP', () {
      final money = Money(minorUnits: 0);

      expect(money.minorUnits, 0);
      expect(money.currencyCode, 'PHP');
    });

    test('allows positive integer minor units and normalizes currency', () {
      expect(
        Money(minorUnits: 12500, currencyCode: 'php'),
        Money(minorUnits: 12500),
      );
    });

    test('rejects negative amounts', () {
      expect(() => Money(minorUnits: -1), throwsA(isA<ValidationFailure>()));
    });

    test('rejects invalid ISO-style currency codes', () {
      for (final code in ['', 'PH', 'PHP1', '₱₱₱']) {
        expect(
          () => Money(minorUnits: 1, currencyCode: code),
          throwsA(isA<ValidationFailure>()),
        );
      }
    });

    test('compares by minor units and currency', () {
      expect(Money(minorUnits: 100), Money(minorUnits: 100));
      expect(Money(minorUnits: 100), isNot(Money(minorUnits: 101)));
      expect(
        Money(minorUnits: 100),
        isNot(Money(minorUnits: 100, currencyCode: 'USD')),
      );
    });
  });
}
