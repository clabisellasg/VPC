import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/accounts/account_models.dart';
import 'package:vpc/src/domain/common/domain_failure.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';

void main() {
  final metadata = RecordMetadata(
    createdAt: DateTime.utc(2026, 8, 28),
    updatedAt: DateTime.utc(2026, 8, 28),
    recordVersion: 0,
  );
  final accountId = AccountId('a1000000-0000-4000-8000-000000000001');
  final playerId = PlayerId('a2000000-0000-4000-8000-000000000001');
  final claimId = PlayerClaimId('a3000000-0000-4000-8000-000000000001');

  test('profile keeps private account and player identities typed', () {
    final profile = AccountProfile(
      accountId: accountId,
      displayName: 'Sample Member',
      playerId: playerId,
      metadata: metadata,
    );
    expect(profile.accountId, accountId);
    expect(profile.playerId, playerId);
  });

  test('claim supports only the approved auditable states', () {
    for (final status in PlayerClaimStatus.values) {
      final reviewed =
          status == PlayerClaimStatus.approved ||
          status == PlayerClaimStatus.rejected;
      final claim = PlayerClaim(
        id: claimId,
        requestingAccountId: accountId,
        playerId: playerId,
        status: status,
        requestedAt: DateTime.utc(2026, 8, 28),
        reviewedAt: reviewed ? DateTime.utc(2026, 8, 29) : null,
        reviewedBy: reviewed
            ? AccountId('a1000000-0000-4000-8000-000000000002')
            : null,
        metadata: metadata,
      );
      expect(claim.status, status);
    }
    expect(PlayerClaimStatus.values.map((value) => value.name), [
      'pending',
      'approved',
      'rejected',
      'cancelled',
    ]);
  });

  test('claim timestamps and review fields must be consistent', () {
    expect(
      () => PlayerClaim(
        id: claimId,
        requestingAccountId: accountId,
        playerId: playerId,
        status: PlayerClaimStatus.approved,
        requestedAt: DateTime.utc(2026, 8, 28),
        metadata: metadata,
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => PlayerClaim(
        id: claimId,
        requestingAccountId: accountId,
        playerId: playerId,
        status: PlayerClaimStatus.pending,
        requestedAt: DateTime(2026, 8, 28),
        metadata: metadata,
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });
}
