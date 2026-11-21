import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app_services.dart';
import 'controllers/auth_controller.dart';
import 'routes/app_pages.dart';
import 'routes/app_routes.dart';
import 'views/splash_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BootApp());
}

/// Paints the splash immediately while Supabase initialises (no blank screen),
/// registers the services, then swaps in the real app.
class BootApp extends StatefulWidget {
  const BootApp({super.key});

  @override
  State<BootApp> createState() => _BootAppState();
}

class _BootAppState extends State<BootApp> {
  late final Future<void> _boot = _bootstrap();

  Future<void> _bootstrap() async {
    final services = await bootstrapServices();
    Get.put<AppServices>(services, permanent: true);
    Get.put<AuthController>(AuthController(services.auth), permanent: true);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _boot,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Startup failed:\n${snapshot.error}'),
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(home: SplashView());
        }
        return const CampusCareApp();
      },
    );
  }
}

class CampusCareApp extends StatefulWidget {
  const CampusCareApp({super.key});

  @override
  State<CampusCareApp> createState() => _CampusCareAppState();
}

class _CampusCareAppState extends State<CampusCareApp> {
  @override
  void initState() {
    super.initState();
    // After the first frame the navigator exists, so restore() may navigate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.find<AuthController>().restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'CampusCare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      initialRoute: Routes.splash,
      getPages: AppPages.pages,
    );
  }
}
