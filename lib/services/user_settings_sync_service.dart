import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
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
  static const notificationNudgesKey = 'notification_nudges.v1';

  final ApiService _api;
  final FlutterSecureStorage _secureStorage;

  Future<bool> loadCachedAutoReflect() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(autoReflectKey) ?? true;
  }

  Future<void> saveAutoReflect(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(autoReflectKey, enabled);
    unawaited(_pushAutoReflect(enabled));
    unawaited(pushLocalSettingsToServer());
  }

  Future<void> restoreFromServer() async {
    final hadLocalSettings = await _hasLocalSettings();
    try {
      final remote = await _api.getUserSettings();
      final appPreferences = _asMap(remote['app_preferences']) ??
          _asMap(remote['preferences']) ??
          const <String, dynamic>{};

      final hasRemotePreferences = appPreferences.isNotEmpty ||
          remote['auto_reflect'] is bool ||
          remote['preferred_tone'] != null;

      if (hadLocalSettings) {
        unawaited(pushLocalSettingsToServer());
        return;
      }

      if (!hasRemotePreferences) {
        return;
      }

      await _hydrateLocalSettings(remote, appPreferences);
    } on DioException {
      // Startup/account-restore sync must never block local app usage.
    } catch (_) {}
  }

  Future<void> pushLocalSettingsToServer() async {
    try {
      await _api.updateUserSettings(await _buildServerPayload());
    } on DioException {
      // Local-first settings remain saved even when background sync misses.
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _buildServerPayload() async {
    final prefs = await SharedPreferences.getInstance();
    final autoReflect = prefs.getBool(autoReflectKey) ?? true;
    final appPreferences = <String, dynamic>{
      'schema_version': 1,
      'client_updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    final appShellMode = prefs.getString(appShellModeKey);
    if (appShellMode != null && appShellMode.isNotEmpty) {
      appPreferences['app_shell_mode'] = appShellMode;
    }

    final notificationNudges =
        _decodeMap(prefs.getString(notificationNudgesKey));
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

    final appShellMode = appPreferences['app_shell_mode']?.toString();
    if (appShellMode != null && appShellMode.isNotEmpty) {
      await prefs.setString(appShellModeKey, appShellMode);
    }

    final notificationNudges = _asMap(appPreferences['notification_nudges']);
    if (notificationNudges != null) {
      await prefs.setString(
          notificationNudgesKey, jsonEncode(notificationNudges));
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
  }

  Future<bool> _hasLocalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(autoReflectKey) ||
        prefs.containsKey(appShellModeKey) ||
        prefs.containsKey(notificationNudgesKey)) {
      return true;
    }

    final sageSettings = await _secureStorage.read(key: sageSettingsKey);
    if (sageSettings != null && sageSettings.isNotEmpty) return true;
    final sageMemory = await _secureStorage.read(key: sageMemoryItemsKey);
    return sageMemory != null && sageMemory.isNotEmpty;
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
}
