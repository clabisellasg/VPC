import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpc/src/app/app.dart';
import 'package:vpc/src/application/accounts/account_models.dart';
import 'package:vpc/src/application/accounts/auth_models.dart';
import 'package:vpc/src/application/accounts/auth_repository.dart';
import 'package:vpc/src/application/accounts/player_claim_repository.dart';
import 'package:vpc/src/core/config/app_environment.dart';
import 'package:vpc/src/domain/common/entity_id.dart';
import 'package:vpc/src/domain/common/record_metadata.dart';
import 'package:vpc/src/domain/common/repository_result.dart';
import 'package:vpc/src/domain/players/permanent_player.dart';
import 'package:vpc/src/infrastructure/accounts/account_providers.dart';
import 'package:vpc/src/infrastructure/persistence/local/local_persistence_providers.dart';

void main() {
  testWidgets('guest keeps M6 access and can open sign-in or registration', (
    tester,
  ) async {
    final app = await _pump(
      tester,
      auth: _FakeAuthRepository(const AuthSignedOut()),
      claims: _FakeClaimRepository(_memberSnapshot()),
    );
    expect(find.text('Browse events'), findsOneWidget);
    app.router.go('/account');
    await tester.pumpAndSettle();
    expect(find.text('No account required for public events'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsWidgets);
    expect(find.byTooltip('Show password'), findsOneWidget);
  });

  testWidgets('registration validates fields and shows confirmation state', (
    tester,
  ) async {
    final auth = _FakeAuthRepository(const AuthSignedOut());
    final app = await _pump(
      tester,
      auth: auth,
      claims: _FakeClaimRepository(_memberSnapshot()),
    );
    app.router.go('/account/register');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();
    expect(find.textContaining('display name between'), findsOneWidget);
    expect(find.text('Enter a valid email address.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Display name'),
      'Sample Member',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'member@example.invalid',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'example-password',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'example-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Check your email'), findsOneWidget);
    expect(auth.signUpCalls, 1);
  });

  testWidgets('signed-in member sees private profile and claim flow', (
    tester,
  ) async {
    final claims = _FakeClaimRepository(_memberSnapshot());
    final app = await _pump(
      tester,
      auth: _FakeAuthRepository(_authenticated()),
      claims: claims,
    );
    app.router.go('/account');
    await tester.pumpAndSettle();
    expect(find.text('Sample Member'), findsOneWidget);
    expect(find.text('Member'), findsOneWidget);
    expect(find.text('member@example.invalid'), findsOneWidget);

    await tester.tap(find.text('Claim an existing player'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchBar), 'Fixture');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('M7 Synthetic Claim Player'), findsOneWidget);
    expect(claims.searchCalls, 1);
  });

  testWidgets('protected organizer route does not flash content to a guest', (
    tester,
  ) async {
    final app = await _pump(
      tester,
      auth: _FakeAuthRepository(const AuthSignedOut()),
      claims: _FakeClaimRepository(_memberSnapshot()),
    );
    app.router.go('/organizer/claims');
    await tester.pumpAndSettle();
    expect(find.text('Player claims'), findsNothing);
    expect(find.text('Sign in'), findsWidgets);
  });

  testWidgets(
    'organizer can review a pending claim through overrideable ports',
    (tester) async {
      final claims = _FakeClaimRepository(_organizerSnapshot());
      final app = await _pump(
        tester,
        auth: _FakeAuthRepository(_authenticated()),
        claims: claims,
      );
      app.router.go('/organizer/claims');
      await tester.pumpAndSettle();
      expect(find.text('M7 Synthetic Claim Player'), findsOneWidget);
      expect(find.text('Requested by Sample Member'), findsOneWidget);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve link'));
      await tester.pumpAndSettle();
      expect(claims.approveCalls, 1);
    },
  );

  testWidgets(
    'unconfigured account state is honest and initializes no SQLite',
    (tester) async {
      var databaseFactoryCalls = 0;
      final app = VpcApp(environment: AppEnvironment.test);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localPersistencePlatformProvider.overrideWithValue(
              LocalPersistencePlatform.web,
            ),
            localDatabaseFactoryProvider.overrideWithValue((_) {
              databaseFactoryCalls++;
              return null;
            }),
          ],
          child: app,
        ),
      );
      app.router.go('/account');
      await tester.pumpAndSettle();
      expect(find.text('Account services are not configured'), findsOneWidget);
      expect(databaseFactoryCalls, 1);
    },
  );
}

Future<VpcApp> _pump(
  WidgetTester tester, {
  required AuthRepository auth,
  required PlayerClaimRepository claims,
}) async {
  final app = VpcApp(environment: AppEnvironment.test);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localPersistencePlatformProvider.overrideWithValue(
          LocalPersistencePlatform.web,
        ),
        authRepositoryProvider.overrideWithValue(auth),
        playerClaimRepositoryProvider.overrideWithValue(claims),
      ],
      child: app,
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

AuthAuthenticated _authenticated() => AuthAuthenticated(
  AuthUser(
    id: AccountId('a1000000-0000-4000-8000-000000000001'),
    email: 'member@example.invalid',
  ),
);

final class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this.initial);

  AuthSessionState initial;
  final changes = StreamController<AuthSessionState>.broadcast();
  int signUpCalls = 0;

  @override
  AuthUser? get currentUser =>
      initial is AuthAuthenticated ? (initial as AuthAuthenticated).user : null;

  @override
  Stream<AuthSessionState> get sessionChanges => changes.stream;

  @override
  Future<AuthResult> refreshCurrentUser() async => AuthSucceeded(initial);

  @override
  Future<AuthResult> restoreSession() async => AuthSucceeded(initial);

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    initial = _authenticated();
    return AuthSucceeded(initial);
  }

  @override
  Future<AuthResult> signOut() async {
    initial = const AuthSignedOut();
    return AuthSucceeded(initial);
  }

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String displayName,
    required String emailRedirectTo,
  }) async {
    signUpCalls++;
    initial = AuthAwaitingEmailConfirmation(email: email);
    return AuthSucceeded(initial);
  }
}

final class _FakeClaimRepository implements PlayerClaimRepository {
  _FakeClaimRepository(this.snapshot);

  AccountSnapshot snapshot;
  int searchCalls = 0;
  int approveCalls = 0;

  @override
  Future<RepositoryResult<AccountSnapshot>> loadCurrentAccount() async =>
      RepositorySuccess(snapshot);

  @override
  Future<RepositoryResult<List<PermanentPlayer>>> searchEligiblePlayers(
    String query,
  ) async {
    searchCalls++;
    return RepositorySuccess([_player()]);
  }

  @override
  Future<RepositoryResult<List<PlayerClaim>>> listPendingClaims() async =>
      RepositorySuccess([_pendingClaim()]);

  @override
  Future<RepositoryResult<PlayerClaim>> approveClaim(
    PlayerClaimId claimId,
  ) async {
    approveCalls++;
    return RepositorySuccess(_reviewedClaim(PlayerClaimStatus.approved));
  }

  @override
  Future<RepositoryResult<PlayerClaim>> rejectClaim(
    PlayerClaimId claimId, {
    String? reason,
  }) async => RepositorySuccess(_reviewedClaim(PlayerClaimStatus.rejected));

  @override
  Future<RepositoryResult<PlayerClaim>> cancelPendingClaim(
    PlayerClaimId claimId,
  ) async => RepositorySuccess(_cancelledClaim());

  @override
  Future<RepositoryResult<PlayerClaim>> submitClaim({
    required PlayerClaimId claimId,
    required PlayerId playerId,
  }) async => RepositorySuccess(_pendingClaim());
}

RecordMetadata _metadata() => RecordMetadata(
  createdAt: DateTime.utc(2026, 8, 28),
  updatedAt: DateTime.utc(2026, 8, 28),
  recordVersion: 0,
);

PermanentPlayer _player() => PermanentPlayer(
  id: PlayerId('a2000000-0000-4000-8000-000000000001'),
  displayName: 'M7 Synthetic Claim Player',
  metadata: _metadata(),
);

PlayerClaim _pendingClaim() => PlayerClaim(
  id: PlayerClaimId('a3000000-0000-4000-8000-000000000001'),
  requestingAccountId: AccountId('a1000000-0000-4000-8000-000000000001'),
  playerId: _player().id,
  status: PlayerClaimStatus.pending,
  requestedAt: DateTime.utc(2026, 8, 28),
  claimantDisplayName: 'Sample Member',
  playerDisplayName: _player().displayName,
  metadata: _metadata(),
);

PlayerClaim _cancelledClaim() => PlayerClaim(
  id: _pendingClaim().id,
  requestingAccountId: _pendingClaim().requestingAccountId,
  playerId: _player().id,
  status: PlayerClaimStatus.cancelled,
  requestedAt: DateTime.utc(2026, 8, 28),
  metadata: _metadata(),
);

PlayerClaim _reviewedClaim(PlayerClaimStatus status) => PlayerClaim(
  id: _pendingClaim().id,
  requestingAccountId: _pendingClaim().requestingAccountId,
  playerId: _player().id,
  status: status,
  requestedAt: DateTime.utc(2026, 8, 28),
  reviewedAt: DateTime.utc(2026, 8, 29),
  reviewedBy: AccountId('a1000000-0000-4000-8000-000000000002'),
  metadata: _metadata(),
);

AccountSnapshot _memberSnapshot() => AccountSnapshot(
  profile: AccountProfile(
    accountId: AccountId('a1000000-0000-4000-8000-000000000001'),
    displayName: 'Sample Member',
    metadata: _metadata(),
  ),
  authorization: AuthorizationState.member,
  claim: null,
);

AccountSnapshot _organizerSnapshot() => AccountSnapshot(
  profile: AccountProfile(
    accountId: AccountId('a1000000-0000-4000-8000-000000000002'),
    displayName: 'Sample Organizer',
    metadata: _metadata(),
  ),
  authorization: AuthorizationState.organizer,
  claim: null,
);
