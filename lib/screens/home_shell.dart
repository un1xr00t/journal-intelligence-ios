// lib/screens/home_shell.dart
//
// AdaptiveScaffold with iOS 26 Liquid Glass bottom navigation.
// Five tabs: Today · Timeline · Write · Intelligence · More

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';

import 'today_screen.dart';
import 'write_screen.dart';
import 'timeline_screen.dart';
import 'ask_journal_screen.dart';
import 'more_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  static const _screens = [
    TodayScreen(),
    TimelineScreen(),
    WriteScreen(),
    AskJournalScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        selectedIndex: _selectedIndex,
        onTap: (i) {
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() => _selectedIndex = i);
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
