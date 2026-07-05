import 'package:flutter/foundation.dart';

class LaunchIntentProvider extends ChangeNotifier {
  int _activeTab = 0;
  int? _pendingTab;
  int _intentVersion = 0;
  int _handledVersion = 0;
  Uri? _lastUri;

  // Bug fix: /write prefill must be one-shot. _lastUri lives for the whole
  // session, and WriteScreen state is recreated on every tab switch, so a
  // fresh state would otherwise re-read the same stale notification prefill
  // and re-inject it every time the Write tab is opened.
  bool _writePrefillConsumed = false;

  int get activeTab => _activeTab;
  int? get pendingTab => _pendingTab;
  int get intentVersion => _intentVersion;
  String? get lastRoute => _lastUri?.toString();
  String? get routePath => _lastUri?.path;
  String? get writePrefillText =>
      _writePrefillConsumed ? null : _lastUri?.queryParameters['prefill'];
  String? get sagePrefillText => _lastUri?.queryParameters['prefill'];
  String? get siriCaptureText => _lastUri?.queryParameters['prefill'];
  String? get siriCaptureSource => _lastUri?.queryParameters['source'];
  String? get siriCaptureReviewReason =>
      _lastUri?.queryParameters['review_reason'];
  String? get siriCapturePreferredFolder =>
      _lastUri?.queryParameters['preferred_folder'];
  bool get siriCaptureJournalOnly =>
      _lastUri?.queryParameters['journal_only'] == '1';
  bool get shouldAutoSendSagePrefill =>
      _lastUri?.queryParameters['auto_send'] == '1';
  bool get shouldAutoSaveSiriCapture =>
      _lastUri?.queryParameters['auto_save'] == '1';
  String? get companionFocus => _lastUri?.queryParameters['focus'];
  bool get hasPendingIntent => _intentVersion != _handledVersion;
  bool get shouldOpenCarPlayCompanion =>
      hasPendingIntent && routePath == '/carplay';
  bool get shouldOpenSage => hasPendingIntent && routePath == '/sage';
  bool get shouldOpenSiriCapture =>
      hasPendingIntent && routePath == '/siri-capture';

  bool registerRoute(String? rawRoute) {
    final normalizedRoute = _normalizeRoute(rawRoute);
    final routePath = normalizedRoute?.path;
    final tab = _tabForRoute(routePath);
    if (tab == null) return false;

    _lastUri = normalizedRoute;
    _writePrefillConsumed = false;
    _activeTab = tab;
    _pendingTab = tab;
    _intentVersion += 1;
    notifyListeners();
    return true;
  }

  /// Returns the /write (or /compose) prefill exactly once per registered
  /// intent. Later calls — e.g. from a recreated WriteScreen state after a
  /// tab switch — return null, so a stale notification route can't keep
  /// re-injecting its prompt into the composer.
  ///
  /// Intentionally does NOT call notifyListeners: it is invoked from widget
  /// lifecycle/listener callbacks and only marks the prefill as spent.
  String? takeWritePrefill() {
    if (_writePrefillConsumed) return null;
    final prefill = _lastUri?.queryParameters['prefill']?.trim();
    if (prefill == null || prefill.isEmpty) return null;
    _writePrefillConsumed = true;
    return prefill;
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
      '/write' || '/compose' || '/siri-capture' => 2,
      '/ask' || '/intelligence' || '/sage' || '/detective' => 3,
      '/more' || '/settings' || '/inbox' || '/sage-inbox' => 4,
      _ => null,
    };
  }
}
