// Live check against your real Supabase project (not mocks).
// Needs: 1 student + 1 admin account, and at least 1 building with 1 room.
//
// PowerShell:
//   $env:SUPABASE_URL="https://xxxx.supabase.co"
//   $env:SUPABASE_PUBLISHABLE_KEY="sb_publishable_..."
//   $env:STUDENT_EMAIL="..."; $env:STUDENT_PASSWORD="..."
//   $env:ADMIN_EMAIL="...";   $env:ADMIN_PASSWORD="..."
//   dart run tool/live_smoke_test.dart
// Adjust the package name below if your pubspec.yaml name is not "campuscare".
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:campuscare/core/errors/api_exception.dart';
import 'package:campuscare/dtos/admin_update_report_request.dart';
import 'package:campuscare/dtos/create_report_request.dart';
import 'package:campuscare/dtos/update_pending_report_request.dart';
import 'package:campuscare/services/report_api_service.dart';

String env(String k) {
  final v = Platform.environment[k];
  if (v == null || v.isEmpty) {
    stderr.writeln('Missing environment variable $k');
    exit(2);
  }
  return v;
}

Future<String> signIn(String url, String key, String email, String password) async {
  final res = await http.post(
    Uri.parse('$url/auth/v1/token?grant_type=password'),
    headers: {'apikey': key, 'Content-Type': 'application/json'},
    body: jsonEncode({'email': email, 'password': password}),
  );
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

Future<void> main() async {
  final url = env('SUPABASE_URL');
  final key = env('SUPABASE_PUBLISHABLE_KEY');
  final studentToken =
      await signIn(url, key, env('STUDENT_EMAIL'), env('STUDENT_PASSWORD'));
  final adminToken = await signIn(url, key, env('ADMIN_EMAIL'), env('ADMIN_PASSWORD'));

  ReportApiService svc(String t) =>
      ReportApiService(getToken: () async => t, baseUrl: '$url/rest/v1', apiKey: key);
  final student = svc(studentToken);
  final admin = svc(adminToken);

  final buildings = await student.listBuildings();
  check(buildings.isNotEmpty, 'buildings readable (seed at least one)');
  final rooms = await student.listRooms(buildings.first.id);
  check(rooms.isNotEmpty, 'rooms readable (seed at least one)');
  final roomId = rooms.first.id;

  final created = await student.createReport(CreateReportRequest(
      roomId: roomId, category: 'AC', issueDetails: ['Not Cooling'], description: ''));
  check(created.status == 'Pending' && created.description == null,
      'create: Pending, blank description stored as null');
  check(created.buildingName != null, 'create: nested room/building returned');

  final history = await student.listHistory(created.id);
  check(history.length == 1, 'history has the submitted event');

  final edited = await student.updatePendingReport(
      created.id,
      UpdatePendingReportRequest(
          roomId: roomId,
          category: 'AC',
          issueDetails: ['Not Cooling', 'Making Noise'],
          description: 'Smoke test edit'));
  check(edited.issueDetails.length == 2 && edited.description == 'Smoke test edit',
      'PATCH edit while Pending');

  final verified = await admin.adminUpdateReport(AdminUpdateReportRequest(
      reportId: created.id, newStatus: 'Verified', priority: 'High', adminNotes: 'Smoke'));
  check(verified.status == 'Verified' && verified.priority == 'High',
      'admin RPC verify returns the updated report');

  try {
    await student.updatePendingReport(
        created.id,
        UpdatePendingReportRequest(
            roomId: roomId, category: 'AC', issueDetails: ['x'], description: 'too late'));
    check(false, 'student edit after Verified is blocked');
  } on ApiException catch (e) {
    check(e.code == 'NO_ROWS', 'student edit after Verified is blocked (NO_ROWS)');
  }

  try {
    await student.deleteReport(created.id);
    check(false, 'student delete after Verified is blocked');
  } on ApiException catch (e) {
    check(e.code == 'NO_ROWS', 'student delete after Verified is blocked (NO_ROWS)');
  }

  final seenByAdmin = await admin.getReport(created.id);
  check(seenByAdmin.status == 'Verified', 'admin can read the student report');
  final history2 = await student.listHistory(created.id);
  check(history2.length == 2, 'student sees the status change in history');

  final temp = await student.createReport(CreateReportRequest(
      roomId: roomId, category: 'Other', issueDetails: [], description: 'Temp report to delete'));
  final deleted = await student.deleteReport(temp.id);
  check(deleted.id == temp.id, 'student deletes own Pending report');

  stdout.writeln('\nLeft behind: report ${created.id} (Verified). Delete it in the Table Editor.');
}
