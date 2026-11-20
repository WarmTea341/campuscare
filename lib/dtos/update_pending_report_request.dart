import '../core/utils/validators.dart';

class UpdatePendingReportRequest {
  final String roomId;
  final String category;
  final List<String> issueDetails;
  final String? description;

  /// photo_path is sent only when [changePhoto] is true.
  /// changePhoto=true + photoPath=null removes the photo.
  final bool changePhoto;
  final String? photoPath;

  const UpdatePendingReportRequest({
    required this.roomId,
    required this.category,
    required this.issueDetails,
    this.description,
    this.changePhoto = false,
    this.photoPath,
  });

  String? validate() => validateReportContent(
      category: category, issueDetails: issueDetails, description: description);

  Map<String, dynamic> toJson() {
    final d = description?.trim();
    final m = <String, dynamic>{
      'room_id': roomId,
      'category': category,
      'issue_details': issueDetails,
      'description': (d == null || d.isEmpty) ? null : d,
    };
    if (changePhoto) m['photo_path'] = photoPath;
    return m;
  }
}
