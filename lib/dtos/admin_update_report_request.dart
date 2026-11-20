import '../core/constants/app_constants.dart';

class AdminUpdateReportRequest {
  final String reportId;
  final String newStatus;
  final String? priority; // omit to keep the current priority
  final String? adminNotes;

  const AdminUpdateReportRequest({
    required this.reportId,
    required this.newStatus,
    this.priority,
    this.adminNotes,
  });

  String? validate() {
    if (!ReportStatus.all.contains(newStatus)) return 'Invalid status.';
    if (priority != null && !ReportPriority.all.contains(priority)) {
      return 'Invalid priority.';
    }
    if ((adminNotes?.trim().length ?? 0) > 1000) return 'Note is too long (max 1000).';
    return null;
  }

  /// Keys match the admin_update_report RPC parameter names.
  Map<String, dynamic> toJson() {
    final n = adminNotes?.trim();
    return {
      'p_report_id': reportId,
      'p_new_status': newStatus,
      if (priority != null) 'p_priority': priority,
      if (n != null && n.isNotEmpty) 'p_admin_notes': n,
    };
  }
}
