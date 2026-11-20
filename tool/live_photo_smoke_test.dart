// Live check of Storage + the photo workflow against your real Supabase project.
// Same environment variables as tool/live_smoke_test.dart. Run:
//   dart run tool/live_photo_smoke_test.dart
// Adjust the package name below if your pubspec.yaml name is not "campuscare".
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:campuscare/core/errors/api_exception.dart';
import 'package:campuscare/dtos/admin_update_report_request.dart';
import 'package:campuscare/dtos/create_report_request.dart';
import 'package:campuscare/services/http_photo_store.dart';
import 'package:campuscare/services/report_api_service.dart';
import 'package:campuscare/services/report_photo_workflow.dart';

// 1x1 PNG
final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

String env(String k) {
  final v = Platform.environment[k];
  if (v == null || v.isEmpty) {
    stderr.writeln('Missing environment variable $k');
    exit(2);
  }
  return v;
}

Future<String> signIn(String url, String key, String email, String password) async {
  final res = await http.post(Uri.parse('$url/auth/v1/token?grant_type=password'),
      headers: {'apikey': key, 'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}));
  if (res.statusCode != 200) {
    stderr.writeln('Login failed for $email: ${res.body}');
    exit(2);
  }
  return (jsonDecode(res.body) as Map<String, dynamic>)['access_token'] as String;
}

void check(bool ok, String name) {
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}: $name');
  if (!ok) exitCode = 1;
}

Future<bool> throwsApi(Future<Object?> Function() f) async {
  try {
    await f();
    return false;
  } on ApiException {
    return true;
  }
}

Future<void> main() async {
  final url = env('SUPABASE_URL');
  final key = env('SUPABASE_PUBLISHABLE_KEY');
  final sTok = await signIn(url, key, env('STUDENT_EMAIL'), env('STUDENT_PASSWORD'));
  final aTok = await signIn(url, key, env('ADMIN_EMAIL'), env('ADMIN_PASSWORD'));

  ReportApiService api(String t) =>
      ReportApiService(getToken: () async => t, baseUrl: '$url/rest/v1', apiKey: key);
  HttpPhotoStore store(String t) =>
      HttpPhotoStore(getToken: () async => t, supabaseUrl: url, apiKey: key);

  final studentApi = api(sTok);
  final adminApi = api(aTok);
  final studentStore = store(sTok);
  final adminStore = store(aTok);
  final student = ReportPhotoWorkflow(api: studentApi, store: studentStore);

  final building = (await studentApi.listBuildings()).first;
  final roomId = (await studentApi.listRooms(building.id)).first.id;
  CreateReportRequest makeReq(String d) => CreateReportRequest(
      roomId: roomId, category: 'AC', issueDetails: const ['Not Cooling'], description: d);

  // 1. submit with photo
  final res = await student.submitReport(makeReq('Photo smoke test'), photo: png);
  check(res.photoError == null && res.report.photoPath != null,
      'submit with photo attaches photo_path');
  final report = res.report;
  final path = report.photoPath!;
  final uid = report.reporterId;

  // 2. signed URL serves the same bytes
  final got = await http.get(Uri.parse((await student.photoUrl(report))!));
  check(got.statusCode == 200 && got.bodyBytes.length == png.length,
      'signed URL serves the uploaded photo');

  // 3. upload policy
  Future<bool> uploadBlocked(String p) async {
    try {
      await studentStore.upload(p, Uint8List.fromList(png), 'image/png');
      await studentStore.remove(p); // it should NOT have worked; clean up
      return false;
    } on ApiException {
      return true;
    }
  }

  check(await uploadBlocked('00000000-0000-0000-0000-000000000001/${report.id}/x.png'),
      'cannot upload into another user\'s folder');
  check(await uploadBlocked('$uid/00000000-0000-0000-0000-000000000002/x.png'),
      'cannot upload for a report that does not exist');

  // 4. replace while Pending
  final replaced = await student.replacePhoto(report, Uint8List.fromList(png));
  check(replaced.photoPath != null && replaced.photoPath != path, 'replace changes photo_path');
  check(await throwsApi(() => studentStore.signedUrl(path)),
      'old photo is gone from storage after replace');

  // 5. admin verifies -> evidence locked for the student
  await adminApi.adminUpdateReport(
      AdminUpdateReportRequest(reportId: report.id, newStatus: 'Verified', priority: 'Low'));
  final locked = replaced.photoPath!;
  check(!(await studentStore.remove(locked)), 'student cannot delete the photo of a Verified report');
  try {
    await student.removePhoto(replaced);
    check(false, 'student cannot detach the photo after Verified');
  } on ApiException catch (e) {
    check(e.code == 'NO_ROWS', 'student cannot detach the photo after Verified (NO_ROWS)');
  }
  check(await throwsApi(() => student.replacePhoto(replaced, Uint8List.fromList(png))),
      'student cannot replace the photo after Verified');
  final stillThere = await http.get(Uri.parse(await studentStore.signedUrl(locked)));
  check(stillThere.statusCode == 200, 'evidence photo still readable after the blocked attempts');
  final adminView = await http.get(Uri.parse(await adminStore.signedUrl(locked)));
  check(adminView.statusCode == 200, 'admin can view the student photo');

  // 6. delete-with-photo on a fresh Pending report
  final r2 = await student.submitReport(makeReq('Photo smoke test 2'), photo: png);
  final p2 = r2.report.photoPath!;
  await student.deleteReport(r2.report);
  check(await throwsApi(() => studentStore.signedUrl(p2)),
      'deleting a Pending report also removes its photo');

  // cleanup: admin may delete the locked evidence object
  await adminStore.remove(locked);
  stdout.writeln('\nCleanup SQL (SQL Editor):');
  stdout.writeln("  delete from public.reports where description like 'Photo smoke test%';");
}
