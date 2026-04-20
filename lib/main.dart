// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthProvider(),
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Attempt session restore on cold boot
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().init();
    });
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
        child: Consumer<AuthProvider>(
          builder: (context, auth, _) {
            return switch (auth.state) {
              AuthState.unknown         => const SplashScreen(),
              AuthState.authenticated   => const HomeShell(),
              AuthState.unauthenticated => const LoginScreen(),
            };
          },
        ),
      ),
    );
  }
}