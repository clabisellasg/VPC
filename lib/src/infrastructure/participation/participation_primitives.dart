import 'dart:math';

import '../../application/participation/participation_contracts.dart';
import '../../domain/common/entity_id.dart';

final class SystemParticipationClock implements ParticipationClock {
  const SystemParticipationClock();
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

final class SecureParticipationIdFactory implements ParticipationIdFactory {
  final Random _random = Random.secure();
  String _uuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  @override
  EventParticipantId participantId() => EventParticipantId(_uuid());
  @override
  DivisionParticipantId divisionParticipantId() =>
      DivisionParticipantId(_uuid());
  @override
  ParticipantPaymentId paymentId() => ParticipantPaymentId(_uuid());
  @override
  SyncOperationId operationId() => SyncOperationId(_uuid());
}
