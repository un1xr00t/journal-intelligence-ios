// lib/screens/more_screen.dart
//
// "More" hub — grouped list of every feature in the app.
// Existing screens are pushed directly; unbuilt features push _PlaceholderScreen.

import 'package:flutter/cupertino.dart';

import '../theme/app_theme.dart';
import 'ask_journal_screen.dart';
import 'detective_screen.dart';
import 'exit_plan_screen.dart';
import 'mental_health_screen.dart';
import 'my_story_screen.dart';
import 'resources_screen.dart';
import 'settings_screen.dart';

// ── Section / item model ───────────────────────────────────────────────────

class _Section {
  final String title;
  final List<_Item> items;
  const _Section(this.title, this.items);
}

class _Item {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Widget Function(BuildContext) builder;

  const _Item({
    required this.label,
    required this.subtitle,
    required this.icon,
    this.iconColor = JournalColors.accent,
    required this.builder,
  });
}

// ── Screen ─────────────────────────────────────────────────────────────────

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  List<_Section> _sections() => [
        _Section('Premium', [
          _Item(
            label: 'Ask My Journal',
            subtitle: 'AI-powered RAG search over your entries',
            icon: CupertinoIcons.chat_bubble_text,
            builder: (_) => const AskJournalScreen(),
          ),
          _Item(
            label: 'Detective Mode',
            subtitle: 'Build case files with evidence & graphs',
            icon: CupertinoIcons.search,
            iconColor: const Color(0xFF8B5CF6),
            builder: (_) => DetectiveScreen(),
          ),
          _Item(
            label: 'Exit Plan',
            subtitle: 'Structured roadmap for major life changes',
            icon: CupertinoIcons.map,
            iconColor: const Color(0xFF10B981),
            builder: (_) => const ExitPlanScreen(),
          ),
          _Item(
            label: 'Fairness Ledger',
            subtitle: 'Track tasks, contributions & equity',
            icon: CupertinoIcons.equal_circle,
            iconColor: const Color(0xFFF59E0B),
            builder: (_) => const _PlaceholderScreen(title: 'Fairness Ledger'),
          ),
          _Item(
            label: 'My Mental Health',
            subtitle: 'Mood trends, crisis indicators & narrative',
            icon: CupertinoIcons.heart,
            iconColor: const Color(0xFFEC4899),
            builder: (_) => const MentalHealthScreen(),
          ),
          _Item(
            label: 'My Story',
            subtitle: 'AI-generated narrative drafts of your journey',
            icon: CupertinoIcons.book,
            builder: (_) => const MyStoryScreen(),
          ),
          _Item(
            label: 'War Room',
            subtitle: 'Crisis triage — act now vs. plan vs. let go',
            icon: CupertinoIcons.bolt_horizontal,
            iconColor: const Color(0xFFEF4444),
            builder: (_) => const _PlaceholderScreen(title: 'War Room'),
          ),
        ]),
        _Section('Case Building', [
          _Item(
            label: 'Contradictions',
            subtitle: 'AI-flagged inconsistencies in your journal',
            icon: CupertinoIcons.exclamationmark_triangle,
            iconColor: const Color(0xFFF59E0B),
            builder: (_) => const _PlaceholderScreen(title: 'Contradictions'),
          ),
          _Item(
            label: 'Proof Vault',
            subtitle: 'Secure folder for evidence & attachments',
            icon: CupertinoIcons.lock_shield,
            iconColor: const Color(0xFF10B981),
            builder: (_) => const _PlaceholderScreen(title: 'Proof Vault'),
          ),
          _Item(
            label: 'Exports',
            subtitle: 'Download your data as PDF or ZIP',
            icon: CupertinoIcons.arrow_up_doc,
            builder: (_) => const _PlaceholderScreen(title: 'Exports'),
          ),
        ]),
        _Section('Insights', [
          _Item(
            label: 'Early Warning',
            subtitle: 'AI alerts before patterns escalate',
            icon: CupertinoIcons.bell_circle,
            iconColor: const Color(0xFFF59E0B),
            builder: (_) => const _PlaceholderScreen(title: 'Early Warning'),
          ),
          _Item(
            label: 'Nervous System',
            subtitle: 'Track your stress & regulation states',
            icon: CupertinoIcons.waveform_path,
            iconColor: const Color(0xFF8B5CF6),
            builder: (_) => const _PlaceholderScreen(title: 'Nervous System'),
          ),
          _Item(
            label: 'Patterns',
            subtitle: 'Long-term behavioral pattern analysis',
            icon: CupertinoIcons.chart_bar_square,
            builder: (_) => const _PlaceholderScreen(title: 'Patterns'),
          ),
        ]),
        _Section('People', [
          _Item(
            label: 'People Map',
            subtitle: 'Visual map of people in your journal',
            icon: CupertinoIcons.person_2_square_stack,
            iconColor: const Color(0xFF06B6D4),
            builder: (_) => const _PlaceholderScreen(title: 'People Map'),
          ),
          _Item(
            label: 'People & Topics',
            subtitle: 'Mentions, sentiment, and topic tags',
            icon: CupertinoIcons.tag,
            builder: (_) => const _PlaceholderScreen(title: 'People & Topics'),
          ),
        ]),
        _Section('Tools', [
          _Item(
            label: 'Budget Planner',
            subtitle: 'Plan finances and run AI comparisons',
            icon: CupertinoIcons.creditcard,
            iconColor: const Color(0xFF10B981),
            builder: (_) => const _PlaceholderScreen(title: 'Budget Planner'),
          ),
        ]),
        _Section('System', [
          _Item(
            label: 'Admin',
            subtitle: 'Users, sessions, AI usage',
            icon: CupertinoIcons.person_badge_plus,
            iconColor: const Color(0xFF9898B0),
            builder: (_) => const _PlaceholderScreen(title: 'Admin'),
          ),
          _Item(
            label: 'Resources',
            subtitle: 'Crisis lines and support resources',
            icon: CupertinoIcons.heart_circle,
            iconColor: const Color(0xFFEC4899),
            builder: (_) => const ResourcesScreen(),
          ),
          _Item(
            label: 'Settings',
            subtitle: 'Account, AI provider, security',
            icon: CupertinoIcons.settings,
            iconColor: const Color(0xFF9898B0),
            builder: (_) => const SettingsScreen(),
          ),
        ]),
      ];

  @override
  Widget build(BuildContext context) {
    final sections = _sections();

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('More'),
            backgroundColor: JournalColors.bgBase.withOpacity(0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
          ),
          for (final section in sections) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 6),
                child: Text(
                  section.title.toUpperCase(),
                  style: const TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: JournalColors.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: JournalColors.border),
                ),
                child: Column(
                  children: List.generate(section.items.length, (i) {
                    final item = section.items[i];
                    final isLast = i == section.items.length - 1;
                    return _MoreRow(
                      item: item,
                      isLast: isLast,
                      onTap: () => Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (ctx) => DefaultTextStyle.merge(
                            style: const TextStyle(decoration: TextDecoration.none),
                            child: item.builder(ctx),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

// ── Row widget ─────────────────────────────────────────────────────────────

class _MoreRow extends StatelessWidget {
  final _Item item;
  final bool isLast;
  final VoidCallback onTap;

  const _MoreRow({
    required this.item,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                // Icon badge
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: item.iconColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(item.icon, color: item.iconColor, size: 18),
                ),
                const SizedBox(width: 13),
                // Labels
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        style: const TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  CupertinoIcons.chevron_right,
                  color: JournalColors.textMuted,
                  size: 14,
                ),
              ],
            ),
          ),
          if (!isLast)
            Padding(
              padding: const EdgeInsets.only(left: 65),
              child: Container(height: 0.5, color: JournalColors.border),
            ),
        ],
      ),
    );
  }
}

// ── Placeholder for unbuilt screens ────────────────────────────────────────

class _PlaceholderScreen extends StatelessWidget {
  final String title;
  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        backgroundColor: JournalColors.bgBase.withOpacity(0.92),
        border: const Border(
          bottom: BorderSide(color: JournalColors.border, width: 0.5),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.hammer,
              color: JournalColors.textMuted,
              size: 40,
            ),
            const SizedBox(height: 14),
            Text(
              '$title — Coming Soon',
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'This feature is being built.',
              style: TextStyle(
                color: JournalColors.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}