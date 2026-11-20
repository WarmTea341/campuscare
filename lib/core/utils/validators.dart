import '../constants/app_constants.dart';

/// Client-side mirror of the database constraints (the DB remains the authority).
/// Returns an error message, or null when valid.
String? validateReportContent({
  required String category,
  required List<String> issueDetails,
  String? description,
}) {
  final desc = description?.trim() ?? '';
  if (!ReportCategory.all.contains(category)) return 'Choose a category.';
  if (issueDetails.length > 3) return 'Select at most 3 quick details.';
  if (issueDetails.join('|').length > 120) return 'Quick details are too long.';
  if (issueDetails.isEmpty && desc.isEmpty) {
    return 'Pick at least one quick detail or write a description.';
  }
  if (category == ReportCategory.other && desc.isEmpty) {
    return 'Describe the issue when the category is "Other".';
  }
  if (desc.isNotEmpty && (desc.length < 3 || desc.length > 500)) {
    return 'Description must be 3-500 characters.';
  }
  return null;
}
