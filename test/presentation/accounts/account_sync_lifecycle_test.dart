import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/application/accounts/account_models.dart';
import 'package:vpc/src/application/accounts/auth_models.dart';
import 'package:vpc/src/application/accounts/auth_repository.dart';
import 'package:vpc/src/application/accounts/player_claim_repository.dart';
import 'package:vpc/src/application/sync/sync_contracts.dart';
import 'package:vpc/src/application/sync/sync_models.dart';
import 'package:vpc/src/application/sync/sync_runtime.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/players/permanent_player.dart';
import 'package:vpc/src/infrastructure/accounts/account_providers.dart';
import 'package:vpc/src/infrastructure/sync/sync_providers.dart';
import 'package:vpc/src/presentation/accounts/account_controller.dart';
import 'package:vpc/src/presentation/accounts/auth_controller.dart';

void main() {
  test(
    'server-confirmed organizer starts M5 sync and sign-out disposes it',
    () async {
      final auth = _AuthFake();
      final coordinator = _CoordinatorFake();
      final runtime = SyncRuntime(coordinator: coordinator);
      var runtimeCreations = 0;
      var runtimeDisposals = 0;
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          playerClaimRepositoryProvider.overrideWithValue(
            _ClaimsFake(AuthorizationState.organizer),
          ),
          syncRuntimeProvider.overrideWith((ref) {
            runtimeCreations++;
            ref.onDispose(() {
              runtimeDisposals++;
              unawaited(runtime.dispose());
            });
            return runtime;
          }),
        ],
      );
      addTearDown(container.dispose);
      final authSubscription = container.listen(
        authControllerProvider,
        (_, _) {},
        fireImmediately: true,
      );
      final accountSubscription = container.listen(
        accountControllerProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(authSubscription.close);
      addTearDown(accountSubscription.close);
      await _flush();

      expect(runtimeCreations, 1);
      expect(coordinator.runs, 1);
      await container.read(authControllerProvider.notifier).signOut();
      await _flush();
      expect(
        container.read(accountControllerProvider).phase,
        AccountPhase.guest,
      );
      expect(runtimeDisposals, 1);
      expect(coordinator.disposals, 1);
    },
  );

  test('ordinary member never starts organizer synchronization', () async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_AuthFake()),
        playerClaimRepositoryProvider.overrideWithValue(
          _ClaimsFake(AuthorizationState.member),
        ),
        syncRuntimeProvider.overrideWith((ref) {
          fail('Member state must not create an organizer sync runtime.');
        }),
      ],
    );
    addTearDown(container.dispose);
    final authSubscription = container.listen(
      authControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    final accountSubscription = container.listen(
      accountControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(authSubscription.close);
    addTearDown(accountSubscription.close);
    await _flush();
    expect(
      container.read(accountControllerProvider).snapshot?.authorization,
      AuthorizationState.member,
    );
  });
}

Future<void> _flush() async {
  for (var index = 0; index < 12; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _CoordinatorFake implements SyncCoordinator {
  int runs = 0;
  int disposals = 0;

  @override
  Future<void> dispose() async => disposals++;

  @override
  Future<SyncReport> synchronize() async {
    runs++;
    return const SyncReport(status: SyncRunStatus.completed);
  }
}

final class _AuthFake implements AuthRepository {
  AuthSessionState state = AuthAuthenticated(
    AuthUser(
      id: AccountId('a1000000-0000-4000-8000-000000000001'),
      email: 'member@example.invalid',
    ),
  );

  @override
  AuthUser? get currentUser => (state as AuthAuthenticated).user;

  @override
  Stream<AuthSessionState> get sessionChanges => const Stream.empty();

  @override
  Future<AuthResult> restoreSession() async => AuthSucceeded(state);

  @override
  Future<AuthResult> signOut() async {
    state = const AuthSignedOut();
    return AuthSucceeded(state);
  }

  @override
  Future<AuthResult> refreshCurrentUser() async => AuthSucceeded(state);

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async => AuthSucceeded(state);

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String displayName,
    required String emailRedirectTo,
  }) async => AuthSucceeded(state);
}

final class _ClaimsFake implements PlayerClaimRepository {
  _ClaimsFake(this.authorization);

  final AuthorizationState authorization;

  @override
  Future<RepositoryResult<AccountSnapshot>> loadCurrentAccount() async =>
      RepositorySuccess(
        AccountSnapshot(
          profile: AccountProfile(
            accountId: AccountId('a1000000-0000-4000-8000-000000000001'),
            displayName: 'Sample Member',
            metadata: RecordMetadata(
              createdAt: DateTime.utc(2026, 8, 28),
              updatedAt: DateTime.utc(2026, 8, 28),
              recordVersion: 0,
            ),
          ),
          authorization: authorization,
          claim: null,
        ),
      );

  @override
  Future<RepositoryResult<PlayerClaim>> approveClaim(PlayerClaimId claimId) =>
      throw UnimplementedError();

  @override
  Future<RepositoryResult<PlayerClaim>> cancelPendingClaim(
    PlayerClaimId claimId,
  ) => throw UnimplementedError();

  @override
  Future<RepositoryResult<List<PlayerClaim>>> listPendingClaims() =>
      throw UnimplementedError();

  @override
  Future<RepositoryResult<PlayerClaim>> rejectClaim(
    PlayerClaimId claimId, {
    String? reason,
  }) => throw UnimplementedError();

  @override
  Future<RepositoryResult<List<PermanentPlayer>>> searchEligiblePlayers(
    String query,
  ) => throw UnimplementedError();

  @override
  Future<RepositoryResult<PlayerClaim>> submitClaim({
    required PlayerClaimId claimId,
    required PlayerId playerId,
  }) => throw UnimplementedError();
}
