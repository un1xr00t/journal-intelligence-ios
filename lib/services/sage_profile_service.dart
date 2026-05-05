import 'dart:convert';
import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'user_settings_sync_service.dart';

class SageSettings {
  const SageSettings({
    required this.voiceId,
    required this.toneMode,
    required this.autoGreeting,
    required this.autoRemember,
    required this.allowSwearing,
    required this.webSearchEnabled,
    required this.warmth,
    required this.directness,
  });

  static const defaults = SageSettings(
    voiceId: 'shimmer',
    toneMode: 'standard',
    autoGreeting: true,
    autoRemember: true,
    allowSwearing: true,
    webSearchEnabled: false,
    warmth: 'warm',
    directness: 'direct',
  );

  final String voiceId;
  final String toneMode;
  final bool autoGreeting;
  final bool autoRemember;
  final bool allowSwearing;
  final bool webSearchEnabled;
  final String warmth;
  final String directness;

  Map<String, dynamic> toJson() => {
        'voice_id': voiceId,
        'tone_mode': toneMode,
        'auto_greeting': autoGreeting,
        'auto_remember': autoRemember,
        'allow_swearing': allowSwearing,
        'web_search_enabled': webSearchEnabled,
        'warmth': warmth,
        'directness': directness,
      };

  factory SageSettings.fromJson(Map<String, dynamic> json) {
    return SageSettings(
      voiceId: json['voice_id']?.toString() ?? defaults.voiceId,
      toneMode: json['tone_mode']?.toString() ?? defaults.toneMode,
      autoGreeting: json['auto_greeting'] as bool? ?? defaults.autoGreeting,
      autoRemember: json['auto_remember'] as bool? ?? defaults.autoRemember,
      allowSwearing: json['allow_swearing'] as bool? ?? defaults.allowSwearing,
      webSearchEnabled:
          json['web_search_enabled'] as bool? ?? defaults.webSearchEnabled,
      warmth: json['warmth']?.toString() ?? defaults.warmth,
      directness: json['directness']?.toString() ?? defaults.directness,
    );
  }

  SageSettings copyWith({
    String? voiceId,
    String? toneMode,
    bool? autoGreeting,
    bool? autoRemember,
    bool? allowSwearing,
    bool? webSearchEnabled,
    String? warmth,
    String? directness,
  }) {
    return SageSettings(
      voiceId: voiceId ?? this.voiceId,
      toneMode: toneMode ?? this.toneMode,
      autoGreeting: autoGreeting ?? this.autoGreeting,
      autoRemember: autoRemember ?? this.autoRemember,
      allowSwearing: allowSwearing ?? this.allowSwearing,
      webSearchEnabled: webSearchEnabled ?? this.webSearchEnabled,
      warmth: warmth ?? this.warmth,
      directness: directness ?? this.directness,
    );
  }

  String toPromptInstruction() {
    final swearing = allowSwearing
        ? 'Swearing is allowed when it genuinely fits the moment.'
        : 'Do not swear.';
    final toneInstruction = toneMode == 'unhinged'
        ? '''
Mode: unhinged
This is chaos-agent-v2 energy for Sage. Be brutally honest, call out avoidance fast, and challenge excuses without softening every edge.
You can use sharper language, dark humor, and pressure when it helps the user face reality, but stay accurate, useful, and grounded in the real context.
Do not become degrading, abusive, or pointlessly cruel. The goal is to wake the user up, not just roast them.
'''
        : '''
Mode: standard
Stay warm, direct, grounded, and emotionally intelligent.
''';
    return '''
[SAGE SETTINGS]
Warmth: $warmth
Directness: $directness
$swearing
Web search: ${webSearchEnabled ? 'ENABLED' : 'DISABLED'}
$toneInstruction
''';
  }
}

class SageMemoryItem {
  const SageMemoryItem({
    required this.id,
    required this.text,
    required this.source,
    required this.createdAt,
  });

  final String id;
  final String text;
  final String source;
  final String createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'source': source,
        'created_at': createdAt,
      };

  factory SageMemoryItem.fromJson(Map<String, dynamic> json) {
    return SageMemoryItem(
      id: json['id']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      source: json['source']?.toString() ?? 'manual',
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}

class SageProfileService {
  static const _settingsKey = 'sage_settings_v1';
  static const _memoryKey = 'sage_memory_items_v1';
  static const _maxMemoryItems = 24;
  static SageSettings? _cachedSettings;

  final _storage = const FlutterSecureStorage();

  static void clearSettingsCache() {
    _cachedSettings = null;
  }

  Future<SageSettings> loadSettings() async {
    final cached = _cachedSettings;
    if (cached != null) return cached;
    final raw = await _storage.read(key: _settingsKey);
    if (raw == null || raw.isEmpty) {
      _cachedSettings = SageSettings.defaults;
      return SageSettings.defaults;
    }
    try {
      final settings = SageSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      _cachedSettings = settings;
      return settings;
    } catch (_) {
      _cachedSettings = SageSettings.defaults;
      return SageSettings.defaults;
    }
  }

  Future<void> saveSettings(SageSettings settings) async {
    _cachedSettings = settings;
    await _storage.write(
      key: _settingsKey,
      value: jsonEncode(settings.toJson()),
    );
    unawaited(UserSettingsSyncService().pushLocalSettingsToServer());
  }

  Future<List<SageMemoryItem>> loadMemoryItems() async {
    final raw = await _storage.read(key: _memoryKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((item) =>
              SageMemoryItem.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.text.trim().isNotEmpty)
          .toList();
      return decoded;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveMemoryItems(List<SageMemoryItem> items) async {
    await _storage.write(
      key: _memoryKey,
      value: jsonEncode(items.map((item) => item.toJson()).toList()),
    );
    unawaited(UserSettingsSyncService().pushLocalSettingsToServer());
  }

  Future<List<SageMemoryItem>> addMemoryTexts(
    List<String> texts, {
    String source = 'manual',
  }) async {
    final current = await loadMemoryItems();
    final next = List<SageMemoryItem>.from(current);
    final existing = next.map((item) => item.text.trim().toLowerCase()).toSet();
    final now = DateTime.now().toIso8601String();

    for (final raw in texts) {
      final text = raw.trim();
      if (text.isEmpty) continue;
      final normalized = text.toLowerCase();
      if (existing.contains(normalized)) continue;
      existing.add(normalized);
      next.insert(
        0,
        SageMemoryItem(
          id: '${DateTime.now().microsecondsSinceEpoch}_${next.length}',
          text: text,
          source: source,
          createdAt: now,
        ),
      );
    }

    final trimmed = next.take(_maxMemoryItems).toList();
    await saveMemoryItems(trimmed);
    return trimmed;
  }

  Future<List<SageMemoryItem>> removeMemoryItem(String id) async {
    final current = await loadMemoryItems();
    final next = current.where((item) => item.id != id).toList();
    await saveMemoryItems(next);
    return next;
  }

  Future<void> clearMemory() async {
    await _storage.delete(key: _memoryKey);
    unawaited(UserSettingsSyncService().pushLocalSettingsToServer());
  }

  String buildMemoryContext(List<SageMemoryItem> items) {
    if (items.isEmpty) return '';
    final lines = items.map((item) => '- ${item.text.trim()}').join('\n');
    return '''
[SAGE MEMORY]
Use these durable details as additional context when relevant:
$lines
''';
  }
}
