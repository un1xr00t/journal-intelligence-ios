import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SageSettings {
  const SageSettings({
    required this.voiceId,
    required this.autoGreeting,
    required this.autoRemember,
    required this.allowSwearing,
    required this.warmth,
    required this.directness,
  });

  static const defaults = SageSettings(
    voiceId: 'shimmer',
    autoGreeting: true,
    autoRemember: true,
    allowSwearing: true,
    warmth: 'warm',
    directness: 'direct',
  );

  final String voiceId;
  final bool autoGreeting;
  final bool autoRemember;
  final bool allowSwearing;
  final String warmth;
  final String directness;

  Map<String, dynamic> toJson() => {
        'voice_id': voiceId,
        'auto_greeting': autoGreeting,
        'auto_remember': autoRemember,
        'allow_swearing': allowSwearing,
        'warmth': warmth,
        'directness': directness,
      };

  factory SageSettings.fromJson(Map<String, dynamic> json) {
    return SageSettings(
      voiceId: json['voice_id']?.toString() ?? defaults.voiceId,
      autoGreeting: json['auto_greeting'] as bool? ?? defaults.autoGreeting,
      autoRemember: json['auto_remember'] as bool? ?? defaults.autoRemember,
      allowSwearing: json['allow_swearing'] as bool? ?? defaults.allowSwearing,
      warmth: json['warmth']?.toString() ?? defaults.warmth,
      directness: json['directness']?.toString() ?? defaults.directness,
    );
  }

  SageSettings copyWith({
    String? voiceId,
    bool? autoGreeting,
    bool? autoRemember,
    bool? allowSwearing,
    String? warmth,
    String? directness,
  }) {
    return SageSettings(
      voiceId: voiceId ?? this.voiceId,
      autoGreeting: autoGreeting ?? this.autoGreeting,
      autoRemember: autoRemember ?? this.autoRemember,
      allowSwearing: allowSwearing ?? this.allowSwearing,
      warmth: warmth ?? this.warmth,
      directness: directness ?? this.directness,
    );
  }

  String toPromptInstruction() {
    final swearing = allowSwearing
        ? 'Swearing is allowed when it genuinely fits the moment.'
        : 'Do not swear.';
    return '''
[SAGE SETTINGS]
Warmth: $warmth
Directness: $directness
$swearing
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

  final _storage = const FlutterSecureStorage();

  Future<SageSettings> loadSettings() async {
    final raw = await _storage.read(key: _settingsKey);
    if (raw == null || raw.isEmpty) return SageSettings.defaults;
    try {
      return SageSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return SageSettings.defaults;
    }
  }

  Future<void> saveSettings(SageSettings settings) {
    return _storage.write(
      key: _settingsKey,
      value: jsonEncode(settings.toJson()),
    );
  }

  Future<List<SageMemoryItem>> loadMemoryItems() async {
    final raw = await _storage.read(key: _memoryKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((item) => SageMemoryItem.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.text.trim().isNotEmpty)
          .toList();
      return decoded;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveMemoryItems(List<SageMemoryItem> items) {
    return _storage.write(
      key: _memoryKey,
      value: jsonEncode(items.map((item) => item.toJson()).toList()),
    );
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

  Future<void> clearMemory() => _storage.delete(key: _memoryKey);

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
