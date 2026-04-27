import 'package:flutter/services.dart';

class LaunchRouteService {
  static const _eventChannel =
      EventChannel('journal_intelligence/launch_route/events');

  Stream<String>? _routes;

  Stream<String> get routes {
    return _routes ??= _eventChannel.receiveBroadcastStream().map((event) {
      return event?.toString() ?? '';
    }).where((route) => route.trim().isNotEmpty);
  }
}
