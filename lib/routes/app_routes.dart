/// Route names. Owner: whoever owns controllers + routing.
/// Pages (GetPage list) are registered in app_pages.dart once the views exist.
abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const studentHome = '/student';
  static const adminHome = '/admin';

  /// arguments: ReportModel? (null = create a new report, non-null = edit that Pending report)
  static const reportForm = '/report/form';

  /// arguments: String reportId
  static const reportDetail = '/report/detail';
}
