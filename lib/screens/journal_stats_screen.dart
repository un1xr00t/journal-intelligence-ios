import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../services/journal_stats_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

class JournalStatsScreen extends StatefulWidget {
  const JournalStatsScreen({super.key});

  @override
  State<JournalStatsScreen> createState() => _JournalStatsScreenState();
}

class _JournalStatsScreenState extends State<JournalStatsScreen>
    with WidgetsBindingObserver {
  final _api = ApiService();
  late final JournalStatsService _statsService;
  JournalStatsSnapshot? _snapshot;
  bool _loading = true;
  bool _refreshing = false;
  bool _reloadQueued = false;
  String? _error;
  Timer? _changeDebounce;
  Timer? _liveRefreshTimer;

  @override
  void initState() {
    super.initState();
    _statsService = JournalStatsService(api: _api);
    WidgetsBinding.instance.addObserver(this);
    _api.journalDataRevision.addListener(_handleJournalDataChange);
    _liveRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _load(silent: true),
    );
    _load();
  }

  @override
  void dispose() {
    _changeDebounce?.cancel();
    _liveRefreshTimer?.cancel();
    _api.journalDataRevision.removeListener(_handleJournalDataChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(silent: true);
    }
  }

  void _handleJournalDataChange() {
    _changeDebounce?.cancel();
    _changeDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _load(silent: true),
    );
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) {
      _reloadQueued = true;
      return;
    }
    _refreshing = true;
    if (!silent && mounted) {
      setState(() {
        _loading = _snapshot == null;
        _error = null;
      });
    }
    try {
      final snapshot = await _statsService.load();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_snapshot == null) _error = _parseError(e);
      });
    } finally {
      _refreshing = false;
      if (_reloadQueued) {
        _reloadQueued = false;
        unawaited(_load(silent: true));
      }
    }
  }

  String _parseError(dynamic error) {
    final text = error.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(text);
    return match?.group(1) ?? 'Journal stats could not be loaded.';
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Journal Stats'),
            backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
          ),
          CupertinoSliverRefreshControl(onRefresh: () => _load()),
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
          else if (_snapshot case final snapshot?)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _StatsHero(snapshot: snapshot),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Writing momentum'),
                  const SizedBox(height: 10),
                  _MomentumGrid(snapshot: snapshot),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Last 30 days'),
                  const SizedBox(height: 10),
                  _ActivityCard(snapshot: snapshot),
                  const SizedBox(height: 24),
                  const SectionHeader(title: '12-month volume'),
                  const SizedBox(height: 10),
                  _MonthlyVolumeCard(months: snapshot.months),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Everything documented'),
                  const SizedBox(height: 10),
                  _CollectionsCard(collections: snapshot.collections),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Journal intelligence'),
                  const SizedBox(height: 10),
                  _IntelligenceCard(snapshot: snapshot),
                  const SizedBox(height: 18),
                  _LiveStatus(generatedAt: snapshot.generatedAt),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatsHero extends StatelessWidget {
  const _StatsHero({required this.snapshot});

  final JournalStatsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            JournalColors.accent.withValues(alpha: 0.30),
            JournalColors.accent2.withValues(alpha: 0.20),
            JournalColors.bgCard,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: JournalColors.borderBright),
        boxShadow: const [
          BoxShadow(color: JournalColors.accentGlow, blurRadius: 24),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: JournalColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: JournalColors.borderBright),
                ),
                child: const Icon(
                  CupertinoIcons.chart_bar_alt_fill,
                  color: JournalColors.textPrimary,
                  size: 22,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: JournalColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: JournalColors.success.withValues(alpha: 0.30),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.bolt_fill,
                      size: 11,
                      color: JournalColors.success,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'LIVE',
                      style: TextStyle(
                        color: JournalColors.success,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            NumberFormat.decimalPattern().format(snapshot.journalEntries),
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 46,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.8,
            ),
          ),
          const Text(
            'JOURNAL ENTRIES',
            style: TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  value: NumberFormat.compact().format(snapshot.totalWords),
                  label: 'Words written',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroMetric(
                  value: NumberFormat.compact()
                      .format(snapshot.totalTrackedRecords),
                  label: 'All records',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroMetric(
                  value: '${snapshot.currentStreak}d',
                  label: 'Current streak',
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
  const _HeroMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JournalColors.bgBase.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentumGrid extends StatelessWidget {
  const _MomentumGrid({required this.snapshot});

  final JournalStatsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final items = [
      (value: '${snapshot.last30Days}', label: 'Entries · 30 days'),
      (value: '${snapshot.thisMonth}', label: 'Entries · this month'),
      (value: '${snapshot.longestStreak}d', label: 'Longest streak'),
      (value: '${snapshot.averageWords}', label: 'Avg words / entry'),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.75,
      ),
      itemCount: items.length,
      itemBuilder: (_, index) {
        final item = items[index];
        return GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.value,
                style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                item.label,
                style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.snapshot});

  final JournalStatsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final maxCount = snapshot.recentDays.fold<int>(
      1,
      (current, day) => day.count > current ? day.count : current,
    );
    return GlassCard(
      accentBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${snapshot.consistencyPercent}%',
                style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'consistency\nacross the last 30 days',
                  style: TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 4.0;
              final width = (constraints.maxWidth - spacing * 9) / 10;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: snapshot.recentDays.map((day) {
                  final strength = day.count == 0
                      ? 0.06
                      : 0.28 + (day.count / maxCount) * 0.62;
                  return Container(
                    width: width,
                    height: width,
                    decoration: BoxDecoration(
                      color: JournalColors.accent.withValues(alpha: strength),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: JournalColors.border),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                '30 days ago',
                style: TextStyle(color: JournalColors.textMuted, fontSize: 10),
              ),
              const Spacer(),
              Text(
                '${snapshot.last30Days} entries',
                style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              const Text(
                'Today',
                style: TextStyle(color: JournalColors.textMuted, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthlyVolumeCard extends StatelessWidget {
  const _MonthlyVolumeCard({required this.months});

  final List<JournalStatsMonth> months;

  @override
  Widget build(BuildContext context) {
    final maxCount = months.fold<int>(
      1,
      (current, month) => month.count > current ? month.count : current,
    );
    return GlassCard(
      child: SizedBox(
        height: 160,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: months.map((month) {
            final ratio = month.count / maxCount;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      month.count == 0 ? '' : '${month.count}',
                      style: const TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 18 + ratio * 92,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            JournalColors.accent2,
                            JournalColors.accent,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      DateFormat.MMM().format(
                        DateTime(month.year, month.month),
                      )[0],
                      style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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

class _CollectionsCard extends StatelessWidget {
  const _CollectionsCard({required this.collections});

  final List<JournalStatsCollection> collections;

  @override
  Widget build(BuildContext context) {
    final maxCount = collections.fold<int>(
      1,
      (current, collection) =>
          (collection.count ?? 0) > current ? collection.count! : current,
    );
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var index = 0; index < collections.length; index++) ...[
            _CollectionRow(
              collection: collections[index],
              maxCount: maxCount,
            ),
            if (index != collections.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: _StatsDivider(),
              ),
          ],
        ],
      ),
    );
  }
}

class _CollectionRow extends StatelessWidget {
  const _CollectionRow({required this.collection, required this.maxCount});

  final JournalStatsCollection collection;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final count = collection.count;
    final ratio = count == null ? 0.0 : count / maxCount;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _collectionColor(collection.id).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              _collectionIcon(collection.id),
              color: _collectionColor(collection.id),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        collection.label,
                        style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      count == null
                          ? '—'
                          : NumberFormat.decimalPattern().format(count),
                      style: TextStyle(
                        color: count == null
                            ? JournalColors.textMuted
                            : JournalColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  collection.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 3,
                    color: JournalColors.bgSurface,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: ratio.clamp(0.0, 1.0),
                      child: Container(color: _collectionColor(collection.id)),
                    ),
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

class _IntelligenceCard extends StatelessWidget {
  const _IntelligenceCard({required this.snapshot});

  final JournalStatsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final dateRange = snapshot.firstEntryDate == null
        ? 'No dated entries yet'
        : '${DateFormat.yMMMd().format(snapshot.firstEntryDate!)} — ${DateFormat.yMMMd().format(snapshot.latestEntryDate!)}';
    return GlassCard(
      child: Column(
        children: [
          _InsightRow(
            icon: CupertinoIcons.calendar,
            label: 'Journal span',
            value: dateRange,
          ),
          const _StatsDivider(verticalPadding: 12),
          _InsightRow(
            icon: CupertinoIcons.flame_fill,
            label: 'Most active day',
            value: snapshot.busiestWeekday,
          ),
          const _StatsDivider(verticalPadding: 12),
          _InsightRow(
            icon: CupertinoIcons.device_phone_portrait,
            label: 'Top capture source',
            value: snapshot.topSource,
          ),
          const _StatsDivider(verticalPadding: 12),
          _InsightRow(
            icon: CupertinoIcons.smiley_fill,
            label: 'Average mood',
            value: _score(snapshot.averageMood),
          ),
          const _StatsDivider(verticalPadding: 12),
          _InsightRow(
            icon: CupertinoIcons.waveform_path_ecg,
            label: 'Average severity',
            value: _score(snapshot.averageSeverity),
          ),
          const _StatsDivider(verticalPadding: 12),
          _InsightRow(
            icon: CupertinoIcons.calendar_badge_plus,
            label: 'Active journal days',
            value: NumberFormat.decimalPattern().format(snapshot.activeDays),
          ),
        ],
      ),
    );
  }

  String _score(double? value) {
    if (value == null) return 'Not enough scored entries';
    return '${(value * 100).round()} / 100';
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: JournalColors.accent, size: 18),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsDivider extends StatelessWidget {
  const _StatsDivider({this.verticalPadding = 0});

  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: const SizedBox(
        height: 1,
        child: ColoredBox(color: JournalColors.border),
      ),
    );
  }
}

class _LiveStatus extends StatelessWidget {
  const _LiveStatus({required this.generatedAt});

  final DateTime generatedAt;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          CupertinoIcons.arrow_2_circlepath,
          color: JournalColors.success,
          size: 12,
        ),
        const SizedBox(width: 7),
        Text(
          'Live updates on · checked ${DateFormat.jm().format(generatedAt)}',
          style: const TextStyle(
            color: JournalColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final Future<void> Function({bool silent}) onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.wifi_slash,
              color: JournalColors.textMuted,
              size: 34,
            ),
            const SizedBox(height: 14),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 14),
            CupertinoButton(
              color: JournalColors.accent,
              onPressed: () => onRetry(),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

Color _collectionColor(String id) {
  return switch (id) {
    'journal' => JournalColors.accent,
    'detective' => JournalColors.accent2,
    'vault' => JournalColors.success,
    'arguments' => JournalColors.orange,
    'follow_ups' => JournalColors.info,
    'orbit' => JournalColors.accent,
    'exit_plan' => JournalColors.success,
    'story' => JournalColors.accent2,
    'sage' => JournalColors.info,
    'evidence' => JournalColors.orange,
    _ => JournalColors.textSecondary,
  };
}

IconData _collectionIcon(String id) {
  return switch (id) {
    'journal' => CupertinoIcons.book_fill,
    'detective' => CupertinoIcons.search,
    'vault' => CupertinoIcons.lock_shield_fill,
    'arguments' => CupertinoIcons.doc_text_search,
    'follow_ups' => CupertinoIcons.briefcase_fill,
    'orbit' => CupertinoIcons.smallcircle_circle_fill,
    'exit_plan' => CupertinoIcons.map_fill,
    'story' => CupertinoIcons.book_circle_fill,
    'sage' => CupertinoIcons.sparkles,
    'evidence' => CupertinoIcons.archivebox_fill,
    _ => CupertinoIcons.circle_grid_3x3_fill,
  };
}
