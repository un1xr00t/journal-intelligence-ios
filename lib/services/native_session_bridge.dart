import 'package:flutter/services.dart';

class NativeSessionBridge {
  NativeSessionBridge._();

  static const MethodChannel _channel =
      MethodChannel('journal_intelligence/native_session');

  static Future<void> syncFromSetCookieHeaders(List<String> headers) async {
    if (headers.isEmpty) return;
    await _channel.invokeMethod<void>(
      'syncFromSetCookieHeaders',
      <String, dynamic>{'headers': headers},
    );
  }

  static Future<void> clear() {
    return _channel.invokeMethod<void>('clear');
  }
}
