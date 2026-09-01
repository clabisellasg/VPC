import 'dart:math';

import '../../application/events/event_setup_contracts.dart';
import '../../domain/common/entity_id.dart';

final class SystemEventSetupClock implements EventSetupClock {
  const SystemEventSetupClock();
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

final class SecureEventSetupIdFactory implements EventSetupIdFactory {
  final Random _random = Random.secure();
  @override
  EventId eventId() => EventId(_uuid());
  @override
  DivisionId divisionId() => DivisionId(_uuid());
  @override
  SyncOperationId operationId() => SyncOperationId(_uuid());

  String _uuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
