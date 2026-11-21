import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/api_exception.dart';
import 'auth_service.dart';

class SupabaseAuthBackend implements AuthBackend {
  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  String? get currentUserId => _auth.currentUser?.id;

  @override
  Future<String> signInWithPassword(String email, String password) async {
    try {
      final res = await _auth.signInWithPassword(email: email, password: password);
      final user = res.user;
      if (user == null) throw const AuthFailure('Sign-in failed. Please try again.');
      return user.id;
    } on AuthRetryableFetchException catch (e) {
      throw ApiException.network(e);
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid login credentials')) {
        throw const AuthFailure('Incorrect email or password.');
      }
      if (m.contains('email not confirmed')) {
        throw const AuthFailure('Your email is not confirmed yet.');
      }
      throw const AuthFailure('Sign-in failed. Please try again.');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on AuthRetryableFetchException catch (e) {
      throw ApiException.network(e);
    }
  }
}
