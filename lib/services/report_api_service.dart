import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/constants/api_constants.dart';
import '../core/errors/api_exception.dart';
import '../dtos/admin_update_report_request.dart';
import '../dtos/create_report_request.dart';
import '../dtos/update_pending_report_request.dart';
import '../models/building_model.dart';
import '../models/profile_model.dart';
import '../models/report_model.dart';
import '../models/report_status_history_model.dart';
import '../models/room_model.dart';

typedef TokenProvider = Future<String?> Function();

/// Thin REST client over Supabase PostgREST. Pure Dart (no Flutter/Supabase imports)
/// so it can be unit-tested with MockClient and run from `dart run`.
class ReportApiService {
  static const _reportSelect = '*,rooms(id,room_number,buildings(id,name))';
  static const _timeout = Duration(seconds: 15);

  final http.Client _client;
  final TokenProvider _getToken;
  final TokenProvider? _refreshToken;
  final String _baseUrl;
  final String _apiKey;

  ReportApiService({
    required TokenProvider getToken,
    TokenProvider? refreshToken,
    http.Client? client,
    String? baseUrl,
    String? apiKey,
  })  : _getToken = getToken,
        _refreshToken = refreshToken,
        _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConstants.restBase,
        _apiKey = apiKey ?? ApiConstants.supabaseKey;

  // ---------------------------------------------------------------- reads

  /// Students get only their own rows, admins get all (enforced by RLS, not here).
  Future<List<ReportModel>> listReports({String? status, int limit = 20, int offset = 0}) async {
    final res = await _request('GET', '/reports', query: {
      'select': _reportSelect,
      'order': 'created_at.desc',
      'limit': '$limit',
      'offset': '$offset',
      if (status != null) 'status': 'eq.$status',
    });
    return _list(res).map(ReportModel.fromJson).toList();
  }

  Future<ReportModel> getReport(String id) async {
    final res = await _request('GET', '/reports',
        query: {'select': _reportSelect, 'id': 'eq.$id', 'limit': '1'});
    final rows = _list(res);
    if (rows.isEmpty) throw ApiException.notFound();
    return ReportModel.fromJson(rows.first);
  }

  Future<List<ReportStatusHistoryModel>> listHistory(String reportId) async {
    final res = await _request('GET', '/report_status_history', query: {
      'select': '*',
      'report_id': 'eq.$reportId',
      'order': 'created_at.asc',
    });
    return _list(res).map(ReportStatusHistoryModel.fromJson).toList();
  }

  Future<List<BuildingModel>> listBuildings() async {
    final res = await _request('GET', '/buildings',
        query: {'select': 'id,name', 'order': 'name.asc'});
    return _list(res).map(BuildingModel.fromJson).toList();
  }

  Future<List<RoomModel>> listRooms(String buildingId) async {
    final res = await _request('GET', '/rooms', query: {
      'select': 'id,building_id,room_number',
      'building_id': 'eq.$buildingId',
      'order': 'room_number.asc',
    });
    return _list(res).map(RoomModel.fromJson).toList();
  }

  /// RLS: a student can read only their own profile row, an admin can read all.
  Future<ProfileModel> getProfile(String userId) async {
    final res = await _request('GET', '/profiles', query: {
      'select': 'id,full_name,student_number,role',
      'id': 'eq.$userId',
      'limit': '1',
    });
    final rows = _list(res);
    if (rows.isEmpty) throw ApiException.notFound();
    return ProfileModel.fromJson(rows.first);
  }

  // --------------------------------------------------------------- writes

  Future<ReportModel> createReport(CreateReportRequest request) async {
    final res = await _request('POST', '/reports',
        query: {'select': _reportSelect}, body: request.toJson(), representation: true);
    return ReportModel.fromJson(_list(res).first);
  }

  /// PATCH. A blocked update returns 200 with [] (RLS filtered the row out),
  /// which is why we ask for the representation and treat empty as failure.
  Future<ReportModel> updatePendingReport(String id, UpdatePendingReportRequest request) async {
    final res = await _request('PATCH', '/reports',
        query: {'id': 'eq.$id', 'select': _reportSelect},
        body: request.toJson(),
        representation: true);
    final rows = _list(res);
    if (rows.isEmpty) throw ApiException.noRowsAffected();
    return ReportModel.fromJson(rows.first);
  }

  /// Photo-only PATCH: does not resend the other fields. null detaches the photo.
  Future<ReportModel> setPhotoPath(String reportId, String? photoPath) async {
    final res = await _request('PATCH', '/reports',
        query: {'id': 'eq.$reportId', 'select': _reportSelect},
        body: {'photo_path': photoPath},
        representation: true);
    final rows = _list(res);
    if (rows.isEmpty) throw ApiException.noRowsAffected();
    return ReportModel.fromJson(rows.first);
  }

  /// Returns the deleted row so the caller can remove its photo from Storage.
  Future<ReportModel> deleteReport(String id) async {
    final res = await _request('DELETE', '/reports',
        query: {'id': 'eq.$id', 'select': '*'}, representation: true);
    final rows = _list(res);
    if (rows.isEmpty) throw ApiException.noRowsAffected();
    return ReportModel.fromJson(rows.first);
  }

  /// Admin triage. The only legal way to change status/priority/notes.
  Future<ReportModel> adminUpdateReport(AdminUpdateReportRequest request) async {
    final res = await _request('POST', '/rpc/admin_update_report', body: request.toJson());
    return ReportModel.fromJson(_object(res));
  }

  // ------------------------------------------------------------- plumbing

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool representation = false,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);

    Future<http.Response> send(String token) async {
      final req = http.Request(method, uri)
        ..headers.addAll({
          'apikey': _apiKey,
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          if (representation) 'Prefer': 'return=representation',
        });
      if (body != null) req.body = jsonEncode(body);
      return http.Response.fromStream(await _client.send(req));
    }

    try {
      final token = await _getToken();
      if (token == null) {
        throw const ApiException(statusCode: 401, technicalMessage: 'No active session');
      }
      var res = await send(token).timeout(_timeout);

      final refresh = _refreshToken;
      if (res.statusCode == 401 && refresh != null) {
        final fresh = await refresh(); // one refresh + one retry, never a loop
        if (fresh != null) res = await send(fresh).timeout(_timeout);
      }

      if (res.statusCode >= 200 && res.statusCode < 300) return res;
      throw ApiException.fromResponse(res);
    } on ApiException {
      rethrow;
    } on TimeoutException catch (e) {
      throw ApiException.network(e);
    } on http.ClientException catch (e) {
      throw ApiException.network(e);
    }
  }

  List<Map<String, dynamic>> _list(http.Response r) =>
      (jsonDecode(utf8.decode(r.bodyBytes)) as List<dynamic>).cast<Map<String, dynamic>>();

  Map<String, dynamic> _object(http.Response r) =>
      jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
}
