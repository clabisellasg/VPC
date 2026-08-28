import 'dart:math';

import '../../application/players/player_directory_reader.dart';
import '../../domain/common/entity_id.dart';

final class SystemPlayerDirectoryClock implements PlayerDirectoryClock {
  const SystemPlayerDirectoryClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

final class SecurePlayerIdFactory implements PlayerIdFactory {
  SecurePlayerIdFactory() : _random = Random.secure();

  final Random _random;

  @override
  PlayerId createPlayerId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return PlayerId(
      '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}',
    );
  }
}
