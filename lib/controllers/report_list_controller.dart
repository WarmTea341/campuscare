import 'package:get/get.dart';

import '../models/report_model.dart';
import '../services/report_api_service.dart';

/// Used by both home screens. RLS decides what each role sees.
class ReportListController extends GetxController {
  ReportListController(this.api);

  final ReportApiService api;

  final RxList<ReportModel> reports = <ReportModel>[].obs;

  /// null = all statuses.
  final RxnString statusFilter = RxnString();

  final RxBool isLoading = false.obs; // first page / reload
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = true.obs;
  final RxString errorMessage = ''.obs;

  /// First page. Called by the controller itself in onInit (widgets don't call it).
  Future<void> load() async {
    // TODO(controllers owner): api.listReports(status: statusFilter.value, limit: 20, offset: 0)
  }

  /// Pull-to-refresh.
  Future<void> reload() async {
    // TODO(controllers owner)
  }

  Future<void> loadMore() async {
    // TODO(controllers owner): next page using reports.length as the offset
  }

  Future<void> setFilter(String? status) async {
    // TODO(controllers owner): set statusFilter, then reload
  }
}
