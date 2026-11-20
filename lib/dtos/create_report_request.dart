import '../core/utils/validators.dart';

class CreateReportRequest {
  final String roomId;
  final String category;
  final List<String> issueDetails;
  final String? description;

  const CreateReportRequest({
    required this.roomId,
    required this.category,
    required this.issueDetails,
    this.description,
  });

  String? validate() => validateReportContent(
      category: category, issueDetails: issueDetails, description: description);

  /// Only the four fields students may send. Blank description becomes null.
  Map<String, dynamic> toJson() {
    final d = description?.trim();
    return {
      'room_id': roomId,
      'category': category,
      'issue_details': issueDetails,
      'description': (d == null || d.isEmpty) ? null : d,
    };
  }
}
