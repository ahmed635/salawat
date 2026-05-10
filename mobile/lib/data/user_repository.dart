import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firestore_paths.dart';

class UserRepository {
  UserRepository(this._db, this._auth);
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  /// Creates or updates the user's profile doc. Called from the onboarding
  /// flow after the user picks their display name.
  Future<void> upsertProfile({required String displayName}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('upsertProfile called before sign-in completed');
    }
    await _db.doc(FirestorePaths.user(uid)).set({
      'displayName': displayName,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(FirebaseFirestore.instance, FirebaseAuth.instance);
});
