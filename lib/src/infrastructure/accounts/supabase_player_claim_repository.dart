import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/accounts/account_models.dart';
import '../../application/accounts/player_claim_repository.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/players/permanent_player.dart';

final class SupabasePlayerClaimRepository implements PlayerClaimRepository {
  const SupabasePlayerClaimRepository(this.client);

  final SupabaseClient client;

  @override
  Future<RepositoryResult<AccountSnapshot>> loadCurrentAccount() =>
      _guard(() async {
        final value = await client.rpc<dynamic>('get_current_account_snapshot');
        final row = _map(value, field: 'account');
        final profile = _profile(_map(row['profile'], field: 'profile'));
        final authorization = _authorization(row['authorization']);
        final claimValue = row['claim'];
        return AccountSnapshot(
          profile: profile,
          authorization: authorization,
          claim: claimValue == null
              ? null
              : _claim(_map(claimValue, field: 'claim')),
        );
      });

  @override
  Future<RepositoryResult<List<PermanentPlayer>>> searchEligiblePlayers(
    String query,
  ) => _guard(() async {
    final value = await client.rpc<dynamic>(
      'list_claimable_players',
      params: <String, Object?>{'p_search': query.trim(), 'p_limit': 50},
    );
    return _rows(value, field: 'players').map(_player).toList(growable: false);
  });

  @override
  Future<RepositoryResult<PlayerClaim>> submitClaim({
    required PlayerClaimId claimId,
    required PlayerId playerId,
  }) => _claimRpc('request_player_claim', <String, Object?>{
    'p_claim_id': claimId.value,
    'p_player_id': playerId.value,
  });

  @override
  Future<RepositoryResult<PlayerClaim>> cancelPendingClaim(
    PlayerClaimId claimId,
  ) => _claimRpc('cancel_player_claim', <String, Object?>{
    'p_claim_id': claimId.value,
  });

  @override
  Future<RepositoryResult<List<PlayerClaim>>> listPendingClaims() => _guard(
    () async {
      final value = await client.rpc<dynamic>('list_pending_player_claims');
      return _rows(value, field: 'claims').map(_claim).toList(growable: false);
    },
  );

  @override
  Future<RepositoryResult<PlayerClaim>> approveClaim(PlayerClaimId claimId) =>
      _claimRpc('approve_player_claim', <String, Object?>{
        'p_claim_id': claimId.value,
      });

  @override
  Future<RepositoryResult<PlayerClaim>> rejectClaim(
    PlayerClaimId claimId, {
    String? reason,
  }) => _claimRpc('reject_player_claim', <String, Object?>{
    'p_claim_id': claimId.value,
    'p_review_reason': reason?.trim(),
  });

  Future<RepositoryResult<PlayerClaim>> _claimRpc(
    String function,
    Map<String, Object?> params,
  ) => _guard(() async {
    final value = await client.rpc<dynamic>(function, params: params);
    return _claim(_map(value, field: 'claim'));
  });

  Future<RepositoryResult<T>> _guard<T>(Future<T> Function() operation) async {
    try {
      return RepositorySuccess(await operation());
    } on DomainFailure catch (failure) {
      return RepositoryFailure(failure);
    } on PostgrestException catch (error) {
      final authorization = error.code == '42501' || error.code == 'PGRST301';
      final conflict = error.code == '23505' || error.code == 'P0001';
      return RepositoryFailure(
        authorization
            ? const UnauthorizedFailure(
                message: 'This account is not authorized for that action.',
              )
            : conflict
            ? const ConflictFailure(
                message: 'The claim changed or is no longer available.',
              )
            : const PersistenceUnavailableFailure(
                message: 'Account and claim data is temporarily unavailable.',
              ),
      );
    } on Exception {
      return const RepositoryFailure(
        PersistenceUnavailableFailure(
          message: 'Account and claim data is temporarily unavailable.',
        ),
      );
    }
  }
}

AccountProfile _profile(Map<String, Object?> row) => AccountProfile(
  accountId: AccountId(_string(row, 'user_id')),
  displayName: _string(row, 'display_name'),
  playerId: row['player_id'] == null
      ? null
      : PlayerId(_string(row, 'player_id')),
  metadata: _metadata(row),
);

PermanentPlayer _player(Map<String, Object?> row) => PermanentPlayer(
  id: PlayerId(_string(row, 'id')),
  displayName: _string(row, 'display_name'),
  metadata: _metadata(row),
);

PlayerClaim _claim(Map<String, Object?> row) => PlayerClaim(
  id: PlayerClaimId(_string(row, 'id')),
  requestingAccountId: AccountId(_string(row, 'requesting_user_id')),
  playerId: PlayerId(_string(row, 'player_id')),
  status: _enum(PlayerClaimStatus.values, _string(row, 'status'), 'status'),
  requestedAt: _timestamp(row, 'requested_at')!,
  reviewedAt: _timestamp(row, 'reviewed_at'),
  reviewedBy: row['reviewed_by'] == null
      ? null
      : AccountId(_string(row, 'reviewed_by')),
  reviewReason: row['review_reason'] as String?,
  claimantDisplayName: row['claimant_display_name'] as String?,
  playerDisplayName: row['player_display_name'] as String?,
  metadata: _metadata(row),
);

AuthorizationState _authorization(Object? value) => switch (value) {
  'member' => AuthorizationState.member,
  'organizer' => AuthorizationState.organizer,
  _ => AuthorizationState.unavailable,
};

RecordMetadata _metadata(Map<String, Object?> row) => RecordMetadata(
  createdAt: _timestamp(row, 'created_at')!,
  updatedAt: _timestamp(row, 'updated_at')!,
  recordVersion: _integer(row, 'version'),
  deletedAt: _timestamp(row, 'deleted_at'),
);

Map<String, Object?> _map(Object? value, {required String field}) {
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw ValidationFailure(field: field, message: '$field data is invalid.');
}

List<Map<String, Object?>> _rows(Object? value, {required String field}) {
  if (value is List) {
    return value.map((row) => _map(row, field: field)).toList(growable: false);
  }
  throw ValidationFailure(field: field, message: '$field data is invalid.');
}

String _string(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw ValidationFailure(field: field, message: '$field must be text.');
}

int _integer(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value is int) {
    return value;
  }
  throw ValidationFailure(field: field, message: '$field must be an integer.');
}

DateTime? _timestamp(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value == null) {
    return null;
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null && RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value)) {
      return parsed.toUtc();
    }
  }
  throw ValidationFailure(field: field, message: '$field must be UTC time.');
}

T _enum<T extends Enum>(List<T> values, String name, String field) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  throw ValidationFailure(field: field, message: '$field is unsupported.');
}
