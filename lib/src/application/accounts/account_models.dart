import '../../domain/common/domain_failure.dart';
import '../../domain/common/domain_validation.dart';
import '../../domain/common/entity_id.dart';
import '../../domain/common/record_metadata.dart';

enum AccountRole { member, organizer }

enum AuthorizationState { guest, member, organizer, unavailable }

enum PlayerClaimStatus { pending, approved, rejected, cancelled }

final class AccountProfile {
  factory AccountProfile({
    required AccountId accountId,
    required String displayName,
    required RecordMetadata metadata,
    PlayerId? playerId,
  }) => AccountProfile._(
    accountId: accountId,
    displayName: requireNonBlank(displayName, field: 'displayName'),
    playerId: playerId,
    metadata: metadata,
  );

  const AccountProfile._({
    required this.accountId,
    required this.displayName,
    required this.playerId,
    required this.metadata,
  });

  final AccountId accountId;
  final String displayName;
  final PlayerId? playerId;
  final RecordMetadata metadata;
}

final class PlayerClaim {
  factory PlayerClaim({
    required PlayerClaimId id,
    required AccountId requestingAccountId,
    required PlayerId playerId,
    required PlayerClaimStatus status,
    required DateTime requestedAt,
    required RecordMetadata metadata,
    AccountId? reviewedBy,
    DateTime? reviewedAt,
    String? reviewReason,
    String? claimantDisplayName,
    String? playerDisplayName,
  }) {
    if (!requestedAt.isUtc || (reviewedAt != null && !reviewedAt.isUtc)) {
      throw const ValidationFailure(
        field: 'claimTimestamps',
        message: 'Claim timestamps must use UTC.',
      );
    }
    final reviewed =
        status == PlayerClaimStatus.approved ||
        status == PlayerClaimStatus.rejected;
    if (reviewed != (reviewedAt != null && reviewedBy != null)) {
      throw const ValidationFailure(
        field: 'claimReview',
        message: 'Reviewed claims require reviewer and review time.',
      );
    }
    return PlayerClaim._(
      id: id,
      requestingAccountId: requestingAccountId,
      playerId: playerId,
      status: status,
      requestedAt: requestedAt,
      reviewedAt: reviewedAt,
      reviewedBy: reviewedBy,
      reviewReason: _optionalText(reviewReason),
      claimantDisplayName: _optionalText(claimantDisplayName),
      playerDisplayName: _optionalText(playerDisplayName),
      metadata: metadata,
    );
  }

  const PlayerClaim._({
    required this.id,
    required this.requestingAccountId,
    required this.playerId,
    required this.status,
    required this.requestedAt,
    required this.reviewedAt,
    required this.reviewedBy,
    required this.reviewReason,
    required this.claimantDisplayName,
    required this.playerDisplayName,
    required this.metadata,
  });

  final PlayerClaimId id;
  final AccountId requestingAccountId;
  final PlayerId playerId;
  final PlayerClaimStatus status;
  final DateTime requestedAt;
  final DateTime? reviewedAt;
  final AccountId? reviewedBy;
  final String? reviewReason;
  final String? claimantDisplayName;
  final String? playerDisplayName;
  final RecordMetadata metadata;
}

String? _optionalText(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

final class AccountSnapshot {
  const AccountSnapshot({
    required this.profile,
    required this.authorization,
    required this.claim,
  });

  final AccountProfile profile;
  final AuthorizationState authorization;
  final PlayerClaim? claim;
}
