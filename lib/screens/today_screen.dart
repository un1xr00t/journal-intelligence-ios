import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../services/follow_up_tasks_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';
import 'follow_ups_screen.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final _api = ApiService();
  final _followUpTasks = FollowUpTaskService();

  Map<String, dynamic>? _brief;
  List<FollowUpTask> _tasks = const [];
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
      final results = await Future.wait<dynamic>([
        _api.getTodayBrief(),
        _followUpTasks.loadTasks(),
      ]);
      final data = results[0] as Map<String, dynamic>;
      final tasks = results[1] as List<FollowUpTask>;
      if (mounted) {
        setState(() {
          _brief = data;
          _tasks = tasks;
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

  String? _readTrend(Map<String, dynamic> map, String key) {
    final value = _readText(map, key)?.toLowerCase();
    if (value == 'rising' || value == 'falling' || value == 'stable') {
      return value;
    }
    return null;
  }

  String? _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('MMM d, y').format(parsed);
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
    final mostImportantDecision = _readText(brief, 'most_important_decision');
    final avoiding = _readText(brief, 'avoiding');
    final independenceNote = _readText(brief, 'independence_note');
    final trajectorySummary = _readText(trajectory, 'summary');

    final latestMood = _readDouble(stats, 'latest_mood');
    final latestSeverity = _readDouble(stats, 'latest_sev');
    final avgMood7d = _readDouble(stats, 'avg_mood_7d');
    final avgSeverity7d = _readDouble(stats, 'avg_sev_7d');
    final entries30d = _readInt(stats, 'total_entries_30d');
    final exitPlanPct = _readDouble(stats, 'exit_plan_pct');
    final exitPlanIdleDays = _readInt(stats, 'exit_plan_idle_days');
    final latestDate = _formatDate(_readText(stats, 'latest_date'));
    final moodTrend = _readTrend(stats, 'mood_trend');
    final stressTrend = _readTrend(stats, 'stress_trend');
    final conflictTrend = _readTrend(stats, 'conflict_trend');
    final followUpSummary = _followUpTasks.summarize(_tasks);

    final todayHorizon = _readText(horizons, 'today');
    final weekHorizon = _readText(horizons, 'this_week');
    final monthHorizon = _readText(horizons, 'this_month');
    final longTermHorizon = _readText(horizons, 'long_term');
    final trajectoryChangesIf = (trajectory['changes_if'] as List?)
            ?.map((item) => item?.toString().trim())
            .whereType<String>()
            .where((item) => item.isNotEmpty)
            .toList() ??
        const <String>[];

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

    if (avgMood7d != null ||
        avgSeverity7d != null ||
        latestDate != null ||
        exitPlanPct != null ||
        exitPlanIdleDays != null ||
        moodTrend != null ||
        stressTrend != null ||
        conflictTrend != null) {
      items.addAll([
        const SectionHeader(title: 'Recent Signals'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (avgMood7d != null)
              _InsightStatCard(
                label: 'Mood 7d',
                value: _formatMoodScore(avgMood7d),
                color: JournalColors.success,
              ),
            if (avgSeverity7d != null)
              _InsightStatCard(
                label: 'Severity 7d',
                value: avgSeverity7d.toStringAsFixed(1),
                color: _severityColor(avgSeverity7d),
              ),
            if (latestDate != null)
              _InsightStatCard(
                label: 'Latest Entry',
                value: latestDate,
                color: JournalColors.info,
              ),
            if (exitPlanPct != null)
              _InsightStatCard(
                label: 'Exit Plan',
                value: '${exitPlanPct.round()}%',
                color: JournalColors.accent2,
              ),
            if (exitPlanIdleDays != null)
              _InsightStatCard(
                label: 'Exit Plan Idle',
                value: '$exitPlanIdleDays days',
                color: JournalColors.orange,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (moodTrend != null)
              _TrendPill(
                label: 'Mood Trend',
                value: moodTrend,
                positiveWhenRising: true,
              ),
            if (stressTrend != null)
              _TrendPill(
                label: 'Stress Trend',
                value: stressTrend,
                positiveWhenRising: false,
              ),
            if (conflictTrend != null)
              _TrendPill(
                label: 'Conflict Trend',
                value: conflictTrend,
                positiveWhenRising: false,
              ),
          ],
        ),
        const SizedBox(height: 18),
      ]);
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

    if (followUpSummary.hasPressure) {
      items.addAll([
        const SectionHeader(title: 'Follow-Up Pressure'),
        const SizedBox(height: 10),
        _TodayFollowUpsCard(
          summary: followUpSummary,
          onOpen: () {
            Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => DefaultTextStyle.merge(
                  style: const TextStyle(decoration: TextDecoration.none),
                  child: const FollowUpsScreen(),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
      ]);
    }

    if (mostImportantDecision != null || avoiding != null) {
      items.addAll([
        const SectionHeader(title: 'Decision Pressure'),
        const SizedBox(height: 10),
        Column(
          children: [
            if (mostImportantDecision != null)
              _SignalCard(
                eyebrow: 'MOST IMPORTANT DECISION',
                title: 'This wants a clear call',
                body: mostImportantDecision,
                icon: CupertinoIcons.arrow_branch,
                color: JournalColors.info,
              ),
            if (mostImportantDecision != null && avoiding != null)
              const SizedBox(height: 10),
            if (avoiding != null)
              _SignalCard(
                eyebrow: 'AVOIDING',
                title: 'Resistance is showing up here',
                body: avoiding,
                icon: CupertinoIcons.hand_raised_fill,
                color: JournalColors.orange,
              ),
          ],
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
                  _TrajectoryPill(
                    label: 'Independence',
                    value: trajectory['independence'] as String?,
                    risingIsPositive: true,
                  ),
                  _TrajectoryPill(
                    label: 'Overall',
                    value: trajectory['overall'] as String?,
                    treatsOverall: true,
                  ),
                ],
              ),
              if (trajectoryChangesIf.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'THIS TRAJECTORY CHANGES IF',
                  style: TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                for (var index = 0; index < trajectoryChangesIf.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: index == trajectoryChangesIf.length - 1 ? 0 : 10,
                    ),
                    child: _BulletLine(text: trajectoryChangesIf[index]),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
      ]);
    }

    if (independenceNote != null) {
      items.addAll([
        const SectionHeader(title: 'Independence'),
        const SizedBox(height: 10),
        _SignalCard(
          eyebrow: 'PROGRESS TOWARD INDEPENDENCE',
          title: 'Movement on autonomy',
          body: independenceNote,
          icon: CupertinoIcons.person_crop_circle_badge_checkmark,
          color: JournalColors.accent2,
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
    final normalized = _normalizeMoodScore(score);
    if (normalized >= 7.0) return JournalColors.success;
    if (normalized >= 4.0) return JournalColors.severity;
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
                      value: _formatMoodScore(latestMood!),
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
                      color: _severityColor(latestSeverity),
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

Color _severityColor(double? severity) {
  if (severity == null) return JournalColors.severity;
  if (severity <= 3.0) return JournalColors.success;
  if (severity <= 6.0) return JournalColors.severity;
  return JournalColors.danger;
}

double _normalizeMoodScore(double score) => score <= 1.0 ? score * 10 : score;

String _formatMoodScore(double score) =>
    _normalizeMoodScore(score).toStringAsFixed(1);

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
  const _TrajectoryPill({
    required this.label,
    this.value,
    this.risingIsPositive = false,
    this.treatsOverall = false,
  });

  final String label;
  final String? value;
  final bool risingIsPositive;
  final bool treatsOverall;

  @override
  Widget build(BuildContext context) {
    final trend = value?.toLowerCase();
    final icon = treatsOverall
        ? switch (trend) {
            'positive' => CupertinoIcons.arrow_up_circle,
            'negative' => CupertinoIcons.arrow_down_circle,
            _ => CupertinoIcons.minus_circle,
          }
        : switch (trend) {
            'rising' => CupertinoIcons.arrow_up,
            'falling' => CupertinoIcons.arrow_down,
            _ => CupertinoIcons.minus,
          };
    final color = treatsOverall
        ? switch (trend) {
            'positive' => JournalColors.success,
            'negative' => JournalColors.danger,
            _ => JournalColors.textMuted,
          }
        : switch (trend) {
            'rising' =>
              risingIsPositive ? JournalColors.success : JournalColors.danger,
            'falling' =>
              risingIsPositive ? JournalColors.danger : JournalColors.success,
            _ => JournalColors.textMuted,
          };
    final text = value == null
        ? label
        : '$label: ${value![0].toUpperCase()}${value!.substring(1)}';

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
            text,
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

class _InsightStatCard extends StatelessWidget {
  const _InsightStatCard({
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
      width: 152,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _withAlpha(color, 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _withAlpha(color, 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: _withAlpha(color, 0.92),
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
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendPill extends StatelessWidget {
  const _TrendPill({
    required this.label,
    required this.value,
    required this.positiveWhenRising,
  });

  final String label;
  final String value;
  final bool positiveWhenRising;

  @override
  Widget build(BuildContext context) {
    final normalized = value.toLowerCase();
    final isRising = normalized == 'rising';
    final isFalling = normalized == 'falling';
    final color = isRising
        ? (positiveWhenRising ? JournalColors.success : JournalColors.danger)
        : isFalling
            ? (positiveWhenRising
                ? JournalColors.danger
                : JournalColors.success)
            : JournalColors.textMuted;
    final icon = isRising
        ? CupertinoIcons.arrow_up
        : isFalling
            ? CupertinoIcons.arrow_down
            : CupertinoIcons.minus;

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
            '$label: ${value[0].toUpperCase()}${value.substring(1)}',
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

class _BulletLine extends StatelessWidget {
  const _BulletLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            CupertinoIcons.arrow_right,
            color: JournalColors.success,
            size: 14,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ),
      ],
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

class _TodayFollowUpsCard extends StatelessWidget {
  const _TodayFollowUpsCard({
    required this.summary,
    required this.onOpen,
  });

  final FollowUpTaskSummary summary;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final nextTask = summary.nextTask;
    final accentColor = summary.overdueCount > 0
        ? JournalColors.danger
        : summary.dueSoonCount > 0
            ? JournalColors.severity
            : JournalColors.info;

    final headline = FollowUpTaskService.pressureHeadline(summary);

    final body = FollowUpTaskService.pressureBody(summary);

    return GlassCard(
      accentBorder: summary.overdueCount > 0 || summary.dueSoonCount > 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: _withAlpha(accentColor, 0.14),
                  border: Border.all(color: _withAlpha(accentColor, 0.32)),
                ),
                child: const Icon(
                  CupertinoIcons.briefcase_fill,
                  color: JournalColors.textPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FOLLOW-UPS',
                      style: TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      headline,
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
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
            children: [
              _FollowUpStatPill(
                label: 'Open',
                value: '${summary.openCount}',
                color: JournalColors.accent,
              ),
              if (summary.overdueCount > 0)
                _FollowUpStatPill(
                  label: 'Overdue',
                  value: '${summary.overdueCount}',
                  color: JournalColors.danger,
                ),
              if (summary.dueSoonCount > 0)
                _FollowUpStatPill(
                  label: 'Due Soon',
                  value: '${summary.dueSoonCount}',
                  color: JournalColors.severity,
                ),
              if (summary.waitingCount > 0)
                _FollowUpStatPill(
                  label: 'Waiting',
                  value: '${summary.waitingCount}',
                  color: JournalColors.info,
                ),
            ],
          ),
          if (nextTask != null) ...[
            const SizedBox(height: 14),
            Text(
              nextTask.title,
              style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if ((nextTask.counterparty ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                nextTask.counterparty!.trim(),
                style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              body,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 16),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onOpen,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Open Follow-Ups',
                  style: TextStyle(
                    color: JournalColors.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 6),
                Icon(
                  CupertinoIcons.arrow_right,
                  color: JournalColors.accent,
                  size: 15,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowUpStatPill extends StatelessWidget {
  const _FollowUpStatPill({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _withAlpha(color, 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _withAlpha(color, 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
