import 'package:flutter/foundation.dart';

class LaunchIntentProvider extends ChangeNotifier {
  int _activeTab = 0;
  int? _pendingTab;
  int _intentVersion = 0;
  int _handledVersion = 0;
  Uri? _lastUri;

  int get activeTab => _activeTab;
  int? get pendingTab => _pendingTab;
  int get intentVersion => _intentVersion;
  String? get lastRoute => _lastUri?.toString();
  String? get routePath => _lastUri?.path;
  String? get writePrefillText => _lastUri?.queryParameters['prefill'];
  String? get sagePrefillText => _lastUri?.queryParameters['prefill'];
  bool get shouldAutoSendSagePrefill =>
      _lastUri?.queryParameters['auto_send'] == '1';
  String? get companionFocus => _lastUri?.queryParameters['focus'];
  bool get hasPendingIntent => _intentVersion != _handledVersion;
  bool get shouldOpenCarPlayCompanion =>
      hasPendingIntent && routePath == '/carplay';
  bool get shouldOpenSage => hasPendingIntent && routePath == '/sage';

  bool registerRoute(String? rawRoute) {
    final normalizedRoute = _normalizeRoute(rawRoute);
    final routePath = normalizedRoute?.path;
    final tab = _tabForRoute(routePath);
    if (tab == null) return false;

    _lastUri = normalizedRoute;
    _activeTab = tab;
    _pendingTab = tab;
    _intentVersion += 1;
    notifyListeners();
    return true;
  }

  void markHandled(int version) {
    if (version != _intentVersion) return;
    _handledVersion = version;
    _pendingTab = null;
    notifyListeners();
  }

  void setActiveTab(int tab) {
    if (_activeTab == tab) return;
    _activeTab = tab;
    notifyListeners();
  }

  Uri? _normalizeRoute(String? rawRoute) {
    if (rawRoute == null) return null;

    final trimmed = rawRoute.trim();
    if (trimmed.isEmpty || trimmed == '/') return null;

    final uri = Uri.tryParse(trimmed);
    String route = trimmed;
    Map<String, String> queryParameters = const <String, String>{};

    if (uri != null && uri.scheme.isNotEmpty) {
      final hostRoute = uri.host.isNotEmpty ? '/${uri.host}' : '';
      route = uri.path.isNotEmpty && uri.path != '/' ? uri.path : hostRoute;
      queryParameters = uri.queryParameters;
    } else if (uri != null) {
      route = uri.path.isNotEmpty ? uri.path : route;
      queryParameters = uri.queryParameters;
    }

    if (route.isEmpty || route == '/') return null;
    if (!route.startsWith('/')) route = '/$route';
    return Uri(path: route.toLowerCase(), queryParameters: queryParameters);
  }

  int? _tabForRoute(String? routeName) {
    return switch (routeName) {
      '/carplay' => 0,
      '/today' => 0,
      '/timeline' => 1,
      '/write' || '/compose' => 2,
      '/ask' || '/intelligence' || '/sage' || '/detective' => 3,
      '/more' || '/settings' => 4,
      _ => null,
    };
  }
}
