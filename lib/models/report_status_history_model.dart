class ReportStatusHistoryModel {
  final int id;
  final String reportId;
  final String? oldStatus; // null for the initial "submitted" event
  final String newStatus;
  final String? changedBy; // null = maintenance change
  final String? notes;
  final DateTime createdAt;

  const ReportStatusHistoryModel({
    required this.id,
    required this.reportId,
    this.oldStatus,
    required this.newStatus,
    this.changedBy,
    this.notes,
    required this.createdAt,
  });

  factory ReportStatusHistoryModel.fromJson(Map<String, dynamic> json) =>
      ReportStatusHistoryModel(
        id: json['id'] as int,
        reportId: json['report_id'] as String,
        oldStatus: json['old_status'] as String?,
        newStatus: json['new_status'] as String,
        changedBy: json['changed_by'] as String?,
        notes: json['notes'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}
