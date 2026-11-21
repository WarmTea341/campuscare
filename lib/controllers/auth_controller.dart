import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/errors/api_exception.dart';
import '../models/profile_model.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';

/// The ONLY controller allowed to navigate (login / logout / session restore).
class AuthController extends GetxController {
  /// [navigate] is injectable so the navigation rule can be unit-tested.
  AuthController(this.auth, {void Function(String route)? navigate})
      : _navigate = navigate ??
            ((route) {
              Get.offAllNamed(route);
            });

  final AuthService auth;
  final void Function(String route) _navigate;

  /// null = signed out.
  final Rxn<ProfileModel> user = Rxn<ProfileModel>();

  /// true until restore() finishes. Splash: spinner while true; if false and
  /// [errorMessage] is not empty, show the message + a retry button calling restore().
  final RxBool isRestoring = true.obs;
  final RxBool isLoading = false.obs;

  /// '' = no error. Always a user-safe message.
  final RxString errorMessage = ''.obs;

  static const _unexpected = 'Something went wrong. Please try again.';

  bool get isAdmin => user.value?.isAdmin ?? false;

  String _homeFor(ProfileModel p) => p.isAdmin ? Routes.adminHome : Routes.studentHome;

  /// App start (called once after the first frame, and by the splash retry button).
  /// Offline / server error: no navigation, no logout, [errorMessage] is set.
  Future<void> restore() async {
    isRestoring.value = true;
    errorMessage.value = '';
    try {
      final profile = await auth.restoreSession();
      user.value = profile;
      _navigate(profile == null ? Routes.login : _homeFor(profile));
    } on ApiException catch (e) {
      errorMessage.value = e.userMessage;
    } catch (e) {
      debugPrint('restore failed: $e');
      errorMessage.value = _unexpected;
    } finally {
      isRestoring.value = false;
    }
  }

  /// true = signed in (navigation to the right home already happened).
  Future<bool> signIn(String email, String password) async {
    if (isLoading.value) return false; // double tap
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final profile = await auth.signIn(email, password);
      user.value = profile;
      _navigate(_homeFor(profile));
      return true;
    } on AuthFailure catch (e) {
      errorMessage.value = e.message;
    } on ApiException catch (e) {
      errorMessage.value = e.userMessage;
    } catch (e) {
      debugPrint('signIn failed: $e');
      errorMessage.value = _unexpected;
    } finally {
      isLoading.value = false;
    }
    return false;
  }

  /// If the server call fails (offline) the session is still alive, so we do NOT
  /// pretend to log out: [errorMessage] is set and nothing navigates.
  Future<void> signOut() async {
    errorMessage.value = '';
    try {
      await auth.signOut();
      user.value = null;
      _navigate(Routes.login);
    } on ApiException catch (e) {
      errorMessage.value = e.userMessage;
    } catch (e) {
      debugPrint('signOut failed: $e');
      errorMessage.value = _unexpected;
    }
  }
}
