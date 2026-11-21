import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/api_exception.dart';
import '../dtos/admin_update_report_request.dart';
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

  static const _unexpected = 'Something went wrong. Please try again.';

  final ReportApiService api;
  final ReportPhotoWorkflow photos;
  final String reportId;
  final bool isAdmin;

  final Rxn<ReportModel> report = Rxn<ReportModel>();
  final RxList<ReportStatusHistoryModel> history = <ReportStatusHistoryModel>[].obs;

  /// Temporary signed URL. null = no photo, OR the URL could not be created:
  /// if `report.photoPath != null && photoUrl == null` show "Photo unavailable".
  final RxnString photoUrl = RxnString();

  final RxBool isLoading = false.obs;
  final RxBool isBusy = false.obs; // a delete / triage is running

  /// '' = no error. Always a user-safe message.
  final RxString errorMessage = ''.obs;

  /// Student may edit/delete only while Pending. (UI hint; the database enforces it.)
  bool get canEditOrDelete => !isAdmin && (report.value?.isPending ?? false);

  /// The only status an admin may move to next (null = already Resolved).
  String? get nextStatus {
    final r = report.value;
    return r == null ? null : ReportStatus.next(r.status);
  }

  bool get canTriage => isAdmin && nextStatus != null;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Report + history + photo URL. Called by the controller itself (onInit),
  /// and again after any change so the screen never shows stale data.
  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final r = await api.getReport(reportId);
      final h = await api.listHistory(reportId);
      String? url;
      try {
        url = await photos.photoUrl(r);
      } catch (e) {
        debugPrint('photo url failed: $e'); // a broken photo must never hide the report
      }
      report.value = r;
      history.assignAll(h);
      photoUrl.value = url;
    } on ApiException catch (e) {
      errorMessage.value = e.userMessage;
    } catch (e) {
      debugPrint('load failed: $e');
      errorMessage.value = _unexpected;
    } finally {
      isLoading.value = false;
    }
  }

  /// true = deleted (the widget then calls Get.back(result: true) so the list reloads).
  Future<bool> deleteReport() async {
    final r = report.value;
    if (r == null || isBusy.value || !canEditOrDelete) return false;
    isBusy.value = true;
    errorMessage.value = '';
    try {
      await photos.deleteReport(r);
      return true;
    } on ApiException catch (e) {
      await _handleFailure(e);
    } catch (e) {
      debugPrint('delete failed: $e');
      errorMessage.value = _unexpected;
    } finally {
      isBusy.value = false;
    }
    return false;
  }

  /// Advance to [nextStatus]. A priority is required when moving to Verified
  /// (passed now, or already set on the report). true = saved.
  Future<bool> triage({String? priority, String? notes}) async {
    final r = report.value;
    final next = nextStatus;
    if (!isAdmin || r == null || next == null || isBusy.value) return false;

    if (next == ReportStatus.verified && priority == null && r.priority == null) {
      errorMessage.value = 'Choose a priority before verifying.';
      return false;
    }
    final request = AdminUpdateReportRequest(
      reportId: r.id,
      newStatus: next,
      priority: priority,
      adminNotes: notes,
    );
    final invalid = request.validate();
    if (invalid != null) {
      errorMessage.value = invalid;
      return false;
    }

    isBusy.value = true;
    errorMessage.value = '';
    try {
      await api.adminUpdateReport(request);
      // The RPC result has no embeds (room/building/reporter), so re-fetch everything.
      await load();
      return true;
    } on ApiException catch (e) {
      await _handleFailure(e);
    } catch (e) {
      debugPrint('triage failed: $e');
      errorMessage.value = _unexpected;
    } finally {
      isBusy.value = false;
    }
    return false;
  }

  /// "Changed under you" errors (another admin moved the status, or the report
  /// is no longer Pending): refresh the screen first, then tell the user.
  Future<void> _handleFailure(ApiException e) async {
    if (e.code == 'NO_ROWS' || e.code == '23514') await load();
    errorMessage.value = e.userMessage;
  }
}
