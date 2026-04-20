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

  // ── Registration / Onboarding ─────────────────────────────────

  Future<Map<String, dynamic>> register(
      String username, String email, String password) async {
    final res = await _dio.post('/api/register', data: {
      'username': username,
      'email': email,
      'password': password,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<void> setupSecurityQuestions({
    required String q1, required String a1,
    required String q2, required String a2,
    required String q3, required String a3,
  }) async {
    await _authedPost('/auth/security-questions/setup', data: {
      'question_1': q1, 'answer_1': a1,
      'question_2': q2, 'answer_2': a2,
      'question_3': q3, 'answer_3': a3,
    });
  }

  Future<Map<String, dynamic>> onboardingMemoryPreview(Map<String, dynamic> data) async {
    final res = await _authedPost('/api/onboarding/memory-preview', data: data);
    return res.data as Map<String, dynamic>;
  }

  Future<void> onboardingMemorySave(Map<String, dynamic> data) async {
    await _authedPost('/api/onboarding/memory', data: data);
  }

  // ── Day One Import ────────────────────────────────────────────

  /// Uploads a .zip or .json Day One export.
  /// Returns { job_id, total } — poll getDayOneImportStatus for progress.
  Future<Map<String, dynamic>> importDayOne(String filePath, String fileName) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final res = await _dio.post(
      '/api/import/dayone',
      data: formData,
      options: Options(receiveTimeout: const Duration(minutes: 2)),
    );
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDayOneImportStatus(String jobId) async {
    final res = await _authedGet('/api/import/dayone/status/$jobId');
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
    final outer = res.data as Map<String, dynamic>;
    return outer['data'] as Map<String, dynamic>;
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

  // ── Entry attachments ─────────────────────────────────────────

  Future<Map<String, dynamic>> uploadEntryAttachment({
    required int entryId,
    required String filePath,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        filename: filename,
      ),
    });
    final res = await _dio.post(
      '/api/entries/$entryId/attachments',
      data: formData,
    );
    return res.data as Map<String, dynamic>;
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

  // ── Memory Profile ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getMemory() async {
    final res = await _authedGet('/api/memory');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateMemory(Map<String, dynamic> data) async {
    final res = await _authedPatch('/api/memory', data: data);
    return res.data as Map<String, dynamic>;
  }

  // ── Account ───────────────────────────────────────────────────────────────────

  Future<void> changePassword(String currentPw, String newPw) async {
    await _authedPost('/auth/change-password', data: {
      'current_password': currentPw,
      'new_password':     newPw,
    });
  }

  // ── Sessions ──────────────────────────────────────────────────────────────────

  Future<List<dynamic>> getSessions() async {
    final res = await _authedGet('/auth/sessions');
    return (res.data as Map<String, dynamic>)['sessions'] as List<dynamic>? ?? [];
  }

  Future<void> revokeSession(dynamic sessionId) async {
    await _authedDelete('/auth/sessions/$sessionId');
  }

  Future<void> revokeAllSessions() async {
    await _authedDelete('/auth/sessions');
  }

  // ── API Key ───────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getApiKey() async {
    final res = await _authedGet('/api/auth/api-key');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> regenerateApiKey() async {
    final res = await _authedPost('/api/auth/api-key/regenerate');
    return res.data as Map<String, dynamic>;
  }

  // ── SMS / Text Journal ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getSmsStatus() async {
    final res = await _authedGet('/api/sms/status');
    return res.data as Map<String, dynamic>;
  }

  Future<void> requestSmsVerification(String phone) async {
    await _authedPost('/api/sms/request-verification', data: {'phone_number': phone});
  }

  Future<void> verifySmsCode(String phone, String code) async {
    await _authedPost('/api/sms/verify', data: {'phone_number': phone, 'code': code});
  }

  Future<void> removeSmsPhone() async {
    await _authedDelete('/api/sms/phone');
  }

  // ── Reflect Mode ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getReflectMode() async {
    final res = await _authedGet('/api/settings/reflect-mode');
    return res.data as Map<String, dynamic>;
  }

  Future<void> setReflectMode(bool autoReflect) async {
    await _authedPut('/api/settings/reflect-mode', data: {'auto_reflect': autoReflect});
  }

  // ── AI Provider ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getAiProvider() async {
    final res = await _authedGet('/api/settings/ai-provider');
    return res.data as Map<String, dynamic>;
  }

  Future<void> updateAiProvider(Map<String, dynamic> data) async {
    await _authedPut('/api/settings/ai-provider', data: data);
  }

  Future<void> clearAiProvider() async {
    await _authedDelete('/api/settings/ai-provider');
  }

  // ── Private helpers ───────────────────────────────────────────

  // ── Resources ────────────────────────────────────────────────────────────────

  // GET /api/resources — returns { profile, generated_at } or null profile if not yet generated
  Future<Map<String, dynamic>?> getResources() async {
    final res = await _authedGet('/api/resources');
    return res.data as Map<String, dynamic>?;
  }

  // POST /api/resources/generate — generates (or force-refreshes) personalized resources
  // Returns { profile, generated_at }
  Future<Map<String, dynamic>> generateResources({bool force = false}) async {
    final path = force ? '/api/resources/generate?force=true' : '/api/resources/generate';
    final res = await _authedPost(path, data: {});
    return res.data as Map<String, dynamic>;
  }

  Future<Response> _authedGet(String path, {Map<String, dynamic>? queryParameters}) =>
      _dio.get(path, queryParameters: queryParameters);

  Future<Response> _authedPost(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> _authedPut(String path, {dynamic data}) =>
      _dio.put(path, data: data);

  Future<Response> _authedPatch(String path, {dynamic data}) =>
      _dio.patch(path, data: data);

  Future<Response> _authedDelete(String path) =>
      _dio.delete(path);

  // ── Detective Mode ────────────────────────────────────────────

  Future<Map<String, dynamic>> detectiveCheckAccess() async {
    final r = await _authedGet('/api/detective/access');
    return Map<String, dynamic>.from(r.data);
  }

  Future<List<dynamic>> detectiveGetCases() async {
    final r = await _authedGet('/api/detective/cases');
    return List<dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> detectiveCreateCase(String title) async {
    final r = await _authedPost('/api/detective/cases', data: {'title': title});
    return Map<String, dynamic>.from(r.data);
  }

  Future<List<dynamic>> detectiveGetEntries(String caseId) async {
    final r = await _authedGet('/api/detective/cases/$caseId/entries');
    return List<dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> detectiveAddEntry(String caseId, Map<String, dynamic> data) async {
    final r = await _authedPost('/api/detective/cases/$caseId/entries', data: data);
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> detectiveUpdateEntry(String caseId, String entryId, Map<String, dynamic> data) async {
    await _authedPut('/api/detective/cases/$caseId/entries/$entryId', data: data);
  }

  Future<void> detectiveDeleteEntry(String caseId, String entryId) async {
    await _authedDelete('/api/detective/cases/$caseId/entries/$entryId');
  }

  Future<Map<String, dynamic>> detectiveUploadEntryPhoto(
      String caseId, String entryId, List<int> bytes, String filename) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final r = await _dio.post(
      '/api/detective/cases/$caseId/entries/$entryId/photos',
      data: formData,
      options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
    );
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> detectiveDeleteEntryPhoto(
      String caseId, String entryId, String photoId) async {
    await _authedDelete(
      '/api/detective/cases/$caseId/entries/$entryId/photos/$photoId');
  }

  Future<Map<String, dynamic>> detectiveSynthesizeEntryPhotos(
      String caseId, String entryId) async {
    final r = await _authedPost(
      '/api/detective/cases/$caseId/entries/$entryId/photos/synthesize');
    return Map<String, dynamic>.from(r.data);
  }
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