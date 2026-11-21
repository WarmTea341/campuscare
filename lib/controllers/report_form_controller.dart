import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/api_exception.dart';
import '../dtos/create_report_request.dart';
import '../dtos/update_pending_report_request.dart';
import '../models/building_model.dart';
import '../models/report_model.dart';
import '../models/room_model.dart';
import '../services/photo_picker_service.dart';
import '../services/photo_store.dart';
import '../services/report_api_service.dart';
import '../services/report_photo_workflow.dart';

/// One form for BOTH create and edit. [initialReport] == null -> create.
/// Edit is only valid while initialReport.isPending.
class ReportFormController extends GetxController {
  ReportFormController({
    required this.api,
    required this.photos,
    required this.picker,
    this.initialReport,
  });

  static const _unexpected = 'Something went wrong. Please try again.';

  final ReportApiService api;
  final ReportPhotoWorkflow photos;
  final PhotoPickerService picker;
  final ReportModel? initialReport;

  bool get isEditing => initialReport != null;

  // ---- form state (widgets read these inside Obx) ----
  final RxList<BuildingModel> buildings = <BuildingModel>[].obs;
  final RxList<RoomModel> rooms = <RoomModel>[].obs;
  final Rxn<BuildingModel> selectedBuilding = Rxn<BuildingModel>();
  final Rxn<RoomModel> selectedRoom = Rxn<RoomModel>();
  final RxnString category = RxnString();
  final RxList<String> selectedTags = <String>[].obs;
  final RxString description = ''.obs;

  /// Picked this session, not uploaded yet.
  final Rxn<Uint8List> newPhoto = Rxn<Uint8List>();

  /// Edit mode only: user chose to remove the photo that is already saved.
  final RxBool removeExistingPhoto = false.obs;

  // ---- status ----
  final RxBool isLoading = false.obs; // loading buildings/rooms
  final RxBool isSubmitting = false.obs; // guards double taps

  /// Inline validation message from request.validate(), '' = none.
  final RxString formError = ''.obs;

  /// Load/submit failure, user-safe, '' = none.
  final RxString errorMessage = ''.obs;

  /// Set when the REPORT saved but its photo did not. submit() still returns true.
  final RxString warningMessage = ''.obs;

  int _roomGeneration = 0;

  /// Quick-tag chips for the current category.
  List<String> get quickTagOptions =>
      ReportCategory.quickTags[category.value] ?? const [];

  /// True in edit mode when the report already has a saved photo that hasn't been
  /// replaced or marked for removal.
  bool get hasExistingPhoto =>
      isEditing &&
      initialReport?.photoPath != null &&
      !removeExistingPhoto.value &&
      newPhoto.value == null;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Called by the controller in onInit. In edit mode, prefill from initialReport.
  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final loadedBuildings = await api.listBuildings();
      buildings.assignAll(loadedBuildings);

      final existing = initialReport;
      if (existing != null) {
        category.value = existing.category;
        selectedTags.assignAll(existing.issueDetails);
        description.value = existing.description ?? '';

        BuildingModel? matchedBuilding;
        for (final b in loadedBuildings) {
          if (b.name == existing.buildingName) {
            matchedBuilding = b;
            break;
          }
        }

        if (matchedBuilding != null) {
          selectedBuilding.value = matchedBuilding;
          final loadedRooms = await api.listRooms(matchedBuilding.id);
          rooms.assignAll(loadedRooms);
          for (final r in loadedRooms) {
            if (r.id == existing.roomId) {
              selectedRoom.value = r;
              break;
            }
          }
        }
      }
    } on ApiException catch (e) {
      errorMessage.value = e.userMessage;
    } catch (e) {
      debugPrint('form load failed: $e');
      errorMessage.value = _unexpected;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> selectBuilding(BuildingModel? building) async {
    if (building != null && building.id == selectedBuilding.value?.id) return;
    selectedBuilding.value = building;
    selectedRoom.value = null;
    rooms.clear();
    formError.value = '';

    final gen = ++_roomGeneration;
    if (building == null) {
      isLoading.value = false;
      return;
    }

    isLoading.value = true;
    errorMessage.value = '';
    try {
      final loadedRooms = await api.listRooms(building.id);
      if (gen != _roomGeneration) return;
      rooms.assignAll(loadedRooms);
    } on ApiException catch (e) {
      if (gen == _roomGeneration) errorMessage.value = e.userMessage;
    } catch (e) {
      debugPrint('listRooms failed: $e');
      if (gen == _roomGeneration) errorMessage.value = _unexpected;
    } finally {
      if (gen == _roomGeneration) isLoading.value = false;
    }
  }

  void selectRoom(RoomModel? room) {
    selectedRoom.value = room;
    formError.value = '';
  }

  /// Changing category clears selectedTags.
  void setCategory(String? value) {
    if (category.value == value) return;
    category.value = value;
    selectedTags.clear();
    formError.value = '';
  }

  /// Max 3 tags (DB constraint).
  void toggleTag(String tag) {
    formError.value = '';
    if (selectedTags.contains(tag)) {
      selectedTags.remove(tag);
    } else if (selectedTags.length < 3) {
      selectedTags.add(tag);
    } else {
      formError.value = 'You can select up to 3 issue tags.';
    }
  }

  void setDescription(String value) {
    description.value = value;
    if (formError.value.isNotEmpty) formError.value = '';
  }

  Future<void> pickPhoto(ImageSource source) async {
    errorMessage.value = '';
    try {
      final bytes = await picker.pick(source);
      if (bytes != null) {
        newPhoto.value = bytes;
        removeExistingPhoto.value = false;
      }
    } on PhotoException catch (e) {
      errorMessage.value = e.message;
    } catch (e) {
      debugPrint('pickPhoto failed: $e');
      errorMessage.value = _unexpected;
    }
  }

  /// Clears a newly picked photo; if none is picked in edit mode, marks the
  /// existing saved photo for removal.
  void clearPickedPhoto() {
    if (newPhoto.value != null) {
      newPhoto.value = null;
    } else if (isEditing && initialReport?.photoPath != null) {
      removeExistingPhoto.value = true;
    }
  }

  void undoRemoveExistingPhoto() {
    removeExistingPhoto.value = false;
  }

  /// true = the REPORT was saved (create or edit). Check [warningMessage] for photo problems.
  /// Create: photos.submitReport. Edit: updatePendingReport, then replacePhoto/removePhoto.
  Future<bool> submit() async {
    if (isSubmitting.value) return false;
    formError.value = '';
    errorMessage.value = '';
    warningMessage.value = '';

    final room = selectedRoom.value;
    if (room == null) {
      formError.value = 'Select a building and room.';
      return false;
    }

    final cat = category.value;
    if (cat == null || cat.isEmpty) {
      formError.value = 'Select a category.';
      return false;
    }

    if (!isEditing) {
      return _submitCreate(room.id, cat);
    }
    return _submitEdit(initialReport!, room.id, cat);
  }

  Future<bool> _submitCreate(String roomId, String cat) async {
    final request = CreateReportRequest(
      roomId: roomId,
      category: cat,
      issueDetails: selectedTags.toList(),
      description: description.value,
    );
    final invalid = request.validate();
    if (invalid != null) {
      formError.value = invalid;
      return false;
    }

    isSubmitting.value = true;
    try {
      final result = await photos.submitReport(request, photo: newPhoto.value);
      final photoErr = result.photoError;
      if (photoErr != null) {
        warningMessage.value = switch (photoErr) {
          PhotoException e => 'Report saved, but photo failed: ${e.message}',
          ApiException e => 'Report saved, but photo failed: ${e.userMessage}',
          _ => 'Report saved, but photo upload failed. You can retry in edit.',
        };
      }
      return true;
    } on PhotoException catch (e) {
      errorMessage.value = e.message;
    } on ApiException catch (e) {
      errorMessage.value = e.userMessage;
    } catch (e) {
      debugPrint('create submit failed: $e');
      errorMessage.value = _unexpected;
    } finally {
      isSubmitting.value = false;
    }
    return false;
  }

  Future<bool> _submitEdit(
    ReportModel existing,
    String roomId,
    String cat,
  ) async {
    if (!existing.isPending) {
      errorMessage.value = 'This report can no longer be changed.';
      return false;
    }

    final request = UpdatePendingReportRequest(
      roomId: roomId,
      category: cat,
      issueDetails: selectedTags.toList(),
      description: description.value,
    );
    final invalid = request.validate();
    if (invalid != null) {
      formError.value = invalid;
      return false;
    }

    isSubmitting.value = true;
    try {
      var updated = await api.updatePendingReport(existing.id, request);

      if (newPhoto.value != null) {
        try {
          updated = await photos.replacePhoto(updated, newPhoto.value!);
        } on PhotoException catch (e) {
          warningMessage.value =
              'Changes saved, but photo failed: ${e.message}';
        } on ApiException catch (e) {
          warningMessage.value =
              'Changes saved, but photo failed: ${e.userMessage}';
        } catch (e) {
          debugPrint('replacePhoto failed: $e');
          warningMessage.value =
              'Changes saved, but photo upload failed. You can retry later.';
        }
      } else if (removeExistingPhoto.value && updated.photoPath != null) {
        try {
          updated = await photos.removePhoto(updated);
        } on PhotoException catch (e) {
          warningMessage.value =
              'Changes saved, but removing photo failed: ${e.message}';
        } on ApiException catch (e) {
          warningMessage.value =
              'Changes saved, but removing photo failed: ${e.userMessage}';
        } catch (e) {
          debugPrint('removePhoto failed: $e');
          warningMessage.value =
              'Changes saved, but removing the old photo failed.';
        }
      }
      return true;
    } on ApiException catch (e) {
      errorMessage.value = e.userMessage;
    } catch (e) {
      debugPrint('edit submit failed: $e');
      errorMessage.value = _unexpected;
    } finally {
      isSubmitting.value = false;
    }
    return false;
  }
}
