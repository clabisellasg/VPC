import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/sync/sync_contracts.dart';
import '../../application/sync/sync_models.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/players/permanent_player.dart';
import 'player_sync_codec.dart';

final class SupabasePlayerSyncGateway implements SyncRemoteGateway {
  const SupabasePlayerSyncGateway(this.client);

  final SupabaseClient client;

  @override
  Future<RemoteApplyResult> applyPlayerOperation(
    SyncOperation operation,
  ) async {
    if (client.auth.currentSession == null) {
      return const RemoteApplyFailure(
        kind: SyncFailureKind.authorizationBlocked,
        safeMessage: 'An authenticated organizer session is required.',
      );
    }
    try {
      final response = await client.rpc<dynamic>(
        'apply_player_sync_operation',
        params: <String, Object?>{
          'p_operation_id': operation.id.value,
          'p_entity_id': operation.entityId.value,
          'p_operation_kind': operation.kind.name,
          'p_base_version': operation.baseVersion,
          'p_payload': playerPayloadMap(operation.payload),
        },
      );
      if (response is! Map<String, dynamic>) {
        return const RemoteApplyFailure(
          kind: SyncFailureKind.invalidRemoteData,
          safeMessage: 'The synchronization response was invalid.',
        );
      }
      final status = response['status'];
      if (status == 'accepted') {
        final player = _playerFromResponse(response['player']);
        return RemoteApplyAccepted(
          player: player,
          replayed: response['replayed'] == true,
        );
      }
      if (status == 'conflict') {
        return RemoteApplyConflict(
          remotePlayer: response['player'] == null
              ? null
              : _playerFromResponse(response['player']),
        );
      }
      return const RemoteApplyFailure(
        kind: SyncFailureKind.permanent,
        safeMessage: 'The cloud rejected the synchronization operation.',
      );
    } on PostgrestException catch (error) {
      return _postgrestFailure(error);
    } on DomainFailure {
      return const RemoteApplyFailure(
        kind: SyncFailureKind.invalidRemoteData,
        safeMessage: 'The cloud returned invalid player data.',
      );
    } on Exception {
      return const RemoteApplyFailure(
        kind: SyncFailureKind.retryable,
        safeMessage: 'The cloud is temporarily unavailable.',
      );
    }
  }

  @override
  Future<RemotePullResult> pullPlayers({
    SyncCheckpoint? after,
    required int limit,
  }) async {
    if (client.auth.currentSession == null) {
      return const RemotePullFailure(
        kind: SyncFailureKind.authorizationBlocked,
        safeMessage: 'An authenticated organizer session is required for tombstone-aware pull.',
      );
    }
    try {
      final response = await client.rpc<dynamic>(
        'pull_player_sync_changes',
        params: <String, Object?>{
          'p_after_updated_at': after?.updatedAt.toIso8601String(),
          'p_after_id': after?.entityId.value,
          'p_limit': limit,
        },
      );
      if (response is! List) {
        return const RemotePullFailure(
          kind: SyncFailureKind.invalidRemoteData,
          safeMessage: 'The synchronization pull response was invalid.',
        );
      }
      final players = <dynamic>[...response]
          .map(_playerFromResponse)
          .toList(growable: false);
      return RemotePullSuccess(
        RemotePullPage(players: players, hasMore: players.length == limit),
      );
    } on PostgrestException catch (error) {
      final failure = _postgrestFailure(error);
      return RemotePullFailure(
        kind: failure.kind,
        safeMessage: failure.safeMessage,
      );
    } on DomainFailure {
      return const RemotePullFailure(
        kind: SyncFailureKind.invalidRemoteData,
        safeMessage: 'The cloud returned invalid player data.',
      );
    } on Exception {
      return const RemotePullFailure(
        kind: SyncFailureKind.retryable,
        safeMessage: 'The cloud is temporarily unavailable.',
      );
    }
  }

  PermanentPlayer _playerFromResponse(Object? value) {
    if (value is! Map) {
      throw const ValidationFailure(
        field: 'remotePlayer',
        message: 'Remote player data is invalid.',
      );
    }
    return playerFromSyncMap(Map<String, dynamic>.from(value));
  }
}

RemoteApplyFailure _postgrestFailure(PostgrestException error) {
  final authorization = error.code == '42501' || error.code == 'PGRST301';
  final permanent = error.code == '22023' || error.code == '23514';
  return RemoteApplyFailure(
    kind: authorization
        ? SyncFailureKind.authorizationBlocked
        : permanent
        ? SyncFailureKind.permanent
        : SyncFailureKind.retryable,
    safeMessage: authorization
        ? 'An authenticated organizer session is required.'
        : permanent
        ? 'The cloud rejected the synchronization operation.'
        : 'The cloud is temporarily unavailable.',
  );
}
