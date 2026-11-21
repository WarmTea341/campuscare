import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:campuscare/controllers/report_form_controller.dart';
import 'package:campuscare/models/building_model.dart';
import 'package:campuscare/models/report_model.dart';
import 'package:campuscare/models/room_model.dart';
import 'package:campuscare/services/photo_picker_service.dart';
import 'package:campuscare/services/photo_store.dart';
import 'package:campuscare/services/report_api_service.dart';
import 'package:campuscare/services/report_photo_workflow.dart';

http.Response json(Object o, [int code = 200]) => http.Response(
  jsonEncode(o),
  code,
  headers: {'content-type': 'application/json'},
);

final fakeJpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

Map<String, dynamic> reportJson({
  String id = 'r1',
  String status = 'Pending',
  String? photo,
  String? description = 'Leaking pipe',
}) => {
  'id': id,
  'reporter_id': 'u1',
  'room_id': 'room2',
  'category': 'AC',
  'issue_details': ['Not Cooling'],
  'description': description,
  'photo_path': photo,
  'status': status,
  'priority': null,
  'admin_notes': null,
  'created_at': '2026-11-19T01:00:00+00:00',
  'updated_at': '2026-11-19T01:00:00+00:00',
  'rooms': {
    'id': 'room2',
    'room_number': 'T-102',
    'buildings': {'id': 'b1', 'name': 'Building A'},
  },
  'profiles': {'full_name': 'Ahmad Fauzan', 'student_number': '230605110001'},
};

class FakePicker implements PhotoPickerService {
  Uint8List? nextBytes;
  Object? nextError;

  @override
  Future<Uint8List?> pick(ImageSource source) async {
    final err = nextError;
    if (err != null) throw err;
    return nextBytes;
  }
}

class FakeStore implements PhotoStore {
  final ops = <String>[];
  bool failUpload = false;
  bool failRemove = false;

  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) async {
    if (failUpload) throw const PhotoException('Bucket offline');
    ops.add('upload:$path');
  }

  @override
  Future<bool> remove(String path) async {
    if (failRemove) throw const PhotoException('Delete failed');
    ops.add('remove:$path');
    return true;
  }

  @override
  Future<String> signedUrl(String path, {int expiresInSeconds = 3600}) async =>
      'https://signed/$path';
}

class Backend {
  final calls = <String>[];
  Map<String, dynamic>? lastPostBody;
  Map<String, dynamic>? lastPatchBody;
  bool patchBlocked = false;
  Completer<void>? writeGate;
  String? currentPhoto;

  int count(String key) => calls.where((c) => c == key).length;

  Future<http.Response> handle(http.Request req) async {
    final key = '${req.method} ${req.url.path}';
    calls.add(key);

    switch (key) {
      case 'GET /rest/v1/buildings':
        return json([
          {'id': 'b1', 'name': 'Building A'},
          {'id': 'b2', 'name': 'Building B'},
        ]);
      case 'GET /rest/v1/rooms':
        final bId = req.url.queryParameters['building_id'];
        if (bId == 'eq.b1') {
          return json([
            {'id': 'room1', 'building_id': 'b1', 'room_number': 'T-101'},
            {'id': 'room2', 'building_id': 'b1', 'room_number': 'T-102'},
          ]);
        }
        return json([
          {'id': 'room3', 'building_id': 'b2', 'room_number': 'L-201'},
        ]);
      case 'POST /rest/v1/reports':
        lastPostBody = jsonDecode(req.body) as Map<String, dynamic>;
        await writeGate?.future;
        return json([
          reportJson(
            id: 'r-new',
            photo: currentPhoto,
            description: lastPostBody!['description'] as String?,
          ),
        ]);
      case 'PATCH /rest/v1/reports':
        lastPatchBody = jsonDecode(req.body) as Map<String, dynamic>;
        await writeGate?.future;
        if (patchBlocked) return json([]);
        if (lastPatchBody!.containsKey('photo_path')) {
          currentPhoto = lastPatchBody!['photo_path'] as String?;
        }
        return json([reportJson(id: 'r1', photo: currentPhoto)]);
    }
    return json({'message': 'unexpected $key'}, 500);
  }
}

({ReportFormController c, Backend b, FakeStore store, FakePicker picker})
setup({ReportModel? initialReport}) {
  final b = Backend()..currentPhoto = initialReport?.photoPath;
  final store = FakeStore();
  final picker = FakePicker();
  final api = ReportApiService(
    client: MockClient(b.handle),
    baseUrl: 'https://test.supabase.co/rest/v1',
    apiKey: 'pk_test',
    getToken: () async => 'token-1',
  );
  final c = ReportFormController(
    api: api,
    photos: ReportPhotoWorkflow(api: api, store: store),
    picker: picker,
    initialReport: initialReport,
  );
  return (c: c, b: b, store: store, picker: picker);
}

void main() {
  group('load & form interactions', () {
    test(
      'create mode loads buildings and cascades rooms on selectBuilding',
      () async {
        final t = setup();
        await t.c.load();

        expect(t.c.isEditing, false);
        expect(t.c.buildings, hasLength(2));
        expect(t.c.rooms, isEmpty);

        await t.c.selectBuilding(
          const BuildingModel(id: 'b1', name: 'Building A'),
        );
        expect(t.c.rooms.map((r) => r.roomNumber), ['T-101', 'T-102']);

        t.c.selectRoom(
          const RoomModel(id: 'room1', buildingId: 'b1', roomNumber: 'T-101'),
        );
        expect(t.c.selectedRoom.value?.id, 'room1');
      },
    );

    test(
      'edit mode prefills building, room, category, tags and description',
      () async {
        final existing = ReportModel.fromJson(
          reportJson(photo: 'u1/r1/old.jpg'),
        );
        final t = setup(initialReport: existing);
        await t.c.load();

        expect(t.c.isEditing, true);
        expect(t.c.selectedBuilding.value?.id, 'b1');
        expect(t.c.selectedRoom.value?.id, 'room2');
        expect(t.c.category.value, 'AC');
        expect(t.c.selectedTags, ['Not Cooling']);
        expect(t.c.description.value, 'Leaking pipe');
        expect(t.c.hasExistingPhoto, true);
      },
    );

    test('setCategory clears tags and toggleTag enforces max 3 tags', () {
      final t = setup();
      t.c.setCategory('AC');
      expect(t.c.quickTagOptions, isNotEmpty);

      t.c.toggleTag('Tag 1');
      t.c.toggleTag('Tag 2');
      t.c.toggleTag('Tag 3');
      expect(t.c.selectedTags, ['Tag 1', 'Tag 2', 'Tag 3']);

      t.c.toggleTag('Tag 4'); // 4th tag rejected
      expect(t.c.selectedTags, hasLength(3));
      expect(t.c.formError.value, isNotEmpty);

      t.c.toggleTag('Tag 2'); // deselect works
      expect(t.c.selectedTags, ['Tag 1', 'Tag 3']);

      t.c.setCategory('Electrical');
      expect(t.c.selectedTags, isEmpty);
    });
  });

  group('submit (create)', () {
    test(
      'validates missing room, category, and DTO rules before network',
      () async {
        final t = setup();
        expect(await t.c.submit(), false);
        expect(t.c.formError.value, isNotEmpty);

        t.c.selectRoom(
          const RoomModel(id: 'room1', buildingId: 'b1', roomNumber: 'T-101'),
        );
        expect(await t.c.submit(), false);
        expect(t.c.formError.value, isNotEmpty);

        // 'Other' requires a description (tags alone fail DTO validation)
        t.c.setCategory('Other');
        t.c.toggleTag('Misc');
        expect(await t.c.submit(), false);
        expect(t.c.formError.value, isNotEmpty);
        expect(t.b.count('POST /rest/v1/reports'), 0);
      },
    );

    test('creates report and uploads picked photo', () async {
      final t = setup();
      t.c.selectRoom(
        const RoomModel(id: 'room1', buildingId: 'b1', roomNumber: 'T-101'),
      );
      t.c.setCategory('AC');
      t.c.toggleTag('Not Cooling');
      t.picker.nextBytes = fakeJpeg;
      await t.c.pickPhoto(ImageSource.gallery);

      expect(await t.c.submit(), true);
      expect(t.b.count('POST /rest/v1/reports'), 1);
      expect(t.store.ops, hasLength(1));
      expect(t.c.warningMessage.value, '');
    });

    test(
      'non-atomic photo failure still returns true and sets warningMessage',
      () async {
        final t = setup();
        t.c.selectRoom(
          const RoomModel(id: 'room1', buildingId: 'b1', roomNumber: 'T-101'),
        );
        t.c.setCategory('AC');
        t.c.toggleTag('Not Cooling');
        t.picker.nextBytes = fakeJpeg;
        await t.c.pickPhoto(ImageSource.camera);
        t.store.failUpload = true;

        expect(await t.c.submit(), true);
        expect(t.b.count('POST /rest/v1/reports'), 1);
        expect(t.c.warningMessage.value, contains('Bucket offline'));
      },
    );

    test(
      'double tap: second submit is ignored while first is running',
      () async {
        final t = setup();
        t.c.selectRoom(
          const RoomModel(id: 'room1', buildingId: 'b1', roomNumber: 'T-101'),
        );
        t.c.setCategory('AC');
        t.c.toggleTag('Not Cooling');
        t.b.writeGate = Completer<void>();

        final first = t.c.submit();
        final second = await t.c.submit();
        expect(second, false);

        t.b.writeGate!.complete();
        expect(await first, true);
        expect(t.b.count('POST /rest/v1/reports'), 1);
      },
    );
  });

  group('submit (edit)', () {
    test(
      'updates text and replaces existing photo when new photo picked',
      () async {
        final existing = ReportModel.fromJson(
          reportJson(photo: 'u1/r1/old.jpg'),
        );
        final t = setup(initialReport: existing);
        await t.c.load();

        t.c.setDescription('Updated description');
        t.picker.nextBytes = fakeJpeg;
        await t.c.pickPhoto(ImageSource.gallery);

        expect(await t.c.submit(), true);
        expect(
          t.b.count('PATCH /rest/v1/reports'),
          2,
        ); // 1 text PATCH + 1 photo_path PATCH
        expect(t.store.ops.any((op) => op.startsWith('upload:')), true);
        expect(t.store.ops, contains('remove:u1/r1/old.jpg'));
        expect(t.c.warningMessage.value, '');
      },
    );

    test(
      'removes existing photo when clearPickedPhoto called on saved photo',
      () async {
        final existing = ReportModel.fromJson(
          reportJson(photo: 'u1/r1/old.jpg'),
        );
        final t = setup(initialReport: existing);
        await t.c.load();

        t.c.clearPickedPhoto();
        expect(t.c.removeExistingPhoto.value, true);
        expect(t.c.hasExistingPhoto, false);

        expect(await t.c.submit(), true);
        expect(t.store.ops, contains('remove:u1/r1/old.jpg'));
        expect(t.c.warningMessage.value, '');
      },
    );

    test('partial failure in edit (text saved, photo upload failed) returns true with warning', () async {
      final existing = ReportModel.fromJson(reportJson(photo: 'u1/r1/old.jpg'));
      final t = setup(initialReport: existing);
      await t.c.load();

      t.picker.nextBytes = fakeJpeg;
      await t.c.pickPhoto(ImageSource.gallery);
      t.store.failUpload = true;

      expect(await t.c.submit(), true);
      expect(t.b.count('PATCH /rest/v1/reports'), 1); // text saved
      expect(t.c.warningMessage.value, contains('Bucket offline'));
    });

    test(
      'blocked edit (NO_ROWS) returns false and explains status changed',
      () async {
        final existing = ReportModel.fromJson(reportJson());
        final t = setup(initialReport: existing);
        await t.c.load();
        t.b.patchBlocked = true;

        expect(await t.c.submit(), false);
        expect(t.c.errorMessage.value, contains('can no longer be changed'));
      },
    );
  });
}
