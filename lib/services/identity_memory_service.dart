import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IdentityMemoryEvidence {
  const IdentityMemoryEvidence({
    required this.entryId,
    required this.snippet,
    required this.seenAt,
  });

  final String entryId;
  final String snippet;
  final DateTime seenAt;

  Map<String, dynamic> toJson() => {
        'entry_id': entryId,
        'snippet': snippet,
        'seen_at': seenAt.toIso8601String(),
      };

  factory IdentityMemoryEvidence.fromJson(Map<String, dynamic> json) {
    return IdentityMemoryEvidence(
      entryId: json['entry_id']?.toString() ?? '',
      snippet: json['snippet']?.toString() ?? '',
      seenAt: DateTime.tryParse(json['seen_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class IdentityMemoryEntity {
  const IdentityMemoryEntity({
    required this.id,
    required this.name,
    required this.type,
    required this.aliases,
    required this.description,
    required this.confidence,
    required this.lastSeen,
    required this.mentionCount,
    required this.evidence,
    required this.userCorrected,
  });

  final String id;
  final String name;
  final String type;
  final List<String> aliases;
  final String description;
  final double confidence;
  final DateTime lastSeen;
  final int mentionCount;
  final List<IdentityMemoryEvidence> evidence;
  final bool userCorrected;

  IdentityMemoryEntity copyWith({
    String? name,
    String? type,
    List<String>? aliases,
    String? description,
    double? confidence,
    DateTime? lastSeen,
    int? mentionCount,
    List<IdentityMemoryEvidence>? evidence,
    bool? userCorrected,
  }) {
    return IdentityMemoryEntity(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      aliases: aliases ?? this.aliases,
      description: description ?? this.description,
      confidence: confidence ?? this.confidence,
      lastSeen: lastSeen ?? this.lastSeen,
      mentionCount: mentionCount ?? this.mentionCount,
      evidence: evidence ?? this.evidence,
      userCorrected: userCorrected ?? this.userCorrected,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'aliases': aliases,
        'description': description,
        'confidence': confidence,
        'last_seen': lastSeen.toIso8601String(),
        'mention_count': mentionCount,
        'evidence': evidence.map((item) => item.toJson()).toList(),
        'user_corrected': userCorrected,
      };

  factory IdentityMemoryEntity.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString() ?? '';
    return IdentityMemoryEntity(
      id: json['id']?.toString() ??
          name
              .replaceAll(RegExp(r'\s+'), ' ')
              .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
              .trim()
              .toLowerCase(),
      name: name,
      type: json['type']?.toString() ?? 'unknown',
      aliases: (json['aliases'] as List? ?? const [])
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      description: json['description']?.toString() ?? '',
      confidence:
          (json['confidence'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.0,
      lastSeen: DateTime.tryParse(json['last_seen']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      mentionCount: (json['mention_count'] as num?)?.toInt() ?? 0,
      evidence: (json['evidence'] as List? ?? const [])
          .whereType<Map>()
          .map((item) =>
              IdentityMemoryEvidence.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.snippet.trim().isNotEmpty)
          .toList(growable: false),
      userCorrected: json['user_corrected'] == true,
    );
  }
}

class IdentityMemoryService {
  static const _storageKey = 'identity_memory.entities.v1';
  static const _marker = 'Known identity memory:';
  static const _maxEvidencePerEntity = 5;
  static List<IdentityMemoryEntity>? _memoryCache;

  Future<List<IdentityMemoryEntity>> loadEntities() async {
    final cached = _memoryCache;
    if (cached != null) return List<IdentityMemoryEntity>.from(cached);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final entities = decoded
          .whereType<Map>()
          .map((item) =>
              IdentityMemoryEntity.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.name.trim().isNotEmpty)
          .toList();
      entities.sort(_compareEntities);
      _memoryCache = List<IdentityMemoryEntity>.from(entities);
      return entities;
    } catch (e) {
      _debugLog('load failed: $e');
      return const [];
    }
  }

  Future<String> buildContextBlock() async {
    final entities = (await loadEntities())
        .where((item) =>
            item.userCorrected ||
            item.confidence >= 0.45 ||
            (item.confidence >= 0.35 && item.mentionCount >= 3))
        .toList()
      ..sort(_compareEntities);

    if (entities.isEmpty) return '';

    final lines = <String>[_marker];
    for (final entity in entities.take(40)) {
      final aliases = entity.aliases
          .where((item) => item.toLowerCase() != entity.name.toLowerCase())
          .take(3)
          .join(', ');
      final aliasText = aliases.isEmpty ? '' : ' aliases: $aliases;';
      final corrected = entity.userCorrected ? ' user-corrected;' : '';
      final evidenceText = entity.evidence.isEmpty
          ? ''
          : ' evidence: ${entity.evidence.first.snippet}';
      lines.add(
        '- ${entity.name}: ${entity.type}; ${entity.description}$aliasText'
        ' confidence ${entity.confidence.toStringAsFixed(2)};'
        ' mentions ${entity.mentionCount};$corrected$evidenceText',
      );
    }
    lines.add(
      'Use user-corrected identity facts first. Use inferred facts only when '
      'the confidence/evidence supports them. Do not ask who a known name is.',
    );
    return lines.join('\n');
  }

  Future<String> appendContext(String contextString) async {
    final trimmed = contextString.trim();
    if (trimmed.contains(_marker)) return trimmed;

    final memory = await buildContextBlock();
    if (memory.isEmpty) return trimmed;
    if (trimmed.isEmpty) return memory;
    return '$trimmed\n\n$memory';
  }

  Future<void> learnFromEntry({
    required String entryId,
    required String text,
    DateTime? seenAt,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final date = seenAt ?? DateTime.now().toUtc();
    final existing = await loadEntities();
    final byId = {
      for (final entity in existing) entity.id: entity,
    };

    for (final candidate in _extractCandidates(trimmed, entryId, date)) {
      final previous = byId[candidate.id];
      byId[candidate.id] =
          previous == null ? candidate : _mergeEntity(previous, candidate);
    }

    final next = byId.values.toList()..sort(_compareEntities);
    await _writeEntities(next);
    _debugLog('learned ${next.length} identity entities');
  }

  Future<void> rebuildFromEntries(List<Map<String, dynamic>> entries) async {
    await _writeEntities(const []);
    for (final entry in entries) {
      final id = entry['id']?.toString();
      final text = (entry['normalized_text'] ?? entry['text'])?.toString();
      if (id == null || id.isEmpty || text == null || text.trim().isEmpty) {
        continue;
      }
      await learnFromEntry(
        entryId: id,
        text: text,
        seenAt: DateTime.tryParse(
          entry['entry_date']?.toString() ??
              entry['ingested_at']?.toString() ??
              '',
        ),
      );
    }
  }

  Future<void> applyCorrection({
    required String name,
    required String type,
    required String description,
    List<String> aliases = const [],
  }) async {
    final cleanName = _cleanName(name);
    if (cleanName.isEmpty) return;

    final entities = await loadEntities();
    final id = _entityId(cleanName);
    final now = DateTime.now().toUtc();
    final existing = entities.where((item) => item.id != id).toList();
    final previous = entities.where((item) => item.id == id).firstOrNull;
    final aliasSet = <String>{cleanName, ...aliases.map(_cleanName)}
      ..removeWhere((item) => item.isEmpty);

    existing.add(
      IdentityMemoryEntity(
        id: id,
        name: cleanName,
        type: _normalizeType(type),
        aliases: aliasSet.toList(),
        description: description.trim(),
        confidence: 1,
        lastSeen: previous?.lastSeen ?? now,
        mentionCount: max(previous?.mentionCount ?? 1, 1),
        evidence: previous?.evidence ?? const [],
        userCorrected: true,
      ),
    );
    existing.sort(_compareEntities);
    await _writeEntities(existing);
  }

  Future<void> _writeEntities(List<IdentityMemoryEntity> entities) async {
    _memoryCache = List<IdentityMemoryEntity>.from(entities);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(entities.map((item) => item.toJson()).toList()),
    );
  }

  IdentityMemoryEntity _mergeEntity(
    IdentityMemoryEntity previous,
    IdentityMemoryEntity candidate,
  ) {
    if (previous.userCorrected) {
      return previous.copyWith(
        lastSeen: _latest(previous.lastSeen, candidate.lastSeen),
        mentionCount: previous.mentionCount + candidate.mentionCount,
        evidence: _mergeEvidence(previous.evidence, candidate.evidence),
      );
    }

    final aliases = <String>{...previous.aliases, ...candidate.aliases}
      ..removeWhere((item) => item.trim().isEmpty);
    final strongerCandidate = candidate.confidence > previous.confidence;

    return previous.copyWith(
      type: strongerCandidate ? candidate.type : previous.type,
      description: strongerCandidate || previous.description.trim().isEmpty
          ? candidate.description
          : previous.description,
      aliases: aliases.toList(),
      confidence: max(previous.confidence, candidate.confidence)
          .clamp(0.0, 1.0)
          .toDouble(),
      lastSeen: _latest(previous.lastSeen, candidate.lastSeen),
      mentionCount: previous.mentionCount + candidate.mentionCount,
      evidence: _mergeEvidence(previous.evidence, candidate.evidence),
    );
  }

  List<IdentityMemoryEvidence> _mergeEvidence(
    List<IdentityMemoryEvidence> a,
    List<IdentityMemoryEvidence> b,
  ) {
    final byEntry = <String, IdentityMemoryEvidence>{};
    for (final item in [...a, ...b]) {
      if (item.entryId.isEmpty || item.snippet.trim().isEmpty) continue;
      byEntry[item.entryId] = item;
    }
    final evidence = byEntry.values.toList()
      ..sort((left, right) => right.seenAt.compareTo(left.seenAt));
    return evidence.take(_maxEvidencePerEntity).toList(growable: false);
  }

  List<IdentityMemoryEntity> _extractCandidates(
    String text,
    String entryId,
    DateTime seenAt,
  ) {
    final candidates = <IdentityMemoryEntity>[];

    void add({
      required String name,
      required String type,
      required String description,
      required double confidence,
      required String snippet,
      List<String> aliases = const [],
    }) {
      final clean = _cleanName(name);
      if (clean.isEmpty || _ignoredNames.contains(clean.toLowerCase())) return;
      final aliasSet = <String>{clean, ...aliases.map(_cleanName)}
        ..removeWhere((item) => item.isEmpty);
      candidates.add(
        IdentityMemoryEntity(
          id: _entityId(clean),
          name: clean,
          type: _normalizeType(type),
          aliases: aliasSet.toList(),
          description: description.trim(),
          confidence: confidence.clamp(0.0, 1.0),
          lastSeen: seenAt,
          mentionCount: _mentionCount(text, clean),
          evidence: [
            IdentityMemoryEvidence(
              entryId: entryId,
              snippet: _snippet(text, snippet),
              seenAt: seenAt,
            ),
          ],
          userCorrected: false,
        ),
      );
    }

    for (final match in _myRelationshipName.allMatches(text)) {
      final relation = match.namedGroup('relation') ?? '';
      final name = match.namedGroup('name') ?? '';
      add(
        name: name,
        type: _typeForRelation(relation),
        description: _descriptionForRelation(relation),
        confidence: _confidenceForRelation(relation),
        snippet: match.group(0) ?? name,
      );
    }

    for (final match in _nameIsRelationship.allMatches(text)) {
      final name = match.namedGroup('name') ?? '';
      final relation = match.namedGroup('relation') ?? '';
      add(
        name: name,
        type: _typeForRelation(relation),
        description: _descriptionForRelation(relation),
        confidence: _confidenceForRelation(relation),
        snippet: match.group(0) ?? name,
      );
    }

    for (final match in _petNamed.allMatches(text)) {
      final name = match.namedGroup('name') ?? '';
      add(
        name: name,
        type: 'pet',
        description: 'pet',
        confidence: 0.9,
        snippet: match.group(0) ?? name,
      );
    }

    for (final match in _namePet.allMatches(text)) {
      final relation = match.namedGroup('relation') ?? 'pet';
      final name = match.namedGroup('name') ?? '';
      add(
        name: name,
        type: 'pet',
        description: _descriptionForRelation(relation),
        confidence: 0.9,
        snippet: match.group(0) ?? name,
      );
    }

    for (final match in _projectPattern.allMatches(text)) {
      final name = match.namedGroup('name') ?? '';
      add(
        name: name,
        type: 'project',
        description: 'project mentioned in journal entries',
        confidence: 0.55,
        snippet: match.group(0) ?? name,
      );
    }

    for (final match in _organizationPattern.allMatches(text)) {
      final name = match.namedGroup('name') ?? '';
      add(
        name: name,
        type: 'organization',
        description: 'organization or company mentioned in journal entries',
        confidence: 0.5,
        snippet: match.group(0) ?? name,
      );
    }

    for (final match in _capitalizedName.allMatches(text)) {
      final name = match.namedGroup('name') ?? '';
      final clean = _cleanName(name);
      if (clean.isEmpty || _ignoredNames.contains(clean.toLowerCase())) {
        continue;
      }
      final count = _mentionCount(text, clean);
      if (count < 2) continue;
      add(
        name: clean,
        type: 'unknown',
        description: 'recurring name mentioned in journal entries',
        confidence: min(0.2 + (count * 0.05), 0.4),
        snippet: clean,
      );
    }

    return candidates;
  }

  static final _myRelationshipName = RegExp(
    r'\bmy\s+(?<relation>dog|cat|pet|puppy|kitten|mom|mother|dad|father|brother|sister|friend|partner|wife|husband|girlfriend|boyfriend|ex|boss|coworker|therapist|doctor)\s+(?<name>[A-Z][A-Za-z0-9_-]{1,}(?:\s+[A-Z][A-Za-z0-9_-]{1,}){0,2})\b',
  );

  static final _nameIsRelationship = RegExp(
    r'\b(?<name>[A-Z][A-Za-z0-9_-]{1,}(?:\s+[A-Z][A-Za-z0-9_-]{1,}){0,2})\s+(?:is|was|=)\s+(?:my\s+)?(?<relation>dog|cat|pet|puppy|kitten|mom|mother|dad|father|brother|sister|friend|partner|wife|husband|girlfriend|boyfriend|ex|boss|coworker|therapist|doctor)\b',
  );

  static final _petNamed = RegExp(
    r'\b(?:dog|cat|pet|puppy|kitten)\s+(?:named|called)\s+(?<name>[A-Z][A-Za-z0-9_-]{1,}(?:\s+[A-Z][A-Za-z0-9_-]{1,}){0,2})\b',
  );

  static final _namePet = RegExp(
    r'\b(?<name>[A-Z][A-Za-z0-9_-]{1,}(?:\s+[A-Z][A-Za-z0-9_-]{1,}){0,2})\s+(?:the\s+)?(?<relation>dog|cat|pet|puppy|kitten)\b',
  );

  static final _projectPattern = RegExp(
    r'\b(?:project|app|feature)\s+(?<name>[A-Z][A-Za-z0-9_-]{2,}(?:\s+[A-Z][A-Za-z0-9_-]{2,}){0,3})\b',
  );

  static final _organizationPattern = RegExp(
    r'\b(?:at|from|with|for)\s+(?<name>[A-Z][A-Za-z0-9_-]{2,}(?:\s+[A-Z][A-Za-z0-9_-]{2,}){0,3})\s+(?:Inc|LLC|Corp|Company|School|Hospital|University|Studio|Labs)\b',
  );

  static final _capitalizedName = RegExp(
    r'\b(?<name>[A-Z][A-Za-z0-9_-]{2,}(?:\s+[A-Z][A-Za-z0-9_-]{2,}){0,2})\b',
  );

  static const _ignoredNames = {
    'i',
    'me',
    'my',
    'today',
    'tonight',
    'morning',
    'afternoon',
    'evening',
    'journal',
    'sage',
    'voice',
    'reflection',
    'the',
    'this',
    'that',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  };

  static String _descriptionForRelation(String relation) {
    final normalized = relation.trim().toLowerCase();
    return switch (normalized) {
      'dog' || 'puppy' => 'dog',
      'cat' || 'kitten' => 'cat',
      'pet' => 'pet',
      'mom' || 'mother' => 'mother',
      'dad' || 'father' => 'father',
      'ex' => 'ex',
      _ => normalized,
    };
  }

  static String _typeForRelation(String relation) {
    final normalized = relation.trim().toLowerCase();
    return switch (normalized) {
      'dog' || 'cat' || 'pet' || 'puppy' || 'kitten' => 'pet',
      'friend' ||
      'partner' ||
      'wife' ||
      'husband' ||
      'girlfriend' ||
      'boyfriend' ||
      'ex' ||
      'mom' ||
      'mother' ||
      'dad' ||
      'father' ||
      'brother' ||
      'sister' ||
      'boss' ||
      'coworker' ||
      'therapist' ||
      'doctor' =>
        'person',
      _ => 'unknown',
    };
  }

  static double _confidenceForRelation(String relation) {
    final normalized = relation.trim().toLowerCase();
    return switch (normalized) {
      'dog' || 'cat' || 'pet' || 'puppy' || 'kitten' => 0.9,
      'mom' || 'mother' || 'dad' || 'father' => 0.85,
      'friend' || 'partner' || 'wife' || 'husband' => 0.8,
      _ => 0.7,
    };
  }

  static String _normalizeType(String type) {
    final normalized = type.trim().toLowerCase();
    return switch (normalized) {
      'person' ||
      'pet' ||
      'place' ||
      'project' ||
      'organization' ||
      'theme' =>
        normalized,
      _ => 'unknown',
    };
  }

  static int _mentionCount(String text, String name) {
    final escaped = RegExp.escape(name.trim());
    if (escaped.isEmpty) return 0;
    return RegExp('\\b$escaped\\b', caseSensitive: false)
        .allMatches(text)
        .length;
  }

  static String _cleanName(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim();
  }

  static String _entityId(String name) => _cleanName(name).toLowerCase();

  static String _snippet(String text, String needle) {
    final cleanNeedle = needle.trim();
    if (cleanNeedle.isEmpty) return text.substring(0, min(text.length, 180));
    final lowerText = text.toLowerCase();
    final lowerNeedle = cleanNeedle.toLowerCase();
    final index = lowerText.indexOf(lowerNeedle);
    if (index < 0) return text.substring(0, min(text.length, 180));
    final start = max(0, index - 70);
    final end = min(text.length, index + cleanNeedle.length + 70);
    return text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static DateTime _latest(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

  static int _compareEntities(
    IdentityMemoryEntity a,
    IdentityMemoryEntity b,
  ) {
    if (a.userCorrected != b.userCorrected) return a.userCorrected ? -1 : 1;
    final confidence = b.confidence.compareTo(a.confidence);
    if (confidence != 0) return confidence;
    final mentions = b.mentionCount.compareTo(a.mentionCount);
    if (mentions != 0) return mentions;
    return b.lastSeen.compareTo(a.lastSeen);
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[identity-memory] $message');
    }
  }
}
