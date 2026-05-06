// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/app_lock_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/app_shell_mode_provider.dart';
import 'providers/launch_intent_provider.dart';
import 'services/launch_route_service.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/pin_unlock_screen.dart';
import 'screens/quiet_journal_shell.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AppLockProvider()),
        ChangeNotifierProvider(create: (_) => AppShellModeProvider()),
        ChangeNotifierProvider(create: (_) => LaunchIntentProvider()),
      ],
      child: const JournalApp(),
    ),
  );
}

class JournalApp extends StatefulWidget {
  const JournalApp({super.key});

  @override
  State<JournalApp> createState() => _JournalAppState();
}

class _JournalAppState extends State<JournalApp> with WidgetsBindingObserver {
  final _launchRouteService = LaunchRouteService();
  AuthProvider? _authProvider;
  bool _bootstrapping = true;
  bool _lifecycleLockEnabled = false;

  Future<bool> _handleExternalRoute(String? route) async {
    if (!mounted) return false;
    final handled = context.read<LaunchIntentProvider>().registerRoute(route);
    if (handled && route != null && route.trim().isNotEmpty) {
      await _launchRouteService.persistPendingRoute(route);
    }
    return handled;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _launchRouteService.routes.listen((route) {
      unawaited(_handleExternalRoute(route));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapAppLaunch());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_authProvider != null) return;
    _authProvider = context.read<AuthProvider>();
    _authProvider!.addListener(_handleAuthChanged);
  }

  Future<void> _bootstrapAppLaunch() async {
    final launchIntent = context.read<LaunchIntentProvider>();
    final auth = context.read<AuthProvider>();
    final appLock = context.read<AppLockProvider>();
    final initialRoute = await _launchRouteService.getInitialRoute();
    final persistedRoute = await _launchRouteService.getPersistedPendingRoute();
    final routeToRegister = initialRoute ??
        persistedRoute ??
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    if (mounted) {
      final handled = launchIntent.registerRoute(routeToRegister);
      if (handled && routeToRegister.trim().isNotEmpty) {
        await _launchRouteService.persistPendingRoute(routeToRegister);
      } else {
        await _launchRouteService.clearPersistedPendingRoute();
      }
      await auth.init();
      if (!mounted) return;
      final username = auth.user?['username']?.toString().trim() ?? '';
      if (auth.isAuthenticated && username.isNotEmpty) {
        await context.read<AppShellModeProvider>().reloadFromLocalStorage();
        await appLock.prepareForAuthenticatedUser(
          username,
          lockImmediately: auth.lastAuthWasSessionRestore,
        );
      } else {
        appLock.clearSessionState();
      }
      if (mounted) {
        setState(() {
          _bootstrapping = false;
          _lifecycleLockEnabled = true;
        });
      }
    }
  }

  Future<void> _handleAuthChanged() async {
    if (!mounted) return;
    final auth = _authProvider;
    if (auth == null) return;
    final appLock = context.read<AppLockProvider>();
    if (auth.isAuthenticated) {
      final username = auth.user?['username']?.toString().trim() ?? '';
      if (username.isNotEmpty) {
        await context.read<AppShellModeProvider>().reloadFromLocalStorage();
        await appLock.prepareForAuthenticatedUser(
          username,
          lockImmediately: auth.lastAuthWasSessionRestore,
        );
      }
      return;
    }
    if (auth.state == AuthState.unauthenticated) {
      appLock.clearSessionState();
    }
  }

  @override
  Future<bool> didPushRoute(String route) {
    return _handleExternalRoute(route);
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    return _handleExternalRoute(routeInformation.uri.toString());
  }

  @override
  void didChangeMetrics() {
    // iOS 26 beta reports 0x0 on first frame then fires this when real bounds arrive
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_lifecycleLockEnabled || !mounted) return;
    final appLock = context.read<AppLockProvider>();
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        appLock.armForResumeLock();
        break;
      case AppLifecycleState.resumed:
        appLock.handleAppResumed(
          authenticated: context.read<AuthProvider>().isAuthenticated,
        );
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_handleAuthChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Journal Intelligence',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: Consumer4<AuthProvider, LaunchIntentProvider,
            AppShellModeProvider, AppLockProvider>(
          builder: (context, auth, launchIntent, shellMode, appLock, _) {
            if (!launchIntent.hasPendingIntent) {
              unawaited(_launchRouteService.clearPersistedPendingRoute());
            }
            if (_bootstrapping) {
              return const SplashScreen();
            }
            return switch (auth.state) {
              AuthState.unknown => const SplashScreen(),
              AuthState.authenticated => appLock.isLocked
                  ? PinUnlockScreen.unlock(
                      username: auth.user?['username']?.toString(),
                      onUnlock: appLock.unlockWithPin,
                      onSignOut: () => auth.logout(),
                    )
                  : shellMode.isQuietJournal
                      ? QuietJournalShell(initialTab: launchIntent.activeTab)
                      : HomeShell(initialTab: launchIntent.activeTab),
              AuthState.unauthenticated => const LoginScreen(),
            };
          },
        ),
      ),
    );
  }
}
