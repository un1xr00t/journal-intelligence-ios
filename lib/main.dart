// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/app_shell_mode_provider.dart';
import 'providers/launch_intent_provider.dart';
import 'services/launch_route_service.dart';
import 'screens/quiet_journal_shell.dart';
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
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

  Future<void> _bootstrapAppLaunch() async {
    final launchIntent = context.read<LaunchIntentProvider>();
    final auth = context.read<AuthProvider>();
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
      auth.init();
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
  void dispose() {
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
        child:
            Consumer3<AuthProvider, LaunchIntentProvider, AppShellModeProvider>(
          builder: (context, auth, launchIntent, shellMode, _) {
            if (!launchIntent.hasPendingIntent) {
              unawaited(_launchRouteService.clearPersistedPendingRoute());
            }
            return switch (auth.state) {
              AuthState.unknown => const SplashScreen(),
              AuthState.authenticated => shellMode.isQuietJournal
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
