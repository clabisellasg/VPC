import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../application/accounts/auth_models.dart';
import '../../application/accounts/auth_repository.dart';
import '../../domain/common/domain_failure.dart';
import '../../domain/common/entity_id.dart';

final class GatewayAuthUser {
  const GatewayAuthUser({required this.id, required this.email});

  final String id;
  final String? email;
}

final class GatewayAuthResponse {
  const GatewayAuthResponse({required this.user, required this.hasSession});

  final GatewayAuthUser? user;
  final bool hasSession;
}

abstract interface class AuthGateway {
  GatewayAuthUser? get currentUser;

  Stream<GatewayAuthUser?> get authChanges;

  Future<GatewayAuthResponse> signUp({
    required String email,
    required String password,
    required String displayName,
    required String emailRedirectTo,
  });

  Future<GatewayAuthResponse> signIn({
    required String email,
    required String password,
  });

  Future<void> signOut();

  Future<GatewayAuthResponse> refreshCurrentUser();
}

final class OfficialSupabaseAuthGateway implements AuthGateway {
  const OfficialSupabaseAuthGateway(this.client);

  final SupabaseClient client;

  @override
  GatewayAuthUser? get currentUser => _mapUser(client.auth.currentUser);

  @override
  Stream<GatewayAuthUser?> get authChanges => client.auth.onAuthStateChange.map(
    (state) => _mapUser(state.session?.user),
  );

  @override
  Future<GatewayAuthResponse> signUp({
    required String email,
    required String password,
    required String displayName,
    required String emailRedirectTo,
  }) async {
    final response = await client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: emailRedirectTo,
      data: <String, Object?>{'display_name': displayName},
    );
    return GatewayAuthResponse(
      user: _mapUser(response.user),
      hasSession: response.session != null,
    );
  }

  @override
  Future<GatewayAuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return GatewayAuthResponse(
      user: _mapUser(response.user),
      hasSession: response.session != null,
    );
  }

  @override
  Future<void> signOut() => client.auth.signOut();

  @override
  Future<GatewayAuthResponse> refreshCurrentUser() async {
    final response = await client.auth.refreshSession();
    return GatewayAuthResponse(
      user: _mapUser(response.user),
      hasSession: response.session != null,
    );
  }

  GatewayAuthUser? _mapUser(User? user) =>
      user == null ? null : GatewayAuthUser(id: user.id, email: user.email);
}

final class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository(this.gateway);

  final AuthGateway gateway;

  @override
  AuthUser? get currentUser => _mapUser(gateway.currentUser);

  @override
  Stream<AuthSessionState> get sessionChanges => gateway.authChanges
      .map<AuthSessionState>(
        (user) => user == null
            ? const AuthSignedOut()
            : AuthAuthenticated(_requiredUser(user)),
      )
      .transform(
        StreamTransformer<AuthSessionState, AuthSessionState>.fromHandlers(
          handleError: (_, _, sink) => sink.add(
            const AuthRecoverableFailure(
              AuthFailure(
                AuthFailureKind.offline,
                'Account status is temporarily unavailable.',
              ),
            ),
          ),
        ),
      );

  @override
  Future<AuthResult> restoreSession() async {
    try {
      final user = currentUser;
      return AuthSucceeded(
        user == null ? const AuthSignedOut() : AuthAuthenticated(user),
      );
    } on DomainFailure {
      return const AuthFailed(
        AuthFailure(
          AuthFailureKind.unknown,
          'The saved account session is invalid.',
        ),
      );
    }
  }

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String displayName,
    required String emailRedirectTo,
  }) => _guard(() async {
    final response = await gateway.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      displayName: displayName.trim(),
      emailRedirectTo: emailRedirectTo,
    );
    if (!response.hasSession) {
      return AuthSucceeded(
        AuthAwaitingEmailConfirmation(email: email.trim().toLowerCase()),
      );
    }
    return AuthSucceeded(AuthAuthenticated(_requiredUser(response.user)));
  });

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) => _guard(() async {
    final response = await gateway.signIn(
      email: email.trim().toLowerCase(),
      password: password,
    );
    return AuthSucceeded(AuthAuthenticated(_requiredUser(response.user)));
  });

  @override
  Future<AuthResult> signOut() => _guard(() async {
    await gateway.signOut();
    return const AuthSucceeded(AuthSignedOut());
  });

  @override
  Future<AuthResult> refreshCurrentUser() => _guard(() async {
    final response = await gateway.refreshCurrentUser();
    if (!response.hasSession || response.user == null) {
      return const AuthSucceeded(AuthSignedOut());
    }
    return AuthSucceeded(AuthAuthenticated(_requiredUser(response.user)));
  });

  Future<AuthResult> _guard(Future<AuthResult> Function() operation) async {
    try {
      return await operation();
    } on AuthException catch (error) {
      return AuthFailed(_safeFailure(error));
    } on DomainFailure {
      return const AuthFailed(
        AuthFailure(AuthFailureKind.unknown, 'Account data was invalid.'),
      );
    } on Exception {
      return const AuthFailed(
        AuthFailure(
          AuthFailureKind.offline,
          'The account service is temporarily unavailable.',
        ),
      );
    }
  }

  AuthUser _requiredUser(GatewayAuthUser? value) {
    final user = _mapUser(value);
    if (user == null) {
      throw const ValidationFailure(
        field: 'authUser',
        message: 'Authenticated user data is incomplete.',
      );
    }
    return user;
  }

  AuthUser? _mapUser(GatewayAuthUser? value) {
    final email = value?.email?.trim();
    if (value == null || email == null || email.isEmpty) {
      return null;
    }
    return AuthUser(id: AccountId(value.id), email: email);
  }
}

AuthFailure _safeFailure(AuthException error) {
  final code = error.code?.toLowerCase();
  if (code == 'invalid_credentials' || code == 'email_not_confirmed') {
    return const AuthFailure(
      AuthFailureKind.invalidCredentials,
      'The email or password was not accepted.',
    );
  }
  if (code == 'user_already_exists' || code == 'email_exists') {
    return const AuthFailure(
      AuthFailureKind.duplicateAccount,
      'Registration could not be completed. Try signing in or use another email.',
    );
  }
  if (code == 'weak_password' || code == 'validation_failed') {
    return const AuthFailure(
      AuthFailureKind.invalidInput,
      'Check the account details and password requirements.',
    );
  }
  if (error.statusCode == '429') {
    return const AuthFailure(
      AuthFailureKind.rateLimited,
      'Too many attempts. Please wait before trying again.',
    );
  }
  if (code == 'otp_expired' || code == 'flow_state_expired') {
    return const AuthFailure(
      AuthFailureKind.expiredLink,
      'This confirmation link is invalid or expired.',
    );
  }
  return const AuthFailure(
    AuthFailureKind.offline,
    'The account service is temporarily unavailable.',
  );
}

final class UnconfiguredAuthRepository implements AuthRepository {
  const UnconfiguredAuthRepository();

  static const _failure = AuthFailure(
    AuthFailureKind.unconfigured,
    'Account services are not configured for this build.',
  );

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthSessionState> get sessionChanges => const Stream.empty();

  @override
  Future<AuthResult> restoreSession() async =>
      const AuthSucceeded(AuthUnconfigured());

  @override
  Future<AuthResult> refreshCurrentUser() async => const AuthFailed(_failure);

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async => const AuthFailed(_failure);

  @override
  Future<AuthResult> signOut() async => const AuthSucceeded(AuthSignedOut());

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String displayName,
    required String emailRedirectTo,
  }) async => const AuthFailed(_failure);
}
