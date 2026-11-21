// Adjust the package name if your pubspec.yaml name is not "campuscare".
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:campuscare/controllers/report_list_controller.dart';
import 'package:campuscare/services/report_api_service.dart';

http.Response json(Object o, [int code = 200]) =>
    http.Response(jsonEncode(o), code, headers: {'content-type': 'application/json'});

Map<String, dynamic> reportJson(String id, String status) => {
      'id': id,
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
      'rooms': null,
      'profiles': null,
    };

/// r0..r(n-1); even index = Pending, odd = Verified.
List<Map<String, dynamic>> dataset(int n) =>
    List.generate(n, (i) => reportJson('r$i', i.isEven ? 'Pending' : 'Verified'));

/// Behaves like PostgREST: honours status=eq.X, limit and offset.
Future<http.Response> serve(List<Map<String, dynamic>> all, http.Request req) async {
  final q = req.url.queryParameters;
  var rows = all;
  final f = q['status'];
  if (f != null) rows = rows.where((r) => 'eq.${r['status']}' == f).toList();
  final offset = int.parse(q['offset']!);
  final limit = int.parse(q['limit']!);
  return json(rows.skip(offset).take(limit).toList());
}

ReportListController make(MockClientHandler h) => ReportListController(ReportApiService(
      client: MockClient(h),
      baseUrl: 'https://test.supabase.co/rest/v1',
      apiKey: 'pk_test',
      getToken: () async => 'token-1',
    ));

void main() {
  test('load fetches the first page', () async {
    final all = dataset(45);
    final c = make((req) => serve(all, req));
    await c.load();
    expect(c.reports, hasLength(20));
    expect(c.hasMore.value, true);
    expect(c.isLoading.value, false);
    expect(c.isEmptyState, false);
  });

  test('loadMore appends pages and stops after a short page', () async {
    final all = dataset(45);
    var requests = 0;
    final c = make((req) {
      requests++;
      return serve(all, req);
    });
    await c.load();
    await c.loadMore();
    expect(c.reports, hasLength(40));
    await c.loadMore();
    expect(c.reports, hasLength(45));
    expect(c.hasMore.value, false);
    final before = requests;
    await c.loadMore(); // nothing left: no request
    expect(requests, before);
  });

  test('loadMore is ignored while a load is running', () async {
    final all = dataset(45);
    var requests = 0;
    final c = make((req) {
      requests++;
      return serve(all, req);
    });
    final loading = c.load();
    await c.loadMore();
    await loading;
    expect(requests, 1);
    expect(c.reports, hasLength(20));
  });

  test('setFilter replaces the list with only that status', () async {
    final all = dataset(45);
    final c = make((req) => serve(all, req));
    await c.load();
    await c.setFilter('Pending');
    expect(c.reports.every((r) => r.status == 'Pending'), true);
    expect(c.reports, isNotEmpty);
    await c.setFilter(null);
    expect(c.reports.any((r) => r.status == 'Verified'), true);
  });

  test('setFilter with the same value does nothing', () async {
    var requests = 0;
    final c = make((req) {
      requests++;
      return serve(dataset(5), req);
    });
    await c.setFilter(null);
    expect(requests, 0);
  });

  test('a stale response (older filter) never overwrites the newer list', () async {
    final all = dataset(45);
    final gate = Completer<void>();
    final c = make((req) async {
      if (req.url.queryParameters['status'] == null) await gate.future; // first load is slow
      return serve(all, req);
    });
    final first = c.load();
    await c.setFilter('Pending');
    gate.complete();
    await first;
    expect(c.reports, isNotEmpty);
    expect(c.reports.every((r) => r.status == 'Pending'), true);
    expect(c.isLoading.value, false);
  });

  test('reload failure keeps the rows on screen and sets a safe message', () async {
    final all = dataset(45);
    var fail = false;
    final c = make((req) async {
      if (fail) throw http.ClientException('no network');
      return serve(all, req);
    });
    await c.load();
    fail = true;
    await c.reload();
    expect(c.reports, hasLength(20));
    expect(c.errorMessage.value, contains('No connection'));
    expect(c.isLoading.value, false);
  });

  test('loadMore skips duplicates when new reports shift the offset', () async {
    final all = dataset(45);
    final c = make((req) => serve(all, req));
    await c.load();
    all.insert(0, reportJson('new1', 'Pending')); // shifts everything by one
    await c.loadMore();
    final ids = c.reports.map((r) => r.id).toList();
    expect(ids.toSet().length, ids.length);
  });
}
