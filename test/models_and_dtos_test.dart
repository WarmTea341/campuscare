// Adjust the package name if your pubspec.yaml name is not "campuscare".
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:campuscare/core/errors/api_exception.dart';
import 'package:campuscare/dtos/admin_update_report_request.dart';
import 'package:campuscare/dtos/create_report_request.dart';
import 'package:campuscare/dtos/update_pending_report_request.dart';
import 'package:campuscare/models/report_model.dart';
import 'package:campuscare/models/report_status_history_model.dart';

void main() {
  final fullJson = {
    'id': 'r1',
    'reporter_id': 'u1',
    'room_id': 'room1',
    'category': 'AC',
    'issue_details': ['Not Cooling', 'Making Noise'],
    'description': 'Does not cool',
    'photo_path': 'u1/r1/a.jpg',
    'status': 'In Progress',
    'priority': 'High',
    'admin_notes': 'Technician assigned',
    'created_at': '2026-11-19T01:00:00+00:00',
    'updated_at': '2026-11-19T02:00:00.123456+00:00',
    'rooms': {
      'id': 'room1',
      'room_number': 'T-101',
      'buildings': {'id': 'b1', 'name': 'Building A'},
    },
  };

  group('ReportModel', () {
    test('parses a full response with nested room/building', () {
      final r = ReportModel.fromJson(fullJson);
      expect(r.issueDetails, ['Not Cooling', 'Making Noise']);
      expect(r.buildingName, 'Building A');
      expect(r.roomNumber, 'T-101');
      expect(r.displayTitle, 'AC - Building A, T-101');
      expect(r.isPending, false);
      expect(r.createdAt.toUtc().hour, 1);
    });

    test('handles nulls and missing nested objects', () {
      final r = ReportModel.fromJson({
        ...fullJson,
        'description': null,
        'photo_path': null,
        'priority': null,
        'admin_notes': null,
        'rooms': null,
        'status': 'Pending',
      });
      expect(r.description, isNull);
      expect(r.photoPath, isNull);
      expect(r.priority, isNull);
      expect(r.buildingName, isNull);
      expect(r.isPending, true);
    });

    test('toJson round-trips through fromJson', () {
      final a = ReportModel.fromJson(fullJson);
      final b = ReportModel.fromJson(a.toJson());
      expect(b.id, a.id);
      expect(b.issueDetails, a.issueDetails);
      expect(b.createdAt, a.createdAt);
      expect(b.buildingName, a.buildingName);
    });
  });

  test('ReportStatusHistoryModel parses initial event with null old_status', () {
    final h = ReportStatusHistoryModel.fromJson({
      'id': 1,
      'report_id': 'r1',
      'old_status': null,
      'new_status': 'Pending',
      'changed_by': null,
      'notes': 'Report submitted',
      'created_at': '2026-11-19T01:00:00+00:00',
    });
    expect(h.oldStatus, isNull);
    expect(h.changedBy, isNull);
    expect(h.newStatus, 'Pending');
  });

  group('CreateReportRequest', () {
    test('sends exactly the 4 student fields, blank description -> null', () {
      final j = const CreateReportRequest(
        roomId: 'room1',
        category: 'AC',
        issueDetails: ['Not Cooling'],
        description: '   ',
      ).toJson();
      expect(j.keys.toSet(), {'room_id', 'category', 'issue_details', 'description'});
      expect(j['description'], isNull);
      for (final k in ['status', 'priority', 'reporter_id', 'admin_notes']) {
        expect(j.containsKey(k), false);
      }
    });

    test('validation mirrors DB constraints', () {
      String? v(String c, List<String> t, [String? d]) => CreateReportRequest(
              roomId: 'x', category: c, issueDetails: t, description: d)
          .validate();
      expect(v('AC', ['Not Cooling']), isNull);
      expect(v('AC', []), isNotNull); // nothing at all
      expect(v('Other', ['x']), isNotNull); // Other needs description
      expect(v('Other', [], 'Broken projector'), isNull);
      expect(v('AC', ['a', 'b', 'c', 'd']), isNotNull); // >3 tags
      expect(v('AC', [], 'ok'), isNotNull); // description < 3 chars
      expect(v('Nope', ['x']), isNotNull); // unknown category
    });
  });

  group('UpdatePendingReportRequest', () {
    test('photo_path only sent when changePhoto is true', () {
      const base = UpdatePendingReportRequest(
          roomId: 'r', category: 'AC', issueDetails: ['Not Cooling']);
      expect(base.toJson().containsKey('photo_path'), false);
      const remove = UpdatePendingReportRequest(
          roomId: 'r', category: 'AC', issueDetails: ['Not Cooling'], changePhoto: true);
      expect(remove.toJson().containsKey('photo_path'), true);
      expect(remove.toJson()['photo_path'], isNull);
    });
  });

  group('AdminUpdateReportRequest', () {
    test('omits priority and blank notes; uses RPC parameter names', () {
      final j = const AdminUpdateReportRequest(
              reportId: 'r1', newStatus: 'In Progress', adminNotes: '  ')
          .toJson();
      expect(j, {'p_report_id': 'r1', 'p_new_status': 'In Progress'});
    });

    test('rejects bad status/priority', () {
      expect(const AdminUpdateReportRequest(reportId: 'r', newStatus: 'Done').validate(),
          isNotNull);
      expect(
          const AdminUpdateReportRequest(
                  reportId: 'r', newStatus: 'Verified', priority: 'Urgent')
              .validate(),
          isNotNull);
      expect(
          const AdminUpdateReportRequest(
                  reportId: 'r', newStatus: 'Verified', priority: 'High')
              .validate(),
          isNull);
    });
  });

  group('ApiException', () {
    test('parses PostgREST error body', () {
      final e = ApiException.fromResponse(http.Response(
          '{"code":"42501","message":"permission denied for table reports"}', 403));
      expect(e.code, '42501');
      expect(e.isForbidden, true);
      expect(e.userMessage, isNot(contains('permission denied'))); // no raw SQL errors in UI
    });

    test('handles non-JSON body and network errors', () {
      final e = ApiException.fromResponse(http.Response('Bad Gateway', 502));
      expect(e.userMessage, isNotEmpty);
      expect(ApiException.network('SocketException').isNetwork, true);
    });
  });
}
