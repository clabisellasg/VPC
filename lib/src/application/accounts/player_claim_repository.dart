import '../../domain/common/entity_id.dart';
import '../../domain/common/repository_result.dart';
import '../../domain/players/permanent_player.dart';
import 'account_models.dart';

abstract interface class PlayerClaimRepository {
  Future<RepositoryResult<AccountSnapshot>> loadCurrentAccount();

  Future<RepositoryResult<List<PermanentPlayer>>> searchEligiblePlayers(
    String query,
  );

  Future<RepositoryResult<PlayerClaim>> submitClaim({
    required PlayerClaimId claimId,
    required PlayerId playerId,
  });

  Future<RepositoryResult<PlayerClaim>> cancelPendingClaim(
    PlayerClaimId claimId,
  );

  Future<RepositoryResult<List<PlayerClaim>>> listPendingClaims();

  Future<RepositoryResult<PlayerClaim>> approveClaim(PlayerClaimId claimId);

  Future<RepositoryResult<PlayerClaim>> rejectClaim(
    PlayerClaimId claimId, {
    String? reason,
  });
}
