import 'package:get/get.dart';

import '../models/report_model.dart';
import '../models/report_status_history_model.dart';
import '../services/report_api_service.dart';
import '../services/report_photo_workflow.dart';

/// Detail screen for both roles. [isAdmin] only decides which actions are offered.
class ReportDetailController extends GetxController {
  ReportDetailController({
    required this.api,
    required this.photos,
    required this.reportId,
    required this.isAdmin,
  });

  final ReportApiService api;
  final ReportPhotoWorkflow photos;
  final String reportId;
  final bool isAdmin;

  final Rxn<ReportModel> report = Rxn<ReportModel>();
  final RxList<ReportStatusHistoryModel> history = <ReportStatusHistoryModel>[].obs;

  /// Temporary signed URL for the photo, null = no photo.
  final RxnString photoUrl = RxnString();

  final RxBool isLoading = false.obs;
  final RxBool isBusy = false.obs; // a delete / triage is running
  final RxString errorMessage = ''.obs;

  /// Student may edit/delete only while Pending. (UI hint; the database enforces it.)
  bool get canEditOrDelete => !isAdmin && (report.value?.isPending ?? false);

  /// The only status an admin may move to next (null = already Resolved).
  /// TODO: ReportStatus.next(report.value!.status)
  String? get nextStatus => null;

  /// Fetch report + history + photo URL. Called by the controller in onInit.
  Future<void> load() async {
    // TODO(controllers owner): api.getReport, api.listHistory, photos.photoUrl
  }

  /// true = deleted (the widget then calls Get.back()).
  Future<bool> deleteReport() async {
    // TODO(controllers owner): photos.deleteReport(report.value!)
    return false;
  }

  /// Advance to [nextStatus]. Priority is required when moving to Verified.
  /// true = saved. Must re-fetch with getReport afterwards (the RPC result has no embeds).
  Future<bool> triage({String? priority, String? notes}) async {
    // TODO(controllers owner): validate(), api.adminUpdateReport, then load()
    return false;
  }
}
