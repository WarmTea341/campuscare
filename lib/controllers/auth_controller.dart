import 'package:get/get.dart';

import '../models/profile_model.dart';
import '../services/auth_service.dart';

/// The ONLY controller allowed to navigate (login / logout / session restore).
class AuthController extends GetxController {
  AuthController(this.auth);

  final AuthService auth;

  /// null = signed out.
  final Rxn<ProfileModel> user = Rxn<ProfileModel>();

  /// true until the first restore() finishes (show the splash while true).
  final RxBool isRestoring = true.obs;
  final RxBool isLoading = false.obs;

  /// '' = no error. Always a user-safe message.
  final RxString errorMessage = ''.obs;

  bool get isAdmin => user.value?.isAdmin ?? false;

  /// App start. Sets [user], then routes to login / student home / admin home.
  /// Offline: keeps the session and sets [errorMessage] (does NOT log out).
  Future<void> restore() async {
    // TODO(controllers owner): auth.restoreSession() -> route by role
  }

  /// true = signed in (navigation to the right home already happened).
  Future<bool> signIn(String email, String password) async {
    // TODO(controllers owner)
    return false;
  }

  Future<void> signOut() async {
    // TODO(controllers owner): auth.signOut(), clear user, route to login
  }
}
