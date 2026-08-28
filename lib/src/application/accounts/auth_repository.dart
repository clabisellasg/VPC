import 'auth_models.dart';

abstract interface class AuthRepository {
  AuthUser? get currentUser;

  Stream<AuthSessionState> get sessionChanges;

  Future<AuthResult> restoreSession();

  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String displayName,
    required String emailRedirectTo,
  });

  Future<AuthResult> signIn({required String email, required String password});

  Future<AuthResult> signOut();

  Future<AuthResult> refreshCurrentUser();
}
