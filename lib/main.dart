// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/launch_intent_provider.dart';
import 'services/launch_route_service.dart';
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
    return context.read<LaunchIntentProvider>().registerRoute(route);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final launchIntent = context.read<LaunchIntentProvider>();
      launchIntent.registerRoute(
        WidgetsBinding.instance.platformDispatcher.defaultRouteName,
      );
      context.read<AuthProvider>().init();
    });

    _launchRouteService.routes.listen((route) {
      _handleExternalRoute(route);
    });
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
        child: Consumer2<AuthProvider, LaunchIntentProvider>(
          builder: (context, auth, launchIntent, _) {
            return switch (auth.state) {
              AuthState.unknown => const SplashScreen(),
              AuthState.authenticated =>
                HomeShell(initialTab: launchIntent.activeTab),
              AuthState.unauthenticated => const LoginScreen(),
            };
          },
        ),
      ),
    );
  }
}
