import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int? statusCode; // null = no HTTP response (network failure)
  final String? code; // PostgREST / Postgres error code, e.g. 42501, 23514
  final String technicalMessage; // for logs only, never show to the user

  const ApiException({this.statusCode, this.code, required this.technicalMessage});

  factory ApiException.fromResponse(http.Response r) {
    String? code;
    var msg = r.body;
    try {
      final body = jsonDecode(r.body);
      if (body is Map<String, dynamic>) {
        code = body['code']?.toString();
        msg = body['message']?.toString() ?? msg;
      }
    } catch (_) {}
    return ApiException(statusCode: r.statusCode, code: code, technicalMessage: msg);
  }

  factory ApiException.network(Object error) =>
      ApiException(technicalMessage: error.toString());

  /// PATCH/DELETE matched no rows: blocked by RLS (e.g. report is no longer Pending) or gone.
  factory ApiException.noRowsAffected() => const ApiException(
      statusCode: 403,
      code: 'NO_ROWS',
      technicalMessage: 'Request matched no rows (blocked by RLS or already changed)');

  factory ApiException.notFound() =>
      const ApiException(statusCode: 404, code: 'P0002', technicalMessage: 'Not found');

  bool get isNetwork => statusCode == null;
  bool get isSessionExpired => statusCode == 401;
  bool get isForbidden => statusCode == 403 || code == '42501';

  String get userMessage {
    if (isNetwork) return 'No connection. Check your internet and try again.';
    if (code == 'NO_ROWS') {
      return 'This report can no longer be changed. It may already be verified or deleted.';
    }
    if (isSessionExpired) return 'Your session has expired. Please sign in again.';
    if (isForbidden) return 'You are not allowed to do that.';
    if (code == '23514') return 'That change is not valid for this report.';
    if (code == '22023') return 'Required information is missing.';
    if (code == 'P0002') return 'Report not found.';
    return 'Something went wrong. Please try again.';
  }

  @override
  String toString() => 'ApiException($statusCode, $code): $technicalMessage';
}
