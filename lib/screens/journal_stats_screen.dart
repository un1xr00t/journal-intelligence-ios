import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../services/journal_stats_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';
import 'argument_tracker_screen.dart';
import 'detective_screen.dart';
import 'entry_detail_screen.dart';
import 'exit_plan_screen.dart';
import 'follow_ups_screen.dart';
import 'my_story_screen.dart';
import 'orbit_ledger_screen.dart';
import 'proof_vault_screen.dart';
import 'saved_sage_chats_screen.dart';
import 'timeline_screen.dart';

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
                  const SectionHeader(title: 'Last 12 weeks'),
                  const SizedBox(height: 10),
                  _ActivityCard(snapshot: snapshot),
                  const SizedBox(height: 24),
                  const SectionHeader(title: '12-month volume'),
                  const SizedBox(height: 10),
                  _MonthlyVolumeCard(snapshot: snapshot),
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
          ..._milestoneChips(),
        ],
      ),
    );
  }

  /// Up to three "almost there" chips computed from data already on hand.
  List<Widget> _milestoneChips() {
    final chips = <({String text, bool emphasized})>[];

    final entries = snapshot.journalEntries;
    if (entries > 0) {
      final nextEntryGoal = ((entries ~/ 50) + 1) * 50;
      final entriesLeft = nextEntryGoal - entries;
      chips.add((
        text: '$entriesLeft to $nextEntryGoal entries',
        emphasized: entriesLeft <= 10,
      ));
    }

    final current = snapshot.currentStreak;
    final longest = snapshot.longestStreak;
    if (current > 0 && current < longest) {
      chips.add((
        text: '${longest - current}d to beat your ${longest}d record',
        emphasized: longest - current <= 3,
      ));
    } else if (current == longest && longest > 3) {
      chips.add((text: 'Record streak — ${longest}d', emphasized: true));
    }

    final words = snapshot.totalWords;
    if (words > 0) {
      final nextWordGoal = ((words ~/ 25000) + 1) * 25000;
      final wordsLeft = nextWordGoal - words;
      if (wordsLeft <= 5000) {
        chips.add((
          text: '${NumberFormat.compact().format(wordsLeft)} words to '
              '${NumberFormat.compact().format(nextWordGoal)}',
          emphasized: true,
        ));
      }
    }

    if (chips.isEmpty) return const [];
    return [
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final chip in chips.take(3))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: JournalColors.bgBase.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: chip.emphasized
                      ? JournalColors.borderBright
                      : JournalColors.border,
                ),
              ),
              child: Text(
                chip.text,
                style: TextStyle(
                  color: chip.emphasized
                      ? JournalColors.textPrimary
                      : JournalColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    ];
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
    // Suppress comparisons the journal isn't old enough to support —
    // a misleading ▲ is worse than no chip at all.
    final has60d = snapshot.spansAtLeast(60);
    final hasPrevMonth = snapshot.spansAtLeast(31);
    final streakEnd = snapshot.longestStreakEnd;
    final items = [
      (
        value: '${snapshot.last30Days}',
        label: 'Entries · 30 days',
        delta: has60d
            ? _deltaText(snapshot.last30Days - snapshot.prev30Days,
                'vs prior 30d')
            : null,
        deltaColor: has60d
            ? _deltaColor(snapshot.last30Days - snapshot.prev30Days)
            : null,
      ),
      (
        value: '${snapshot.thisMonth}',
        label: 'Entries · this month',
        delta: hasPrevMonth
            ? _deltaText(snapshot.thisMonth - snapshot.prevMonthToDate,
                'vs last month')
            : null,
        deltaColor: hasPrevMonth
            ? _deltaColor(snapshot.thisMonth - snapshot.prevMonthToDate)
            : null,
      ),
      (
        value: '${snapshot.longestStreak}d',
        label: 'Longest streak',
        delta: streakEnd == null
            ? null
            : 'Set in ${DateFormat.MMM().format(streakEnd)}',
        deltaColor: JournalColors.textMuted,
      ),
      (
        value: '${snapshot.averageWords}',
        label: 'Avg words / entry',
        delta: snapshot.last30Days == 0
            ? null
            : _deltaText(
                snapshot.averageWords30d - snapshot.averageWords, 'vs lifetime'),
        deltaColor: snapshot.last30Days == 0
            ? null
            : _deltaColor(snapshot.averageWords30d - snapshot.averageWords),
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.55,
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
              if (item.delta != null) ...[
                const SizedBox(height: 6),
                Text(
                  item.delta!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: item.deltaColor ?? JournalColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _deltaText(int delta, String suffix) {
    if (delta == 0) return '— even $suffix';
    final arrow = delta > 0 ? '▲' : '▼';
    return '$arrow ${delta.abs()} $suffix';
  }

  Color _deltaColor(int delta) {
    if (delta == 0) return JournalColors.textMuted;
    return delta > 0 ? JournalColors.success : JournalColors.danger;
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.snapshot});

  final JournalStatsSnapshot snapshot;

  static const _weeks = 12;
  static const _gap = 3.0;
  static const _gutterWidth = 16.0;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Monday-aligned window: last full 12 weeks ending with today's week.
    // Calendar-safe arithmetic (no Duration) so DST can't shift a day.
    final start = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1) - 7 * (_weeks - 1),
    );
    var windowEntries = 0;
    for (final day in snapshot.entriesByDay.keys) {
      if (!day.isBefore(start) && !day.isAfter(today)) {
        windowEntries += snapshot.entriesByDay[day]!.length;
      }
    }
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
              final cell = (constraints.maxWidth -
                      _gutterWidth -
                      _gap * (_weeks - 1)) /
                  _weeks;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _gutterWidth,
                    child: Column(
                      children: [
                        for (var row = 0; row < 7; row++)
                          SizedBox(
                            height: cell + (row == 6 ? 0 : _gap),
                            child: row.isEven
                                ? Text(
                                    const ['M', '', 'W', '', 'F', '', 'S'][row],
                                    style: const TextStyle(
                                      color: JournalColors.textMuted,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ),
                  for (var week = 0; week < _weeks; week++) ...[
                    Column(
                      children: [
                        for (var row = 0; row < 7; row++) ...[
                          _cellFor(
                            context,
                            DateTime(
                              start.year,
                              start.month,
                              start.day + week * 7 + row,
                            ),
                            today,
                            cell,
                          ),
                          if (row != 6) const SizedBox(height: _gap),
                        ],
                      ],
                    ),
                    if (week != _weeks - 1) const SizedBox(width: _gap),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                '12 weeks ago',
                style: TextStyle(color: JournalColors.textMuted, fontSize: 10),
              ),
              const Spacer(),
              Text(
                '$windowEntries entries',
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
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text(
                'Less',
                style: TextStyle(color: JournalColors.textMuted, fontSize: 9),
              ),
              const SizedBox(width: 5),
              for (var bucket = 0; bucket <= 4; bucket++) ...[
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _bucketColor(bucket),
                    borderRadius: BorderRadius.circular(2.5),
                    border: Border.all(color: JournalColors.border, width: 0.5),
                  ),
                ),
                const SizedBox(width: 3),
              ],
              const SizedBox(width: 2),
              const Text(
                'More',
                style: TextStyle(color: JournalColors.textMuted, fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cellFor(
    BuildContext context,
    DateTime date,
    DateTime today,
    double size,
  ) {
    if (date.isAfter(today)) {
      // Days later this week that haven't happened yet.
      return SizedBox(width: size, height: size);
    }
    final first = snapshot.firstEntryDate;
    final beforeJournal = first != null && date.isBefore(first);
    final entries = snapshot.entriesByDay[date] ?? const [];
    final count = entries.length;
    final color = beforeJournal
        ? JournalColors.bgSurface
        : _bucketColor(count > 4 ? 4 : count);
    return GestureDetector(
      onTap: count == 0
          ? null
          : () => _showEntriesSheet(
                context,
                title: '${DateFormat.MMMEd().format(date)} — $count '
                    '${count == 1 ? 'entry' : 'entries'}',
                entries: entries,
              ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3.5),
          border: Border.all(color: JournalColors.border, width: 0.5),
        ),
      ),
    );
  }

  Color _bucketColor(int bucket) {
    return switch (bucket) {
      0 => JournalColors.bgCardAlt,
      1 => JournalColors.accent.withValues(alpha: 0.25),
      2 => JournalColors.accent.withValues(alpha: 0.45),
      3 => JournalColors.accent.withValues(alpha: 0.70),
      _ => JournalColors.accent,
    };
  }
}

class _MonthlyVolumeCard extends StatelessWidget {
  const _MonthlyVolumeCard({required this.snapshot});

  final JournalStatsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final months = snapshot.months;
    final maxCount = months.fold<int>(
      1,
      (current, month) => month.count > current ? month.count : current,
    );
    return GlassCard(
      child: SizedBox(
        height: 168,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: months.map((month) {
            final ratio = month.count / maxCount;
            // Unambiguous axis: 3-letter months, year marker on January
            // and on the first bar when the window crosses a year boundary.
            final isFirst = month == months.first;
            final showYear = month.month == DateTime.january || isFirst;
            final label = DateFormat.MMM().format(
              DateTime(month.year, month.month),
            );
            final yearLabel = "'${'${month.year}'.substring(2)}";
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showMonthEntries(context, month),
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
                        height: 18 + ratio * 88,
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
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 11,
                        child: showYear
                            ? Text(
                                yearLabel,
                                style: const TextStyle(
                                  color: JournalColors.textMuted,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showMonthEntries(BuildContext context, JournalStatsMonth month) {
    final days = snapshot.entriesByDay.keys
        .where((day) => day.year == month.year && day.month == month.month)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    final entries = [
      for (final day in days) ...snapshot.entriesByDay[day]!,
    ];
    final title = DateFormat.yMMMM().format(DateTime(month.year, month.month));
    _showEntriesSheet(
      context,
      title: '$title — ${entries.length} '
          '${entries.length == 1 ? 'entry' : 'entries'}',
      entries: entries,
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

  /// Destination screen per collection. Evidence has no standalone screen
  /// yet, and unavailable sources (count == null) stay inert.
  Widget? _destination() {
    return switch (collection.id) {
      'journal' => const TimelineScreen(),
      'detective' => const DetectiveScreen(),
      'vault' => const ProofVaultScreen(),
      'arguments' => const ArgumentTrackerScreen(),
      'follow_ups' => const FollowUpsScreen(),
      'orbit' => const OrbitLedgerScreen(),
      'exit_plan' => const ExitPlanScreen(),
      'story' => const MyStoryScreen(),
      'sage' => const SavedSageChatsScreen(),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final count = collection.count;
    final ratio = count == null ? 0.0 : count / maxCount;
    final destination = count == null ? null : _destination();
    final row = Padding(
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
          if (destination != null) ...[
            const SizedBox(width: 8),
            const Icon(
              CupertinoIcons.chevron_right,
              color: JournalColors.textMuted,
              size: 14,
            ),
          ],
        ],
      ),
    );
    if (destination == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _pushScreen(context, destination),
      child: row,
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
    final topSource = snapshot.topSource;
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
            value: topSource == null
                ? '—'
                : '$topSource · ${snapshot.topSourceSharePercent}%',
            valueColor: topSource == null ? JournalColors.textMuted : null,
          ),
          const _StatsDivider(verticalPadding: 12),
          _InsightRow(
            icon: CupertinoIcons.smiley_fill,
            label: 'Average mood',
            value: _score(snapshot.averageMood),
            valueColor: snapshot.averageMood == null
                ? JournalColors.textMuted
                : _moodColor(snapshot.averageMood!),
            subLabel: _coverage(snapshot.moodScoredCount),
          ),
          const _StatsDivider(verticalPadding: 12),
          _InsightRow(
            icon: CupertinoIcons.waveform_path_ecg,
            label: 'Average severity',
            value: _score(snapshot.averageSeverity),
            valueColor: snapshot.averageSeverity == null
                ? JournalColors.textMuted
                : JournalColors.severity,
            subLabel: _coverage(snapshot.severityScoredCount),
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
    return '${(value * 100).round().clamp(0, 100)} / 100';
  }

  String? _coverage(int scored) {
    if (scored == 0) return null;
    return 'Based on $scored of ${snapshot.journalEntries} entries';
  }

  Color _moodColor(double score) {
    if (score >= 0.7) return JournalColors.success;
    if (score >= 0.4) return JournalColors.severity;
    return JournalColors.danger;
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.subLabel,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final String? subLabel;

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: valueColor ?? JournalColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subLabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  subLabel!,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
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

void _pushScreen(BuildContext context, Widget screen) {
  HapticFeedback.lightImpact();
  Navigator.push(
    context,
    CupertinoPageRoute(
      builder: (ctx) => DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: screen,
      ),
    ),
  );
}

const _entrySheetCap = 30;

void _showEntriesSheet(
  BuildContext context, {
  required String title,
  required List<Map<String, dynamic>> entries,
}) {
  if (entries.isEmpty) return;
  HapticFeedback.lightImpact();
  final visible = entries.take(_entrySheetCap).toList();
  final overflow = entries.length - visible.length;
  showCupertinoModalPopup<void>(
    context: context,
    builder: (sheetContext) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(sheetContext).size.height * 0.72,
      ),
      decoration: const BoxDecoration(
        color: JournalColors.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: JournalColors.borderBright)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      color: JournalColors.textMuted,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                itemCount: visible.length + (overflow > 0 ? 1 : 0),
                separatorBuilder: (_, __) =>
                    const _StatsDivider(verticalPadding: 4),
                itemBuilder: (_, index) {
                  if (index == visible.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        '+$overflow more',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }
                  return _EntrySheetRow(
                    entry: visible[index],
                    onTap: () {
                      final id =
                          int.tryParse(visible[index]['id']?.toString() ?? '');
                      if (id == null) return;
                      Navigator.pop(sheetContext);
                      _pushScreen(context, EntryDetailScreen(entryId: id));
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EntrySheetRow extends StatelessWidget {
  const _EntrySheetRow({required this.entry, required this.onTap});

  final Map<String, dynamic> entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = (entry['summary_text'] ??
            entry['normalized_text'] ??
            entry['text'] ??
            '')
        .toString()
        .trim();
    final rawDate =
        entry['entry_date']?.toString() ?? entry['ingested_at']?.toString();
    final parsed = DateTime.tryParse(rawDate ?? '');
    final stamp = parsed == null
        ? ''
        : DateFormat.MMMd().add_jm().format(
              parsed.isUtc ? parsed.toLocal() : parsed,
            );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (stamp.isNotEmpty)
                    Text(
                      stamp,
                      style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              CupertinoIcons.chevron_right,
              color: JournalColors.textMuted,
              size: 14,
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
