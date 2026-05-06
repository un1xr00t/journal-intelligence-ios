import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/user_settings_sync_service.dart';

enum AppShellMode {
  intelligence,
  quietJournal,
}

class AppShellModeProvider extends ChangeNotifier {
  static const _prefsKey = 'app_shell_mode.v1';

  AppShellMode _mode = AppShellMode.intelligence;
  bool _loaded = false;

  AppShellModeProvider() {
    _load();
  }

  AppShellMode get mode => _mode;
  bool get loaded => _loaded;
  bool get isQuietJournal => _mode == AppShellMode.quietJournal;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      _mode = raw == AppShellMode.quietJournal.name
          ? AppShellMode.quietJournal
          : AppShellMode.intelligence;
    } catch (_) {
      _mode = AppShellMode.intelligence;
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> reloadFromLocalStorage() => _load();

  Future<void> setQuietJournal(bool enabled) async {
    final nextMode =
        enabled ? AppShellMode.quietJournal : AppShellMode.intelligence;
    if (_mode == nextMode) return;

    _mode = nextMode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _mode.name);
      final settingsSync = UserSettingsSyncService();
      await settingsSync.markLocalSettingsDirty();
      await settingsSync.pushLocalSettingsToServer(throwOnFailure: true);
    } catch (_) {}
  }
}
