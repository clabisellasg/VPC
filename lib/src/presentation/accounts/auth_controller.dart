import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/accounts/auth_models.dart';
import '../../application/accounts/auth_repository.dart';
import '../../infrastructure/accounts/account_providers.dart';

final class AuthViewState {
  const AuthViewState({
    required this.session,
    this.isSubmitting = false,
    this.message,
  });

  const AuthViewState.restoring() : this(session: const AuthRestoring());

  final AuthSessionState session;
  final bool isSubmitting;
  final String? message;

  AuthViewState copyWith({
    AuthSessionState? session,
    bool? isSubmitting,
    String? message,
    bool clearMessage = false,
  }) => AuthViewState(
    session: session ?? this.session,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    message: clearMessage ? null : message ?? this.message,
  );
}

final authControllerProvider = NotifierProvider<AuthController, AuthViewState>(
  AuthController.new,
);

final class AuthController extends Notifier<AuthViewState> {
  StreamSubscription<AuthSessionState>? _subscription;
  bool _disposed = false;

  @override
  AuthViewState build() {
    final repository = ref.watch(authRepositoryProvider);
    _disposed = false;
    _subscription?.cancel();
    _subscription = repository.sessionChanges.listen(
      (session) {
        if (!_disposed) {
          state = AuthViewState(session: session);
        }
      },
      onError: (_) {
        if (!_disposed) {
          state = const AuthViewState(
            session: AuthRecoverableFailure(
              AuthFailure(
                AuthFailureKind.offline,
                'Account status is temporarily unavailable.',
              ),
            ),
          );
        }
      },
    );
    ref.onDispose(() {
      _disposed = true;
      unawaited(_subscription?.cancel());
    });
    unawaited(_restore(repository));
    return const AuthViewState.restoring();
  }

  Future<void> _restore(AuthRepository repository) async {
    final result = await repository.restoreSession();
    if (!_disposed) {
      _apply(result);
    }
  }

  Future<bool> signIn({required String email, required String password}) =>
      _submit(
        () => ref
            .read(authRepositoryProvider)
            .signIn(email: email, password: password),
      );

  Future<bool> register({
    required String email,
    required String password,
    required String displayName,
  }) => _submit(
    () => ref
        .read(authRepositoryProvider)
        .signUp(
          email: email,
          password: password,
          displayName: displayName,
          emailRedirectTo: ref.read(authRedirectProvider),
        ),
  );

  Future<void> signOut() async {
    await _submit(() => ref.read(authRepositoryProvider).signOut());
  }

  Future<bool> refreshUser() =>
      _submit(() => ref.read(authRepositoryProvider).refreshCurrentUser());

  Future<bool> _submit(Future<AuthResult> Function() operation) async {
    if (state.isSubmitting) {
      return false;
    }
    state = state.copyWith(isSubmitting: true, clearMessage: true);
    final result = await operation();
    if (_disposed) {
      return false;
    }
    return _apply(result);
  }

  bool _apply(AuthResult result) {
    switch (result) {
      case AuthSucceeded(state: final session):
        state = AuthViewState(session: session);
        return true;
      case AuthFailed(:final failure):
        state = state.copyWith(
          isSubmitting: false,
          message: failure.safeMessage,
        );
        return false;
    }
  }
}
