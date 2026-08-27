import 'dart:async';
import 'dart:math';

import '../../application/sync/sync_contracts.dart';
import '../../domain/common/entity_id.dart';

final class SystemSyncClock implements SyncClock {
  const SystemSyncClock();

  @override
  Future<void> delay(Duration duration) => Future<void>.delayed(duration);

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

final class SecureSyncIdFactory implements SyncIdFactory {
  SecureSyncIdFactory() : _random = Random.secure();

  final Random _random;

  @override
  SyncConflictId conflictId() => SyncConflictId(_uuidV4());

  @override
  SyncOperationId operationId() => SyncOperationId(_uuidV4());

  String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

final class RandomSyncJitter implements SyncJitter {
  RandomSyncJitter() : _random = Random.secure();

  final Random _random;

  @override
  int milliseconds(int upperExclusive) =>
      upperExclusive <= 0 ? 0 : _random.nextInt(upperExclusive);
}
