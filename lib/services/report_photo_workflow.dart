import 'dart:typed_data';

import '../dtos/create_report_request.dart';
import '../models/report_model.dart';
import 'photo_store.dart';
import 'report_api_service.dart';

class SubmitResult {
  final ReportModel report;

  /// Non-null when the report was saved but attaching the photo failed.
  /// The UI should say "Report submitted, photo failed - retry" instead of losing the report.
  final Object? photoError;
  const SubmitResult(this.report, {this.photoError});
}

/// Coordinates the database row and the storage object, which cannot be atomic.
/// Rules: never lose a report because of its photo; never delete evidence unless
/// the row change succeeded first; cleanup of old/orphan objects is best-effort.
class ReportPhotoWorkflow {
  final ReportApiService _api;
  final PhotoStore _store;
  final int Function() _clock;

  ReportPhotoWorkflow({
    required this._api,
    required this._store,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().microsecondsSinceEpoch);

  Future<SubmitResult> submitReport(CreateReportRequest request, {Uint8List? photo}) async {
    if (photo != null) validatePhotoBytes(photo); // reject BEFORE creating the report
    final created = await _api.createReport(request);
    if (photo == null) return SubmitResult(created);
    try {
      return SubmitResult(await _attach(created, photo));
    } catch (e) {
      return SubmitResult(created, photoError: e);
    }
  }

  /// upload new -> point the row at it -> delete old (best-effort).
  /// If the row update fails, the old photo stays and the new upload is removed.
  Future<ReportModel> replacePhoto(ReportModel report, Uint8List photo) async {
    validatePhotoBytes(photo);
    final oldPath = report.photoPath;
    final updated = await _attach(report, photo);
    if (oldPath != null) await _safeRemove(oldPath);
    return updated;
  }

  Future<ReportModel> removePhoto(ReportModel report) async {
    final oldPath = report.photoPath;
    if (oldPath == null) return report;
    final updated = await _api.setPhotoPath(report.id, null); // row first
    await _safeRemove(oldPath);
    return updated;
  }

  /// Deletes the row first; the photo is only touched if the row delete succeeded.
  Future<void> deleteReport(ReportModel report) async {
    final deleted = await _api.deleteReport(report.id);
    final path = deleted.photoPath;
    if (path != null) await _safeRemove(path);
  }

  Future<String?> photoUrl(ReportModel report) async {
    final path = report.photoPath;
    return path == null ? null : _store.signedUrl(path);
  }

  Future<ReportModel> _attach(ReportModel report, Uint8List photo) async {
    final img = validatePhotoBytes(photo);
    final path = '${report.reporterId}/${report.id}/${_clock()}.${img.extension}';
    await _store.upload(path, photo, img.contentType);
    try {
      return await _api.setPhotoPath(report.id, path);
    } catch (_) {
      await _safeRemove(path); // don't leave an orphan behind
      rethrow;
    }
  }

  Future<void> _safeRemove(String path) async {
    try {
      await _store.remove(path);
    } catch (_) {
      // best-effort cleanup; an orphan object is harmless, a failed UX is not
    }
  }
}
