import 'domain_failure.dart';

String requireNonBlank(String value, {required String field}) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ValidationFailure(field: field, message: '$field cannot be blank.');
  }
  return normalized;
}

void requireUtc(DateTime value, {required String field}) {
  if (!value.isUtc) {
    throw ValidationFailure(field: field, message: '$field must be UTC.');
  }
}

void requireNonNegative(int value, {required String field}) {
  if (value < 0) {
    throw ValidationFailure(
      field: field,
      message: '$field cannot be negative.',
    );
  }
}

void requirePositive(int value, {required String field}) {
  if (value <= 0) {
    throw ValidationFailure(field: field, message: '$field must be positive.');
  }
}
