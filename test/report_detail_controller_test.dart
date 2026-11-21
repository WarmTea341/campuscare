// Adjust the package name if your pubspec.yaml name is not "campuscare".
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:campuscare/controllers/report_detail_controller.dart';
import 'package:campuscare/services/photo_store.dart';
import 'package:campuscare/services/report_api_service.dart';
import 'package:campuscare/services/report_photo_workflow.dart';

http.Response json(Object o, [int code = 200]) => http.Response(
  jsonEncode(o),
  code,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> reportJson({
  String status = 'Pending',
  String? priority,
  String? photo,
}) => {
  'id': 'r1',
  'reporter_id': 'u1',
  'room_id': 'room1',
  'category': 'AC',
  'issue_details': ['Not Cooling'],
  'description': null,
  'photo_path': photo,
  'status': status,
  'priority': priority,
  'admin_notes': null,
  'created_at': '2026-11-19T01:00:00+00:00',
  'updated_at': '2026-11-19T01:00:00+00:00',
  'rooms': null,
  'profiles': null,
};

final historyRow = {
  'id': 1,
  'report_id': 'r1',
  'old_status': null,
  'new_status': 'Pending',
  'changed_by': null,
  'notes': 'Report submitted',
  'created_at': '2026-11-19T01:00:00+00:00',
};

class FakeStore implements PhotoStore {
  final ops = <String>[];
  bool failSign = false;

  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) async {}

  @override
  Future<bool> remove(String path) async {
    ops.add('remove:$path');
    return true;
  }

  @override
  Future<String> signedUrl(String path, {int expiresInSeconds = 3600}) async {
    if (failSign) throw Exception('sign failed');
    return 'https://signed/$path';
  }
}

class Backend {
  Map<String, dynamic>? report = reportJson();
  bool deleteBlocked = false;
  Map<String, dynamic>? rpcError; // {'code':..,'message':..}
  Completer<void>? rpcGate;
  final calls = <String>[];
  Map<String, dynamic>? lastRpcBody;

  int count(String key) => calls.where((c) => c == key).length;

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    switch (key) {
      case 'GET /rest/v1/reports':
        return json(report == null ? [] : [report]);
      case 'GET /rest/v1/report_status_history':
        return json([historyRow]);
      case 'DELETE /rest/v1/reports':
        return json(deleteBlocked ? [] : [report]);
      case 'POST /rest/v1/rpc/admin_update_report':
        lastRpcBody = jsonDecode(req.body) as Map<String, dynamic>;
        await rpcGate?.future;
        if (rpcError != null) return json(rpcError!, 400);
        report = {...report!, 'status': lastRpcBody!['p_new_status']};
        report = {...report!, 'status': lastRpcBody!['p_new_status']};
        return json(report!); 
    }
    return json({'message': 'unexpected $key'}, 500);
  }
}

({ReportDetailController c, Backend b, FakeStore store}) setup({
  bool isAdmin = false,
}) {
  final b = Backend();
  final store = FakeStore();
  final api = ReportApiService(
    client: MockClient(b.handle),
    baseUrl: 'https://test.supabase.co/rest/v1',
    apiKey: 'pk_test',
    getToken: () async => 'token-1',
  );
  final c = ReportDetailController(
    api: api,
    photos: ReportPhotoWorkflow(api: api, store: store),
    reportId: 'r1',
    isAdmin: isAdmin,
  );
  return (c: c, b: b, store: store);
}

void main() {
  group('load', () {
    test('fills report, history and the photo URL', () async {
      final t = setup();
      t.b.report = reportJson(photo: 'u1/r1/p.jpg');
      await t.c.load();
      expect(t.c.report.value?.id, 'r1');
      expect(t.c.history, hasLength(1));
      expect(t.c.photoUrl.value, 'https://signed/u1/r1/p.jpg');
      expect(t.c.errorMessage.value, '');
      expect(t.c.isLoading.value, false);
    });

    test('a failing photo URL does not hide the report', () async {
      final t = setup();
      t.b.report = reportJson(photo: 'u1/r1/p.jpg');
      t.store.failSign = true;
      await t.c.load();
      expect(t.c.report.value, isNotNull);
      expect(t.c.photoUrl.value, isNull);
      expect(t.c.errorMessage.value, '');
    });

    test('missing report -> safe message, nothing loaded', () async {
      final t = setup();
      t.b.report = null;
      await t.c.load();
      expect(t.c.report.value, isNull);
      expect(t.c.errorMessage.value, 'Report not found.');
    });
  });

  group('derived state', () {
    test('canEditOrDelete: student + Pending only', () async {
      final student = setup();
      await student.c.load();
      expect(student.c.canEditOrDelete, true);

      final verified = setup();
      verified.b.report = reportJson(status: 'Verified');
      await verified.c.load();
      expect(verified.c.canEditOrDelete, false);

      final admin = setup(isAdmin: true);
      await admin.c.load();
      expect(admin.c.canEditOrDelete, false);
    });

    test('nextStatus follows the workflow and ends at Resolved', () async {
      final t = setup(isAdmin: true);
      await t.c.load();
      expect(t.c.nextStatus, 'Verified');
      t.b.report = reportJson(status: 'In Progress');
      await t.c.load();
      expect(t.c.nextStatus, 'Resolved');
      t.b.report = reportJson(status: 'Resolved');
      await t.c.load();
      expect(t.c.nextStatus, isNull);
      expect(t.c.canTriage, false);
    });
  });

  group('deleteReport', () {
    test('success removes the report and its photo', () async {
      final t = setup();
      t.b.report = reportJson(photo: 'u1/r1/p.jpg');
      await t.c.load();
      expect(await t.c.deleteReport(), true);
      expect(t.store.ops, ['remove:u1/r1/p.jpg']);
      expect(t.c.isBusy.value, false);
    });

    test('not allowed (admin or not Pending) -> false, no request', () async {
      final t = setup(isAdmin: true);
      await t.c.load();
      expect(await t.c.deleteReport(), false);
      expect(t.b.count('DELETE /rest/v1/reports'), 0);
    });

    test(
      'blocked by RLS (changed under you) -> reloads and explains',
      () async {
        final t = setup();
        await t.c.load();
        t.b.deleteBlocked = true;
        expect(await t.c.deleteReport(), false);
        expect(t.b.count('GET /rest/v1/reports'), 2); // reloaded
        expect(t.c.errorMessage.value, contains('can no longer be changed'));
        expect(t.store.ops, isEmpty); // photo untouched
      },
    );
  });

  group('triage', () {
    test('success sends p_* params, then reloads the report', () async {
      final t = setup(isAdmin: true);
      await t.c.load();
      expect(await t.c.triage(priority: 'High', notes: '  Checked  '), true);
      expect(t.b.lastRpcBody, {
        'p_report_id': 'r1',
        'p_new_status': 'Verified',
        'p_priority': 'High',
        'p_admin_notes': 'Checked',
      });
      expect(t.c.report.value?.status, 'Verified');
      expect(t.c.nextStatus, 'In Progress');
      expect(t.b.count('GET /rest/v1/reports'), 2);
    });

    test('Verified without a priority -> false, no request', () async {
      final t = setup(isAdmin: true);
      await t.c.load();
      expect(await t.c.triage(), false);
      expect(t.c.errorMessage.value, contains('priority'));
      expect(t.b.count('POST /rest/v1/rpc/admin_update_report'), 0);
    });

    test('a student cannot triage', () async {
      final t = setup();
      await t.c.load();
      expect(await t.c.triage(priority: 'High'), false);
      expect(t.b.count('POST /rest/v1/rpc/admin_update_report'), 0);
    });

    test(
      'another admin moved it first (23514) -> reload + safe message',
      () async {
        final t = setup(isAdmin: true);
        await t.c.load();
        t.b.rpcError = {'code': '23514', 'message': 'Status unchanged'};
        expect(await t.c.triage(priority: 'High'), false);
        expect(t.b.count('GET /rest/v1/reports'), 2);
        expect(t.c.errorMessage.value, contains('not valid'));
      },
    );

    test('double tap: second call is ignored while the first runs', () async {
      final t = setup(isAdmin: true);
      await t.c.load();
      t.b.rpcGate = Completer<void>();
      final first = t.c.triage(priority: 'High');
      final second = await t.c.triage(priority: 'High');
      expect(second, false);
      t.b.rpcGate!.complete();
      expect(await first, true);
      expect(t.b.count('POST /rest/v1/rpc/admin_update_report'), 1);
    });
  });
}
