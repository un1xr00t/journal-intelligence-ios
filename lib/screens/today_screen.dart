import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getTodayBrief();
      if (mounted) {
        setState(() {
          _brief = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _parseError(e);
          _loading = false;
        });
      }
    }
  }

  String _parseError(dynamic e) {
    final str = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    return match?.group(1) ?? 'Something went wrong.';
  }

  Map<String, dynamic> _readMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, entryValue) => MapEntry(key.toString(), entryValue),
      );
    }
    return <String, dynamic>{};
  }

  String? _readText(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return value?.toString().trim().isNotEmpty == true
        ? value.toString().trim()
        : null;
  }

  double? _readDouble(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  int? _readInt(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  List<Widget> _buildContent() {
    final noData = _brief!['no_data'] as bool? ?? false;
    final brief = _readMap(_brief!['brief']);
    final stats = _readMap(_brief!['stats']);
    final trajectory = _readMap(brief['trajectory']);
    final horizons = _readMap(brief['time_horizons']);

    final emotionalState = _readText(brief, 'emotional_state');
    final doToday = _readText(brief, 'do_today');
    final stopDoing = _readText(brief, 'stop_doing');
    final biggestRisk = _readText(brief, 'biggest_risk');
    final gettingBetter = _readText(brief, 'getting_better');
    final gettingWorse = _readText(brief, 'getting_worse');
    final trajectorySummary = _readText(trajectory, 'summary');

    final latestMood = _readDouble(stats, 'latest_mood');
    final latestSeverity = _readDouble(stats, 'latest_sev');
    final entries30d = _readInt(stats, 'total_entries_30d');

    final todayHorizon = _readText(horizons, 'today');
    final weekHorizon = _readText(horizons, 'this_week');
    final monthHorizon = _readText(horizons, 'this_month');
    final longTermHorizon = _readText(horizons, 'long_term');

    final items = <Widget>[
      _TodayHero(
        noData: noData,
        emotionalState: emotionalState,
        latestMood: latestMood,
        latestSeverity: latestSeverity,
        entries30d: entries30d,
      ),
      const SizedBox(height: 20),
    ];

    if (noData) {
      items.add(
        const GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _HeroGlyph(icon: CupertinoIcons.book, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This view needs a little more journal history.',
                      style: TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14),
              Text(
                'Write a few more entries and this page will start showing a daily summary here.',
                style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      );
      items.add(const SizedBox(height: 40));
      return items;
    }

    if (doToday != null || stopDoing != null) {
      items.addAll([
        const SectionHeader(title: 'Daily Focus'),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 720;
            if (stacked) {
              return Column(
                children: [
                  if (doToday != null)
                    _FocusCard(
                      eyebrow: 'DO TODAY',
                      title: 'Make this move',
                      body: doToday,
                      icon: CupertinoIcons.arrow_right_circle_fill,
                      color: JournalColors.accent,
                    ),
                  if (doToday != null && stopDoing != null)
                    const SizedBox(height: 12),
                  if (stopDoing != null)
                    _FocusCard(
                      eyebrow: 'STOP DOING',
                      title: 'Cut the drag',
                      body: stopDoing,
                      icon: CupertinoIcons.xmark_circle_fill,
                      color: JournalColors.danger,
                    ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (doToday != null)
                  Expanded(
                    child: _FocusCard(
                      eyebrow: 'DO TODAY',
                      title: 'Make this move',
                      body: doToday,
                      icon: CupertinoIcons.arrow_right_circle_fill,
                      color: JournalColors.accent,
                    ),
                  ),
                if (doToday != null && stopDoing != null)
                  const SizedBox(width: 12),
                if (stopDoing != null)
                  Expanded(
                    child: _FocusCard(
                      eyebrow: 'STOP DOING',
                      title: 'Cut the drag',
                      body: stopDoing,
                      icon: CupertinoIcons.xmark_circle_fill,
                      color: JournalColors.danger,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
      ]);
    }

    if (biggestRisk != null) {
      items.addAll([
        const SectionHeader(title: 'Risk Radar'),
        const SizedBox(height: 10),
        _RiskCard(text: biggestRisk),
        const SizedBox(height: 18),
      ]);
    }

    if (gettingBetter != null || gettingWorse != null) {
      items.addAll([
        const SectionHeader(title: 'Signals'),
        const SizedBox(height: 10),
        if (gettingBetter != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SignalCard(
              eyebrow: 'GETTING BETTER',
              title: 'Momentum is building here',
              body: gettingBetter,
              icon: CupertinoIcons.arrow_up_circle_fill,
              color: JournalColors.success,
            ),
          ),
        if (gettingWorse != null)
          _SignalCard(
            eyebrow: 'GETTING WORSE',
            title: 'This needs intervention',
            body: gettingWorse,
            icon: CupertinoIcons.arrow_down_circle_fill,
            color: JournalColors.danger,
          ),
        const SizedBox(height: 18),
      ]);
    }

    if (trajectorySummary != null) {
      items.addAll([
        const SectionHeader(title: 'Trajectory'),
        const SizedBox(height: 10),
        GlassCard(
          accentBorder: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  _HeroGlyph(icon: CupertinoIcons.sparkles, size: 18),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'OVERALL ARC',
                      style: TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                trajectorySummary,
                style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TrajectoryPill(
                    label: 'Mood',
                    value: trajectory['mood'] as String?,
                  ),
                  _TrajectoryPill(
                    label: 'Stress',
                    value: trajectory['stress'] as String?,
                  ),
                  _TrajectoryPill(
                    label: 'Conflict',
                    value: trajectory['conflict'] as String?,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
      ]);
    }

    if (todayHorizon != null ||
        weekHorizon != null ||
        monthHorizon != null ||
        longTermHorizon != null) {
      items.addAll([
        const SectionHeader(title: 'Time Horizons'),
        const SizedBox(height: 10),
        GlassCard(
          child: Column(
            children: [
              if (todayHorizon != null)
                _HorizonTile(
                  label: 'Today',
                  text: todayHorizon,
                  color: JournalColors.accent,
                ),
              if (weekHorizon != null)
                _HorizonTile(
                  label: 'This Week',
                  text: weekHorizon,
                  color: JournalColors.info,
                ),
              if (monthHorizon != null)
                _HorizonTile(
                  label: 'This Month',
                  text: monthHorizon,
                  color: JournalColors.orange,
                ),
              if (longTermHorizon != null)
                _HorizonTile(
                  label: 'Long Term',
                  text: longTermHorizon,
                  color: JournalColors.accent2,
                  isLast: true,
                ),
            ],
          ),
        ),
      ]);
    }

    items.add(const SizedBox(height: 40));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: Stack(
        children: [
          const Positioned.fill(child: _TodayBackdrop()),
          CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('Today'),
                backgroundColor: _withAlpha(JournalColors.bgBase, 0.85),
                border: const Border(
                  bottom: BorderSide(color: JournalColors.border, width: 0.5),
                ),
                trailing: GestureDetector(
                  onTap: _load,
                  child: const Icon(
                    CupertinoIcons.refresh,
                    color: JournalColors.accent,
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  child: Center(
                    child: CupertinoActivityIndicator(
                      color: JournalColors.accent,
                    ),
                  ),
                )
              else if (_error != null)
                SliverFillRemaining(
                  child: _ErrorView(error: _error!, onRetry: _load),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(_buildContent()),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayBackdrop extends StatelessWidget {
  const _TodayBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF080A16),
                    JournalColors.bgBase,
                    Color(0xFF05060D),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 88,
            left: -28,
            child: _GlowOrb(
              size: 180,
              color: _withAlpha(JournalColors.accent, 0.20),
            ),
          ),
          Positioned(
            top: 236,
            right: -40,
            child: _GlowOrb(
              size: 150,
              color: _withAlpha(JournalColors.accent2, 0.16),
            ),
          ),
          Positioned(
            bottom: 132,
            left: 24,
            child: _GlowOrb(
              size: 130,
              color: _withAlpha(JournalColors.info, 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, _withAlpha(color, 0)],
        ),
      ),
    );
  }
}

class _TodayHero extends StatelessWidget {
  const _TodayHero({
    required this.noData,
    required this.emotionalState,
    required this.latestMood,
    required this.latestSeverity,
    required this.entries30d,
  });

  final bool noData;
  final String? emotionalState;
  final double? latestMood;
  final double? latestSeverity;
  final int? entries30d;

  Color _moodColor(double score) {
    if (score >= 0.7) return JournalColors.success;
    if (score >= 0.4) return JournalColors.severity;
    return JournalColors.danger;
  }

  Color _severityColor(double severity) {
    if (severity <= 3.0) return JournalColors.success;
    if (severity <= 6.0) return JournalColors.severity;
    return JournalColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekday = DateFormat('EEEE').format(now);
    final dateLabel = DateFormat('MMMM d, y').format(now);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: JournalColors.borderBright),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _withAlpha(JournalColors.bgCard, 0.97),
            _withAlpha(const Color(0xFF11142A), 0.94),
            _withAlpha(const Color(0xFF191122), 0.92),
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: JournalColors.accentGlow,
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _HeroGlyph(icon: CupertinoIcons.sparkles, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$weekday · $dateLabel'.toUpperCase(),
                      style: const TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      noData
                          ? 'Today\'s summary will appear once there is more to read.'
                          : 'A quick read on what your journal is showing today.',
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _withAlpha(Colors.white, 0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _withAlpha(Colors.white, 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EMOTIONAL CLIMATE',
                  style: TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  emotionalState ??
                      'No clear emotional signal has surfaced yet.',
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 16,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          if (!noData &&
              (latestMood != null ||
                  latestSeverity != null ||
                  entries30d != null)) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (latestMood != null)
                  Expanded(
                    child: _MetricTile(
                      label: 'Mood',
                      value: '${(latestMood! * 100).round()}%',
                      color: _moodColor(latestMood!),
                    ),
                  ),
                if (latestMood != null &&
                    (latestSeverity != null || entries30d != null))
                  const SizedBox(width: 10),
                if (latestSeverity != null)
                  Expanded(
                    child: _MetricTile(
                      label: 'Severity',
                      value: latestSeverity!.toStringAsFixed(1),
                      color: _severityColor(latestSeverity!),
                    ),
                  ),
                if (latestSeverity != null && entries30d != null)
                  const SizedBox(width: 10),
                if (entries30d != null)
                  Expanded(
                    child: _MetricTile(
                      label: 'Entries 30d',
                      value: '$entries30d',
                      color: JournalColors.info,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroGlyph extends StatelessWidget {
  const _HeroGlyph({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 2.1,
      height: size * 2.1,
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
      child: Icon(icon, color: JournalColors.textPrimary, size: size),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _withAlpha(color, 0.10),
        border: Border.all(color: _withAlpha(color, 0.24)),
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
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.icon,
    required this.color,
  });

  final String eyebrow;
  final String title;
  final String body;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _withAlpha(color, 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: _withAlpha(color, 0.24)),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: TextStyle(
                        color: _withAlpha(color, 0.92),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            body,
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskCard extends StatelessWidget {
  const _RiskCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _withAlpha(JournalColors.severity, 0.12),
            _withAlpha(JournalColors.orange, 0.08),
          ],
        ),
        border: Border.all(color: _withAlpha(JournalColors.severity, 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _withAlpha(JournalColors.severity, 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: _withAlpha(JournalColors.severity, 0.24),
              ),
            ),
            child: const Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              color: JournalColors.severity,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BIGGEST RISK',
                  style: TextStyle(
                    color: JournalColors.severity,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.icon,
    required this.color,
  });

  final String eyebrow;
  final String title;
  final String body;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _withAlpha(color, 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: _withAlpha(color, 0.24)),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrajectoryPill extends StatelessWidget {
  const _TrajectoryPill({required this.label, this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final trend = value?.toLowerCase();
    final icon = switch (trend) {
      'rising' => CupertinoIcons.arrow_up,
      'falling' => CupertinoIcons.arrow_down,
      _ => CupertinoIcons.minus,
    };
    final color = switch (trend) {
      'rising' => JournalColors.success,
      'falling' => JournalColors.danger,
      _ => JournalColors.textMuted,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: _withAlpha(color, 0.10),
        border: Border.all(color: _withAlpha(color, 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HorizonTile extends StatelessWidget {
  const _HorizonTile({
    required this.label,
    required this.text,
    required this.color,
    this.isLast = false,
  });

  final String label;
  final String text;
  final Color color;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: JournalColors.bgCard,
                border: Border.all(color: JournalColors.borderBright),
              ),
              child: const Icon(
                CupertinoIcons.wifi_slash,
                color: JournalColors.textMuted,
                size: 34,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Today brief unavailable',
              style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton(
              color: JournalColors.accent,
              borderRadius: BorderRadius.circular(14),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
