// lib/screens/more_screen.dart
//
// "More" hub — grouped list of every feature in the app.
// Existing screens are pushed directly; unbuilt features push _PlaceholderScreen.

import 'package:flutter/cupertino.dart';

import '../theme/app_theme.dart';
import 'ask_journal_screen.dart';
import 'budget_planner_screen.dart';
import 'detective_screen.dart';
import 'exit_plan_screen.dart';
import 'fairness_ledger_screen.dart';
import 'mental_health_screen.dart';
import 'my_story_screen.dart';
import 'proof_vault_screen.dart';
import 'resources_screen.dart';
import 'settings_screen.dart';
import 'war_room_screen.dart';

// ── Section / item model ───────────────────────────────────────────────────

class _Section {
  final String title;
  final String subtitle;
  final Color accentColor;
  final List<_Item> items;
  const _Section(this.title, this.subtitle, this.accentColor, this.items);
}

class _Item {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final String? badge;
  final Widget Function(BuildContext) builder;

  const _Item({
    required this.label,
    required this.subtitle,
    required this.icon,
    this.iconColor = JournalColors.accent,
    this.badge,
    required this.builder,
  });
}

// ── Screen ─────────────────────────────────────────────────────────────────

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  List<_Section> _sections() => [
        _Section('Featured', 'Frequently used tools and analysis views.',
            JournalColors.accent, [
          _Item(
            label: 'Ask My Journal',
            subtitle: 'AI-powered RAG search over your entries',
            icon: CupertinoIcons.chat_bubble_text,
            badge: 'Core',
            builder: (_) => const AskJournalScreen(),
          ),
          _Item(
            label: 'Detective Mode',
            subtitle: 'Build case files with evidence & graphs',
            icon: CupertinoIcons.search,
            iconColor: const Color(0xFF8B5CF6),
            badge: 'Power',
            builder: (_) => const DetectiveScreen(),
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
            iconColor: JournalColors.severity,
            badge: 'Track',
            builder: (_) => const FairnessLedgerScreen(),
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
            badge: 'Now',
            builder: (_) => const WarRoomScreen(),
          ),
        ]),
        _Section(
            'Case Building',
            'Organize records, exports, and supporting details.',
            const Color(0xFF10B981), [
          _Item(
            label: 'Contradictions',
            subtitle: 'AI-flagged inconsistencies in your journal',
            icon: CupertinoIcons.exclamationmark_triangle,
            iconColor: const Color(0xFFF59E0B),
            badge: 'Labs',
            builder: (_) => const _PlaceholderScreen(title: 'Contradictions'),
          ),
          _Item(
            label: 'Proof Vault',
            subtitle: 'Folders, dated entries, photos, and AI summaries',
            icon: CupertinoIcons.lock_shield,
            iconColor: const Color(0xFF10B981),
            badge: 'New',
            builder: (_) => const ProofVaultScreen(),
          ),
          _Item(
            label: 'Exports',
            subtitle: 'Download your data as PDF or ZIP',
            icon: CupertinoIcons.arrow_up_doc,
            badge: 'Soon',
            builder: (_) => const _PlaceholderScreen(title: 'Exports'),
          ),
        ]),
        _Section('Insights', 'Review patterns and longer-term signals.',
            const Color(0xFFF59E0B), [
          _Item(
            label: 'Early Warning',
            subtitle: 'AI alerts before patterns escalate',
            icon: CupertinoIcons.bell_circle,
            iconColor: const Color(0xFFF59E0B),
            badge: 'Soon',
            builder: (_) => const _PlaceholderScreen(title: 'Early Warning'),
          ),
          _Item(
            label: 'Nervous System',
            subtitle: 'Track your stress & regulation states',
            icon: CupertinoIcons.waveform_path,
            iconColor: const Color(0xFF8B5CF6),
            badge: 'Soon',
            builder: (_) => const _PlaceholderScreen(title: 'Nervous System'),
          ),
          _Item(
            label: 'Patterns',
            subtitle: 'Long-term behavioral pattern analysis',
            icon: CupertinoIcons.chart_bar_square,
            badge: 'Soon',
            builder: (_) => const _PlaceholderScreen(title: 'Patterns'),
          ),
        ]),
        _Section('People', 'Review people mentioned in your journal.',
            const Color(0xFF06B6D4), [
          _Item(
            label: 'People Map',
            subtitle: 'Visual map of people in your journal',
            icon: CupertinoIcons.person_2_square_stack,
            iconColor: const Color(0xFF06B6D4),
            badge: 'Soon',
            builder: (_) => const _PlaceholderScreen(title: 'People Map'),
          ),
          _Item(
            label: 'People & Topics',
            subtitle: 'Mentions, sentiment, and topic tags',
            icon: CupertinoIcons.tag,
            badge: 'Soon',
            builder: (_) => const _PlaceholderScreen(title: 'People & Topics'),
          ),
        ]),
        _Section(
            'Tools', 'Planning and support tools.', const Color(0xFF10B981), [
          _Item(
            label: 'Budget Planner',
            subtitle: 'Plan finances and run AI comparisons',
            icon: CupertinoIcons.creditcard,
            iconColor: const Color(0xFF10B981),
            builder: (_) => const BudgetPlannerScreen(),
          ),
        ]),
        _Section('System', 'Safety rails, settings, and account controls.',
            const Color(0xFF9898B0), [
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
            backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: [
                      JournalColors.accent.withValues(alpha: 0.24),
                      const Color(0xFF10B981).withValues(alpha: 0.18),
                      const Color(0xFF06B6D4).withValues(alpha: 0.12),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: JournalColors.borderBright),
                  boxShadow: const [
                    BoxShadow(
                      color: JournalColors.accentGlow,
                      blurRadius: 24,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'More tools',
                      style: TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Additional tools, analysis views, and account controls live here.',
                      style: TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _HeroMetric(
                          value: '${sections.length}',
                          label: 'Collections',
                        ),
                        _HeroMetric(
                          value:
                              '${sections.fold<int>(0, (sum, section) => sum + section.items.length)}',
                          label: 'Tools',
                        ),
                        const _HeroMetric(
                          value: '1',
                          label: 'New',
                          highlight: 'Proof Vault',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _FeatureBanner(
                      title: 'Proof Vault',
                      subtitle:
                          'Organize proof by folder with photos and summaries.',
                      color: const Color(0xFF10B981),
                      icon: CupertinoIcons.lock_shield,
                      onTap: () => Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (ctx) => DefaultTextStyle.merge(
                            style: const TextStyle(
                                decoration: TextDecoration.none),
                            child: const ProofVaultScreen(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FeatureBanner(
                      title: 'War Room',
                      subtitle: 'Fast crisis triage for what needs action now.',
                      color: const Color(0xFFEF4444),
                      icon: CupertinoIcons.bolt_horizontal,
                      onTap: () => Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (ctx) => DefaultTextStyle.merge(
                            style: const TextStyle(
                                decoration: TextDecoration.none),
                            child: const WarRoomScreen(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final section in sections) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: section.accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.title.toUpperCase(),
                            style: const TextStyle(
                              color: JournalColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            section.subtitle,
                            style: const TextStyle(
                              color: JournalColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                height: 1,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                color: section.accentColor.withValues(alpha: 0.12),
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: JournalColors.bgCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: section.accentColor.withValues(alpha: 0.18)),
                  boxShadow: [
                    BoxShadow(
                      color: section.accentColor.withValues(alpha: 0.08),
                      blurRadius: 20,
                      spreadRadius: 0,
                    ),
                  ],
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
                            style: const TextStyle(
                                decoration: TextDecoration.none),
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

class _HeroMetric extends StatelessWidget {
  final String value;
  final String label;
  final String? highlight;

  const _HeroMetric({
    required this.value,
    required this.label,
    this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: JournalColors.bgBase.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JournalColors.borderBright),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (highlight != null) ...[
            const SizedBox(height: 4),
            Text(
              highlight!,
              style: const TextStyle(
                color: Color(0xFF6EE7B7),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeatureBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _FeatureBanner({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 172,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
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
                    color: item.iconColor.withValues(alpha: 0.15),
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
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (item.badge != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: item.iconColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: item.iconColor.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Text(
                            item.badge!,
                            style: TextStyle(
                              color: item.iconColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
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
              child: Container(
                height: 0.5,
                color: JournalColors.border.withValues(alpha: 0.8),
              ),
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
        backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
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
