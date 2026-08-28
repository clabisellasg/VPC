import '../../domain/common/entity_id.dart';

final class AuthUser {
  const AuthUser({required this.id, required this.email});

  final AccountId id;
  final String email;

  @override
  bool operator ==(Object other) =>
      other is AuthUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);
}

enum AuthFailureKind {
  invalidCredentials,
  duplicateAccount,
  invalidInput,
  offline,
  unconfigured,
  rateLimited,
  expiredLink,
  unknown,
}

final class AuthFailure {
  const AuthFailure(this.kind, this.safeMessage);

  final AuthFailureKind kind;
  final String safeMessage;
}

sealed class AuthSessionState {
  const AuthSessionState();
}

final class AuthRestoring extends AuthSessionState {
  const AuthRestoring();
}

final class AuthSignedOut extends AuthSessionState {
  const AuthSignedOut();
}

final class AuthAwaitingEmailConfirmation extends AuthSessionState {
  const AuthAwaitingEmailConfirmation({required this.email});

  final String email;
}

final class AuthAuthenticated extends AuthSessionState {
  const AuthAuthenticated(this.user);

  final AuthUser user;
}

final class AuthUnconfigured extends AuthSessionState {
  const AuthUnconfigured();
}

final class AuthRecoverableFailure extends AuthSessionState {
  const AuthRecoverableFailure(this.failure);

  final AuthFailure failure;
}

sealed class AuthResult {
  const AuthResult();
}

final class AuthSucceeded extends AuthResult {
  const AuthSucceeded(this.state);

  final AuthSessionState state;
}

final class AuthFailed extends AuthResult {
  const AuthFailed(this.failure);

  final AuthFailure failure;
}
