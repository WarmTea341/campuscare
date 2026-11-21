import 'package:get/get.dart';

import '../app_services.dart';
import '../controllers/auth_controller.dart';
import '../controllers/report_detail_controller.dart';
import '../controllers/report_form_controller.dart';
import '../controllers/report_list_controller.dart';
import '../models/report_model.dart';
import '../views/admin_home_view.dart';
import '../views/login_view.dart';
import '../views/report_detail_view.dart';
import '../views/report_form_view.dart';
import '../views/splash_view.dart';
import '../views/student_home_view.dart';
import 'app_routes.dart';

/// Owner: controllers/routing owner. A controller is created when its route opens
/// and disposed when the route is popped.
abstract final class AppPages {
  static void _listBinding() {
    Get.put(ReportListController(Get.find<AppServices>().api));
  }

  static final pages = <GetPage<dynamic>>[
    GetPage(name: Routes.splash, page: () => const SplashView()),
    GetPage(name: Routes.login, page: () => const LoginView()),
    GetPage(
      name: Routes.studentHome,
      page: () => const StudentHomeView(),
      binding: BindingsBuilder(_listBinding),
    ),
    GetPage(
      name: Routes.adminHome,
      page: () => const AdminHomeView(),
      binding: BindingsBuilder(_listBinding),
    ),
    GetPage(
      name: Routes.reportForm,
      page: () => const ReportFormView(),
      binding: BindingsBuilder(() {
        final s = Get.find<AppServices>();
        Get.put(ReportFormController(
          api: s.api,
          photos: s.photos,
          picker: s.picker,
          initialReport: Get.arguments as ReportModel?, // null = create
        ));
      }),
    ),
    GetPage(
      name: Routes.reportDetail,
      page: () => const ReportDetailView(),
      binding: BindingsBuilder(() {
        final s = Get.find<AppServices>();
        Get.put(ReportDetailController(
          api: s.api,
          photos: s.photos,
          reportId: Get.arguments as String,
          isAdmin: Get.find<AuthController>().isAdmin,
        ));
      }),
    ),
  ];
}
