import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthRepository {
  AuthRepository(this._auth);
  final FirebaseAuth _auth;

  /// Returns the current user, signing in anonymously if there is none.
  /// Idempotent — safe to call on every app start.
  Future<User> ensureSignedIn() async {
    final existing = _auth.currentUser;
    if (existing != null) return existing;
    final credential = await _auth.signInAnonymously();
    return credential.user!;
  }

  Stream<User?> authStateChanges() => _auth.authStateChanges();
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(FirebaseAuth.instance);
});

/// Reactive current user. Watched by the rest of the app to wait for auth.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Triggers anonymous sign-in once at startup. Watched in app.dart so the
/// rest of the tree can rely on a User being present.
final ensureSignedInProvider = FutureProvider<User>((ref) {
  return ref.watch(authRepositoryProvider).ensureSignedIn();
});
