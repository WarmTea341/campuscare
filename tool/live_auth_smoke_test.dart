// Live check of profile/role lookup and login errors against your real project.
// Same environment variables as the other live tests. Run:
//   dart run tool/live_auth_smoke_test.dart
// Adjust the package name below if your pubspec.yaml name is not "campuscare".
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:campuscare/core/errors/api_exception.dart';
import 'package:campuscare/models/profile_model.dart';
import 'package:campuscare/services/report_api_service.dart';

String env(String k) {
  final v = Platform.environment[k];
  if (v == null || v.isEmpty) {
    stderr.writeln('Missing environment variable $k');
    exit(2);
  }
  return v;
}

Future<http.Response> login(String url, String key, String email, String password) =>
    http.post(Uri.parse('$url/auth/v1/token?grant_type=password'),
        headers: {'apikey': key, 'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}));

void check(bool ok, String name) {
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}: $name');
  if (!ok) exitCode = 1;
}

Future<void> main() async {
  final url = env('SUPABASE_URL');
  final key = env('SUPABASE_PUBLISHABLE_KEY');

  final sRes = await login(url, key, env('STUDENT_EMAIL'), env('STUDENT_PASSWORD'));
  final aRes = await login(url, key, env('ADMIN_EMAIL'), env('ADMIN_PASSWORD'));
  final sBody = jsonDecode(sRes.body) as Map<String, dynamic>;
  final aBody = jsonDecode(aRes.body) as Map<String, dynamic>;
  final sId = (sBody['user'] as Map<String, dynamic>)['id'] as String;
  final aId = (aBody['user'] as Map<String, dynamic>)['id'] as String;

  ReportApiService api(String t) =>
      ReportApiService(getToken: () async => t, baseUrl: '$url/rest/v1', apiKey: key);
  final student = api(sBody['access_token'] as String);
  final admin = api(aBody['access_token'] as String);

  final sp = await student.getProfile(sId);
  check(sp.role == UserRole.student && !sp.isAdmin, 'student profile loads with role student');
  final ap = await admin.getProfile(aId);
  check(ap.role == UserRole.admin && ap.isAdmin, 'admin profile loads with role admin');

  try {
    await student.getProfile(aId);
    check(false, 'student cannot read the admin profile');
  } on ApiException catch (e) {
    check(e.code == 'P0002', 'student cannot read the admin profile (not found)');
  }
  final seen = await admin.getProfile(sId);
  check(seen.id == sId, 'admin can read a student profile');

  final bad = await login(url, key, env('STUDENT_EMAIL'), 'definitely-wrong-password');
  check(bad.statusCode == 400 && bad.body.toLowerCase().contains('invalid login credentials'),
      'wrong password -> "Invalid login credentials" (the message SupabaseAuthBackend maps)');
}
