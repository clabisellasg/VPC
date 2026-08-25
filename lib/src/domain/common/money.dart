import 'domain_failure.dart';

/// A nonnegative monetary amount stored exclusively in integer minor units.
final class Money {
  factory Money({required int minorUnits, String currencyCode = 'PHP'}) {
    if (minorUnits < 0) {
      throw const ValidationFailure(
        field: 'minorUnits',
        message: 'Money cannot be negative.',
      );
    }

    final normalizedCurrency = currencyCode.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalizedCurrency)) {
      throw const ValidationFailure(
        field: 'currencyCode',
        message: 'Currency must be a three-letter ISO-style code.',
      );
    }

    return Money._(minorUnits: minorUnits, currencyCode: normalizedCurrency);
  }

  const Money._({required this.minorUnits, required this.currencyCode});

  final int minorUnits;
  final String currencyCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Money &&
          other.minorUnits == minorUnits &&
          other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(minorUnits, currencyCode);

  @override
  String toString() => '$currencyCode $minorUnits minor units';
}
