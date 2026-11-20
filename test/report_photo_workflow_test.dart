// Adjust the package name if your pubspec.yaml name is not "campuscare".
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:campuscare/core/errors/api_exception.dart';
import 'package:campuscare/dtos/create_report_request.dart';
import 'package:campuscare/models/report_model.dart';
import 'package:campuscare/services/http_photo_store.dart';
import 'package:campuscare/services/photo_store.dart';
import 'package:campuscare/services/report_api_service.dart';
import 'package:campuscare/services/report_photo_workflow.dart';

http.Response json(Object o, [int code = 200]) =>
    http.Response(jsonEncode(o), code, headers: {'content-type': 'application/json'});

Map<String, dynamic> reportJson({String? photo}) => {
      'id': 'r1',
      'reporter_id': 'u1',
      'room_id': 'room1',
      'category': 'AC',
      'issue_details': ['Not Cooling'],
      'description': null,
      'photo_path': photo,
      'status': 'Pending',
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

Uint8List jpeg([int extra = 5]) =>
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(extra, 0)]);

class FakePhotoStore implements PhotoStore {
  final ops = <String>[];
  bool failUpload = false;
  bool failRemove = false;

  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) async {
    ops.add('upload:$path');
    if (failUpload) throw const ApiException(statusCode: 500, technicalMessage: 'upload failed');
  }

  @override
  Future<bool> remove(String path) async {
    ops.add('remove:$path');
    if (failRemove) throw const ApiException(statusCode: 500, technicalMessage: 'remove failed');
    return true;
  }

  @override
  Future<String> signedUrl(String path, {int expiresInSeconds = 3600}) async =>
      'https://signed/$path';
}

class FakeApi {
  final calls = <String>[];
  bool failPatch = false;
  bool blockDelete = false;
  String? deletedRowPhoto;

  Future<http.Response> handle(http.Request req) async {
    calls.add(req.method);
    if (req.method == 'POST') return json([reportJson()], 201);
    if (req.method == 'PATCH') {
      if (failPatch) return json({'code': 'XX000', 'message': 'boom'}, 500);
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return json([reportJson(photo: body['photo_path'] as String?)]);
    }
    if (req.method == 'DELETE') {
      return blockDelete ? json([]) : json([reportJson(photo: deletedRowPhoto)]);
    }
    return json([]);
  }
}

({ReportPhotoWorkflow flow, FakeApi api, FakePhotoStore store}) setup() {
  final api = FakeApi();
  final store = FakePhotoStore();
  final flow = ReportPhotoWorkflow(
    api: ReportApiService(
      client: MockClient(api.handle),
      baseUrl: 'https://test.supabase.co/rest/v1',
      apiKey: 'pk_test',
      getToken: () async => 'token-1',
    ),
    store: store,
    clock: () => 111,
  );
  return (flow: flow, api: api, store: store);
}

const request =
    CreateReportRequest(roomId: 'room1', category: 'AC', issueDetails: ['Not Cooling']);

void main() {
  group('ReportPhotoWorkflow', () {
    test('submit without photo never touches storage', () async {
      final t = setup();
      final r = await t.flow.submitReport(request);
      expect(r.photoError, isNull);
      expect(t.store.ops, isEmpty);
      expect(t.api.calls, ['POST']);
    });

    test('submit with photo: create -> upload -> PATCH photo_path', () async {
      final t = setup();
      final r = await t.flow.submitReport(request, photo: jpeg());
      expect(t.store.ops, ['upload:u1/r1/111.jpg']);
      expect(t.api.calls, ['POST', 'PATCH']);
      expect(r.photoError, isNull);
      expect(r.report.photoPath, 'u1/r1/111.jpg');
    });

    test('unsupported photo is rejected BEFORE the report is created', () async {
      final t = setup();
      await expectLater(
          t.flow.submitReport(request, photo: Uint8List.fromList([1, 2, 3, 4])),
          throwsA(isA<PhotoException>()));
      expect(t.api.calls, isEmpty);
    });

    test('oversized photo is rejected before the report is created', () async {
      final t = setup();
      final big = Uint8List(maxPhotoBytes + 1)..setAll(0, [0xFF, 0xD8, 0xFF]);
      await expectLater(t.flow.submitReport(request, photo: big), throwsA(isA<PhotoException>()));
      expect(t.api.calls, isEmpty);
    });

    test('upload failure keeps the report and reports photoError', () async {
      final t = setup();
      t.store.failUpload = true;
      final r = await t.flow.submitReport(request, photo: jpeg());
      expect(r.report.id, 'r1');
      expect(r.photoError, isA<ApiException>());
      expect(t.api.calls, ['POST']); // no PATCH attempted
    });

    test('PATCH failure after upload removes the orphan and reports photoError', () async {
      final t = setup()..api.failPatch = true;
      final r = await t.flow.submitReport(request, photo: jpeg());
      expect(r.photoError, isNotNull);
      expect(t.store.ops, ['upload:u1/r1/111.jpg', 'remove:u1/r1/111.jpg']);
    });

    test('replacePhoto: upload new, PATCH, then delete old', () async {
      final t = setup();
      final report = ReportModel.fromJson(reportJson(photo: 'u1/r1/old.jpg'));
      final updated = await t.flow.replacePhoto(report, jpeg());
      expect(t.store.ops, ['upload:u1/r1/111.jpg', 'remove:u1/r1/old.jpg']);
      expect(updated.photoPath, 'u1/r1/111.jpg');
    });

    test('replacePhoto: PATCH failure removes the NEW upload and keeps the old photo', () async {
      final t = setup()..api.failPatch = true;
      final report = ReportModel.fromJson(reportJson(photo: 'u1/r1/old.jpg'));
      await expectLater(t.flow.replacePhoto(report, jpeg()), throwsA(isA<ApiException>()));
      expect(t.store.ops, ['upload:u1/r1/111.jpg', 'remove:u1/r1/111.jpg']);
    });

    test('failed cleanup of the old photo does not fail the replace', () async {
      final t = setup();
      final report = ReportModel.fromJson(reportJson(photo: 'u1/r1/old.jpg'));
      // upload succeeds, then removal throws
      final failing = ReportPhotoWorkflow(
        api: ReportApiService(
          client: MockClient(t.api.handle),
          baseUrl: 'https://test.supabase.co/rest/v1',
          apiKey: 'pk_test',
          getToken: () async => 'token-1',
        ),
        store: t.store..failRemove = true,
        clock: () => 111,
      );
      final updated = await failing.replacePhoto(report, jpeg());
      expect(updated.photoPath, 'u1/r1/111.jpg');
    });

    test('removePhoto: row first, then the object', () async {
      final t = setup();
      final report = ReportModel.fromJson(reportJson(photo: 'u1/r1/old.jpg'));
      final updated = await t.flow.removePhoto(report);
      expect(t.api.calls, ['PATCH']);
      expect(t.store.ops, ['remove:u1/r1/old.jpg']);
      expect(updated.photoPath, isNull);
    });

    test('deleteReport removes the photo after the row is gone', () async {
      final t = setup()..api.deletedRowPhoto = 'u1/r1/p.jpg';
      await t.flow.deleteReport(ReportModel.fromJson(reportJson(photo: 'u1/r1/p.jpg')));
      expect(t.api.calls, ['DELETE']);
      expect(t.store.ops, ['remove:u1/r1/p.jpg']);
    });

    test('deleteReport blocked by RLS leaves the photo untouched', () async {
      final t = setup()..api.blockDelete = true;
      await expectLater(
          t.flow.deleteReport(ReportModel.fromJson(reportJson(photo: 'u1/r1/p.jpg'))),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NO_ROWS')));
      expect(t.store.ops, isEmpty);
    });
  });

  test('detectImage recognises JPEG and PNG by magic bytes only', () {
    expect(detectImage(jpeg())?.contentType, 'image/jpeg');
    expect(
        detectImage(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
            ?.extension,
        'png');
    expect(detectImage(Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0, 0, 0, 0])), isNull); // GIF
    expect(detectImage(Uint8List(0)), isNull);
  });

  group('HttpPhotoStore', () {
    HttpPhotoStore make(MockClientHandler h, {Future<String?> Function()? refresh}) =>
        HttpPhotoStore(
          client: MockClient(h),
          supabaseUrl: 'https://test.supabase.co',
          apiKey: 'pk_test',
          getToken: () async => 'token-1',
          refreshToken: refresh,
        );

    test('upload POSTs bytes with content type, no upsert', () async {
      late http.Request captured;
      final s = make((req) async {
        captured = req;
        return json({'Key': 'report-photos/u1/r1/1.jpg'});
      });
      await s.upload('u1/r1/1.jpg', jpeg(), 'image/jpeg');
      expect(captured.method, 'POST');
      expect(captured.url.toString(),
          'https://test.supabase.co/storage/v1/object/report-photos/u1/r1/1.jpg');
      expect(captured.headers['Content-Type'], 'image/jpeg');
      expect(captured.headers['x-upsert'], 'false');
      expect(captured.headers['Authorization'], 'Bearer token-1');
      expect(captured.bodyBytes, jpeg());
    });

    test('remove sends prefixes and reports whether something was deleted', () async {
      late http.Request captured;
      var answer = <dynamic>[
        {'name': 'u1/r1/1.jpg'}
      ];
      final s = make((req) async {
        captured = req;
        return json(answer);
      });
      expect(await s.remove('u1/r1/1.jpg'), true);
      expect(captured.method, 'DELETE');
      expect(jsonDecode(captured.body), {
        'prefixes': ['u1/r1/1.jpg']
      });
      answer = [];
      expect(await s.remove('u1/r1/1.jpg'), false); // RLS-filtered delete
    });

    test('signedUrl handles both signedURL formats', () async {
      var signed = '/object/sign/report-photos/u1/r1/1.jpg?token=abc';
      final s = make((req) async => json({'signedURL': signed}));
      expect(await s.signedUrl('u1/r1/1.jpg'),
          'https://test.supabase.co/storage/v1/object/sign/report-photos/u1/r1/1.jpg?token=abc');
      signed = '/storage/v1/object/sign/report-photos/u1/r1/1.jpg?token=abc';
      expect(await s.signedUrl('u1/r1/1.jpg'),
          'https://test.supabase.co/storage/v1/object/sign/report-photos/u1/r1/1.jpg?token=abc');
    });

    test('401 -> refresh -> one retry with the new token', () async {
      final seen = <String?>[];
      final s = make((req) async {
        seen.add(req.headers['Authorization']);
        return seen.length == 1 ? json({'message': 'JWT expired'}, 401) : json({'Key': 'x'});
      }, refresh: () async => 'token-2');
      await s.upload('u1/r1/1.jpg', jpeg(), 'image/jpeg');
      expect(seen, ['Bearer token-1', 'Bearer token-2']);
    });
  });
}
