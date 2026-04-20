// lib/services/api_service.dart
//
// All HTTP calls to journal.williamthomas.name.
// Uses Dio + CookieManager so the HttpOnly refresh_token cookie is handled
// exactly like the web app — no backend changes required.

import 'package:flutter/foundation.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static const String baseUrl = 'https://journal.williamthomas.name';

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;
  late final CookieJar _cookieJar;
  final _storage = const FlutterSecureStorage();

  String? _accessToken;

  ApiService._internal() {
    _cookieJar = CookieJar();
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      contentType: 'application/json',
      headers: {'Accept': 'application/json'},
    ));

    _dio.interceptors.add(CookieManager(_cookieJar));
    // Inject auth header on every request
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_accessToken != null) {
          options.headers['Authorization'] = 'Bearer $_accessToken';
        }
        return handler.next(options);
      },
    ));
    _dio.interceptors.add(_AuthInterceptor(this));
  }

  // ── Token management ──────────────────────────────────────────

  void setAccessToken(String token) {
    _accessToken = token;
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    await _cookieJar.deleteAll();
    await _storage.delete(key: 'username');
  }

  String? get accessToken => _accessToken;
  bool get isAuthenticated => _accessToken != null;

  // ── Auth ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await _dio.post('/auth/login', data: {
      'username': username,
      'password': password,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verify2FA(String partialToken, String code) async {
    final res = await _dio.post('/auth/2fa/verify-login', data: {
      'partial_token': partialToken,
      'totp_code': code,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } catch (_) {}
    await clearTokens();
  }

  Future<String?> refreshAccessToken() async {
    try {
      // Cookie jar automatically sends the refresh_token cookie
      final res = await _dio.post('/auth/refresh');
      return (res.data as Map<String, dynamic>)['access_token'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getMe() async {
    final res = await _authedGet('/auth/me');
    return res.data as Map<String, dynamic>;
  }

  // ── Today / Daily brief ───────────────────────────────────────

  Future<Map<String, dynamic>> getTodayBrief() async {
    final res = await _authedGet('/api/today');
    return res.data as Map<String, dynamic>;
  }

  // ── Entries / Timeline ────────────────────────────────────────

  Future<List<dynamic>> getTimeline({int page = 1, int limit = 20}) async {
    final res = await _authedGet('/api/entries', queryParameters: {
      'page': page,
      'limit': limit,
    });
    return (res.data as Map<String, dynamic>)['entries'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> getEntry(int entryId) async {
    final res = await _authedGet('/api/entries/$entryId');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createEntry({
    required String text,
    String? entryDate,
  }) async {
    final res = await _authedPost('/api/journal/write', data: {
      'text': text,
      if (entryDate != null) 'entry_date': entryDate,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateEntry(int entryId, String text) async {
    final res = await _authedPut('/api/entries/$entryId', data: {'text': text});
    return res.data as Map<String, dynamic>;
  }

  Future<void> deleteEntry(int entryId) async {
    await _authedDelete('/api/entries/$entryId');
  }

  // ── AI Reflections ────────────────────────────────────────────

  Future<Map<String, dynamic>> getReflection(int entryId, {String tone = 'therapist'}) async {
    final res = await _authedPost('/api/reflect/$entryId', data: {'tone': tone});
    return res.data as Map<String, dynamic>;
  }

  // ── Ask My Journal (RAG) ──────────────────────────────────────

  Future<Map<String, dynamic>> askJournal(String question) async {
    final res = await _authedPost('/api/journal/ask', data: {'query': question});
    return res.data as Map<String, dynamic>;
  }

  // ── Therapist Insight (used as "Living Summary" on Timeline) ────
  // GET /api/therapist/insight/status?tone=therapist
  // Returns: { insight, generated_at, entry_count, entry_date,
  //            tone, tone_name, cached, input_tokens, output_tokens }
  // Returns {} if no insight has been generated yet for that tone.

  Future<Map<String, dynamic>> getTherapistInsightStatus({String tone = 'therapist'}) async {
    final res = await _authedGet('/api/therapist/insight/status', queryParameters: {'tone': tone});
    return res.data as Map<String, dynamic>;
  }

  // POST /api/therapist/insight — generates (or returns cached) insight
  // Body: { tone, force? }
  Future<Map<String, dynamic>> generateTherapistInsight({String tone = 'therapist', bool force = false}) async {
    final res = await _authedPost('/api/therapist/insight', data: {'tone': tone, 'force': force});
    return res.data as Map<String, dynamic>;
  }

  // ── Settings ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> getUserSettings() async {
    final res = await _authedGet('/api/settings');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateUserSettings(Map<String, dynamic> updates) async {
    final res = await _authedPut('/api/settings', data: updates);
    return res.data as Map<String, dynamic>;
  }

  // ── Mental Health ─────────────────────────────────────────────

  Future<Map<String, dynamic>> getMentalHealthData() async {
    final res = await _authedGet('/api/mental-health/dashboard');
    return res.data as Map<String, dynamic>;
  }

  // ── Passkey ───────────────────────────────────────────────────────────────
 
  Future<Map<String, dynamic>> passkeyAuthBegin() async {
    final res = await _dio.post('/auth/passkey/authenticate-begin', data: {});
    return res.data as Map<String, dynamic>;
  }
 
  Future<Map<String, dynamic>> passkeyAuthComplete({
    required String challengeId,
    required Map<String, dynamic> credential,
  }) async {
    final res = await _dio.post('/auth/passkey/authenticate-complete', data: {
      'challenge_id': challengeId,
      'credential':   credential,
    });
    return res.data as Map<String, dynamic>;
  }
 
  // ── 2FA backup code ───────────────────────────────────────────────────────
 
  Future<Map<String, dynamic>> useBackupCode(
      String partialToken, String backupCode) async {
    final res = await _dio.post('/auth/2fa/use-backup', data: {
      'partial_token': partialToken,
      'backup_code':   backupCode,
    });
    return res.data as Map<String, dynamic>;
  }

  // ── Private helpers ───────────────────────────────────────────

  Future<Response> _authedGet(String path, {Map<String, dynamic>? queryParameters}) =>
      _dio.get(path, queryParameters: queryParameters);

  Future<Response> _authedPost(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> _authedPut(String path, {dynamic data}) =>
      _dio.put(path, data: data);

  Future<Response> _authedDelete(String path) =>
      _dio.delete(path);
}

// ── Auto-refresh interceptor ──────────────────────────────────────────────────
//
// On 401, silently refresh and retry once — mirrors the Axios interceptor
// in the web app.

class _AuthInterceptor extends Interceptor {
  final ApiService _api;
  _AuthInterceptor(this._api);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && _api._accessToken != null) {
      final newToken = await _api.refreshAccessToken();
      if (newToken != null) {
        _api.setAccessToken(newToken);
        // Retry with new token
        try {
          final opts = err.requestOptions;
          opts.headers['Authorization'] = 'Bearer $newToken';
          final res = await _api._dio.fetch(opts);
          return handler.resolve(res);
        } catch (e) {
          // ignore, fall through to clear
        }
      }
      // Refresh failed — clear tokens so app goes to login
      await _api.clearTokens();
    }
    super.onError(err, handler);
  }
}