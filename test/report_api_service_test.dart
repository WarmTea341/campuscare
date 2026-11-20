// Adjust the package name if your pubspec.yaml name is not "campuscare".
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:campuscare/core/errors/api_exception.dart';
import 'package:campuscare/dtos/admin_update_report_request.dart';
import 'package:campuscare/dtos/create_report_request.dart';
import 'package:campuscare/dtos/update_pending_report_request.dart';
import 'package:campuscare/services/report_api_service.dart';

http.Response json(Object o, [int code = 200]) =>
    http.Response(jsonEncode(o), code, headers: {'content-type': 'application/json'});

Map<String, dynamic> reportJson({String status = 'Pending'}) => {
      'id': 'r1',
      'reporter_id': 'u1',
      'room_id': 'room1',
      'category': 'AC',
      'issue_details': ['Not Cooling'],
      'description': null,
      'photo_path': null,
      'status': status,
      'priority': null,
      'admin_notes': null,
      'created_at': '2026-11-19T01:00:00+00:00',
      'updated_at': '2026-11-19T01:00:00+00:00',
      'rooms': {
        'id': 'room1',
        'room_number': 'T-101',
        'buildings': {'id': 'b1', 'name': 'Building A'},
      },
    };

ReportApiService makeService(
  MockClientHandler handler, {
  Future<String?> Function()? token,
  Future<String?> Function()? refresh,
}) =>
    ReportApiService(
      client: MockClient(handler),
      baseUrl: 'https://test.supabase.co/rest/v1',
      apiKey: 'pk_test',
      getToken: token ?? () async => 'token-1',
      refreshToken: refresh,
    );

const updateReq = UpdatePendingReportRequest(
    roomId: 'room1', category: 'AC', issueDetails: ['Not Cooling']);

void main() {
  test('listReports builds the right URL and headers', () async {
    late http.Request captured;
    final s = makeService((req) async {
      captured = req;
      return json([reportJson()]);
    });
    final list = await s.listReports(status: 'Pending', limit: 10, offset: 20);

    expect(captured.method, 'GET');
    expect(captured.url.path, '/rest/v1/reports');
    final q = captured.url.queryParameters;
    expect(q['status'], 'eq.Pending');
    expect(q['limit'], '10');
    expect(q['offset'], '20');
    expect(q['order'], 'created_at.desc');
    expect(q['select'], contains('rooms('));
    expect(captured.headers['apikey'], 'pk_test');
    expect(captured.headers['Authorization'], 'Bearer token-1');
    expect(list.single.id, 'r1');
  });

  test('listRooms filters by building', () async {
    late http.Request captured;
    final s = makeService((req) async {
      captured = req;
      return json([
        {'id': 'room1', 'building_id': 'b1', 'room_number': 'T-101'}
      ]);
    });
    final rooms = await s.listRooms('b1');
    expect(captured.url.queryParameters['building_id'], 'eq.b1');
    expect(rooms.single.roomNumber, 'T-101');
  });

  test('createReport POSTs only the 4 student fields and asks for representation', () async {
    late http.Request captured;
    final s = makeService((req) async {
      captured = req;
      return json([reportJson()], 201);
    });
    final r = await s.createReport(const CreateReportRequest(
        roomId: 'room1', category: 'AC', issueDetails: ['Not Cooling'], description: ''));

    expect(captured.method, 'POST');
    expect(captured.headers['Prefer'], 'return=representation');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body.keys.toSet(), {'room_id', 'category', 'issue_details', 'description'});
    expect(body['description'], isNull);
    expect(r.status, 'Pending');
  });

  test('updatePendingReport PATCHes by id and returns the row', () async {
    late http.Request captured;
    final s = makeService((req) async {
      captured = req;
      return json([reportJson()]);
    });
    await s.updatePendingReport('r1', updateReq);
    expect(captured.method, 'PATCH');
    expect(captured.url.queryParameters['id'], 'eq.r1');
    expect(captured.headers['Prefer'], 'return=representation');
    expect((jsonDecode(captured.body) as Map).containsKey('photo_path'), false);
  });

  test('updatePendingReport: empty result (blocked by RLS) -> NO_ROWS', () async {
    final s = makeService((req) async => json([]));
    await expectLater(
        s.updatePendingReport('r1', updateReq),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NO_ROWS')));
  });

  test('deleteReport returns the deleted row', () async {
    late http.Request captured;
    final s = makeService((req) async {
      captured = req;
      return json([reportJson()]);
    });
    final r = await s.deleteReport('r1');
    expect(captured.method, 'DELETE');
    expect(captured.url.queryParameters['id'], 'eq.r1');
    expect(r.id, 'r1');
  });

  test('deleteReport: empty result -> NO_ROWS', () async {
    final s = makeService((req) async => json([]));
    await expectLater(s.deleteReport('r1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NO_ROWS')));
  });

  test('adminUpdateReport calls the RPC with p_* parameters', () async {
    late http.Request captured;
    final s = makeService((req) async {
      captured = req;
      return json(reportJson(status: 'Verified'));
    });
    final r = await s.adminUpdateReport(const AdminUpdateReportRequest(
        reportId: 'r1', newStatus: 'Verified', priority: 'High'));
    expect(captured.method, 'POST');
    expect(captured.url.path, '/rest/v1/rpc/admin_update_report');
    expect(jsonDecode(captured.body),
        {'p_report_id': 'r1', 'p_new_status': 'Verified', 'p_priority': 'High'});
    expect(r.status, 'Verified');
  });

  test('database error code is preserved and mapped to a safe message', () async {
    final s = makeService((req) async =>
        json({'code': '23514', 'message': 'Invalid report status transition'}, 400));
    await expectLater(
        s.adminUpdateReport(const AdminUpdateReportRequest(reportId: 'r1', newStatus: 'Resolved')),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', '23514')
            .having((e) => e.userMessage, 'message', isNot(contains('Invalid report status')))));
  });

  test('401 -> refresh token -> retry once with the new token', () async {
    final seen = <String?>[];
    final s = makeService((req) async {
      seen.add(req.headers['Authorization']);
      return seen.length == 1
          ? json({'code': 'PGRST303', 'message': 'JWT expired'}, 401)
          : json([reportJson()]);
    }, refresh: () async => 'token-2');
    await s.listReports();
    expect(seen, ['Bearer token-1', 'Bearer token-2']);
  });

  test('401 twice -> session expired after exactly 2 requests (no loop)', () async {
    var calls = 0;
    final s = makeService((req) async {
      calls++;
      return json({'code': 'PGRST303', 'message': 'JWT expired'}, 401);
    }, refresh: () async => 'token-2');
    await expectLater(s.listReports(),
        throwsA(isA<ApiException>().having((e) => e.isSessionExpired, 'expired', true)));
    expect(calls, 2);
  });

  test('401 and refresh fails -> session expired after 1 request', () async {
    var calls = 0;
    final s = makeService((req) async {
      calls++;
      return json({'message': 'JWT expired'}, 401);
    }, refresh: () async => null);
    await expectLater(s.listReports(),
        throwsA(isA<ApiException>().having((e) => e.isSessionExpired, 'expired', true)));
    expect(calls, 1);
  });

  test('network failure -> ApiException.isNetwork', () async {
    final s = makeService((req) async => throw http.ClientException('boom'));
    await expectLater(s.listReports(),
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', true)));
  });

  test('no session -> 401 without sending any request', () async {
    var calls = 0;
    final s = makeService((req) async {
      calls++;
      return json([]);
    }, token: () async => null);
    await expectLater(s.listReports(),
        throwsA(isA<ApiException>().having((e) => e.isSessionExpired, 'expired', true)));
    expect(calls, 0);
  });
}
