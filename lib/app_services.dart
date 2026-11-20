import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/api_constants.dart';
import 'services/auth_service.dart';
import 'services/photo_picker_service.dart';
import 'services/report_api_service.dart';
import 'services/report_api_service_supabase.dart';
import 'services/report_photo_workflow.dart';
import 'services/supabase_auth_backend.dart';

/// Everything the UI layer needs. Register these with GetX in the UI step.
class AppServices {
  final ReportApiService api;
  final ReportPhotoWorkflow photos;
  final PhotoPickerService picker;
  final AuthService auth;

  const AppServices({
    required this.api,
    required this.photos,
    required this.picker,
    required this.auth,
  });
}

Future<AppServices> bootstrapServices() async {
  if (ApiConstants.supabaseUrl.isEmpty || ApiConstants.supabaseKey.isEmpty) {
    throw StateError('Missing SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY. '
        'Run with: flutter run --dart-define-from-file=env.json (env.json must be valid JSON).');
  }
  await Supabase.initialize(url: ApiConstants.supabaseUrl, anonKey: ApiConstants.supabaseKey);

  final api = createSupabaseReportApi();
  return AppServices(
    api: api,
    photos: ReportPhotoWorkflow(api: api, store: createSupabasePhotoStore()),
    picker: PhotoPickerService(),
    auth: AuthService(backend: SupabaseAuthBackend(), api: api),
  );
}
