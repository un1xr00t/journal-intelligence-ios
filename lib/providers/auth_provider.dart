// lib/providers/auth_provider.dart
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

enum AuthState { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  AuthState _state = AuthState.unknown;
  Map<String, dynamic>? _user;
  String? _error;
  bool _loading = false;

  AuthState get state => _state;
  Map<String, dynamic>? get user => _user;
  String? get error => _error;
  bool get loading => _loading;
  bool get isAuthenticated => _state == AuthState.authenticated;

  // ── Init — try to restore session via refresh cookie ─────────

  Future<void> init() async {
    try {
      final newToken = await _api.refreshAccessToken();
      if (newToken != null) {
        _api.setAccessToken(newToken);
        _user = await _api.getMe();
        _state = AuthState.authenticated;
      } else {
        _state = AuthState.unauthenticated;
      }
    } catch (_) {
      _state = AuthState.unauthenticated;
    }
    notifyListeners();
  }

  // ── Login ─────────────────────────────────────────────────────

  /// Returns null on success, or a map with requires_2fa + partial_token on 2FA.
  Future<Map<String, dynamic>?> login(String username, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _api.login(username, password);

      if (data['requires_2fa'] == true) {
        _loading = false;
        notifyListeners();
        return data; // Caller handles 2FA screen
      }

      _api.setAccessToken(data['access_token'] as String);
      _user = await _api.getMe();
      _state = AuthState.authenticated;
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
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _parseError(dynamic e) {
    if (e is Exception) {
      final str = e.toString();
      // Dio error with response body
      if (str.contains('"detail"')) {
        final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
        if (match != null) return match.group(1)!;
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
