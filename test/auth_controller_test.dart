// Adjust the package name if your pubspec.yaml name is not "campuscare".
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:campuscare/controllers/auth_controller.dart';
import 'package:campuscare/core/errors/api_exception.dart';
import 'package:campuscare/routes/app_routes.dart';
import 'package:campuscare/services/auth_service.dart';
import 'package:campuscare/services/report_api_service.dart';

http.Response json(Object o, [int code = 200]) =>
    http.Response(jsonEncode(o), code, headers: {'content-type': 'application/json'});

Map<String, dynamic> profileJson({String role = 'student'}) =>
    {'id': 'u1', 'full_name': 'Test User', 'student_number': '240001', 'role': role};

class FakeBackend implements AuthBackend {
  String? uid;
  Object? signInError;
  Object? signOutError;
  final signInEmails = <String>[];
  var signOuts = 0;

  @override
  String? get currentUserId => uid;

  @override
  Future<String> signInWithPassword(String email, String password) async {
    signInEmails.add(email);
    final err = signInError;
    if (err != null) throw err;
    uid = 'u1';
    return 'u1';
  }

  @override
  Future<void> signOut() async {
    final err = signOutError;
    if (err != null) throw err;
    signOuts++;
    uid = null;
  }
}

({AuthController c, FakeBackend backend, List<String> routes}) setup(MockClientHandler h) {
  final backend = FakeBackend();
  final routes = <String>[];
  final api = ReportApiService(
    client: MockClient(h),
    baseUrl: 'https://test.supabase.co/rest/v1',
    apiKey: 'pk_test',
    getToken: () async => 'token-1',
  );
  final c = AuthController(AuthService(backend: backend, api: api), navigate: routes.add);
  return (c: c, backend: backend, routes: routes);
}

void main() {
  group('restore', () {
    test('no saved session -> login', () async {
      final t = setup((req) async => json([profileJson()]));
      await t.c.restore();
      expect(t.routes, [Routes.login]);
      expect(t.c.user.value, isNull);
      expect(t.c.isRestoring.value, false);
    });

    test('student session -> student home', () async {
      final t = setup((req) async => json([profileJson()]));
      t.backend.uid = 'u1';
      await t.c.restore();
      expect(t.routes, [Routes.studentHome]);
      expect(t.c.isAdmin, false);
    });

    test('admin session -> admin home', () async {
      final t = setup((req) async => json([profileJson(role: 'admin')]));
      t.backend.uid = 'u1';
      await t.c.restore();
      expect(t.routes, [Routes.adminHome]);
      expect(t.c.isAdmin, true);
    });

    test('expired session (401) -> login', () async {
      final t = setup((req) async => json({'message': 'JWT expired'}, 401));
      t.backend.uid = 'u1';
      await t.c.restore();
      expect(t.routes, [Routes.login]);
    });

    test('offline -> no navigation, no logout, message set, restoring finished', () async {
      final t = setup((req) async => throw http.ClientException('no network'));
      t.backend.uid = 'u1';
      await t.c.restore();
      expect(t.routes, isEmpty);
      expect(t.backend.uid, 'u1');
      expect(t.c.errorMessage.value, contains('No connection'));
      expect(t.c.isRestoring.value, false);
    });

    test('retry after offline succeeds and clears the error', () async {
      var offline = true;
      final t = setup((req) async {
        if (offline) throw http.ClientException('no network');
        return json([profileJson()]);
      });
      t.backend.uid = 'u1';
      await t.c.restore();
      offline = false;
      await t.c.restore();
      expect(t.c.errorMessage.value, '');
      expect(t.routes, [Routes.studentHome]);
    });
  });

  group('signIn', () {
    test('student -> true and student home', () async {
      final t = setup((req) async => json([profileJson()]));
      expect(await t.c.signIn('a@b.c', 'pw'), true);
      expect(t.routes, [Routes.studentHome]);
      expect(t.c.isLoading.value, false);
    });

    test('admin -> admin home', () async {
      final t = setup((req) async => json([profileJson(role: 'admin')]));
      await t.c.signIn('a@b.c', 'pw');
      expect(t.routes, [Routes.adminHome]);
    });

    test('wrong credentials -> false, message, no navigation', () async {
      final t = setup((req) async => json([profileJson()]));
      t.backend.signInError = const AuthFailure('Incorrect email or password.');
      expect(await t.c.signIn('a@b.c', 'bad'), false);
      expect(t.c.errorMessage.value, 'Incorrect email or password.');
      expect(t.routes, isEmpty);
      expect(t.c.isLoading.value, false);
    });

    test('invalid email is rejected before the backend', () async {
      final t = setup((req) async => json([profileJson()]));
      expect(await t.c.signIn('nope', 'pw'), false);
      expect(t.c.errorMessage.value, isNotEmpty);
      expect(t.backend.signInEmails, isEmpty);
    });

    test('double tap: second call is ignored while the first is running', () async {
      final t = setup((req) async => json([profileJson()]));
      final first = t.c.signIn('a@b.c', 'pw');
      final second = await t.c.signIn('a@b.c', 'pw');
      expect(second, false);
      expect(await first, true);
      expect(t.backend.signInEmails, hasLength(1));
    });

    test('profile lookup failure -> false, message, signed out again, no navigation', () async {
      final t = setup((req) async => json([]));
      expect(await t.c.signIn('a@b.c', 'pw'), false);
      expect(t.c.errorMessage.value, isNotEmpty);
      expect(t.backend.uid, isNull);
      expect(t.routes, isEmpty);
    });
  });

  group('signOut', () {
    test('success -> user cleared, back to login', () async {
      final t = setup((req) async => json([profileJson()]));
      await t.c.signIn('a@b.c', 'pw');
      t.routes.clear();
      await t.c.signOut();
      expect(t.c.user.value, isNull);
      expect(t.routes, [Routes.login]);
    });

    test('offline -> stays signed in, message set, no navigation', () async {
      final t = setup((req) async => json([profileJson()]));
      await t.c.signIn('a@b.c', 'pw');
      t.routes.clear();
      t.backend.signOutError = ApiException.network('no network');
      await t.c.signOut();
      expect(t.c.user.value, isNotNull);
      expect(t.routes, isEmpty);
      expect(t.c.errorMessage.value, contains('No connection'));
    });
  });
}
