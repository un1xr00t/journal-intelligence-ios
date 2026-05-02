// lib/services/api_service.dart
//
// All HTTP calls to journal.williamthomas.name.
// Uses Dio + CookieManager so the HttpOnly refresh_token cookie is handled
// exactly like the web app — no backend changes required.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;

import 'ai_response_limits.dart';
import 'local_storage_paths.dart';
import 'native_session_bridge.dart';

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

const int _kEntryAttachmentTargetBytes = 12 * 1024 * 1024;
const int _kEntryAttachmentMaxDimension = 2400;

class _PreparedEntryAttachment {
  const _PreparedEntryAttachment({
    required this.bytes,
    required this.filename,
    required this.mediaType,
  });

  final Uint8List bytes;
  final String filename;
  final MediaType mediaType;
}

String _filenameStem(String filename) {
  final trimmed = filename.trim();
  if (trimmed.isEmpty) return 'attachment';
  final dotIndex = trimmed.lastIndexOf('.');
  if (dotIndex <= 0) return trimmed;
  return trimmed.substring(0, dotIndex);
}

Future<_PreparedEntryAttachment> _prepareEntryAttachment({
  required String filePath,
  required String filename,
}) async {
  final originalBytes = await File(filePath).readAsBytes();
  if (originalBytes.length <= _kEntryAttachmentTargetBytes) {
    return _PreparedEntryAttachment(
      bytes: originalBytes,
      filename: filename,
      mediaType: _imageMimeType(filename),
    );
  }

  final decoded = img.decodeImage(originalBytes);
  if (decoded == null) {
    throw Exception(
      'Attachment is too large to upload. Please choose a smaller photo.',
    );
  }

  var working = img.bakeOrientation(decoded);
  if (working.width > _kEntryAttachmentMaxDimension ||
      working.height > _kEntryAttachmentMaxDimension) {
    if (working.width >= working.height) {
      working = img.copyResize(
        working,
        width: _kEntryAttachmentMaxDimension,
        interpolation: img.Interpolation.cubic,
      );
    } else {
      working = img.copyResize(
        working,
        height: _kEntryAttachmentMaxDimension,
        interpolation: img.Interpolation.cubic,
      );
    }
  }

  Uint8List resizedBytes = Uint8List(0);
  for (final quality in [88, 82, 76, 70, 64, 58, 52]) {
    resizedBytes = Uint8List.fromList(img.encodeJpg(working, quality: quality));
    if (resizedBytes.length <= _kEntryAttachmentTargetBytes) {
      return _PreparedEntryAttachment(
        bytes: resizedBytes,
        filename: '${_filenameStem(filename)}.jpg',
        mediaType: MediaType('image', 'jpeg'),
      );
    }
  }

  var attempts = 0;
  while (resizedBytes.length > _kEntryAttachmentTargetBytes && attempts < 6) {
    attempts += 1;
    final nextWidth = (working.width * 0.85).floor().clamp(1, working.width);
    final nextHeight = (working.height * 0.85).floor().clamp(1, working.height);
    if (nextWidth == working.width && nextHeight == working.height) {
      break;
    }
    working = img.copyResize(
      working,
      width: nextWidth,
      height: nextHeight,
      interpolation: img.Interpolation.cubic,
    );
    resizedBytes = Uint8List.fromList(img.encodeJpg(working, quality: 70));
  }

  if (resizedBytes.isEmpty ||
      resizedBytes.length > _kEntryAttachmentTargetBytes) {
    throw Exception(
      'Attachment is too large to upload. Please choose a smaller photo.',
    );
  }

  return _PreparedEntryAttachment(
    bytes: resizedBytes,
    filename: '${_filenameStem(filename)}.jpg',
    mediaType: MediaType('image', 'jpeg'),
  );
}

class SavedFloatchatMessage {
  const SavedFloatchatMessage({
    required this.role,
    required this.content,
    this.actions = const [],
    this.attachments = const [],
  });

  final String role;
  final String content;
  final List<Map<String, dynamic>> actions;
  final List<Map<String, dynamic>> attachments;

  factory SavedFloatchatMessage.fromJson(Map<String, dynamic> json) {
    return SavedFloatchatMessage(
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
      actions: (json['actions'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList() ??
          const <Map<String, dynamic>>[],
      attachments: (json['attachments'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList() ??
          const <Map<String, dynamic>>[],
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        if (actions.isNotEmpty) 'actions': actions,
        if (attachments.isNotEmpty) 'attachments': attachments,
      };
}

class SavedFloatchatConversation {
  const SavedFloatchatConversation({
    required this.id,
    required this.title,
    required this.preview,
    required this.messageCount,
    required this.webSearchEnabled,
    required this.createdAt,
    required this.updatedAt,
    this.contextString,
    this.messages = const [],
  });

  final String id;
  final String title;
  final String preview;
  final int messageCount;
  final bool webSearchEnabled;
  final String createdAt;
  final String updatedAt;
  final String? contextString;
  final List<SavedFloatchatMessage> messages;

  factory SavedFloatchatConversation.fromJson(Map<String, dynamic> json) {
    return SavedFloatchatConversation(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Saved Sage conversation',
      preview: json['preview']?.toString() ?? '',
      messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
      webSearchEnabled: json['web_search_enabled'] == true,
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
      contextString: json['context_string']?.toString(),
      messages: (json['messages'] as List?)
              ?.whereType<Map>()
              .map((item) => SavedFloatchatMessage.fromJson(
                  Map<String, dynamic>.from(item)))
              .toList() ??
          const <SavedFloatchatMessage>[],
    );
  }
}

class SageTrackCheckIn {
  const SageTrackCheckIn({
    required this.id,
    required this.createdAt,
    required this.source,
    required this.moodLabel,
    required this.progressStatus,
    required this.whatHappened,
    required this.win,
    required this.hardPart,
    required this.nextStep,
    required this.userConfirmed,
  });

  final String id;
  final String createdAt;
  final String source;
  final String moodLabel;
  final String progressStatus;
  final String whatHappened;
  final String win;
  final String hardPart;
  final String nextStep;
  final bool userConfirmed;

  factory SageTrackCheckIn.fromJson(Map<String, dynamic> json) {
    return SageTrackCheckIn(
      id: json['id']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      source: json['source']?.toString() ?? 'manual',
      moodLabel: json['mood_label']?.toString() ?? '',
      progressStatus: json['progress_status']?.toString() ?? '',
      whatHappened: json['what_happened']?.toString() ?? '',
      win: json['win']?.toString() ?? '',
      hardPart: json['hard_part']?.toString() ?? '',
      nextStep: json['next_step']?.toString() ?? '',
      userConfirmed: json['user_confirmed'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt,
        'source': source,
        'mood_label': moodLabel,
        'progress_status': progressStatus,
        'what_happened': whatHappened,
        'win': win,
        'hard_part': hardPart,
        'next_step': nextStep,
        'user_confirmed': userConfirmed,
      };
}

class SageFocusTrack {
  const SageFocusTrack({
    required this.id,
    required this.title,
    required this.category,
    required this.status,
    required this.isPrimary,
    required this.checkInCadence,
    required this.currentGoal,
    required this.whyThisMatters,
    required this.nextCommitment,
    required this.summaryCompact,
    required this.createdAt,
    required this.updatedAt,
    this.lastCheckInAt,
    this.stuckPoints = const [],
    this.recentWins = const [],
    this.openLoops = const [],
    this.successMarkers = const [],
    this.checkIns = const [],
  });

  final String id;
  final String title;
  final String category;
  final String status;
  final bool isPrimary;
  final String checkInCadence;
  final String currentGoal;
  final String whyThisMatters;
  final String nextCommitment;
  final String summaryCompact;
  final String createdAt;
  final String updatedAt;
  final String? lastCheckInAt;
  final List<String> stuckPoints;
  final List<String> recentWins;
  final List<String> openLoops;
  final List<String> successMarkers;
  final List<SageTrackCheckIn> checkIns;

  factory SageFocusTrack.fromJson(Map<String, dynamic> json) {
    List<String> readStringList(dynamic value) {
      if (value is! List) return const [];
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList();
    }

    return SageFocusTrack(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Focus track',
      category: json['category']?.toString() ?? 'general',
      status: json['status']?.toString() ?? 'active',
      isPrimary: json['is_primary'] == true,
      checkInCadence: json['check_in_cadence']?.toString() ?? 'weekly',
      currentGoal: json['current_goal']?.toString() ?? '',
      whyThisMatters: json['why_this_matters']?.toString() ?? '',
      nextCommitment: json['next_commitment']?.toString() ?? '',
      summaryCompact: json['summary_compact']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
      lastCheckInAt: json['last_check_in_at']?.toString(),
      stuckPoints: readStringList(json['stuck_points']),
      recentWins: readStringList(json['recent_wins']),
      openLoops: readStringList(json['open_loops']),
      successMarkers: readStringList(json['success_markers']),
      checkIns: (json['check_ins'] as List?)
              ?.whereType<Map>()
              .map((item) =>
                  SageTrackCheckIn.fromJson(Map<String, dynamic>.from(item)))
              .toList() ??
          const <SageTrackCheckIn>[],
    );
  }

  SageFocusTrack copyWith({
    String? id,
    String? title,
    String? category,
    String? status,
    bool? isPrimary,
    String? checkInCadence,
    String? currentGoal,
    String? whyThisMatters,
    String? nextCommitment,
    String? summaryCompact,
    String? createdAt,
    String? updatedAt,
    String? lastCheckInAt,
    List<String>? stuckPoints,
    List<String>? recentWins,
    List<String>? openLoops,
    List<String>? successMarkers,
    List<SageTrackCheckIn>? checkIns,
  }) {
    return SageFocusTrack(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      status: status ?? this.status,
      isPrimary: isPrimary ?? this.isPrimary,
      checkInCadence: checkInCadence ?? this.checkInCadence,
      currentGoal: currentGoal ?? this.currentGoal,
      whyThisMatters: whyThisMatters ?? this.whyThisMatters,
      nextCommitment: nextCommitment ?? this.nextCommitment,
      summaryCompact: summaryCompact ?? this.summaryCompact,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastCheckInAt: lastCheckInAt ?? this.lastCheckInAt,
      stuckPoints: stuckPoints ?? this.stuckPoints,
      recentWins: recentWins ?? this.recentWins,
      openLoops: openLoops ?? this.openLoops,
      successMarkers: successMarkers ?? this.successMarkers,
      checkIns: checkIns ?? this.checkIns,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'status': status,
        'is_primary': isPrimary,
        'check_in_cadence': checkInCadence,
        'current_goal': currentGoal,
        'why_this_matters': whyThisMatters,
        'next_commitment': nextCommitment,
        'summary_compact': summaryCompact,
        'created_at': createdAt,
        'updated_at': updatedAt,
        if (lastCheckInAt != null) 'last_check_in_at': lastCheckInAt,
        'stuck_points': stuckPoints,
        'recent_wins': recentWins,
        'open_loops': openLoops,
        'success_markers': successMarkers,
        'check_ins': checkIns.map((item) => item.toJson()).toList(),
      };
}

class TimelinePage {
  const TimelinePage({
    required this.entries,
    required this.page,
    required this.hasMore,
  });

  final List<Map<String, dynamic>> entries;
  final int page;
  final bool hasMore;
}

class ApiService {
  static const String baseUrl = 'https://journal.williamthomas.name';
  static const String _inviteTokenStorageKey = 'invite_access_token';
  static const String _savedFloatchatStorageKey =
      'saved_floatchat_conversations_v1';
  static const String _sageTracksStorageKey = 'sage_focus_tracks_v1';

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;
  late final CookieJar _cookieJar;
  late final Future<void> _ready;
  final _storage = const FlutterSecureStorage();

  String? _accessToken;
  String? _inviteAccessToken;
  String? _floatchatContextString;
  Map<String, dynamic>? _voiceSettingsCache;
  DateTime? _voiceSettingsCachedAt;
  static const Duration _voiceSettingsCacheTtl = Duration(minutes: 5);
  static const int _maxCachedImageResponses = 120;
  final _imageBytesCache = <String, List<int>>{};
  final _imageBytesInFlight = <String, Future<List<int>>>{};

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      contentType: 'application/json',
      headers: {'Accept': 'application/json'},
    ));

    _ready = _initializeSessionStorage();
    // Inject auth header on every request
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        await _ready;
        if (_accessToken != null) {
          options.headers['Authorization'] = 'Bearer $_accessToken';
        }
        _inviteAccessToken ??= await _storage.read(key: _inviteTokenStorageKey);
        if (_inviteAccessToken != null) {
          options.headers['X-Invite-Token'] = _inviteAccessToken;
        }
        return handler.next(options);
      },
    ));
    _dio.interceptors.add(_AuthInterceptor(this));
  }

  Future<void> _initializeSessionStorage() async {
    final appSupportDir = await resolveAppSupportDirectory();
    final cookiePath = '${appSupportDir.path}/http_cookies';
    _cookieJar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage(cookiePath),
    );
    _dio.interceptors.insert(0, CookieManager(_cookieJar));
  }

  Future<void> ensureReady() => _ready;

  // ── Token management ──────────────────────────────────────────

  void setAccessToken(String token) {
    _accessToken = token;
  }

  Future<void> clearTokens() async {
    await _ready;
    _accessToken = null;
    _floatchatContextString = null;
    await _cookieJar.deleteAll();
    await _storage.delete(key: 'username');
    try {
      await NativeSessionBridge.clear();
    } catch (_) {
      // Keep normal auth/logout flows working even if the Siri bridge is unavailable.
    }
  }

  Future<void> setInviteAccessToken(String token) async {
    _inviteAccessToken = token;
    await _storage.write(key: _inviteTokenStorageKey, value: token);
  }

  Future<void> clearInviteAccessToken() async {
    _inviteAccessToken = null;
    await _storage.delete(key: _inviteTokenStorageKey);
  }

  String? get accessToken => _accessToken;
  bool get isAuthenticated => _accessToken != null;

  List<String> _extractSetCookieHeaders(Response response) {
    final headers = response.headers.map['set-cookie'];
    if (headers == null || headers.isEmpty) return const <String>[];
    return headers
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _syncNativeSessionFromResponse(Response response) async {
    final headers = _extractSetCookieHeaders(response);
    if (headers.isEmpty) return;
    try {
      await NativeSessionBridge.syncFromSetCookieHeaders(headers);
    } catch (_) {
      // Keep app auth resilient even if native Siri session sync fails.
    }
  }

  bool _isRouteMissing(DioException error) => error.response?.statusCode == 404;

  String _collapseSavedText(String value, {required int limit}) {
    final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= limit) return collapsed;
    return '${collapsed.substring(0, limit - 1).trimRight()}…';
  }

  String _deriveSavedTitle(
    List<Map<String, dynamic>> messages, {
    String? explicitTitle,
  }) {
    final explicit = explicitTitle?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return _collapseSavedText(explicit, limit: 80);
    }

    for (final message in messages) {
      if (message['role']?.toString() == 'user') {
        final content = message['content']?.toString().trim() ?? '';
        if (content.isNotEmpty) return _collapseSavedText(content, limit: 80);
      }
    }

    for (final message in messages) {
      final content = message['content']?.toString().trim() ?? '';
      if (content.isNotEmpty) return _collapseSavedText(content, limit: 80);
    }

    return 'Saved Sage conversation';
  }

  String _deriveSavedPreview(List<Map<String, dynamic>> messages) {
    for (final message in messages.reversed) {
      if (message['role']?.toString() == 'assistant') {
        final content = message['content']?.toString().trim() ?? '';
        if (content.isNotEmpty) return _collapseSavedText(content, limit: 180);
      }
    }

    for (final message in messages.reversed) {
      final content = message['content']?.toString().trim() ?? '';
      if (content.isNotEmpty) return _collapseSavedText(content, limit: 180);
    }

    return 'No preview available.';
  }

  Future<List<SavedFloatchatConversation>>
      _readLocalSavedFloatchatConversations() async {
    final raw = await _storage.read(key: _savedFloatchatStorageKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((item) => SavedFloatchatConversation.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeLocalSavedFloatchatConversations(
    List<SavedFloatchatConversation> items,
  ) {
    return _storage.write(
      key: _savedFloatchatStorageKey,
      value: jsonEncode(
        items
            .map((item) => {
                  'id': item.id,
                  'title': item.title,
                  'preview': item.preview,
                  'message_count': item.messageCount,
                  'web_search_enabled': item.webSearchEnabled,
                  'created_at': item.createdAt,
                  'updated_at': item.updatedAt,
                  'context_string': item.contextString,
                  'messages':
                      item.messages.map((message) => message.toJson()).toList(),
                })
            .toList(),
      ),
    );
  }

  Future<SavedFloatchatConversation> _saveFloatchatConversationLocally({
    String? conversationId,
    String? title,
    required String contextString,
    required List<Map<String, dynamic>> messages,
    required bool webSearchEnabled,
  }) async {
    final existing = await _readLocalSavedFloatchatConversations();
    final now = DateTime.now().toUtc().toIso8601String();
    final id = (conversationId != null && conversationId.trim().isNotEmpty)
        ? conversationId.trim()
        : 'local_${DateTime.now().microsecondsSinceEpoch}';

    SavedFloatchatConversation? previous;
    for (final item in existing) {
      if (item.id == id) {
        previous = item;
        break;
      }
    }

    final saved = SavedFloatchatConversation(
      id: id,
      title: _deriveSavedTitle(messages, explicitTitle: title),
      preview: _deriveSavedPreview(messages),
      messageCount: messages.length,
      webSearchEnabled: webSearchEnabled,
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
      contextString: contextString,
      messages: messages
          .map((item) => SavedFloatchatMessage.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(),
    );

    final next = [
      saved,
      ...existing.where((item) => item.id != id),
    ];
    await _writeLocalSavedFloatchatConversations(next);
    return saved;
  }

  Future<SavedFloatchatConversation> _getLocalSavedFloatchatConversation(
    String conversationId,
  ) async {
    final items = await _readLocalSavedFloatchatConversations();
    for (final item in items) {
      if (item.id == conversationId) return item;
    }
    throw DioException(
      requestOptions:
          RequestOptions(path: '/api/floatchat/saved/$conversationId'),
      response: Response(
        requestOptions:
            RequestOptions(path: '/api/floatchat/saved/$conversationId'),
        statusCode: 404,
        data: {'detail': 'Saved conversation not found.'},
      ),
    );
  }

  Future<List<SageFocusTrack>> _readLocalSageTracks() async {
    final raw = await _storage.read(key: _sageTracksStorageKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List;
      final tracks = decoded
          .whereType<Map>()
          .map((item) =>
              SageFocusTrack.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      tracks.sort((a, b) {
        if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
        final aTime = DateTime.tryParse(a.updatedAt);
        final bTime = DateTime.tryParse(b.updatedAt);
        if (aTime == null || bTime == null) {
          return b.updatedAt.compareTo(a.updatedAt);
        }
        return bTime.compareTo(aTime);
      });
      return tracks;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeLocalSageTracks(List<SageFocusTrack> tracks) {
    return _storage.write(
      key: _sageTracksStorageKey,
      value: jsonEncode(tracks.map((item) => item.toJson()).toList()),
    );
  }

  String _buildTrackSummary({
    required String title,
    required String currentGoal,
    required List<String> recentWins,
    required List<String> stuckPoints,
    required String nextCommitment,
  }) {
    final parts = <String>[];
    if (currentGoal.trim().isNotEmpty) {
      parts.add('Goal: ${currentGoal.trim()}');
    }
    if (recentWins.isNotEmpty) {
      parts.add('Wins: ${recentWins.take(2).join('; ')}');
    }
    if (stuckPoints.isNotEmpty) {
      parts.add('Stuck: ${stuckPoints.take(2).join('; ')}');
    }
    if (nextCommitment.trim().isNotEmpty) {
      parts.add('Next: ${nextCommitment.trim()}');
    }
    if (parts.isEmpty) return title.trim();
    return parts.join(' ');
  }

  Future<List<SageFocusTrack>> listSageTracks() async {
    try {
      final res = await _authedGet('/api/sage/tracks');
      final data = res.data;
      final items = data is List
          ? data
          : (data is Map ? data['tracks'] as List? ?? const [] : const []);
      return items
          .whereType<Map>()
          .map((item) =>
              SageFocusTrack.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on DioException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
      return _readLocalSageTracks();
    }
  }

  Future<SageFocusTrack?> getPrimarySageTrack() async {
    final tracks = await listSageTracks();
    for (final track in tracks) {
      if (track.isPrimary && track.status == 'active') return track;
    }
    for (final track in tracks) {
      if (track.status == 'active') return track;
    }
    return null;
  }

  Future<SageFocusTrack> getSageTrack(String trackId) async {
    try {
      final res = await _authedGet('/api/sage/tracks/$trackId');
      return SageFocusTrack.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
      final tracks = await _readLocalSageTracks();
      for (final track in tracks) {
        if (track.id == trackId) return track;
      }
      throw DioException(
        requestOptions: RequestOptions(path: '/api/sage/tracks/$trackId'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/sage/tracks/$trackId'),
          statusCode: 404,
          data: {'detail': 'Focus track not found.'},
        ),
      );
    }
  }

  Future<SageFocusTrack> createSageTrack(Map<String, dynamic> body) async {
    try {
      final res = await _authedPost('/api/sage/tracks', data: body);
      return SageFocusTrack.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
      final tracks = await _readLocalSageTracks();
      final now = DateTime.now().toUtc().toIso8601String();
      final title = body['title']?.toString().trim().isNotEmpty == true
          ? body['title'].toString().trim()
          : 'Focus track';
      final category = body['category']?.toString().trim().isNotEmpty == true
          ? body['category'].toString().trim()
          : 'general';
      final currentGoal = body['current_goal']?.toString().trim() ?? '';
      final whyThisMatters = body['why_this_matters']?.toString().trim() ?? '';
      final nextCommitment = body['next_commitment']?.toString().trim() ?? '';
      final stuckPoints = ((body['stuck_points'] as List?) ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
      final recentWins = ((body['recent_wins'] as List?) ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
      final openLoops = ((body['open_loops'] as List?) ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
      final successMarkers = ((body['success_markers'] as List?) ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
      final isPrimary = body['is_primary'] == true || tracks.isEmpty;
      final track = SageFocusTrack(
        id: 'local_track_${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        category: category,
        status: 'active',
        isPrimary: isPrimary,
        checkInCadence:
            body['check_in_cadence']?.toString().trim().isNotEmpty == true
                ? body['check_in_cadence'].toString().trim()
                : 'weekly',
        currentGoal: currentGoal,
        whyThisMatters: whyThisMatters,
        nextCommitment: nextCommitment,
        summaryCompact: _buildTrackSummary(
          title: title,
          currentGoal: currentGoal,
          recentWins: recentWins,
          stuckPoints: stuckPoints,
          nextCommitment: nextCommitment,
        ),
        createdAt: now,
        updatedAt: now,
        stuckPoints: stuckPoints,
        recentWins: recentWins,
        openLoops: openLoops,
        successMarkers: successMarkers,
      );
      final next = [
        if (isPrimary)
          ...tracks.map((item) => item.copyWith(isPrimary: false))
        else
          ...tracks,
      ];
      next.insert(0, track);
      await _writeLocalSageTracks(next);
      return track;
    }
  }

  Future<SageFocusTrack> updateSageTrack(
    String trackId,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await _authedPatch('/api/sage/tracks/$trackId', data: body);
      return SageFocusTrack.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
      final tracks = await _readLocalSageTracks();
      final index = tracks.indexWhere((item) => item.id == trackId);
      if (index == -1) rethrow;
      final current = tracks[index];
      List<String>? parseList(String key) {
        if (!body.containsKey(key)) return null;
        final raw = body[key];
        if (raw is! List) return const [];
        return raw
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }

      final nextTrack = current.copyWith(
        title:
            body.containsKey('title') ? body['title']?.toString() ?? '' : null,
        category: body.containsKey('category')
            ? body['category']?.toString() ?? ''
            : null,
        status: body.containsKey('status')
            ? body['status']?.toString() ?? ''
            : null,
        isPrimary:
            body.containsKey('is_primary') ? body['is_primary'] == true : null,
        checkInCadence: body.containsKey('check_in_cadence')
            ? body['check_in_cadence']?.toString() ?? ''
            : null,
        currentGoal: body.containsKey('current_goal')
            ? body['current_goal']?.toString() ?? ''
            : null,
        whyThisMatters: body.containsKey('why_this_matters')
            ? body['why_this_matters']?.toString() ?? ''
            : null,
        nextCommitment: body.containsKey('next_commitment')
            ? body['next_commitment']?.toString() ?? ''
            : null,
        lastCheckInAt: body.containsKey('last_check_in_at')
            ? body['last_check_in_at']?.toString()
            : null,
        stuckPoints: parseList('stuck_points'),
        recentWins: parseList('recent_wins'),
        openLoops: parseList('open_loops'),
        successMarkers: parseList('success_markers'),
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      final normalized = nextTrack.copyWith(
        summaryCompact: _buildTrackSummary(
          title: nextTrack.title,
          currentGoal: nextTrack.currentGoal,
          recentWins: nextTrack.recentWins,
          stuckPoints: nextTrack.stuckPoints,
          nextCommitment: nextTrack.nextCommitment,
        ),
      );
      final rewritten = tracks
          .map((item) => item.id == trackId
              ? normalized
              : normalized.isPrimary
                  ? item.copyWith(isPrimary: false)
                  : item)
          .toList();
      await _writeLocalSageTracks(rewritten);
      return normalized;
    }
  }

  Future<void> deleteSageTrack(String trackId) async {
    try {
      await _authedDelete('/api/sage/tracks/$trackId');
    } on DioException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
      final tracks = await _readLocalSageTracks();
      final removed = tracks.where((item) => item.id != trackId).toList();
      if (removed.isNotEmpty && !removed.any((item) => item.isPrimary)) {
        removed[0] = removed[0].copyWith(isPrimary: true);
      }
      await _writeLocalSageTracks(removed);
    }
  }

  Future<SageFocusTrack> setPrimarySageTrack(String trackId) async {
    try {
      final res = await _authedPost('/api/sage/tracks/$trackId/set-primary');
      return SageFocusTrack.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
      final tracks = await _readLocalSageTracks();
      SageFocusTrack? selected;
      final next = tracks.map((item) {
        final updated = item.copyWith(isPrimary: item.id == trackId);
        if (updated.id == trackId) selected = updated;
        return updated;
      }).toList();
      await _writeLocalSageTracks(next);
      if (selected == null) rethrow;
      return selected!;
    }
  }

  Future<SageFocusTrack> pauseSageTrack(String trackId) {
    return updateSageTrack(trackId, {'status': 'paused', 'is_primary': false});
  }

  Future<SageFocusTrack> resumeSageTrack(String trackId) {
    return updateSageTrack(trackId, {'status': 'active'});
  }

  Future<SageFocusTrack> archiveSageTrack(String trackId) {
    return updateSageTrack(
        trackId, {'status': 'archived', 'is_primary': false});
  }

  Future<List<SageTrackCheckIn>> listSageTrackCheckIns(String trackId) async {
    try {
      final res = await _authedGet('/api/sage/tracks/$trackId/check-ins');
      final data = res.data;
      final items = data is List
          ? data
          : (data is Map ? data['check_ins'] as List? ?? const [] : const []);
      return items
          .whereType<Map>()
          .map((item) =>
              SageTrackCheckIn.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on DioException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
      final track = await getSageTrack(trackId);
      return track.checkIns;
    }
  }

  Future<SageTrackCheckIn> createSageTrackCheckIn(
    String trackId,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await _authedPost(
        '/api/sage/tracks/$trackId/check-ins',
        data: body,
      );
      return SageTrackCheckIn.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
      final tracks = await _readLocalSageTracks();
      final index = tracks.indexWhere((item) => item.id == trackId);
      if (index == -1) rethrow;
      final current = tracks[index];
      final now = DateTime.now().toUtc().toIso8601String();
      final checkIn = SageTrackCheckIn(
        id: 'local_checkin_${DateTime.now().microsecondsSinceEpoch}',
        createdAt: now,
        source: body['source']?.toString() ?? 'manual',
        moodLabel: body['mood_label']?.toString() ?? '',
        progressStatus: body['progress_status']?.toString() ?? '',
        whatHappened: body['what_happened']?.toString() ?? '',
        win: body['win']?.toString() ?? '',
        hardPart: body['hard_part']?.toString() ?? '',
        nextStep: body['next_step']?.toString() ?? '',
        userConfirmed: body['user_confirmed'] != false,
      );
      final recentWins = List<String>.from(current.recentWins);
      final openLoops = List<String>.from(current.openLoops);
      if (checkIn.win.trim().isNotEmpty) {
        recentWins.insert(0, checkIn.win.trim());
      }
      if (checkIn.nextStep.trim().isNotEmpty) {
        openLoops.insert(0, checkIn.nextStep.trim());
      }
      final nextTrack = current
          .copyWith(
            updatedAt: now,
            lastCheckInAt: now,
            nextCommitment: checkIn.nextStep.trim().isNotEmpty
                ? checkIn.nextStep.trim()
                : current.nextCommitment,
            recentWins: recentWins.take(6).toList(),
            openLoops: openLoops.take(6).toList(),
            checkIns: [checkIn, ...current.checkIns].take(20).toList(),
          )
          .copyWith(
            summaryCompact: _buildTrackSummary(
              title: current.title,
              currentGoal: current.currentGoal,
              recentWins: recentWins.take(6).toList(),
              stuckPoints: current.stuckPoints,
              nextCommitment: checkIn.nextStep.trim().isNotEmpty
                  ? checkIn.nextStep.trim()
                  : current.nextCommitment,
            ),
          );
      tracks[index] = nextTrack;
      await _writeLocalSageTracks(tracks);
      return checkIn;
    }
  }

  // ── Auth ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login(String username, String password) async {
    await _ready;
    final res = await _dio.post('/auth/login', data: {
      'username': username,
      'password': password,
    });
    await _syncNativeSessionFromResponse(res);
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verify2FA(
      String partialToken, String code) async {
    await _ready;
    final res = await _dio.post('/auth/2fa/verify-login', data: {
      'partial_token': partialToken,
      'totp_code': code,
    });
    await _syncNativeSessionFromResponse(res);
    return res.data as Map<String, dynamic>;
  }

  // ── Registration / Onboarding ─────────────────────────────────

  Future<Map<String, dynamic>> register(
      String username, String email, String password) async {
    await _ready;
    final res = await _dio.post('/api/register', data: {
      'username': username,
      'email': email,
      'password': password,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getInviteStatus(String token) async {
    final res = await _dio.get('/api/invite/$token/status');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> verifyInvite({
    required String token,
    required String passphrase,
  }) async {
    final res = await _dio
        .post('/api/invite/$token/verify', data: {'passphrase': passphrase});
    return Map<String, dynamic>.from(res.data as Map);
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
    await _ready;
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
    await _ready;
    try {
      await _dio.post('/auth/logout');
    } catch (_) {}
    await clearTokens();
  }

  Future<String?> refreshAccessToken() async {
    await _ready;
    try {
      // Cookie jar automatically sends the refresh_token cookie
      final res = await _dio.post('/auth/refresh');
      await _syncNativeSessionFromResponse(res);
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

  Future<List<dynamic>> getBudgetComparisons() async {
    final res = await _authedGet('/api/budget/comparisons');
    final data = res.data;
    if (data is List) return List<dynamic>.from(data);
    if (data is Map) {
      return List<dynamic>.from(
        data['comparisons'] ?? data['items'] ?? const <dynamic>[],
      );
    }
    return const [];
  }

  // ── Sage / Floating Chat ────────────────────────────────────

  Future<String> getFloatchatContext({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _floatchatContextString != null &&
        _floatchatContextString!.trim().isNotEmpty) {
      return _floatchatContextString!;
    }

    final res = await _authedGet('/api/floatchat/context');
    final data = Map<String, dynamic>.from(res.data as Map);
    final contextString = data['context_string']?.toString().trim() ?? '';
    _floatchatContextString = contextString;
    return contextString;
  }

  Future<Map<String, dynamic>> sendFloatchatMessage({
    required List<Map<String, dynamic>> messages,
    required String contextString,
    bool webSearchEnabled = false,
    List<Map<String, dynamic>> attachments = const [],
    int maxTokens = AiResponseLimits.sageReplyMaxTokens,
  }) async {
    final imageAttachments = attachments
        .where((item) => item['kind']?.toString() == 'image')
        .toList();
    final fileAttachments = attachments
        .where((item) => item['kind']?.toString() != 'image')
        .toList();

    final body = <String, dynamic>{
      'messages': messages,
      'context_string': contextString,
      'max_tokens': maxTokens,
      if (webSearchEnabled) 'enable_web_search': true,
      if (fileAttachments.isNotEmpty) 'attachments': fileAttachments,
      if (imageAttachments.isNotEmpty) 'images': imageAttachments,
    };

    final res = await _authedPost('/api/floatchat/message', data: body);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<SavedFloatchatConversation> saveFloatchatConversation({
    String? conversationId,
    String? title,
    required String contextString,
    required List<Map<String, dynamic>> messages,
    bool webSearchEnabled = false,
  }) async {
    final payload = {
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      'context_string': contextString,
      'messages': messages,
      'web_search_enabled': webSearchEnabled,
    };

    try {
      final Response res;
      if (conversationId != null && conversationId.trim().isNotEmpty) {
        res = await _authedPut(
          '/api/floatchat/saved/${conversationId.trim()}',
          data: payload,
        );
      } else {
        res = await _authedPost('/api/floatchat/saved', data: payload);
      }

      return SavedFloatchatConversation.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
      return _saveFloatchatConversationLocally(
        conversationId: conversationId,
        title: title,
        contextString: contextString,
        messages: messages,
        webSearchEnabled: webSearchEnabled,
      );
    }
  }

  Future<List<SavedFloatchatConversation>>
      listSavedFloatchatConversations() async {
    try {
      final res = await _authedGet('/api/floatchat/saved');
      final data = res.data;
      final items = data is List
          ? data
          : (data is Map ? data['items'] as List? ?? const [] : const []);
      return items
          .whereType<Map>()
          .map((item) => SavedFloatchatConversation.fromJson(
              Map<String, dynamic>.from(item)))
          .toList();
    } on DioException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
      return _readLocalSavedFloatchatConversations();
    }
  }

  Future<SavedFloatchatConversation> getSavedFloatchatConversation(
    String conversationId,
  ) async {
    try {
      final res = await _authedGet('/api/floatchat/saved/$conversationId');
      return SavedFloatchatConversation.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
      return _getLocalSavedFloatchatConversation(conversationId);
    }
  }

  Future<void> deleteSavedFloatchatConversation(String conversationId) async {
    try {
      await _authedDelete('/api/floatchat/saved/$conversationId');
    } on DioException catch (e) {
      if (!_isRouteMissing(e)) rethrow;
      final items = await _readLocalSavedFloatchatConversations();
      final next = items.where((item) => item.id != conversationId).toList();
      await _writeLocalSavedFloatchatConversations(next);
    }
  }

  Future<List<int>> voiceSpeak({
    required String text,
    String? voiceId,
  }) async {
    final res = await _dio.post<List<int>>(
      '/api/voice/speak',
      data: {
        'text': text,
        if (voiceId != null && voiceId.isNotEmpty) 'voice_id': voiceId,
      },
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 90),
      ),
    );
    return List<int>.from(res.data ?? const <int>[]);
  }

  Future<Map<String, dynamic>> getVoiceSettings() async {
    final cached = _voiceSettingsCache;
    final cachedAt = _voiceSettingsCachedAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _voiceSettingsCacheTtl) {
      return Map<String, dynamic>.from(cached);
    }
    final res = await _authedGet('/api/voice/settings');
    final data = Map<String, dynamic>.from(res.data as Map);
    _voiceSettingsCache = Map<String, dynamic>.from(data);
    _voiceSettingsCachedAt = DateTime.now();
    return data;
  }

  // ── Entries / Timeline ────────────────────────────────────────

  Future<TimelinePage> getTimelinePage({int page = 1, int limit = 20}) async {
    final res = await _authedGet('/api/entries', queryParameters: {
      'page': page,
      'limit': limit,
      'offset': (page - 1) * limit,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    final entries = (data['entries'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
    final responsePage = (data['page'] as num?)?.toInt() ?? page;
    final pages = (data['pages'] as num?)?.toInt();
    final total = (data['total'] as num?)?.toInt();
    final hasMore = pages != null
        ? responsePage < pages
        : total != null
            ? responsePage * limit < total
            : entries.length == limit;

    return TimelinePage(
      entries: entries,
      page: responsePage,
      hasMore: hasMore,
    );
  }

  Future<List<dynamic>> getTimeline({int page = 1, int limit = 20}) async {
    final timelinePage = await getTimelinePage(page: page, limit: limit);
    return timelinePage.entries;
  }

  Future<Map<String, dynamic>> getEntry(int entryId) async {
    final res = await _authedGet('/api/entries/$entryId');
    final body = Map<String, dynamic>.from(res.data as Map);
    final nested = body['data'];
    if (nested is Map) {
      return Map<String, dynamic>.from(nested);
    }
    final entry = body['entry'];
    if (entry is Map) {
      return Map<String, dynamic>.from(entry);
    }
    return body;
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
    final prepared = await _prepareEntryAttachment(
      filePath: filePath,
      filename: filename,
    );
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        prepared.bytes,
        filename: prepared.filename,
        contentType: prepared.mediaType,
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

  Future<Map<String, dynamic>> getPeopleIntelligence() async {
    final res = await _authedGet('/api/people/intelligence');
    return Map<String, dynamic>.from(res.data as Map);
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
    await _syncNativeSessionFromResponse(res);
    return res.data as Map<String, dynamic>;
  }

  // ── 2FA backup code ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> useBackupCode(
      String partialToken, String backupCode) async {
    final res = await _dio.post('/auth/2fa/use-backup', data: {
      'partial_token': partialToken,
      'backup_code': backupCode,
    });
    await _syncNativeSessionFromResponse(res);
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

  // ── Admin ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getMasterSummary() async {
    final res = await _authedGet('/api/summary/master');
    final data = Map<String, dynamic>.from(res.data as Map);
    final summary = data['data'];
    if (summary is Map) {
      return summary.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return data;
  }

  Future<List<dynamic>> getAdminUsers() async {
    final res = await _authedGet('/api/admin/users');
    return (res.data as Map<String, dynamic>)['users'] as List<dynamic>? ?? [];
  }

  Future<Map<String, dynamic>> createAdminUser({
    required String username,
    required String email,
    required String password,
    required String role,
  }) async {
    final res = await _authedPost('/api/admin/users', data: {
      'username': username,
      'email': email,
      'password': password,
      'role': role,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> deleteAdminUser(int userId) async {
    await _authedDelete('/api/admin/users/$userId');
  }

  Future<void> revokeAdminUserSessions(int userId) async {
    await _authedDelete('/api/admin/sessions/$userId');
  }

  Future<Map<String, dynamic>> getAdminAiUsage({
    String? startDate,
    String? endDate,
  }) async {
    final queryParameters = <String, dynamic>{};
    if (startDate != null && startDate.isNotEmpty) {
      queryParameters['start_date'] = startDate;
    }
    if (endDate != null && endDate.isNotEmpty) {
      queryParameters['end_date'] = endDate;
    }

    final res = await _authedGet(
      '/api/admin/ai-usage',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<dynamic>> getAdminInvites() async {
    final res = await _authedGet('/api/admin/invites');
    return (res.data as Map<String, dynamic>)['invites'] as List<dynamic>? ??
        [];
  }

  Future<Map<String, dynamic>> createAdminInvite({
    String? label,
    required String expiresIn,
  }) async {
    final res = await _authedPost('/api/admin/invites', data: {
      'label': label?.trim().isNotEmpty == true ? label!.trim() : null,
      'expires_in': expiresIn,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> deleteAdminInvite(int inviteId) async {
    await _authedDelete('/api/admin/invites/$inviteId');
  }

  Future<void> runPatternDetection() async {
    await _authedPost('/api/patterns/run', data: {});
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
      {Map<String, dynamic>? queryParameters}) async {
    await _ready;
    return _dio.get(path, queryParameters: queryParameters);
  }

  Future<Response> _authedPost(String path, {dynamic data}) async {
    await _ready;
    return _dio.post(path, data: data);
  }

  Future<Response> _authedPut(String path, {dynamic data}) async {
    await _ready;
    return _dio.put(path, data: data);
  }

  Future<Response> _authedPatch(String path, {dynamic data}) async {
    await _ready;
    return _dio.patch(path, data: data);
  }

  Future<Response> _authedDelete(String path) async {
    await _ready;
    return _dio.delete(path);
  }

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
    final cached = _imageBytesCache.remove(relativePath);
    if (cached != null) {
      _imageBytesCache[relativePath] = cached;
      return cached;
    }

    final inFlight = _imageBytesInFlight[relativePath];
    if (inFlight != null) return inFlight;

    final request = _fetchAndCacheImageBytes(relativePath);
    _imageBytesInFlight[relativePath] = request;
    try {
      return await request;
    } finally {
      _imageBytesInFlight.remove(relativePath);
    }
  }

  Future<List<int>> _fetchAndCacheImageBytes(String relativePath) async {
    final r = await _dio.get<List<int>>(
      relativePath,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Authorization': 'Bearer $_accessToken'},
      ),
    );
    final bytes = r.data ?? const <int>[];
    if (bytes.isNotEmpty) {
      _imageBytesCache[relativePath] = bytes;
      while (_imageBytesCache.length > _maxCachedImageResponses) {
        _imageBytesCache.remove(_imageBytesCache.keys.first);
      }
    }
    return bytes;
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

  Future<Map<String, dynamic>> generateExport({
    required String packetType,
    required String dateStart,
    required String dateEnd,
    String? format,
    bool redact = false,
    List<int> alertIds = const [],
  }) async {
    final r = await _dio.post(
      '/api/export/generate',
      data: {
        'packet_type': packetType,
        'date_start': dateStart,
        'date_end': dateEnd,
        if (format != null) 'format': format,
        'redact': redact,
        'alert_ids': alertIds,
      },
      options: Options(receiveTimeout: const Duration(minutes: 3)),
    );
    return Map<String, dynamic>.from(r.data as Map);
  }

  Future<void> downloadExportToFile(int exportId, String savePath) async {
    await _dio.download(
      '/api/export/$exportId',
      savePath,
      options: Options(
        headers: {'Accept': '*/*'},
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
  }

  Future<Response<List<int>>> fetchExportBlob(int exportId) async {
    return _dio.get<List<int>>(
      '/api/export/$exportId',
      options: Options(
        headers: {'Accept': '*/*'},
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
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
