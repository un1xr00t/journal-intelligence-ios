import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class OrbitLedgerEntry {
  const OrbitLedgerEntry({
    required this.id,
    required this.request,
    required this.type,
    required this.urgency,
    required this.loggedAt,
    this.note,
  });

  final String id;
  final String request;
  final String type;
  final String urgency;
  final DateTime loggedAt;
  final String? note;

  OrbitLedgerEntry copyWith({
    String? id,
    String? request,
    String? type,
    String? urgency,
    DateTime? loggedAt,
    String? note,
  }) {
    return OrbitLedgerEntry(
      id: id ?? this.id,
      request: request ?? this.request,
      type: type ?? this.type,
      urgency: urgency ?? this.urgency,
      loggedAt: loggedAt ?? this.loggedAt,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'request': request,
        'type': type,
        'urgency': urgency,
        'logged_at': loggedAt.toIso8601String(),
        'note': note,
      };

  factory OrbitLedgerEntry.fromJson(Map<String, dynamic> json) {
    return OrbitLedgerEntry(
      id: json['id']?.toString() ?? '',
      request: json['request']?.toString() ?? '',
      type: json['type']?.toString() ?? json['category']?.toString() ?? 'Other',
      urgency: json['urgency']?.toString() ?? 'Normal',
      loggedAt: DateTime.tryParse(
            json['logged_at']?.toString() ??
                json['created_at']?.toString() ??
                '',
          ) ??
          DateTime.now(),
      note: json['note']?.toString(),
    );
  }
}

class OrbitLedgerService {
  static const _storageKey = 'orbit_ledger.entries.v1';

  Future<List<OrbitLedgerEntry>> loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];

    final entries = decoded
        .whereType<Map>()
        .map((item) =>
            OrbitLedgerEntry.fromJson(Map<String, dynamic>.from(item)))
        .toList();

    entries.sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    return entries;
  }

  Future<void> saveEntries(List<OrbitLedgerEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }
}
