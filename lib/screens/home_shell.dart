// lib/screens/home_shell.dart
//
// AdaptiveScaffold with iOS 26 Liquid Glass bottom navigation.
// Five tabs: Today · Timeline · Write · Intelligence · More

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../providers/launch_intent_provider.dart';
import 'carplay_companion_screen.dart';

import 'today_screen.dart';
import 'write_screen.dart';
import 'timeline_screen.dart';
import 'ask_journal_screen.dart';
import 'more_screen.dart';
import 'sage_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _selectedIndex;
  LaunchIntentProvider? _launchIntent;
  int _lastHandledIntentVersion = 0;
  bool _carPlayCompanionVisible = false;
  bool _sageVisible = false;

  static const _screens = [
    TodayScreen(),
    TimelineScreen(),
    WriteScreen(),
    AskJournalScreen(),
    MoreScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab.clamp(0, _screens.length - 1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final launchIntent = context.read<LaunchIntentProvider>();
    if (_launchIntent == launchIntent) return;

    _launchIntent?.removeListener(_handleLaunchIntentChange);
    _launchIntent = launchIntent;
    _launchIntent?.addListener(_handleLaunchIntentChange);
    _handleLaunchIntentChange();
  }

  @override
  void didUpdateWidget(HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _selectedIndex = widget.initialTab.clamp(0, _screens.length - 1);
    }
  }

  @override
  void dispose() {
    _launchIntent?.removeListener(_handleLaunchIntentChange);
    super.dispose();
  }

  void _handleLaunchIntentChange() {
    final launchIntent = _launchIntent;
    if (launchIntent == null || !launchIntent.hasPendingIntent) return;

    final version = launchIntent.intentVersion;
    final pendingTab = launchIntent.pendingTab;
    if (version == _lastHandledIntentVersion || pendingTab == null) return;

    final nextTab = pendingTab.clamp(0, _screens.length - 1);
    _lastHandledIntentVersion = version;

    if (mounted && _selectedIndex != nextTab) {
      setState(() => _selectedIndex = nextTab);
    }

    if (launchIntent.shouldOpenCarPlayCompanion && !_carPlayCompanionVisible) {
      final focus = launchIntent.companionFocus ?? 'hub';
      launchIntent.markHandled(version);
      _openCarPlayCompanion(focus);
      return;
    }

    if (launchIntent.shouldOpenSage && !_sageVisible) {
      launchIntent.markHandled(version);
      _openSage();
      return;
    }

    launchIntent.markHandled(version);
  }

  void _openCarPlayCompanion(String focus) {
    _carPlayCompanionVisible = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _carPlayCompanionVisible = false;
        return;
      }
      await Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => CarPlayCompanionScreen(initialFocus: focus),
        ),
      );
      _carPlayCompanionVisible = false;
    });
  }

  void _openSage() {
    _sageVisible = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _sageVisible = false;
        return;
      }
      await pushSageScreen(context);
      _sageVisible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        selectedIndex: _selectedIndex,
        onTap: (i) {
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() => _selectedIndex = i);
          context.read<LaunchIntentProvider>().setActiveTab(i);
        },
        items: [
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS26OrHigher()
                ? "sparkles"
                : CupertinoIcons.sparkles,
            selectedIcon: PlatformInfo.isIOS26OrHigher()
                ? "sparkles"
                : CupertinoIcons.sparkles,
            label: 'Today',
          ),
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS26OrHigher()
                ? "calendar.badge.clock"
                : CupertinoIcons.time,
            selectedIcon: PlatformInfo.isIOS26OrHigher()
                ? "calendar.badge.clock"
                : CupertinoIcons.time,
            label: 'Timeline',
          ),
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS26OrHigher()
                ? "pencil.and.list.clipboard"
                : CupertinoIcons.pencil,
            selectedIcon: PlatformInfo.isIOS26OrHigher()
                ? "pencil.and.list.clipboard"
                : CupertinoIcons.pencil,
            label: 'Write',
          ),
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS26OrHigher()
                ? "brain.head.profile"
                : CupertinoIcons.chat_bubble_2,
            selectedIcon: PlatformInfo.isIOS26OrHigher()
                ? "brain.head.profile"
                : CupertinoIcons.chat_bubble_2_fill,
            label: 'Intelligence',
          ),
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS26OrHigher()
                ? "ellipsis.circle"
                : CupertinoIcons.ellipsis_circle,
            selectedIcon: PlatformInfo.isIOS26OrHigher()
                ? "ellipsis.circle.fill"
                : CupertinoIcons.ellipsis_circle_fill,
            label: 'More',
          ),
        ],
      ),
    );
  }
}
