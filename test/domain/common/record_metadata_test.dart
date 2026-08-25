import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';

void main() {
  group('RecordMetadata', () {
    test('accepts UTC timestamps, a tombstone, and nonnegative version', () {
      final metadata = RecordMetadata(
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
        deletedAt: DateTime.utc(2026, 1, 3),
        recordVersion: 0,
      );

      expect(metadata.createdAt.isUtc, isTrue);
      expect(metadata.updatedAt.isUtc, isTrue);
      expect(metadata.isDeleted, isTrue);
    });

    test('rejects local timestamps consistently', () {
      expect(
        () => RecordMetadata(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
          recordVersion: 0,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('rejects a negative record version', () {
      expect(
        () => RecordMetadata(
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
          recordVersion: -1,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('rejects chronologically invalid update and deletion times', () {
      expect(
        () => RecordMetadata(
          createdAt: DateTime.utc(2026, 1, 2),
          updatedAt: DateTime.utc(2026, 1, 1),
          recordVersion: 0,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => RecordMetadata(
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 3),
          deletedAt: DateTime.utc(2026, 1, 2),
          recordVersion: 1,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });
}
