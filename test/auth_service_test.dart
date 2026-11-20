// Adjust the package name if your pubspec.yaml name is not "campuscare".
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:campuscare/core/errors/api_exception.dart';
import 'package:campuscare/models/profile_model.dart';
import 'package:campuscare/services/auth_service.dart';
import 'package:campuscare/services/report_api_service.dart';

http.Response json(Object o, [int code = 200]) =>
    http.Response(jsonEncode(o), code, headers: {'content-type': 'application/json'});

Map<String, dynamic> profileJson({String role = 'student'}) =>
    {'id': 'u1', 'full_name': 'Test Student', 'student_number': '240001', 'role': role};

class FakeBackend implements AuthBackend {
  String? uid;
  Object? signInError;
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
    signOuts++;
    uid = null;
  }
}

({AuthService auth, FakeBackend backend, List<String> calls}) setup(MockClientHandler h) {
  final backend = FakeBackend();
  final calls = <String>[];
  final api = ReportApiService(
    client: MockClient((req) {
      calls.add('${req.method} ${req.url.path}');
      return h(req);
    }),
    baseUrl: 'https://test.supabase.co/rest/v1',
    apiKey: 'pk_test',
    getToken: () async => 'token-1',
  );
  return (auth: AuthService(backend: backend, api: api), backend: backend, calls: calls);
}

void main() {
  test('ProfileModel maps roles and defaults unknown roles to student', () {
    expect(ProfileModel.fromJson(profileJson(role: 'admin')).isAdmin, true);
    expect(ProfileModel.fromJson(profileJson()).isAdmin, false);
    expect(ProfileModel.fromJson(profileJson(role: 'superuser')).role, UserRole.student);
  });

  group('signIn', () {
    test('returns the profile with its role', () async {
      final t = setup((req) async => json([profileJson(role: 'admin')]));
      final p = await t.auth.signIn('a@b.c', 'pw');
      expect(p.isAdmin, true);
      expect(t.calls, ['GET /rest/v1/profiles']);
    });

    test('trims and lowercases the email', () async {
      final t = setup((req) async => json([profileJson()]));
      await t.auth.signIn('  Student@UIN.AC.ID ', 'pw');
      expect(t.backend.signInEmails, ['student@uin.ac.id']);
    });

    test('rejects a bad email or empty password without calling the backend', () async {
      final t = setup((req) async => json([profileJson()]));
      await expectLater(t.auth.signIn('not-an-email', 'pw'), throwsA(isA<AuthFailure>()));
      await expectLater(t.auth.signIn('a@b.c', ''), throwsA(isA<AuthFailure>()));
      expect(t.backend.signInEmails, isEmpty);
    });

    test('backend failure propagates and no profile request is made', () async {
      final t = setup((req) async => json([profileJson()]));
      t.backend.signInError = const AuthFailure('Incorrect email or password.');
      await expectLater(t.auth.signIn('a@b.c', 'bad'), throwsA(isA<AuthFailure>()));
      expect(t.calls, isEmpty);
    });

    test('profile lookup failure signs out again (no half-logged-in session)', () async {
      final t = setup((req) async => json([])); // profile missing
      await expectLater(t.auth.signIn('a@b.c', 'pw'),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'P0002')));
      expect(t.backend.signOuts, 1);
      expect(t.backend.uid, isNull);
    });
  });

  group('restoreSession', () {
    test('no saved session -> null, no network call', () async {
      final t = setup((req) async => json([profileJson()]));
      expect(await t.auth.restoreSession(), isNull);
      expect(t.calls, isEmpty);
    });

    test('saved session -> profile', () async {
      final t = setup((req) async => json([profileJson()]));
      t.backend.uid = 'u1';
      final p = await t.auth.restoreSession();
      expect(p?.fullName, 'Test Student');
    });

    test('expired session (401) -> signed out, null', () async {
      final t = setup((req) async => json({'message': 'JWT expired'}, 401));
      t.backend.uid = 'u1';
      expect(await t.auth.restoreSession(), isNull);
      expect(t.backend.signOuts, 1);
    });

    test('profile row gone -> signed out, null', () async {
      final t = setup((req) async => json([]));
      t.backend.uid = 'u1';
      expect(await t.auth.restoreSession(), isNull);
      expect(t.backend.signOuts, 1);
    });

    test('offline -> error is rethrown and the user stays signed in', () async {
      final t = setup((req) async => throw http.ClientException('no network'));
      t.backend.uid = 'u1';
      await expectLater(t.auth.restoreSession(),
          throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', true)));
      expect(t.backend.signOuts, 0);
    });
  });
}
