import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vpc/src/application/accounts/auth_models.dart';
import 'package:vpc/src/infrastructure/accounts/supabase_auth_repository.dart';

void main() {
  const user = GatewayAuthUser(
    id: 'a1000000-0000-4000-8000-000000000001',
    email: 'member@example.invalid',
  );

  test('restores signed-out and persisted authenticated sessions', () async {
    final signedOut = SupabaseAuthRepository(_FakeGateway());
    expect(
      (await signedOut.restoreSession() as AuthSucceeded).state,
      isA<AuthSignedOut>(),
    );

    final restored = SupabaseAuthRepository(_FakeGateway(current: user));
    final state = (await restored.restoreSession() as AuthSucceeded).state;
    expect(state, isA<AuthAuthenticated>());
    expect((state as AuthAuthenticated).user.email, 'member@example.invalid');
  });

  test('maps registration with and without email confirmation', () async {
    final confirmation = SupabaseAuthRepository(
      _FakeGateway(
        signUpResponse: const GatewayAuthResponse(
          user: user,
          hasSession: false,
        ),
      ),
    );
    final waiting = await confirmation.signUp(
      email: 'MEMBER@example.invalid',
      password: 'not-a-real-password',
      displayName: 'Member',
      emailRedirectTo:
          'com.voltapaddleclub.vpc://auth-callback/account/confirm',
    );
    expect(
      (waiting as AuthSucceeded).state,
      isA<AuthAwaitingEmailConfirmation>(),
    );

    final immediate = SupabaseAuthRepository(
      _FakeGateway(
        signUpResponse: const GatewayAuthResponse(user: user, hasSession: true),
      ),
    );
    expect(
      (await immediate.signUp(
        email: user.email!,
        password: 'not-a-real-password',
        displayName: 'Member',
        emailRedirectTo: 'https://example.invalid/account/confirm',
      ) as AuthSucceeded).state,
      isA<AuthAuthenticated>(),
    );
  });

  test('sign in, state changes, refresh, and sign out map safely', () async {
    final gateway = _FakeGateway(
      signInResponse: const GatewayAuthResponse(user: user, hasSession: true),
      refreshResponse: const GatewayAuthResponse(user: user, hasSession: true),
    );
    final repository = SupabaseAuthRepository(gateway);
    expect(
      (await repository.signIn(
        email: user.email!,
        password: 'not-a-real-password',
      ) as AuthSucceeded).state,
      isA<AuthAuthenticated>(),
    );
    final next = repository.sessionChanges.first;
    gateway.emit(user);
    expect(await next, isA<AuthAuthenticated>());
    expect(
      (await repository.refreshCurrentUser() as AuthSucceeded).state,
      isA<AuthAuthenticated>(),
    );
    expect(
      (await repository.signOut() as AuthSucceeded).state,
      isA<AuthSignedOut>(),
    );
    expect(gateway.signOutCalls, 1);
  });

  test(
    'typed failures are redacted and never contain credentials or tokens',
    () async {
      final repository = SupabaseAuthRepository(
        _FakeGateway(
          error: const AuthApiException(
            'invalid login for secret@example.invalid token=do-not-show',
            statusCode: '400',
            code: 'invalid_credentials',
          ),
        ),
      );
      final result = await repository.signIn(
        email: 'secret@example.invalid',
        password: 'do-not-show',
      );
      final failure = (result as AuthFailed).failure;
      expect(failure.kind, AuthFailureKind.invalidCredentials);
      expect(failure.safeMessage, isNot(contains('secret@example.invalid')));
      expect(failure.safeMessage, isNot(contains('do-not-show')));
      expect(failure.safeMessage, isNot(contains('token')));
    },
  );

  test('unconfigured repository is valid for public builds', () async {
    const repository = UnconfiguredAuthRepository();
    expect(
      (await repository.restoreSession() as AuthSucceeded).state,
      isA<AuthUnconfigured>(),
    );
    expect(
      (await repository.signIn(
        email: 'x@example.invalid',
        password: 'hidden',
      ) as AuthFailed).failure.kind,
      AuthFailureKind.unconfigured,
    );
  });
}

final class _FakeGateway implements AuthGateway {
  _FakeGateway({
    this.current,
    this.signUpResponse,
    this.signInResponse,
    this.refreshResponse,
    this.error,
  });

  GatewayAuthUser? current;
  final GatewayAuthResponse? signUpResponse;
  final GatewayAuthResponse? signInResponse;
  final GatewayAuthResponse? refreshResponse;
  final AuthException? error;
  final _changes = StreamController<GatewayAuthUser?>.broadcast();
  int signOutCalls = 0;

  void emit(GatewayAuthUser? user) => _changes.add(user);

  @override
  Stream<GatewayAuthUser?> get authChanges => _changes.stream;

  @override
  GatewayAuthUser? get currentUser => current;

  Never _throw() => throw error!;

  @override
  Future<GatewayAuthResponse> refreshCurrentUser() async =>
      error == null ? refreshResponse! : _throw();

  @override
  Future<GatewayAuthResponse> signIn({
    required String email,
    required String password,
  }) async => error == null ? signInResponse! : _throw();

  @override
  Future<void> signOut() async {
    if (error != null) {
      _throw();
    }
    signOutCalls++;
    current = null;
  }

  @override
  Future<GatewayAuthResponse> signUp({
    required String email,
    required String password,
    required String displayName,
    required String emailRedirectTo,
  }) async => error == null ? signUpResponse! : _throw();
}
