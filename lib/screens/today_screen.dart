// lib/screens/today_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final _api = ApiService();

  Map<String, dynamic>? _brief;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _api.getTodayBrief();
      if (mounted) setState(() { _brief = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<Widget> _buildContent() {
    final noData   = _brief!['no_data'] as bool? ?? false;
    final brief    = (_brief!['brief']  as Map<String, dynamic>?) ?? {};
    final stats    = (_brief!['stats']  as Map<String, dynamic>?) ?? {};
    final traj     = (brief['trajectory']     as Map<String, dynamic>?) ?? {};
    final horizons = (brief['time_horizons']  as Map<String, dynamic>?) ?? {};

    String? str(Map m, String k) {
      final v = m[k];
      return (v is String && v.isNotEmpty) ? v : null;
    }

    final items = <Widget>[_DateBadge(), const SizedBox(height: 20)];

    if (noData) {
      items.add(GlassCard(
        child: Column(children: const [
          Icon(CupertinoIcons.book, color: JournalColors.textMuted, size: 40),
          SizedBox(height: 12),
          Text('Not enough entries yet to generate a brief.',
              textAlign: TextAlign.center,
              style: TextStyle(color: JournalColors.textSecondary, fontSize: 15, height: 1.6)),
        ]),
      ));
      items.add(const SizedBox(height: 40));
      return items;
    }

    // Emotional state
    final emotionalState = str(brief, 'emotional_state');
    if (emotionalState != null) {
      items.addAll([
        GlassCard(
          accentBorder: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('EMOTIONAL STATE', style: TextStyle(
                color: JournalColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const SizedBox(height: 10),
            Text(emotionalState, style: const TextStyle(
                color: JournalColors.textPrimary, fontSize: 16, height: 1.6)),
          ]),
        ),
        const SizedBox(height: 16),
      ]);
    }

    // Stats row — latest_mood is a double (0.0–1.0 scale)
    final latestMoodRaw = stats['latest_mood'];
    final latestMood = latestMoodRaw is num ? latestMoodRaw.toDouble() : null;
    final latestSev  = (stats['latest_sev'] as num?)?.toDouble();
    final entries30d = stats['total_entries_30d'] as int?;
    if (latestMood != null || latestSev != null || entries30d != null) {
      items.addAll([
        GlassCard(
          child: Row(children: [
            if (latestMood != null)
              Expanded(child: _StatChip(
                  label: 'Mood', value: '${(latestMood * 100).round()}%', color: _moodColor(latestMood))),
            if (latestSev != null)
              Expanded(child: _StatChip(
                  label: 'Severity', value: latestSev.toStringAsFixed(1), color: _sevColor(latestSev))),
            if (entries30d != null)
              Expanded(child: _StatChip(
                  label: 'Entries (30d)', value: '$entries30d', color: JournalColors.accent)),
          ]),
        ),
        const SizedBox(height: 24),
      ]);
    }

    // Do today
    final doToday = str(brief, 'do_today');
    if (doToday != null) {
      items.addAll([
        const SectionHeader(title: 'Do Today'), const SizedBox(height: 10),
        GlassCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(CupertinoIcons.arrow_right_circle_fill, color: JournalColors.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(doToday, style: const TextStyle(
              color: JournalColors.textPrimary, fontSize: 15, height: 1.6))),
        ])),
        const SizedBox(height: 16),
      ]);
    }

    // Stop doing
    final stopDoing = str(brief, 'stop_doing');
    if (stopDoing != null) {
      items.addAll([
        const SectionHeader(title: 'Stop Doing'), const SizedBox(height: 10),
        GlassCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(CupertinoIcons.xmark_circle_fill, color: Color(0xFFEF4444), size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(stopDoing, style: const TextStyle(
              color: JournalColors.textPrimary, fontSize: 15, height: 1.6))),
        ])),
        const SizedBox(height: 16),
      ]);
    }

    // Biggest risk
    final biggestRisk = str(brief, 'biggest_risk');
    if (biggestRisk != null) {
      items.addAll([
        const SectionHeader(title: 'Biggest Risk'), const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.25)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(CupertinoIcons.exclamationmark_triangle_fill,
                color: Color(0xFFF59E0B), size: 18),
            const SizedBox(width: 12),
            Expanded(child: Text(biggestRisk, style: const TextStyle(
                color: JournalColors.textPrimary, fontSize: 14, height: 1.5))),
          ]),
        ),
        const SizedBox(height: 16),
      ]);
    }

    // Getting better / worse
    final better = str(brief, 'getting_better');
    final worse  = str(brief, 'getting_worse');
    if (better != null || worse != null) {
      items.addAll([const SectionHeader(title: 'Trends'), const SizedBox(height: 10)]);
      if (better != null) {
        items.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(CupertinoIcons.arrow_up_circle_fill, color: Color(0xFF22C55E), size: 20),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('GETTING BETTER', style: TextStyle(color: Color(0xFF22C55E),
                  fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
              const SizedBox(height: 4),
              Text(better, style: const TextStyle(color: JournalColors.textPrimary, fontSize: 14, height: 1.5)),
            ])),
          ])),
        ));
      }
      if (worse != null) {
        items.add(GlassCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(CupertinoIcons.arrow_down_circle_fill, color: Color(0xFFEF4444), size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('GETTING WORSE', style: TextStyle(color: Color(0xFFEF4444),
                fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
            const SizedBox(height: 4),
            Text(worse, style: const TextStyle(color: JournalColors.textPrimary, fontSize: 14, height: 1.5)),
          ])),
        ])));
      }
      items.add(const SizedBox(height: 16));
    }

    // Trajectory
    final trajSummary = str(traj, 'summary');
    if (trajSummary != null) {
      items.addAll([
        const SectionHeader(title: 'Overall Trajectory'), const SizedBox(height: 10),
        GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(trajSummary, style: const TextStyle(
              color: JournalColors.textPrimary, fontSize: 15, height: 1.6)),
          const SizedBox(height: 12),
          Row(children: [
            _TrendChip(label: 'Mood',     value: traj['mood']     as String?),
            const SizedBox(width: 8),
            _TrendChip(label: 'Stress',   value: traj['stress']   as String?),
            const SizedBox(width: 8),
            _TrendChip(label: 'Conflict', value: traj['conflict'] as String?),
          ]),
        ])),
        const SizedBox(height: 16),
      ]);
    }

    // Time horizons
    final hToday = str(horizons, 'today');
    final hWeek  = str(horizons, 'this_week');
    final hMonth = str(horizons, 'this_month');
    final hLong  = str(horizons, 'long_term');
    if (hToday != null || hWeek != null || hMonth != null || hLong != null) {
      items.addAll([
        const SectionHeader(title: 'Time Horizons'), const SizedBox(height: 10),
        GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (hToday != null) _HorizonRow(label: 'Today',      text: hToday),
          if (hWeek  != null) _HorizonRow(label: 'This Week',  text: hWeek),
          if (hMonth != null) _HorizonRow(label: 'This Month', text: hMonth),
          if (hLong  != null) _HorizonRow(label: 'Long Term',  text: hLong),
        ])),
        const SizedBox(height: 16),
      ]);
    }

    items.add(const SizedBox(height: 40));
    return items;
  }

  Color _moodColor(double score) {
    if (score >= 0.7) return const Color(0xFF22C55E);
    if (score >= 0.4) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  Color _sevColor(double sev) {
    if (sev <= 3.0) return const Color(0xFF22C55E);
    if (sev <= 6.0) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Today'),
            backgroundColor: JournalColors.bgBase.withOpacity(0.9),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
            trailing: GestureDetector(
              onTap: _load,
              child: const Icon(CupertinoIcons.refresh, color: JournalColors.accent),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CupertinoActivityIndicator(color: JournalColors.accent),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: _ErrorView(error: _error!, onRetry: _load),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              sliver: SliverList(
                delegate: SliverChildListDelegate(_buildContent()),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w700)),
    const SizedBox(height: 4),
    Text(label, style: const TextStyle(color: JournalColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
  ]);
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.label, this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final icon = switch (value) {
      'rising'  => CupertinoIcons.arrow_up,
      'falling' => CupertinoIcons.arrow_down,
      _         => CupertinoIcons.minus,
    };
    final color = switch (value) {
      'rising'  => const Color(0xFF22C55E),
      'falling' => const Color(0xFFEF4444),
      _         => JournalColors.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _HorizonRow extends StatelessWidget {
  const _HorizonRow({required this.label, required this.text});
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(
          color: JournalColors.accent, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
      const SizedBox(height: 4),
      Text(text, style: const TextStyle(color: JournalColors.textSecondary, fontSize: 14, height: 1.5)),
    ]),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(CupertinoIcons.wifi_slash, color: JournalColors.textMuted, size: 48),
          const SizedBox(height: 16),
          const Text('Could not load today\'s brief',
              style: TextStyle(color: JournalColors.textSecondary)),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: JournalColors.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Retry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
class _DateBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dayName  = DateFormat('EEEE').format(now);
    final dateStr  = DateFormat('MMMM d, y').format(now);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: JournalColors.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: JournalColors.borderBright),
          ),
          child: Row(
            children: [
              const Icon(CupertinoIcons.calendar, color: JournalColors.accent, size: 14),
              const SizedBox(width: 6),
              Text(
                '$dayName · $dateStr',
                style: const TextStyle(
                  color: JournalColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
