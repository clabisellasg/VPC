import 'dart:convert';

import '../../application/sync/sync_models.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/players/permanent_player.dart';

String encodePlayerPayload(PlayerSyncPayload payload) =>
    jsonEncode(<String, Object?>{
      'created_at': payload.metadata.createdAt.toIso8601String(),
      'deleted_at': payload.metadata.deletedAt?.toIso8601String(),
      'display_name': payload.displayName,
      'id': payload.id.value,
      'updated_at': payload.metadata.updatedAt.toIso8601String(),
      'version': payload.metadata.recordVersion,
    });

PlayerSyncPayload decodePlayerPayload(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw const ValidationFailure(
      field: 'payload',
      message: 'Stored player synchronization payload is invalid.',
    );
  }
  return PlayerSyncPayload.fromPlayer(playerFromSyncMap(decoded));
}

PermanentPlayer playerFromSyncMap(Map<String, dynamic> map) {
  try {
    return PermanentPlayer(
      id: PlayerId(map['id'] as String),
      displayName: map['display_name'] as String,
      metadata: RecordMetadata(
        createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
        updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
        recordVersion: (map['version'] as num).toInt(),
        deletedAt: switch (map['deleted_at']) {
          final String value => DateTime.parse(value).toUtc(),
          null => null,
          _ => throw const FormatException(),
        },
      ),
    );
  } on DomainFailure {
    rethrow;
  } catch (_) {
    throw const ValidationFailure(
      field: 'remotePlayer',
      message: 'Remote player data is invalid.',
    );
  }
}

Map<String, Object?> playerPayloadMap(PlayerSyncPayload payload) =>
    jsonDecode(encodePlayerPayload(payload)) as Map<String, Object?>;
