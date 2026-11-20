class ReportStatus {
  static const pending = 'Pending';
  static const verified = 'Verified';
  static const inProgress = 'In Progress';
  static const resolved = 'Resolved';
  static const all = [pending, verified, inProgress, resolved];

  /// Next valid status, or null when the report is already Resolved.
  static String? next(String current) {
    switch (current) {
      case pending:
        return verified;
      case verified:
        return inProgress;
      case inProgress:
        return resolved;
      default:
        return null;
    }
  }
}

class ReportPriority {
  static const all = ['Low', 'Medium', 'High', 'Critical'];
}

class ReportCategory {
  static const other = 'Other';
  static const all = ['AC', 'Electricity', 'Furniture', 'Wi-Fi', 'Plumbing', other];

  static const quickTags = <String, List<String>>{
    'AC': ['Not Cooling', 'Leaking Water', 'No Power', 'Making Noise'],
    'Electricity': ['No Power', 'Flickering', 'Damaged Socket'],
    'Furniture': ['Broken', 'Loose', 'Unstable'],
    'Wi-Fi': ['No Connection', 'Very Slow', 'Unstable'],
    'Plumbing': ['Water Leakage', 'Clogged', 'No Water'],
    other: <String>[],
  };
}
