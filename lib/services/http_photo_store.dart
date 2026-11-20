import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import '../core/constants/api_constants.dart';
import '../core/errors/api_exception.dart';
import 'photo_store.dart';
import 'report_api_service.dart' show TokenProvider;

/// Supabase Storage over plain REST (pure Dart, so the live smoke test can run it).
class HttpPhotoStore implements PhotoStore {
  static const bucket = 'report-photos';
  static const _timeout = Duration(seconds: 30); // uploads are slower than JSON calls

  final http.Client _client;
  final TokenProvider _getToken;
  final TokenProvider? _refreshToken;
  final String _supabaseUrl;
  final String _apiKey;

  HttpPhotoStore({
    required this._getToken,
    this._refreshToken,
    http.Client? client,
    String? supabaseUrl,
    String? apiKey,
  })  : _client = client ?? http.Client(),
        _supabaseUrl = supabaseUrl ?? ApiConstants.supabaseUrl,
        _apiKey = apiKey ?? ApiConstants.supabaseKey;

  String get _storage => '$_supabaseUrl/storage/v1';

  String _encode(String path) => path.split('/').map(Uri.encodeComponent).join('/');

  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) async {
    await _send('POST', Uri.parse('$_storage/object/$bucket/${_encode(path)}'),
        body: bytes, headers: {'Content-Type': contentType, 'x-upsert': 'false'});
  }

  @override
  Future<bool> remove(String path) async {
    final res = await _send('DELETE', Uri.parse('$_storage/object/$bucket'),
        body: Uint8List.fromList(utf8.encode(jsonEncode({'prefixes': [path]}))),
        headers: {'Content-Type': 'application/json'});
    final deleted = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return deleted.isNotEmpty;
  }

  @override
  Future<String> signedUrl(String path, {int expiresInSeconds = 3600}) async {
    final res = await _send('POST', Uri.parse('$_storage/object/sign/$bucket/${_encode(path)}'),
        body: Uint8List.fromList(utf8.encode(jsonEncode({'expiresIn': expiresInSeconds}))),
        headers: {'Content-Type': 'application/json'});
    final signed =
        (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['signedURL'] as String;
    // Storage versions differ: some return "/object/sign/...", others "/storage/v1/object/sign/...".
    return signed.startsWith('/storage/v1') ? '$_supabaseUrl$signed' : '$_storage$signed';
  }

  Future<http.Response> _send(String method, Uri uri,
      {required Uint8List body, required Map<String, String> headers}) async {
    Future<http.Response> attempt(String token) async {
      final req = http.Request(method, uri)
        ..headers.addAll({'apikey': _apiKey, 'Authorization': 'Bearer $token', ...headers})
        ..bodyBytes = body;
      return http.Response.fromStream(await _client.send(req));
    }

    try {
      final token = await _getToken();
      if (token == null) {
        throw const ApiException(statusCode: 401, technicalMessage: 'No active session');
      }
      var res = await attempt(token).timeout(_timeout);

      final refresh = _refreshToken;
      if (res.statusCode == 401 && refresh != null) {
        final fresh = await refresh(); // one refresh + one retry, never a loop
        if (fresh != null) res = await attempt(fresh).timeout(_timeout);
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
}
