import 'dart:math';

import '../../application/teams/team_formation_contracts.dart';
import '../../domain/common/entity_id.dart';

final class SecureTeamIdFactory implements TeamIdFactory {
  final Random _random = Random.secure();
  String _uuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  @override
  TeamId nextTeamId() => TeamId(_uuid());
  @override
  SyncOperationId nextOperationId() => SyncOperationId(_uuid());
}

final class SeededTeamRandom implements TeamRandomSource {
  SeededTeamRandom([int? seed]) : _random = Random(seed);
  final Random _random;
  @override
  List<T> shuffled<T>(List<T> values) {
    final copy = List<T>.of(values);
    copy.shuffle(_random);
    return copy;
  }
}
