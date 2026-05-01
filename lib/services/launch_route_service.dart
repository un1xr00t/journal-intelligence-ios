import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LaunchRouteService {
  static const _eventChannel =
      EventChannel('journal_intelligence/launch_route/events');
  static const _methodChannel =
      MethodChannel('journal_intelligence/launch_route');
  static const _pendingRouteKey = 'pending_external_route';

  Stream<String>? _routes;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Stream<String> get routes {
    return _routes ??= _eventChannel.receiveBroadcastStream().map((event) {
      return event?.toString() ?? '';
    }).where((route) => route.trim().isNotEmpty);
  }

  Future<String?> getInitialRoute() async {
    final route = await _methodChannel.invokeMethod<String>('getInitialRoute');
    if (route == null || route.trim().isEmpty) {
      return null;
    }
    return route;
  }

  Future<void> persistPendingRoute(String route) async {
    final trimmed = route.trim();
    if (trimmed.isEmpty) return;
    await _storage.write(key: _pendingRouteKey, value: trimmed);
  }

  Future<String?> getPersistedPendingRoute() async {
    final route = await _storage.read(key: _pendingRouteKey);
    if (route == null || route.trim().isEmpty) return null;
    return route.trim();
  }

  Future<void> clearPersistedPendingRoute() async {
    await _storage.delete(key: _pendingRouteKey);
  }
}
