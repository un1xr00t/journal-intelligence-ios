import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

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
  static List<OrbitLedgerEntry>? _memoryCache;

  final ApiService _api;

  OrbitLedgerService({ApiService? api}) : _api = api ?? ApiService();

  Future<List<OrbitLedgerEntry>> loadEntries() async {
    final cached = _memoryCache;
    if (cached != null) return List<OrbitLedgerEntry>.from(cached);
    return _loadEntriesFromLocalCache();
  }

  Future<List<OrbitLedgerEntry>> syncEntriesFromServer() async {
    final localCached = await _loadEntriesFromLocalCache();
    try {
      final remoteEntries = await _api.getOrbitLedgerEntries();
      _debugLog('sync fetched ${remoteEntries.length} remote entries');
      final entries = remoteEntries
          .map((item) => OrbitLedgerEntry.fromJson(item))
          .where((item) => item.request.trim().isNotEmpty)
          .toList();
      if (entries.isEmpty && localCached.isNotEmpty) {
        unawaited(_pushEntriesToServer(localCached));
        return localCached;
      }
      entries.sort(_compareEntries);
      await _writeLocalCache(entries);
      _debugLog('sync hydrated ${entries.length} local entries');
      return entries;
    } on DioException {
      _debugLog('sync failed with DioException');
      return localCached;
    } catch (_) {
      _debugLog('sync failed');
      return localCached;
    }
  }

  Future<void> saveEntries(List<OrbitLedgerEntry> entries) async {
    final sorted = List<OrbitLedgerEntry>.from(entries)..sort(_compareEntries);
    await _writeLocalCache(sorted);
    unawaited(_pushEntriesToServer(sorted));
    _debugLog('save cached ${sorted.length} entries and queued push');
  }

  Future<List<OrbitLedgerEntry>> _loadEntriesFromLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final entries = decoded
          .whereType<Map>()
          .map((item) =>
              OrbitLedgerEntry.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.request.trim().isNotEmpty)
          .toList();

      entries.sort(_compareEntries);
      _memoryCache = List<OrbitLedgerEntry>.from(entries);
      return entries;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeLocalCache(List<OrbitLedgerEntry> entries) async {
    _memoryCache = List<OrbitLedgerEntry>.from(entries);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<void> _pushEntriesToServer(List<OrbitLedgerEntry> entries) async {
    try {
      await _api.saveOrbitLedgerEntries(
        entries.map((entry) => entry.toJson()).toList(),
      );
      _debugLog('push completed with ${entries.length} entries');
    } on DioException {
      _debugLog('push failed with DioException');
    }
  }

  static int _compareEntries(OrbitLedgerEntry a, OrbitLedgerEntry b) =>
      b.loggedAt.compareTo(a.loggedAt);

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[orbit-ledger-sync] $message');
    }
  }
}
