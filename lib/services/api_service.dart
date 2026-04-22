// lib/services/api_service.dart
//
// All HTTP calls to journal.williamthomas.name.
// Uses Dio + CookieManager so the HttpOnly refresh_token cookie is handled
// exactly like the web app — no backend changes required.

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_parser/http_parser.dart';

// Returns the correct MediaType for an image filename so the backend
// can pass a valid media_type to the Anthropic API.
MediaType _imageMimeType(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return MediaType('image', 'jpeg');
    case 'png':
      return MediaType('image', 'png');
    case 'webp':
      return MediaType('image', 'webp');
    case 'gif':
      return MediaType('image', 'gif');
    default:
      return MediaType('image', 'jpeg');
  }
}

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

  Future<Map<String, dynamic>> verify2FA(
      String partialToken, String code) async {
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
    required String q1,
    required String a1,
    required String q2,
    required String a2,
    required String q3,
    required String a3,
  }) async {
    await _authedPost('/auth/security-questions/setup', data: {
      'question_1': q1,
      'answer_1': a1,
      'question_2': q2,
      'answer_2': a2,
      'question_3': q3,
      'answer_3': a3,
    });
  }

  Future<void> verifyPassword(String password) async {
    await _authedPost('/auth/verify-password', data: {'password': password});
  }

  // ── 2FA (TOTP) ────────────────────────────────────────────────

  Future<Map<String, dynamic>> get2FAStatus() async {
    final res = await _authedGet('/auth/2fa/status');
    return res.data as Map<String, dynamic>;
  }

  /// Returns { secret, qr_code, backup_codes }
  Future<Map<String, dynamic>> setup2FA() async {
    final res = await _authedPost('/auth/2fa/setup');
    return res.data as Map<String, dynamic>;
  }

  Future<void> enable2FA(String totpCode) async {
    await _authedPost('/auth/2fa/enable', data: {'totp_code': totpCode});
  }

  Future<void> disable2FA(String totpCode) async {
    await _authedPost('/auth/2fa/disable', data: {'totp_code': totpCode});
  }

  // ── Security Questions ────────────────────────────────────────

  Future<bool> hasSecurityQuestions() async {
    final res = await _authedGet('/auth/security-questions/has-questions');
    return (res.data as Map<String, dynamic>)['has_questions'] as bool? ??
        false;
  }

  Future<List<String>> getSecurityQuestionsBank() async {
    final res = await _authedGet('/auth/security-questions/bank');
    return (res.data as List).cast<String>();
  }

  /// Returns { question_1, question_2, question_3 } — no answers
  Future<Map<String, dynamic>> fetchSecurityQuestions() async {
    final res = await _authedGet('/auth/security-questions/fetch');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> onboardingMemoryPreview(
      Map<String, dynamic> data) async {
    final res = await _authedPost('/api/onboarding/memory-preview', data: data);
    return res.data as Map<String, dynamic>;
  }

  Future<void> onboardingMemorySave(Map<String, dynamic> data) async {
    await _authedPost('/api/onboarding/memory', data: data);
  }

  // ── Day One Import ────────────────────────────────────────────

  /// Uploads a .zip or .json Day One export.
  /// Returns { job_id, total } — poll getDayOneImportStatus for progress.
  Future<Map<String, dynamic>> importDayOne(
      String filePath, String fileName) async {
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

  // ── Early warning ────────────────────────────────────────────

  Future<Map<String, dynamic>> getEarlyWarningStatus() async {
    final res = await _authedGet('/api/early-warning/status');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> dismissEarlyWarning() async {
    await _authedPost('/api/early-warning/dismiss', data: {});
  }

  Future<void> rebuildEarlyWarningPatterns() async {
    await _authedPost('/api/early-warning/rebuild', data: {});
  }

  // ── Budget Planner ───────────────────────────────────────────

  Future<Map<String, dynamic>> getBudgetPlan() async {
    final res = await _authedGet('/api/budget/plan');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> saveBudgetPlan(Map<String, dynamic> data) async {
    final res = await _authedPost('/api/budget/plan', data: data);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> deleteBudgetPlan() async {
    await _authedDelete('/api/budget/plan');
  }

  Future<Map<String, dynamic>> budgetAi({
    required String prompt,
    int maxTokens = 700,
  }) async {
    final res = await _authedPost('/api/budget/ai', data: {
      'prompt': prompt,
      'max_tokens': maxTokens,
    });
    return Map<String, dynamic>.from(res.data as Map);
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
    final res = await _authedPut('/api/entries/$entryId',
        data: {'normalized_text': text});
    final body = res.data as Map<String, dynamic>;
    // Server returns { entry: { ...full entry... } } on success
    return body['entry'] as Map<String, dynamic>? ?? body;
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

  Future<List<dynamic>> getEntryAttachments(int entryId) async {
    final res = await _authedGet('/api/entries/$entryId/attachments');
    final body = res.data as Map<String, dynamic>? ?? {};
    return List<dynamic>.from(body['attachments'] ?? const []);
  }

  // ── AI Reflections ────────────────────────────────────────────

  Future<Map<String, dynamic>> getReflection(int entryId,
      {String tone = 'therapist'}) async {
    final res =
        await _authedPost('/api/reflect/$entryId', data: {'tone': tone});
    return res.data as Map<String, dynamic>;
  }

  // ── Ask My Journal (RAG) ──────────────────────────────────────

  Future<Map<String, dynamic>> askJournal(String question) async {
    final res =
        await _authedPost('/api/journal/ask', data: {'query': question});
    return res.data as Map<String, dynamic>;
  }

  // ── Therapist Insight (used as "Living Summary" on Timeline) ────
  // GET /api/therapist/insight/status?tone=therapist
  // Returns: { insight, generated_at, entry_count, entry_date,
  //            tone, tone_name, cached, input_tokens, output_tokens }
  // Returns {} if no insight has been generated yet for that tone.

  Future<Map<String, dynamic>> getTherapistInsightStatus(
      {String tone = 'therapist'}) async {
    final res = await _authedGet('/api/therapist/insight/status',
        queryParameters: {'tone': tone});
    return res.data as Map<String, dynamic>;
  }

  // POST /api/therapist/insight — generates (or returns cached) insight
  // Body: { tone, force? }
  Future<Map<String, dynamic>> generateTherapistInsight(
      {String tone = 'therapist', bool force = false}) async {
    final res = await _authedPost('/api/therapist/insight',
        data: {'tone': tone, 'force': force});
    return res.data as Map<String, dynamic>;
  }

  // ── Settings ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> getUserSettings() async {
    final res = await _authedGet('/api/settings');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateUserSettings(
      Map<String, dynamic> updates) async {
    final res = await _authedPut('/api/settings', data: updates);
    return res.data as Map<String, dynamic>;
  }

  // ── Mental Health ─────────────────────────────────────────────

  Future<Map<String, dynamic>> getMentalHealthData() async {
    final res = await _authedGet('/api/mental-health/dashboard');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> refreshMentalHealthNarrative() async {
    final res =
        await _authedPost('/api/mental-health/narrative/refresh', data: {});
    return res.data as Map<String, dynamic>;
  }

  // ── Fairness Ledger ──────────────────────────────────────────

  Future<Map<String, dynamic>> getFairnessConfig() async {
    final res = await _authedGet('/api/fairness/config');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> saveFairnessConfig(
      Map<String, dynamic> data) async {
    final res = await _authedPost('/api/fairness/config', data: data);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<dynamic>> getFairnessTasks() async {
    final res = await _authedGet('/api/fairness/tasks');
    return (res.data as Map<String, dynamic>)['tasks'] as List<dynamic>? ?? [];
  }

  Future<void> logFairnessTask({
    required int taskId,
    required String performedBy,
    String? note,
  }) async {
    await _authedPost('/api/fairness/log', data: {
      'task_id': taskId,
      'performed_by': performedBy,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }

  Future<void> deleteFairnessLog(int logId) async {
    await _authedDelete('/api/fairness/log/$logId');
  }

  Future<List<dynamic>> getFairnessLogs({int limit = 60}) async {
    final res = await _authedGet('/api/fairness/logs',
        queryParameters: {'limit': limit});
    return (res.data as Map<String, dynamic>)['logs'] as List<dynamic>? ?? [];
  }

  Future<Map<String, dynamic>> getFairnessSummary() async {
    final res = await _authedGet('/api/fairness/summary');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> generateFairnessSummary() async {
    final res = await _authedPost('/api/fairness/summary/generate', data: {});
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> createFairnessContribution(
      Map<String, dynamic> data) async {
    final res = await _authedPost('/api/fairness/contributions', data: data);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<dynamic>> getFairnessContributions({int limit = 60}) async {
    final res = await _authedGet('/api/fairness/contributions',
        queryParameters: {'limit': limit});
    return (res.data as Map<String, dynamic>)['contributions']
            as List<dynamic>? ??
        [];
  }

  Future<void> deleteFairnessContribution(int contributionId) async {
    await _authedDelete('/api/fairness/contributions/$contributionId');
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
      'credential': credential,
    });
    return res.data as Map<String, dynamic>;
  }

  // ── 2FA backup code ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> useBackupCode(
      String partialToken, String backupCode) async {
    final res = await _dio.post('/auth/2fa/use-backup', data: {
      'partial_token': partialToken,
      'backup_code': backupCode,
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
      'new_password': newPw,
    });
  }

  // ── Sessions ──────────────────────────────────────────────────────────────────

  Future<List<dynamic>> getSessions() async {
    final res = await _authedGet('/auth/sessions');
    return (res.data as Map<String, dynamic>)['sessions'] as List<dynamic>? ??
        [];
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
    await _authedPost('/api/sms/request-verification',
        data: {'phone_number': phone});
  }

  Future<void> verifySmsCode(String phone, String code) async {
    await _authedPost('/api/sms/verify',
        data: {'phone_number': phone, 'code': code});
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
    await _authedPut('/api/settings/reflect-mode',
        data: {'auto_reflect': autoReflect});
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
    final path = force
        ? '/api/resources/generate?force=true'
        : '/api/resources/generate';
    final res = await _authedPost(path, data: {});
    return res.data as Map<String, dynamic>;
  }

  // ── War Room ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> warRoomTriage({
    required String brainDump,
    bool includeJournalContext = true,
  }) async {
    final res = await _authedPost('/api/war-room/triage', data: {
      'brain_dump': brainDump,
      'include_journal_context': includeJournalContext,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Response> _authedGet(String path,
          {Map<String, dynamic>? queryParameters}) =>
      _dio.get(path, queryParameters: queryParameters);

  Future<Response> _authedPost(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> _authedPut(String path, {dynamic data}) =>
      _dio.put(path, data: data);

  Future<Response> _authedPatch(String path, {dynamic data}) =>
      _dio.patch(path, data: data);

  Future<Response> _authedDelete(String path) => _dio.delete(path);

  // ── Proof Vault ───────────────────────────────────────────────────────────

  Future<List<dynamic>> vaultGetFolders() async {
    final r = await _authedGet('/api/vault/folders');
    return List<dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> vaultCreateFolder({
    required String name,
    required String icon,
    required String color,
    String? description,
  }) async {
    final r = await _authedPost('/api/vault/folders', data: {
      'name': name,
      'icon': icon,
      'color': color,
      'description': description,
    });
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> vaultDeleteFolder(String folderId) async {
    await _authedDelete('/api/vault/folders/$folderId');
  }

  Future<List<dynamic>> vaultGetFolderItems(String folderId) async {
    final r = await _authedGet('/api/vault/folders/$folderId/items');
    return List<dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> vaultCreateItem(
      String folderId, Map<String, dynamic> data) async {
    final r =
        await _authedPost('/api/vault/folders/$folderId/items', data: data);
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> vaultUpdateItem(
      String itemId, Map<String, dynamic> data) async {
    final r = await _authedPut('/api/vault/items/$itemId', data: data);
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> vaultDeleteItem(String itemId) async {
    await _authedDelete('/api/vault/items/$itemId');
  }

  Future<Map<String, dynamic>> vaultUploadItemPhoto(
      String itemId, List<int> bytes, String filename) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: _imageMimeType(filename),
      ),
    });
    final r = await _dio.post(
      '/api/vault/items/$itemId/photos',
      data: formData,
      options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
    );
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> vaultDeleteItemPhoto(String itemId, String photoId) async {
    await _authedDelete('/api/vault/items/$itemId/photos/$photoId');
  }

  Future<Map<String, dynamic>> vaultGetCachedFolderSummary(
      String folderId) async {
    final r = await _authedGet('/api/vault/folders/$folderId/summary/cached');
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> vaultGenerateFolderSummary(String folderId,
      {bool force = false}) async {
    final r = await _authedPost(
      '/api/vault/folders/$folderId/summary?force=$force',
      data: {},
    );
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> vaultGetCachedSummary() async {
    final r = await _authedGet('/api/vault/summary/cached');
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> vaultGenerateSummary(
      {bool force = false}) async {
    final r = await _authedPost('/api/vault/summary?force=$force', data: {});
    return Map<String, dynamic>.from(r.data);
  }

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

  Future<void> detectiveDeleteCase(String caseId) async {
    await _authedDelete('/api/detective/cases/$caseId');
  }

  Future<List<dynamic>> detectiveGetEntries(String caseId) async {
    final r = await _authedGet('/api/detective/cases/$caseId/entries');
    return List<dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> detectiveAddEntry(
      String caseId, Map<String, dynamic> data) async {
    final r =
        await _authedPost('/api/detective/cases/$caseId/entries', data: data);
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> detectiveUpdateEntry(
      String caseId, String entryId, Map<String, dynamic> data) async {
    await _authedPut('/api/detective/cases/$caseId/entries/$entryId',
        data: data);
  }

  Future<void> detectiveDeleteEntry(String caseId, String entryId) async {
    await _authedDelete('/api/detective/cases/$caseId/entries/$entryId');
  }

  Future<Map<String, dynamic>> detectiveUploadEntryPhoto(
      String caseId, String entryId, List<int> bytes, String filename) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: _imageMimeType(filename),
      ),
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

  // ── Case Partner chat ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> detectiveChatLatestSession(String caseId) async {
    final r =
        await _authedGet('/api/detective/cases/$caseId/chat/latest-session');
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> detectiveChatSend(
    String caseId, {
    required String message,
    required List<Map<String, dynamic>> history,
    String? compressedContext,
  }) async {
    final r = await _authedPost('/api/detective/cases/$caseId/chat', data: {
      'message': message,
      'history': history,
      if (compressedContext != null) 'compressed_context': compressedContext,
    });
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> detectiveChatSaveMessages(String caseId, String sessionId,
      List<Map<String, dynamic>> messages) async {
    await _authedPost('/api/detective/cases/$caseId/chat/messages',
        data: {'session_id': sessionId, 'messages': messages});
  }

  Future<Map<String, dynamic>> detectiveChatNewSession(String caseId) async {
    final r = await _authedPost('/api/detective/cases/$caseId/chat/session');
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> detectiveChatCompress(
      String caseId, List<Map<String, dynamic>> messages) async {
    final r = await _authedPost('/api/detective/cases/$caseId/chat/compress',
        data: {'messages': messages});
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> detectiveDropWire(String caseId) async {
    final r = await _authedPost('/api/detective/cases/$caseId/wire');
    return Map<String, dynamic>.from(r.data);
  }

  // ── Authenticated image bytes ──────────────────────────────────────────────
  // Used by _AuthImage in detective_case_screen to bypass Flutter's URL-keyed
  // image cache, which doesn't re-send auth headers after a failed fetch.
  Future<List<int>> fetchImageBytes(String relativePath) async {
    final r = await _dio.get<List<int>>(
      relativePath,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Authorization': 'Bearer $_accessToken'},
      ),
    );
    return r.data ?? [];
  }

  // ── Case-level uploads (Photos tab) ─────────────────────────────────────

  Future<List<dynamic>> detectiveGetUploads(String caseId) async {
    final r = await _authedGet('/api/detective/cases/$caseId/uploads');
    return List<dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> detectiveUploadCasePhoto(
      String caseId, List<int> bytes, String filename) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: _imageMimeType(filename),
      ),
    });
    final r = await _dio.post(
      '/api/detective/cases/$caseId/upload',
      data: formData,
      options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
    );
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> detectiveDeleteUpload(String caseId, String uploadId) async {
    await _authedDelete('/api/detective/cases/$caseId/uploads/$uploadId');
  }

  // Deletes an entry-attached photo by its bare photo id (no mphoto_ prefix)
  Future<void> detectiveDeleteEntryPhotoById(
      String caseId, String photoId) async {
    await _authedDelete('/api/detective/cases/$caseId/entry-photos/$photoId');
  }

  // ── Intelligence ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> detectiveGetIntelligence(String caseId) async {
    final r = await _authedGet('/api/detective/cases/$caseId/intelligence');
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> detectiveRefreshIntelligence(
      String caseId) async {
    final r =
        await _authedPost('/api/detective/cases/$caseId/intelligence/refresh');
    return Map<String, dynamic>.from(r.data);
  }

  // ── Wire history ──────────────────────────────────────────────────────────

  Future<List<dynamic>> detectiveGetWireHistory(String caseId) async {
    final r = await _authedGet('/api/detective/cases/$caseId/wire-history');
    return List<dynamic>.from(r.data);
  }

  // ── Export (returns raw PDF bytes) ────────────────────────────────────────

  Future<List<int>> detectiveExport(String caseId, String tone) async {
    final r = await _dio.post(
      '/api/detective/cases/$caseId/export?tone=$tone',
      data: <String, dynamic>{},
      options: Options(
        headers: {'Authorization': 'Bearer $_accessToken'},
        responseType: ResponseType.bytes,
      ),
    );
    return List<int>.from(r.data as List);
  }

  // ── Research ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> detectiveRunResearch(
      String caseId, Map<String, dynamic> data) async {
    final r =
        await _authedPost('/api/detective/cases/$caseId/research', data: data);
    return Map<String, dynamic>.from(r.data);
  }

  Future<List<dynamic>> detectiveGetResearch(String caseId) async {
    final r = await _authedGet('/api/detective/cases/$caseId/research');
    return List<dynamic>.from(r.data);
  }

  // ── Detective settings ────────────────────────────────────────────────────

  Future<Map<String, dynamic>> detectiveGetSettings() async {
    final r = await _authedGet('/api/detective/settings');
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> detectiveSaveSettings(Map<String, dynamic> data) async {
    await _authedPost('/api/detective/settings', data: data);
  }

  // ── Exit Plan ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> exitPlanGet() async {
    final r = await _authedGet('/api/exit-plan');
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> exitPlanDetect() async {
    final r = await _authedGet('/api/exit-plan/detect');
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> exitPlanGenerate(
      {List<String> confirmedBranches = const []}) async {
    await _authedPost('/api/exit-plan/generate', data: {
      'force': false,
      'confirmed_branches': confirmedBranches,
    });
  }

  Future<void> exitPlanPatchTask(
      String taskId, Map<String, dynamic> data) async {
    await _authedPatch('/api/exit-plan/tasks/$taskId', data: data);
  }

  Future<Map<String, dynamic>> exitPlanAddTask(
      Map<String, dynamic> data) async {
    final r = await _authedPost('/api/exit-plan/tasks', data: data);
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> exitPlanEnrichTask(String taskId) async {
    await _authedPost('/api/exit-plan/tasks/$taskId/enrich', data: {});
  }

  Future<void> exitPlanDeleteTask(String taskId) async {
    await _authedDelete('/api/exit-plan/tasks/$taskId');
  }

  Future<Map<String, dynamic>> exitPlanGetNotes({String? taskId}) async {
    final path = taskId != null
        ? '/api/exit-plan/notes?task_id=$taskId'
        : '/api/exit-plan/notes';
    final r = await _authedGet(path);
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> exitPlanAddNote(String noteText, {String? taskId}) async {
    final body = <String, dynamic>{'note_text': noteText};
    if (taskId != null) body['task_id'] = taskId;
    await _authedPost('/api/exit-plan/notes', data: body);
  }

  // ── My Story ──────────────────────────────────────────────────────────────

  /// GET /api/my-story/cases
  /// Returns { cases: [...], has_detective_access: bool }
  Future<Map<String, dynamic>> myStoryGetCases() async {
    final r = await _authedGet('/api/my-story/cases');
    return Map<String, dynamic>.from(r.data);
  }

  /// POST /api/my-story/generate
  /// Body: { case_ids, include_journal, journal_entry_count, manual_context,
  ///         include_fairness, output_purpose, output_style }
  /// Returns { narrative: str }
  Future<Map<String, dynamic>> myStoryGenerate(
      Map<String, dynamic> body) async {
    final r = await _authedPost('/api/my-story/generate', data: body);
    return Map<String, dynamic>.from(r.data);
  }

  /// GET /api/my-story/drafts → List of draft summaries
  Future<List<dynamic>> myStoryGetDrafts() async {
    final r = await _authedGet('/api/my-story/drafts');
    return List<dynamic>.from(r.data);
  }

  /// GET /api/my-story/drafts/{id} → full draft with generated_text
  Future<Map<String, dynamic>> myStoryGetDraft(int id) async {
    final r = await _authedGet('/api/my-story/drafts/$id');
    return Map<String, dynamic>.from(r.data);
  }

  /// POST /api/my-story/drafts
  /// Body: { title, generated_text, manual_context, output_purpose, sources_summary }
  Future<Map<String, dynamic>> myStorySaveDraft(
      Map<String, dynamic> body) async {
    final r = await _authedPost('/api/my-story/drafts', data: body);
    return Map<String, dynamic>.from(r.data);
  }

  /// DELETE /api/my-story/drafts/{id}
  Future<void> myStoryDeleteDraft(int id) async {
    await _authedDelete('/api/my-story/drafts/$id');
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
