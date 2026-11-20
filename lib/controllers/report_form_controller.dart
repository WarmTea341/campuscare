import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../models/building_model.dart';
import '../models/report_model.dart';
import '../models/room_model.dart';
import '../services/photo_picker_service.dart';
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

  /// Quick-tag chips for the current category.
  List<String> get quickTagOptions => const []; // TODO: ReportCategory.quickTags[category.value]

  /// Called by the controller in onInit. In edit mode, prefill from initialReport.
  Future<void> load() async {
    // TODO(controllers owner): api.listBuildings(); prefill when isEditing
  }

  Future<void> selectBuilding(BuildingModel? building) async {
    // TODO(controllers owner): clear selectedRoom, api.listRooms(building.id)
  }

  void selectRoom(RoomModel? room) {
    // TODO(controllers owner)
  }

  /// Changing category clears selectedTags.
  void setCategory(String? value) {
    // TODO(controllers owner)
  }

  /// Max 3 tags (DB constraint).
  void toggleTag(String tag) {
    // TODO(controllers owner)
  }

  void setDescription(String value) {
    // TODO(controllers owner)
  }

  Future<void> pickPhoto(ImageSource source) async {
    // TODO(controllers owner): picker.pick -> newPhoto; PhotoException -> errorMessage
  }

  void clearPickedPhoto() {
    // TODO(controllers owner)
  }

  /// true = the REPORT was saved (create or edit). Check [warningMessage] for photo problems.
  /// Create: photos.submitReport. Edit: updatePendingReport, then replacePhoto/removePhoto.
  Future<bool> submit() async {
    // TODO(controllers owner): validate() first; guard with isSubmitting
    return false;
  }
}
