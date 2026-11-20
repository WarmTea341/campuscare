import '../core/errors/api_exception.dart';
import '../models/profile_model.dart';
import 'report_api_service.dart';

/// Login problem with a message that is safe to show to the user.
class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);

  @override
  String toString() => 'AuthFailure: $message';
}

/// Thin seam over the auth provider so AuthService can be unit-tested.
abstract class AuthBackend {
  String? get currentUserId;

  /// Returns the signed-in user's id. Throws [AuthFailure] / [ApiException].
  Future<String> signInWithPassword(String email, String password);

  Future<void> signOut();
}

class AuthService {
  final AuthBackend _backend;
  final ReportApiService _api;

  AuthService({required AuthBackend backend, required ReportApiService api})
      : _backend = backend,
        _api = api;

  Future<ProfileModel> signIn(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw const AuthFailure('Enter a valid email address.');
    }
    if (password.isEmpty) throw const AuthFailure('Enter your password.');

    final userId = await _backend.signInWithPassword(cleanEmail, password);
    try {
      return await _api.getProfile(userId);
    } catch (_) {
      await _safeSignOut(); // never leave a half-logged-in session (token but no role)
      rethrow;
    }
  }

  /// App start: returns the profile of the saved session, or null if there is none.
  /// A network failure is rethrown (do NOT log the user out just because they are offline).
  Future<ProfileModel?> restoreSession() async {
    final userId = _backend.currentUserId;
    if (userId == null) return null;
    try {
      return await _api.getProfile(userId);
    } on ApiException catch (e) {
      if (e.isSessionExpired || e.code == 'P0002') {
        await _safeSignOut();
        return null;
      }
      rethrow;
    }
  }

  Future<void> signOut() => _backend.signOut();

  Future<void> _safeSignOut() async {
    try {
      await _backend.signOut();
    } catch (_) {}
  }
}
