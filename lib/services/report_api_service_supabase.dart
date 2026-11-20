import 'package:supabase_flutter/supabase_flutter.dart';

import 'http_photo_store.dart';
import 'report_api_service.dart';
import 'report_photo_workflow.dart';

/// Wiring between the pure-Dart services and the Supabase session.
/// Call after `await Supabase.initialize(url: ..., anonKey: ...)` in main().
Future<String?> _currentToken() async => Supabase.instance.client.auth.currentSession?.accessToken;

Future<String?> _refreshedToken() async {
  try {
    final r = await Supabase.instance.client.auth.refreshSession();
    return r.session?.accessToken;
  } catch (_) {
    return null;
  }
}

ReportApiService createSupabaseReportApi() =>
    ReportApiService(getToken: _currentToken, refreshToken: _refreshedToken);

HttpPhotoStore createSupabasePhotoStore() =>
    HttpPhotoStore(getToken: _currentToken, refreshToken: _refreshedToken);

ReportPhotoWorkflow createReportPhotoWorkflow() => ReportPhotoWorkflow(
    api: createSupabaseReportApi(), store: createSupabasePhotoStore());
