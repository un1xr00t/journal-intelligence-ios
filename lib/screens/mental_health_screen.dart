// lib/screens/mental_health_screen.dart
//
// My Mental Health — dashboard mirroring MentalHealth.jsx
// Data from GET /api/mental-health/dashboard → { stats, narrative, computed_at }
// Narrative refresh via POST /api/mental-health/narrative/refresh

import 'package:flutter/cupertino.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

Color _sevColor(double? sev) {
  if (sev == null) return JournalColors.border;
  if (sev >= 7.5) return JournalColors.danger;
  if (sev >= 6.0) return JournalColors.orange;
  if (sev >= 4.0) return JournalColors.severity;
  return JournalColors.success;
}

String _fmt1(dynamic v) {
  if (v == null) return '—';
  final d = double.tryParse(v.toString());
  return d != null ? d.toStringAsFixed(1) : '—';
}

String _fmt2(dynamic v) {
  if (v == null) return '—';
  final d = double.tryParse(v.toString());
  return d != null ? d.toStringAsFixed(2) : '—';
}

double? _toDouble(dynamic v) =>
    v == null ? null : double.tryParse(v.toString());

// ── Screen ─────────────────────────────────────────────────────────────────────

class MentalHealthScreen extends StatefulWidget {
  const MentalHealthScreen({super.key});

  @override
  State<MentalHealthScreen> createState() => _MentalHealthScreenState();
}

class _MentalHealthScreenState extends State<MentalHealthScreen> {
  final _api = ApiService();

  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.getMentalHealthData();
      if (mounted) {
        setState(() {
          _data = result;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load dashboard.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshNarrative() async {
    setState(() {
      _refreshing = true;
    });
    try {
      final result = await _api.refreshMentalHealthNarrative();
      if (mounted) {
        setState(() {
          if (_data != null) {
            _data = Map<String, dynamic>.from(_data!)
              ..['narrative'] = result['narrative'];
          }
          _refreshing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('My Mental Health'),
            backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
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
                child: _ErrorState(message: _error!, onRetry: _load))
          else if (_data == null || _data!['stats'] == null)
            const SliverFillRemaining(child: _EmptyState())
          else
            SliverToBoxAdapter(child: _buildDashboard()),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    final stats = _data!['stats'] as Map<String, dynamic>;
    final narrative = _data!['narrative'] as Map<String, dynamic>?;
    final computedAt = _data!['computed_at'] as String?;

    String computedLabel = '';
    if (computedAt != null) {
      try {
        final dt = DateTime.parse('${computedAt}Z').toLocal();
        computedLabel =
            'computed ${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        computedLabel = 'computed recently';
      }
    }

    final calendar = (stats['calendar'] as List<dynamic>?) ?? [];
    final stressors = (stats['stressors'] as List<dynamic>?) ?? [];
    final protectors = (stats['protectors'] as List<dynamic>?) ?? [];
    final dayOfWeek = (stats['day_of_week'] as List<dynamic>?) ?? [];
    final keywordShifts = (stats['keyword_shifts'] as List<dynamic>?) ?? [];
    final peopleImpact = (stats['people_impact'] as List<dynamic>?) ?? [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DashboardHero(
            computedLabel: computedLabel,
            avgMood: _fmt1(stats['avg_mood']),
            avgSeverity: _fmt1(stats['avg_severity']),
            streak: stats['streak'] != null ? '${stats['streak']}d' : '—',
          ),
          const SizedBox(height: 18),
          const SectionHeader(title: 'Key Measures'),
          const SizedBox(height: 10),
          SizedBox(
            height: 104,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _StatChip(
                    label: 'Wellbeing',
                    value: _fmt1(stats['avg_mood']),
                    color: JournalColors.success,
                    sub: '30-day avg mood'),
                _StatChip(
                    label: 'Avg Severity',
                    value: _fmt1(stats['avg_severity']),
                    color: JournalColors.severity,
                    sub: '30-day avg'),
                _StatChip(
                    label: 'Volatility',
                    value: _fmt2(stats['volatility']),
                    color: JournalColors.accent2,
                    sub: 'mood std dev'),
                _StatChip(
                  label: 'Recovery',
                  value: stats['recovery_speed_days'] != null
                      ? '${_toDouble(stats['recovery_speed_days'])?.toStringAsFixed(0)}d'
                      : '—',
                  color: JournalColors.orange,
                  sub: 'avg to baseline',
                ),
                _StatChip(
                    label: 'Journaled',
                    value: '${stats['days_journaled'] ?? '—'}/30',
                    color: JournalColors.info,
                    sub: 'days this period'),
                _StatChip(
                    label: 'High distress',
                    value: '${stats['high_distress_days'] ?? '—'}',
                    color: JournalColors.danger,
                    sub: 'severity 7+ days'),
                _StatChip(
                    label: 'Low distress',
                    value: '${stats['low_distress_days'] ?? '—'}',
                    color: JournalColors.success,
                    sub: 'severity 4 or under'),
                _StatChip(
                  label: 'Streak',
                  value: stats['streak'] != null ? '${stats['streak']}d' : '—',
                  color: JournalColors.severity,
                  sub: 'current run',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (calendar.isNotEmpty) ...[
            const SectionHeader(title: 'Mood Calendar'),
            const SizedBox(height: 10),
            _MoodCalendar(calendar: calendar),
            const SizedBox(height: 24),
          ],
          const SectionHeader(title: 'Month Over Month'),
          const SizedBox(height: 10),
          _MonthComparison(stats: stats),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Trigger Map'),
          const SizedBox(height: 10),
          _TriggerMap(stressors: stressors, protectors: protectors),
          const SizedBox(height: 24),
          if (dayOfWeek.isNotEmpty) ...[
            const SectionHeader(title: 'Day Patterns'),
            const SizedBox(height: 10),
            _DayOfWeekChart(data: dayOfWeek),
            const SizedBox(height: 24),
          ],
          const SectionHeader(title: 'Language Shifts'),
          const SizedBox(height: 10),
          _KeywordShifts(shifts: keywordShifts),
          const SizedBox(height: 24),
          const SectionHeader(title: 'People Impact'),
          const SizedBox(height: 10),
          _PeopleImpact(people: peopleImpact),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Narrative'),
          const SizedBox(height: 10),
          _Narrative(
            data: narrative,
            refreshing: _refreshing,
            onRefresh: _refreshNarrative,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _DashboardHero extends StatelessWidget {
  final String computedLabel;
  final String avgMood;
  final String avgSeverity;
  final String streak;

  const _DashboardHero({
    required this.computedLabel,
    required this.avgMood,
    required this.avgSeverity,
    required this.streak,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accentBorder: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      _withAlpha(JournalColors.accent, 0.26),
                      _withAlpha(JournalColors.info, 0.16),
                    ],
                  ),
                  border: Border.all(color: JournalColors.borderBright),
                ),
                child: const Icon(
                  CupertinoIcons.heart,
                  color: JournalColors.textPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'MENTAL HEALTH',
                      style: TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Recent patterns, pressure points, and recovery signals.',
                      style: TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.22,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.bgSurface, 0.8),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: JournalColors.border),
                ),
                child: Text(
                  computedLabel.isNotEmpty
                      ? computedLabel.toUpperCase()
                      : 'LATEST READ',
                  style: const TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const Text(
                'Use this page to spot whether things are stabilizing, drifting, or repeating.',
                style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  label: 'Mood',
                  value: avgMood,
                  color: JournalColors.success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroMetric(
                  label: 'Severity',
                  value: avgSeverity,
                  color: JournalColors.severity,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroMetric(
                  label: 'Streak',
                  value: streak,
                  color: JournalColors.info,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _HeroMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _withAlpha(color, 0.10),
        border: Border.all(color: _withAlpha(color, 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: _withAlpha(color, 0.96),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stat chip ──────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String sub;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 126,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JournalColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            sub,
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
            ),
            maxLines: 2,
            overflow: TextOverflow.fade,
          ),
        ],
      ),
    );
  }
}

// ── Mood Calendar ──────────────────────────────────────────────────────────────

class _MoodCalendar extends StatelessWidget {
  final List<dynamic> calendar;
  const _MoodCalendar({required this.calendar});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 12,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
            ),
            itemCount: calendar.length,
            itemBuilder: (_, i) {
              final day = calendar[i] as Map<String, dynamic>? ?? {};
              final sev = _toDouble(day['severity']);
              return Container(
                decoration: BoxDecoration(
                  color: sev != null
                      ? _withAlpha(_sevColor(sev), 0.85)
                      : _withAlpha(JournalColors.border, 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('12 weeks ago',
                  style:
                      TextStyle(color: JournalColors.textMuted, fontSize: 10)),
              Row(
                children: [
                  _LegendDot(color: JournalColors.success, label: 'calm'),
                  const SizedBox(width: 8),
                  _LegendDot(color: JournalColors.severity, label: 'mild'),
                  const SizedBox(width: 8),
                  _LegendDot(color: JournalColors.orange, label: 'elevated'),
                  const SizedBox(width: 8),
                  _LegendDot(color: JournalColors.danger, label: 'high'),
                ],
              ),
              const Text('today',
                  style:
                      TextStyle(color: JournalColors.textMuted, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 3),
        Text(label,
            style:
                const TextStyle(color: JournalColors.textMuted, fontSize: 10)),
      ],
    );
  }
}

// ── Month-over-month comparison ────────────────────────────────────────────────

class _MonthComparison extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _MonthComparison({required this.stats});

  @override
  Widget build(BuildContext context) {
    final moodDelta = _toDouble(stats['mood_delta']);
    final sevDelta = _toDouble(stats['sev_delta']);

    final hdNow = _toDouble(stats['high_distress_days']);
    final hdPrev = _toDouble(stats['prev_high_distress']);
    final hdDelta = (hdNow != null && hdPrev != null) ? hdNow - hdPrev : null;

    final djNow = _toDouble(stats['days_journaled']);
    final djPrev = _toDouble(stats['prev_days_journaled']);
    final djDelta = (djNow != null && djPrev != null) ? djNow - djPrev : null;

    final items = [
      _MoMItem(label: 'Wellbeing', delta: moodDelta, invert: false, unit: ''),
      _MoMItem(label: 'Severity', delta: sevDelta, invert: true, unit: ''),
      _MoMItem(
          label: 'High-distress days', delta: hdDelta, invert: true, unit: 'd'),
      _MoMItem(
          label: 'Journaling consistency',
          delta: djDelta,
          invert: false,
          unit: 'd'),
    ];

    return Row(
      children: items
          .map((item) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _MoMCard(item: item),
                ),
              ))
          .toList(),
    );
  }
}

class _MoMItem {
  final String label;
  final double? delta;
  final bool invert;
  final String unit;
  const _MoMItem(
      {required this.label,
      required this.delta,
      required this.invert,
      required this.unit});
}

class _MoMCard extends StatelessWidget {
  final _MoMItem item;
  const _MoMCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final d = item.delta;
    Color color;
    String valueText;

    if (d == null) {
      color = JournalColors.textMuted;
      valueText = '—';
    } else if (d == 0) {
      color = JournalColors.textMuted;
      valueText = '0${item.unit}';
    } else {
      final good = item.invert ? d < 0 : d > 0;
      color = good ? JournalColors.success : JournalColors.danger;
      final sign = d > 0 ? '+' : '';
      valueText = '$sign${d.toStringAsFixed(1)}${item.unit}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: JournalColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        children: [
          Text(
            item.label.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            valueText,
            style: TextStyle(
                color: color, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text('vs prev 30d',
              style: TextStyle(color: JournalColors.textMuted, fontSize: 9)),
        ],
      ),
    );
  }
}

// ── Trigger map ────────────────────────────────────────────────────────────────

class _TriggerMap extends StatelessWidget {
  final List<dynamic> stressors;
  final List<dynamic> protectors;
  const _TriggerMap({required this.stressors, required this.protectors});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
            child: _TriggerPanel(
                title: 'Stressors',
                titleColor: JournalColors.danger,
                items: stressors,
                isStressor: true)),
        const SizedBox(width: 10),
        Expanded(
            child: _TriggerPanel(
                title: 'Protective factors',
                titleColor: JournalColors.success,
                items: protectors,
                isStressor: false)),
      ],
    );
  }
}

class _TriggerPanel extends StatelessWidget {
  final String title;
  final Color titleColor;
  final List<dynamic> items;
  final bool isStressor;
  const _TriggerPanel(
      {required this.title,
      required this.titleColor,
      required this.items,
      required this.isStressor});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: titleColor,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Text('Not enough data yet',
                style: TextStyle(color: JournalColors.textMuted, fontSize: 12))
          else
            ...items.map((raw) {
              final item = raw as Map<String, dynamic>? ?? {};
              final sev = _toDouble(item['avg_severity']);
              final barFrac = isStressor
                  ? ((sev ?? 0) / 10.0).clamp(0.0, 1.0)
                  : (1.0 - ((sev ?? 0) / 10.0)).clamp(0.0, 1.0);
              final barColor =
                  isStressor ? _sevColor(sev) : JournalColors.success;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item['topic']?.toString() ?? '',
                            style: const TextStyle(
                                color: JournalColors.textSecondary,
                                fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _fmt1(sev),
                          style: TextStyle(
                              color: barColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        height: 5,
                        color: JournalColors.border,
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: barFrac,
                          child: Container(color: barColor),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ── Day-of-week bar chart ──────────────────────────────────────────────────────

class _DayOfWeekChart extends StatelessWidget {
  final List<dynamic> data;
  const _DayOfWeekChart({required this.data});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: SizedBox(
        height: 140,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: data.map((raw) {
            final entry = raw as Map<String, dynamic>? ?? {};
            final sev = _toDouble(entry['avg_severity']);
            final frac = sev != null ? (sev / 10.0).clamp(0.0, 1.0) : 0.0;
            final day = entry['day']?.toString() ?? '';
            final label = day.isNotEmpty ? day[0].toUpperCase() : '';

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: frac > 0 ? frac : 0.03,
                          child: Container(
                            decoration: BoxDecoration(
                              color: sev != null
                                  ? _withAlpha(_sevColor(sev), 0.85)
                                  : _withAlpha(JournalColors.border, 0.3),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(label,
                        style: const TextStyle(
                            color: JournalColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Keyword shifts ─────────────────────────────────────────────────────────────

const _kNegativeWords = {
  'exhausted',
  'scared',
  'hopeless',
  'angry',
  'anxious',
  'frustrated',
  'overwhelmed',
  'numb',
  'rage',
  'alone',
  'ashamed',
};

class _KeywordShifts extends StatelessWidget {
  final List<dynamic> shifts;
  const _KeywordShifts({required this.shifts});

  @override
  Widget build(BuildContext context) {
    if (shifts.isEmpty) {
      return GlassCard(
        child: const Text(
          'More entries needed to detect language shifts.',
          style: TextStyle(color: JournalColors.textMuted, fontSize: 12),
        ),
      );
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('vs prior 30 days',
              style: TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 10,
                  letterSpacing: 0.3)),
          const SizedBox(height: 12),
          ...shifts.map((raw) {
            final item = raw as Map<String, dynamic>? ?? {};
            final keyword = item['keyword']?.toString() ?? '';
            final pct = _toDouble(item['pct_change']) ?? 0;
            final isNeg = _kNegativeWords.contains(keyword.toLowerCase());
            final barColor = pct > 0
                ? (isNeg ? JournalColors.danger : JournalColors.success)
                : JournalColors.success;
            final barFrac = (pct.abs() / 100.0).clamp(0.0, 1.0);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(keyword,
                          style: const TextStyle(
                              color: JournalColors.textSecondary,
                              fontSize: 12)),
                      Text(
                        '${pct > 0 ? '+' : ''}${pct.toStringAsFixed(0)}%',
                        style: TextStyle(
                            color: barColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Container(
                      height: 5,
                      color: JournalColors.border,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: barFrac,
                        child: Container(color: _withAlpha(barColor, 0.8)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── People impact ──────────────────────────────────────────────────────────────

class _PeopleImpact extends StatelessWidget {
  final List<dynamic> people;
  const _PeopleImpact({required this.people});

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return GlassCard(
        child: const Text(
          'No people mentioned 2+ times this period.',
          style: TextStyle(color: JournalColors.textMuted, fontSize: 12),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: JournalColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        children: List.generate(people.length, (i) {
          final raw = people[i] as Map<String, dynamic>? ?? {};
          final name = raw['name']?.toString() ?? '?';
          final sev = _toDouble(raw['avg_severity']);
          final mentions = raw['mentions'];
          final distress = raw['distress_entries'];

          final words = name.trim().split(' ');
          final initials = words
              .take(2)
              .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
              .join();

          late Color impact;
          late Color impactBg;
          late String impactLabel;

          if (sev != null && sev >= 6.5) {
            impact = JournalColors.danger;
            impactBg = _withAlpha(JournalColors.danger, 0.12);
            impactLabel = 'stressor';
          } else if (sev != null && sev <= 4.5) {
            impact = JournalColors.success;
            impactBg = _withAlpha(JournalColors.success, 0.12);
            impactLabel = 'stabilizing';
          } else {
            impact = JournalColors.textMuted;
            impactBg = JournalColors.border;
            impactLabel = 'mixed';
          }

          return Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: impactBg,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            color: impact,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                color: JournalColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              )),
                          const SizedBox(height: 2),
                          Text(
                            '${mentions ?? 0} mentions · avg sev ${_fmt1(sev)} · ${distress ?? 0} high-distress',
                            style: const TextStyle(
                                color: JournalColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: impactBg,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        impactLabel,
                        style: TextStyle(
                            color: impact,
                            fontSize: 10,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              if (i < people.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 62),
                  child: Container(height: 0.5, color: JournalColors.border),
                ),
            ],
          );
        }),
      ),
    );
  }
}

// ── AI Narrative ───────────────────────────────────────────────────────────────

class _Narrative extends StatelessWidget {
  final Map<String, dynamic>? data;
  final bool refreshing;
  final VoidCallback onRefresh;

  const _Narrative(
      {required this.data, required this.refreshing, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (data == null) return const SizedBox.shrink();

    final text = data!['narrative'] as String?;
    final cached = data!['cached'] as bool? ?? false;
    final quotes = (data!['quotes'] as List<dynamic>?) ?? [];

    final cacheLabel = cached ? 'this week' : 'just generated';

    return GlassCard(
      accentBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SUMMARY · $cacheLabel'.toUpperCase(),
                style: const TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: refreshing ? null : onRefresh,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: JournalColors.border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: refreshing
                      ? const CupertinoActivityIndicator(
                          color: JournalColors.textMuted, radius: 7)
                      : const Text(
                          '↻ refresh',
                          style: TextStyle(
                            color: JournalColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (text != null && text.isNotEmpty)
            Text(
              text,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 15,
                height: 1.75,
              ),
            )
          else
            const Text(
              'No narrative yet — add an API key in Settings to generate one.',
              style: TextStyle(color: JournalColors.textMuted, fontSize: 13),
            ),
          if (quotes.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(height: 0.5, color: JournalColors.border),
            const SizedBox(height: 14),
            const Text(
              'SUPPORTING EXCERPTS',
              style: TextStyle(
                color: JournalColors.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 10),
            ...quotes.map((q) {
              final qText =
                  q is String ? q : (q is Map ? q['text']?.toString() : null);
              if (qText == null || qText.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 3,
                      height: 40,
                      decoration: BoxDecoration(
                        color: JournalColors.accent2,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '"$qText"',
                        style: const TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ── Empty / Error states ───────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.heart,
                color: JournalColors.textMuted, size: 44),
            SizedBox(height: 14),
            Text(
              'No journal data yet.',
              style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 6),
            Text(
              'Add some entries to see your mental health dashboard.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: JournalColors.textMuted, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.wifi_slash,
                color: JournalColors.textMuted, size: 36),
            const SizedBox(height: 14),
            Text(message,
                style: const TextStyle(
                    color: JournalColors.textSecondary, fontSize: 15)),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
