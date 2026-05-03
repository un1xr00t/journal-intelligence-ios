import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class JournalPinService {
  JournalPinService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const int pinLength = 4;
  static const _digestPrefix = 'journal_pin_digest_v1_';
  static const _saltPrefix = 'journal_pin_salt_v1_';

  Future<bool> hasPin(String username) async {
    final scopedUser = _scopeUser(username);
    if (scopedUser == null) return false;
    final digest = await _storage.read(key: _digestKey(scopedUser));
    final salt = await _storage.read(key: _saltKey(scopedUser));
    return digest != null && digest.isNotEmpty && salt != null && salt.isNotEmpty;
  }

  Future<void> setPin(String username, String pin) async {
    final scopedUser = _requireScopedUser(username);
    final normalizedPin = _normalizePin(pin);
    final salt = _generateSalt();
    final digest = _deriveDigest(
      username: scopedUser,
      pin: normalizedPin,
      salt: salt,
    );
    await _storage.write(key: _saltKey(scopedUser), value: salt);
    await _storage.write(key: _digestKey(scopedUser), value: digest);
  }

  Future<bool> verifyPin(String username, String pin) async {
    final scopedUser = _scopeUser(username);
    if (scopedUser == null) return false;
    final normalizedPin = _normalizePin(pin);
    final storedSalt = await _storage.read(key: _saltKey(scopedUser));
    final storedDigest = await _storage.read(key: _digestKey(scopedUser));
    if (storedSalt == null || storedDigest == null) return false;
    final computed = _deriveDigest(
      username: scopedUser,
      pin: normalizedPin,
      salt: storedSalt,
    );
    return computed == storedDigest;
  }

  Future<void> clearPin(String username) async {
    final scopedUser = _scopeUser(username);
    if (scopedUser == null) return;
    await _storage.delete(key: _saltKey(scopedUser));
    await _storage.delete(key: _digestKey(scopedUser));
  }

  static bool isValidPin(String pin) {
    return RegExp(r'^\d{4}$').hasMatch(pin);
  }

  String _normalizePin(String pin) {
    final trimmed = pin.trim();
    if (!isValidPin(trimmed)) {
      throw ArgumentError('PIN must be exactly 4 digits.');
    }
    return trimmed;
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _deriveDigest({
    required String username,
    required String pin,
    required String salt,
  }) {
    var value = '$username::$salt::$pin';
    var hash = _fnv1a64(utf8.encode(value));
    for (var round = 0; round < 4096; round++) {
      value = '$username::$salt::$pin::$hash::$round';
      hash = _fnv1a64(utf8.encode(value));
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  int _fnv1a64(List<int> bytes) {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash;
  }

  String _digestKey(String scopedUser) => '$_digestPrefix$scopedUser';
  String _saltKey(String scopedUser) => '$_saltPrefix$scopedUser';

  String _requireScopedUser(String username) {
    final scopedUser = _scopeUser(username);
    if (scopedUser == null) {
      throw ArgumentError('A signed-in username is required to manage the PIN.');
    }
    return scopedUser;
  }

  String? _scopeUser(String username) {
    final trimmed = username.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    return trimmed.replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
  }
}
