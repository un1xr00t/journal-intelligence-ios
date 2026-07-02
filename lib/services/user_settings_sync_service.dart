import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'sage_profile_service.dart';

class UserSettingsSyncService {
  UserSettingsSyncService({
    ApiService? api,
    FlutterSecureStorage? secureStorage,
  })  : _api = api ?? ApiService(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const autoReflectKey = 'settings.auto_reflect.v1';
  static const appShellModeKey = 'app_shell_mode.v1';
  static const sageSettingsKey = 'sage_settings_v1';
  static const sageMemoryItemsKey = 'sage_memory_items_v1';
  static const notificationNudgesKey = 'notification_nudges.settings.v1';
  static const _legacyNotificationNudgesKey = 'notification_nudges.v1';
  static const _dirtyStorageKey = 'settings_dirty.v1';
  static const _localUpdatedAtStorageKey = 'settings_updated_at.v1';

  final ApiService _api;
  final FlutterSecureStorage _secureStorage;

  Future<bool> loadCachedAutoReflect() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(autoReflectKey) ?? true;
  }

  Future<void> saveAutoReflect(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await markLocalSettingsDirty();
    await prefs.setBool(autoReflectKey, enabled);
    await _pushAutoReflect(enabled);
    await pushLocalSettingsToServer(throwOnFailure: true);
  }

  Future<void> markLocalSettingsDirty() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dirtyStorageKey, true);
    await prefs.setString(
      _localUpdatedAtStorageKey,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> restoreFromServer() async {
    final hadLocalSettings = await _hasLocalSettings();

    try {
      final remote = await _api.getUserSettings();
      final appPreferences = _asMap(remote['app_preferences']) ??
          _asMap(remote['preferences']) ??
          const <String, dynamic>{};
      _debugLog(
        'restore fetched app_preferences keys: '
        '${appPreferences.keys.toList()}',
      );

      final hasRemotePreferences = appPreferences.isNotEmpty ||
          remote['auto_reflect'] is bool ||
          remote['preferred_tone'] != null;

      if (!hasRemotePreferences) {
        if (hadLocalSettings) {
          _debugLog('restore found no remote settings; pushed local seed');
          await pushLocalSettingsToServer();
        }
        return;
      }

      await _hydrateLocalSettings(remote, appPreferences);
      _debugLog('restore hydrated local settings');
    } on DioException {
      _debugLog('restore failed with DioException');
      // Startup/account-restore sync must never block local app usage.
    } catch (e) {
      _debugLog('restore failed: $e');
    }
  }

  Future<bool> pushLocalSettingsToServer({bool throwOnFailure = false}) async {
    try {
      if (!await _hasPendingLocalChanges()) {
        await markLocalSettingsDirty();
      }
      final payload = await _buildServerPayload();
      _debugLog(
        'push starting auto_reflect=${payload['auto_reflect']} '
        'updated_at=${_asMap(payload['app_preferences'])?['client_updated_at']}',
      );
      await _api.updateUserSettings(payload);
      await _setPendingLocalChanges(false);
      _debugLog('push completed');
      return true;
    } on DioException catch (e) {
      _debugLog(
        'push failed with DioException status=${e.response?.statusCode} '
        'type=${e.type} message=${e.message} data=${e.response?.data}',
      );
      if (throwOnFailure) rethrow;
      // Local-first settings remain saved even when background sync misses.
    } catch (e) {
      _debugLog('push failed: $e');
      if (throwOnFailure) rethrow;
    }
    return false;
  }

  Future<Map<String, dynamic>> _buildServerPayload() async {
    final prefs = await SharedPreferences.getInstance();
    final autoReflect = prefs.getBool(autoReflectKey) ?? true;
    final updatedAt = prefs.getString(_localUpdatedAtStorageKey) ??
        DateTime.now().toUtc().toIso8601String();
    final appPreferences = <String, dynamic>{
      'schema_version': 1,
      'client_updated_at': updatedAt,
    };

    final appShellMode = prefs.getString(appShellModeKey);
    if (appShellMode != null && appShellMode.isNotEmpty) {
      appPreferences['app_shell_mode'] = appShellMode;
    }

    // Security (H8/H9): nudge settings (contain GPS coords) now live in
    // secure storage. SharedPreferences reads remain as legacy fallback for
    // values written before the migration.
    final notificationNudges =
        _decodeMap(await _secureStorage.read(key: notificationNudgesKey)) ??
            _decodeMap(prefs.getString(notificationNudgesKey)) ??
            _decodeMap(prefs.getString(_legacyNotificationNudgesKey));
    if (notificationNudges != null) {
      appPreferences['notification_nudges'] = notificationNudges;
    }

    final sageSettings =
        _decodeMap(await _secureStorage.read(key: sageSettingsKey));
    if (sageSettings != null) {
      appPreferences['sage_settings'] = sageSettings;
    }

    final sageMemory =
        _decodeList(await _secureStorage.read(key: sageMemoryItemsKey));
    if (sageMemory != null) {
      appPreferences['sage_memory_items'] = sageMemory;
    }

    return {
      'auto_reflect': autoReflect,
      'app_preferences': appPreferences,
    };
  }

  Future<void> _hydrateLocalSettings(
    Map<String, dynamic> remote,
    Map<String, dynamic> appPreferences,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final autoReflect = remote['auto_reflect'];
    if (autoReflect is bool) {
      await prefs.setBool(autoReflectKey, autoReflect);
    }

    final remoteUpdatedAt = appPreferences['client_updated_at']?.toString();
    if (remoteUpdatedAt != null && remoteUpdatedAt.isNotEmpty) {
      await prefs.setString(_localUpdatedAtStorageKey, remoteUpdatedAt);
    }

    final appShellMode = appPreferences['app_shell_mode']?.toString();
    if (appShellMode != null && appShellMode.isNotEmpty) {
      await prefs.setString(appShellModeKey, appShellMode);
    }

    final notificationNudges = _asMap(appPreferences['notification_nudges']);
    if (notificationNudges != null) {
      // Security (H8/H9): write to secure storage and drop any plaintext copy.
      await _secureStorage.write(
        key: notificationNudgesKey,
        value: jsonEncode(notificationNudges),
      );
      await prefs.remove(notificationNudgesKey);
    }

    final sageSettings = _asMap(appPreferences['sage_settings']);
    if (sageSettings != null) {
      await _secureStorage.write(
        key: sageSettingsKey,
        value: jsonEncode(sageSettings),
      );
      SageProfileService.clearSettingsCache();
    }

    final sageMemory = appPreferences['sage_memory_items'];
    if (sageMemory is List) {
      await _secureStorage.write(
        key: sageMemoryItemsKey,
        value: jsonEncode(sageMemory),
      );
    }

    await _setPendingLocalChanges(false);
  }

  Future<bool> _hasLocalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(autoReflectKey) ||
        prefs.containsKey(appShellModeKey) ||
        prefs.containsKey(notificationNudgesKey) ||
        prefs.containsKey(_legacyNotificationNudgesKey)) {
      return true;
    }

    final nudges = await _secureStorage.read(key: notificationNudgesKey);
    if (nudges != null && nudges.isNotEmpty) return true;
    final sageSettings = await _secureStorage.read(key: sageSettingsKey);
    if (sageSettings != null && sageSettings.isNotEmpty) return true;
    final sageMemory = await _secureStorage.read(key: sageMemoryItemsKey);
    return sageMemory != null && sageMemory.isNotEmpty;
  }

  Future<bool> _hasPendingLocalChanges() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dirtyStorageKey) ?? false;
  }

  Future<void> _setPendingLocalChanges(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dirtyStorageKey, value);
  }

  Future<void> _pushAutoReflect(bool enabled) async {
    try {
      await _api.setReflectMode(enabled);
    } on DioException {
      // The generic settings push also carries this value when available.
    } catch (_) {}
  }

  Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return _asMap(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  List<dynamic>? _decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[settings-sync] $message');
    }
  }
}
