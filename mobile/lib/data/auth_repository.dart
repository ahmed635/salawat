import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthRepository {
  AuthRepository(this._auth);
  final FirebaseAuth _auth;

  /// Returns the current user, signing in anonymously if there is none.
  /// Idempotent — safe to call on every app start.
  Future<User> ensureSignedIn() async {
    // [currentUser] is synchronous and can briefly return null at app
    // startup before the SDK has finished hydrating the persisted user
    // from disk. If we trusted that, we'd fall through to
    // signInAnonymously() on every launch and burn a fresh UID — leaving
    // a trail of orphan users/{uid} docs each carrying the user's
    // displayName. authStateChanges() emits the hydrated state as its
    // first event, so we wait on that when currentUser is null.
    var user = _auth.currentUser;
    user ??= await _auth.authStateChanges().first;
    if (user != null) return user;
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
