import 'package:flutter/foundation.dart';

import '../services/journal_pin_service.dart';

class AppLockProvider extends ChangeNotifier {
  AppLockProvider({JournalPinService? pinService})
      : _pinService = pinService ?? JournalPinService();

  final JournalPinService _pinService;

  String? _activeUsername;
  bool _pinEnabled = false;
  bool _locked = false;
  bool _configLoaded = false;
  bool _resumeLockArmed = false;

  String? get activeUsername => _activeUsername;
  bool get pinEnabled => _pinEnabled;
  bool get isLocked => _pinEnabled && _locked;
  bool get isReady => _configLoaded;
  bool get canManagePin => _activeUsername != null && _activeUsername!.isNotEmpty;

  Future<void> prepareForAuthenticatedUser(
    String username, {
    required bool lockImmediately,
  }) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return;

    final enabled = await _pinService.hasPin(trimmed);
    final sameUser = _activeUsername == trimmed;
    final nextLocked = lockImmediately && enabled
        ? true
        : sameUser
            ? (_locked && enabled)
            : false;
    final shouldNotify = _activeUsername != trimmed ||
        _pinEnabled != enabled ||
        _locked != nextLocked ||
        !_configLoaded;

    _activeUsername = trimmed;
    _pinEnabled = enabled;
    _locked = nextLocked;
    _configLoaded = true;
    _resumeLockArmed = false;

    if (shouldNotify) notifyListeners();
  }

  void clearSessionState() {
    final hadState =
        _activeUsername != null || _pinEnabled || _locked || _configLoaded;
    _activeUsername = null;
    _pinEnabled = false;
    _locked = false;
    _configLoaded = false;
    _resumeLockArmed = false;
    if (hadState) notifyListeners();
  }

  void armForResumeLock() {
    if (!_pinEnabled) return;
    _resumeLockArmed = true;
  }

  void handleAppResumed({required bool authenticated}) {
    if (!_resumeLockArmed) return;
    _resumeLockArmed = false;
    if (!authenticated || !_pinEnabled || _locked) return;
    _locked = true;
    notifyListeners();
  }

  Future<void> setPin(String pin) async {
    final username = _requireUsername();
    await _pinService.setPin(username, pin);
    final shouldNotify = !_pinEnabled || _locked;
    _pinEnabled = true;
    _locked = false;
    _configLoaded = true;
    if (shouldNotify) notifyListeners();
  }

  Future<void> disablePin() async {
    final username = _requireUsername();
    await _pinService.clearPin(username);
    final shouldNotify = _pinEnabled || _locked;
    _pinEnabled = false;
    _locked = false;
    _resumeLockArmed = false;
    if (shouldNotify) notifyListeners();
  }

  Future<bool> unlockWithPin(String pin) async {
    final username = _requireUsername();
    final isValid = await _pinService.verifyPin(username, pin);
    if (isValid && _locked) {
      _locked = false;
      notifyListeners();
    }
    return isValid;
  }

  String _requireUsername() {
    final username = _activeUsername;
    if (username == null || username.trim().isEmpty) {
      throw StateError('No authenticated user is available for PIN management.');
    }
    return username;
  }
}
