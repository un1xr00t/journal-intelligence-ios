// lib/providers/auth_provider.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/follow_up_tasks_service.dart';
import '../services/orbit_ledger_service.dart';
import '../services/user_settings_sync_service.dart';

enum AuthState { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final UserSettingsSyncService _settingsSync = UserSettingsSyncService();
  final FollowUpTaskService _followUpTasks = FollowUpTaskService();
  final OrbitLedgerService _orbitLedger = OrbitLedgerService();

  AuthState _state = AuthState.unknown;
  Map<String, dynamic>? _user;
  String? _error;
  bool _loading = false;
  bool _lastAuthWasSessionRestore = false;
  bool _restoreInFlight = false;

  AuthState get state => _state;
  Map<String, dynamic>? get user => _user;
  String? get error => _error;
  bool get loading => _loading;
  bool get isAuthenticated => _state == AuthState.authenticated;
  bool get lastAuthWasSessionRestore => _lastAuthWasSessionRestore;

  // ── Init — try to restore session via refresh cookie ─────────

  Future<void> init() async {
    try {
      final newToken = await _api.refreshAccessToken();
      if (newToken != null) {
        _api.setAccessToken(newToken);
        _user = await _api.getMe();
        _state = AuthState.authenticated;
        _lastAuthWasSessionRestore = true;
        _restoreServerBackedLocalDataInBackground();
      } else {
        _state = AuthState.unauthenticated;
        _lastAuthWasSessionRestore = false;
      }
    } catch (_) {
      _state = AuthState.unauthenticated;
      _lastAuthWasSessionRestore = false;
    }
    notifyListeners();
  }

  // ── Login (standard — used for biometric quick-login) ─────────
  //
  // Transitions state immediately on success. Use loginGetToken
  // when you need to show UI (e.g. biometric offer) before navigating.

  Future<Map<String, dynamic>?> login(String username, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _api.login(username, password);

      if (data['requires_2fa'] == true) {
        _loading = false;
        notifyListeners();
        return data;
      }

      _api.setAccessToken(data['access_token'] as String);
      _user = await _api.getMe();
      _state = AuthState.authenticated;
      _lastAuthWasSessionRestore = false;
      _restoreServerBackedLocalDataInBackground();
      _loading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _error = _parseError(e);
      _loading = false;
      notifyListeners();
      return null;
    }
  }

  // ── Login (pre-transition) ────────────────────────────────────
  //
  // Fetches token + user but does NOT set AuthState.authenticated.
  // Caller shows any post-login UI (biometric dialog etc) then calls
  // completeAuthentication() to navigate to HomeShell.
  //
  // Returns:
  //   { requires_2fa: true, partial_token: '...' }  →  2FA required
  //   { token: '...', user: {...} }                 →  success, call completeAuthentication()
  //   null                                          →  error, check auth.error

  Future<Map<String, dynamic>?> loginGetToken(
      String username, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.login(username, password);
      if (data['requires_2fa'] == true) {
        _loading = false;
        notifyListeners();
        return data;
      }
      _api.setAccessToken(data['access_token'] as String);
      final user = await _api.getMe();
      _loading = false;
      notifyListeners();
      return {'token': data['access_token'] as String, 'user': user};
    } catch (e) {
      _error = _parseError(e);
      _loading = false;
      notifyListeners();
      return null;
    }
  }

  /// Completes the auth transition after post-login UI is done.
  Future<void> completeAuthentication(Map<String, dynamic> user) async {
    _user = user;
    _state = AuthState.authenticated;
    _lastAuthWasSessionRestore = false;
    _restoreServerBackedLocalDataInBackground();
    notifyListeners();
  }

  // ── Complete login after 2FA ──────────────────────────────────

  Future<bool> complete2FA(String partialToken, String code) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.verify2FA(partialToken, code);
      _api.setAccessToken(data['access_token'] as String);
      _user = await _api.getMe();
      _state = AuthState.authenticated;
      _lastAuthWasSessionRestore = false;
      _restoreServerBackedLocalDataInBackground();
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _parseError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  // ── 2FA backup code ───────────────────────────────────────────

  Future<bool> completeWithBackupCode(String partialToken, String code) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.useBackupCode(partialToken, code);
      _api.setAccessToken(data['access_token'] as String);
      _user = await _api.getMe();
      _state = AuthState.authenticated;
      _lastAuthWasSessionRestore = false;
      _restoreServerBackedLocalDataInBackground();
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _parseError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  // ── Passkey ───────────────────────────────────────────────────

  Future<Map<String, dynamic>?> passkeyAuthBegin() async {
    try {
      return await _api.passkeyAuthBegin();
    } catch (e) {
      _error = _parseError(e);
      notifyListeners();
      return null;
    }
  }

  Future<bool> passkeyAuthComplete(
      String challengeId, Map<String, dynamic> credential) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.passkeyAuthComplete(
          challengeId: challengeId, credential: credential);
      _api.setAccessToken(data['access_token'] as String);
      _user = await _api.getMe();
      _state = AuthState.authenticated;
      _lastAuthWasSessionRestore = false;
      _restoreServerBackedLocalDataInBackground();
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _parseError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  // ── Logout ────────────────────────────────────────────────────

  Future<void> logout() async {
    await _api.logout();
    _user = null;
    _state = AuthState.unauthenticated;
    _lastAuthWasSessionRestore = false;
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────

  Future<void> _restoreServerBackedLocalData() async {
    await _settingsSync.restoreFromServer();
    await _followUpTasks.syncTasksFromServer();
    await _orbitLedger.syncEntriesFromServer();
    await _api.migrateLocalSavedFloatchatConversationsToServer();
  }

  void _restoreServerBackedLocalDataInBackground() {
    if (_restoreInFlight) return;
    _restoreInFlight = true;
    unawaited(() async {
      try {
        await _restoreServerBackedLocalData();
      } finally {
        _restoreInFlight = false;
        notifyListeners();
      }
    }());
  }

  void setError(String message) {
    _error = message;
    notifyListeners();
  }

  String _parseError(dynamic e) {
    if (e is Error) {
      return e.toString();
    }
    if (e is Exception) {
      final str = e.toString();
      if (str.contains('"detail"')) {
        final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
        if (match != null) return match.group(1)!;
      }
      if (str.contains('PlatformException(') ||
          str.contains('MissingPluginException')) {
        return str;
      }
      if (str.contains('SocketException') || str.contains('connection')) {
        return 'Cannot reach the server. Check your connection.';
      }
    }
    return 'Something went wrong. Please try again.';
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
