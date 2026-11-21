import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/errors/api_exception.dart';
import '../models/report_model.dart';
import '../services/report_api_service.dart';

/// Used by both home screens. RLS decides what each role sees.
class ReportListController extends GetxController {
  ReportListController(this.api);

  static const pageSize = 20;
  static const _unexpected = 'Something went wrong. Please try again.';

  final ReportApiService api;

  final RxList<ReportModel> reports = <ReportModel>[].obs;

  /// null = all statuses. Values come from ReportStatus.all.
  final RxnString statusFilter = RxnString();

  final RxBool isLoading = false.obs; // first page / reload
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = true.obs;

  /// '' = no error. Always a user-safe message.
  final RxString errorMessage = ''.obs;

  /// Bumped on every first-page load. A response that finishes after a newer
  /// load/filter change started is stale and must not overwrite the list.
  int _generation = 0;

  /// Nothing to show and nothing is loading and there is no error -> "no reports yet".
  bool get isEmptyState =>
      !isLoading.value && errorMessage.value.isEmpty && reports.isEmpty;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// First page. Called by the controller itself (onInit); widgets use reload().
  Future<void> load() => _loadFirstPage();

  /// Pull-to-refresh. Also call it after returning from the form/detail screen with `true`.
  /// On failure the rows already on screen are kept and [errorMessage] is set.
  Future<void> reload() => _loadFirstPage();

  /// Call when the user scrolls near the end of the list.
  Future<void> loadMore() async {
    if (isLoading.value || isLoadingMore.value || !hasMore.value) return;
    final gen = _generation;
    isLoadingMore.value = true;
    errorMessage.value = '';
    try {
      final page = await api.listReports(
        status: statusFilter.value,
        limit: pageSize,
        offset: reports.length,
      );
      if (gen != _generation) return;
      // New reports created between page requests shift the offset: skip duplicates.
      final known = reports.map((r) => r.id).toSet();
      reports.addAll(page.where((r) => !known.contains(r.id)));
      hasMore.value = page.length == pageSize;
    } on ApiException catch (e) {
      if (gen == _generation) errorMessage.value = e.userMessage;
    } catch (e) {
      debugPrint('loadMore failed: $e');
      if (gen == _generation) errorMessage.value = _unexpected;
    } finally {
      if (gen == _generation) isLoadingMore.value = false;
    }
  }

  /// [status] null = all. Clears the list immediately so rows of the old filter never show.
  Future<void> setFilter(String? status) async {
    if (status == statusFilter.value) return;
    statusFilter.value = status;
    reports.clear();
    hasMore.value = true;
    await _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    final gen = ++_generation;
    isLoading.value = true;
    isLoadingMore.value = false; // any running loadMore is now stale
    errorMessage.value = '';
    try {
      final page = await api.listReports(
        status: statusFilter.value,
        limit: pageSize,
        offset: 0,
      );
      if (gen != _generation) return;
      reports.assignAll(page);
      hasMore.value = page.length == pageSize;
    } on ApiException catch (e) {
      if (gen == _generation) errorMessage.value = e.userMessage;
    } catch (e) {
      debugPrint('load failed: $e');
      if (gen == _generation) errorMessage.value = _unexpected;
    } finally {
      if (gen == _generation) isLoading.value = false;
    }
  }
}
