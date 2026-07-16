import 'api_service.dart';
import 'follow_up_tasks_service.dart';
import 'orbit_ledger_service.dart';

String _plural(int n, String singular, [String? pluralForm]) =>
    n == 1 ? singular : (pluralForm ?? '${singular}s');

class JournalStatsCollection {
  const JournalStatsCollection({
    required this.id,
    required this.label,
    required this.count,
    required this.detail,
  });

  final String id;
  final String label;
  final int? count;
  final String detail;
}

class JournalStatsMonth {
  const JournalStatsMonth({
    required this.year,
    required this.month,
    required this.count,
  });

  final int year;
  final int month;
  final int count;
}

class JournalStatsDay {
  const JournalStatsDay({required this.date, required this.count});

  final DateTime date;
  final int count;
}

class JournalStatsSnapshot {
  const JournalStatsSnapshot({
    required this.generatedAt,
    required this.journalEntries,
    required this.totalTrackedRecords,
    required this.totalWords,
    required this.averageWords,
    required this.activeDays,
    required this.currentStreak,
    required this.longestStreak,
    required this.last30Days,
    required this.prev30Days,
    required this.thisMonth,
    required this.prevMonthToDate,
    required this.thisYear,
    required this.consistencyPercent,
    required this.averageMood,
    required this.moodScoredCount,
    required this.averageSeverity,
    required this.severityScoredCount,
    required this.averageWords30d,
    required this.longestStreakEnd,
    required this.firstEntryDate,
    required this.latestEntryDate,
    required this.busiestWeekday,
    required this.topSource,
    required this.topSourceSharePercent,
    required this.collections,
    required this.months,
    required this.recentDays,
    required this.entriesByDay,
  });

  final DateTime generatedAt;
  final int journalEntries;
  final int totalTrackedRecords;
  final int totalWords;
  final int averageWords;
  final int activeDays;
  final int currentStreak;
  final int longestStreak;
  final int last30Days;

  /// Entries in the 30 days before the last-30-day window (days 31–60 ago).
  final int prev30Days;
  final int thisMonth;

  /// Entries in the previous month, counted only through the same
  /// day-of-month as today (day-for-day comparison).
  final int prevMonthToDate;
  final int thisYear;
  final int consistencyPercent;
  final double? averageMood;
  final int moodScoredCount;
  final double? averageSeverity;
  final int severityScoredCount;

  /// Average words per entry across the last 30 days only.
  final int averageWords30d;

  /// The date on which the longest streak ended.
  final DateTime? longestStreakEnd;
  final DateTime? firstEntryDate;
  final DateTime? latestEntryDate;
  final String busiestWeekday;

  /// Null when no entry carries a usable capture source.
  final String? topSource;
  final int? topSourceSharePercent;
  final List<JournalStatsCollection> collections;
  final List<JournalStatsMonth> months;
  final List<JournalStatsDay> recentDays;

  /// Raw entries grouped by local calendar day — powers drill-in sheets
  /// without any additional API calls.
  final Map<DateTime, List<Map<String, dynamic>>> entriesByDay;

  /// True when the journal spans at least [days] days, so period
  /// comparisons against that window are meaningful.
  bool spansAtLeast(int days) {
    final first = firstEntryDate;
    if (first == null) return false;
    return generatedAt.difference(first).inDays >= days;
  }
}

class JournalStatsService {
  JournalStatsService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  Future<JournalStatsSnapshot> load() async {
    final entriesFuture = _api.getAllEntriesForExport(pageSize: 100);
    final detectiveFuture = _safeCollection(_loadDetectiveCount);
    final vaultFuture = _safeCollection(_loadVaultCount);
    final argumentFuture = _safeCollection(() async {
      final reports = await _api.listArgumentTrackerReports();
      return (
        reports.length,
        '${reports.length} saved case ${_plural(reports.length, 'report')}'
      );
    });
    final followUpsFuture = _safeCollection(() async {
      final tasks = await FollowUpTaskService(api: _api).loadTasks();
      final comments = tasks.fold<int>(
        0,
        (sum, task) => sum + task.comments.length,
      );
      return (
        tasks.length + comments,
        '${tasks.length} ${_plural(tasks.length, 'follow-up')} + '
            '$comments ${_plural(comments, 'comment')}'
      );
    });
    final orbitFuture = _safeCollection(() async {
      final entries = await OrbitLedgerService(api: _api).loadEntries();
      return (
        entries.length,
        '${entries.length} logged ${_plural(entries.length, 'request')}'
      );
    });
    final exitPlanFuture = _safeCollection(() async {
      final response = await _api.exitPlanGetNotes();
      final notes = response['notes'] as List? ?? const [];
      return (
        notes.length,
        '${notes.length} plan ${_plural(notes.length, 'note')}'
      );
    });
    final storyFuture = _safeCollection(() async {
      final drafts = await _api.myStoryGetDrafts();
      return (
        drafts.length,
        '${drafts.length} saved narrative ${_plural(drafts.length, 'draft')}'
      );
    });
    final sageFuture = _safeCollection(() async {
      final conversations = await _api.listSavedFloatchatConversations();
      return (
        conversations.length,
        '${conversations.length} saved '
            '${_plural(conversations.length, 'conversation')}'
      );
    });
    final evidenceFuture = _safeCollection(() async {
      final evidence = await _api.getEvidenceRecords();
      return (
        evidence.length,
        '${evidence.length} evidence ${_plural(evidence.length, 'record')}'
      );
    });

    final entries = await entriesFuture;
    final auxiliary = await Future.wait([
      detectiveFuture,
      vaultFuture,
      argumentFuture,
      followUpsFuture,
      orbitFuture,
      exitPlanFuture,
      storyFuture,
      sageFuture,
      evidenceFuture,
    ]);

    final collections = <JournalStatsCollection>[
      JournalStatsCollection(
        id: 'journal',
        label: 'Journal',
        count: entries.length,
        detail:
            '${entries.length} timeline ${_plural(entries.length, 'entry', 'entries')}',
      ),
      _collection('detective', 'Detective Mode', auxiliary[0]),
      _collection('vault', 'Proof Vault', auxiliary[1]),
      _collection('arguments', 'Argument Tracker', auxiliary[2]),
      _collection('follow_ups', 'Follow-Ups', auxiliary[3]),
      _collection('orbit', 'Orbit Ledger', auxiliary[4]),
      _collection('exit_plan', 'Exit Plan', auxiliary[5]),
      _collection('story', 'My Story', auxiliary[6]),
      _collection('sage', 'Sage Conversations', auxiliary[7]),
      _collection('evidence', 'Evidence', auxiliary[8]),
    ];

    return _buildSnapshot(entries, collections);
  }

  Future<(int, String)> _loadDetectiveCount() async {
    final cases = await _api.detectiveGetCases();
    final counts = await Future.wait(
      cases.whereType<Map>().map((item) async {
        final id = item['id']?.toString() ?? '';
        if (id.isEmpty) return 0;
        return (await _api.detectiveGetEntries(id)).length;
      }),
    );
    final total = counts.fold<int>(0, (sum, count) => sum + count);
    return (
      total,
      '$total ${_plural(total, 'entry', 'entries')} across '
          '${cases.length} ${_plural(cases.length, 'case')}'
    );
  }

  Future<(int, String)> _loadVaultCount() async {
    final folders = await _api.vaultGetFolders();
    final counts = await Future.wait(
      folders.whereType<Map>().map((item) async {
        final id = item['id']?.toString() ?? '';
        if (id.isEmpty) return 0;
        return (await _api.vaultGetFolderItems(id)).length;
      }),
    );
    final total = counts.fold<int>(0, (sum, count) => sum + count);
    return (
      total,
      '$total ${_plural(total, 'entry', 'entries')} across '
          '${folders.length} ${_plural(folders.length, 'folder')}'
    );
  }

  Future<(int, String)?> _safeCollection(
    Future<(int, String)> Function() loader,
  ) async {
    try {
      return await loader();
    } catch (_) {
      return null;
    }
  }

  JournalStatsCollection _collection(
    String id,
    String label,
    (int, String)? value,
  ) {
    return JournalStatsCollection(
      id: id,
      label: label,
      count: value?.$1,
      detail: value?.$2 ?? 'Temporarily unavailable',
    );
  }

  JournalStatsSnapshot _buildSnapshot(
    List<Map<String, dynamic>> entries,
    List<JournalStatsCollection> collections,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dates = entries.map(_entryDate).whereType<DateTime>().toList();
    final dateCounts = <DateTime, int>{};
    final entriesByDay = <DateTime, List<Map<String, dynamic>>>{};
    final sourceCounts = <String, int>{};
    final weekdayCounts = List<int>.filled(7, 0);
    final moodScores = <double>[];
    final severityScores = <double>[];
    var totalWords = 0;
    final last30Start = today.subtract(const Duration(days: 29));
    var words30d = 0;
    var entries30d = 0;

    for (final entry in entries) {
      final date = _entryDate(entry);
      final words = _wordCount(entry);
      if (date != null) {
        dateCounts[date] = (dateCounts[date] ?? 0) + 1;
        (entriesByDay[date] ??= []).add(entry);
        weekdayCounts[date.weekday - 1]++;
        if (!date.isBefore(last30Start) && !date.isAfter(today)) {
          words30d += words;
          entries30d++;
        }
      }
      final source = _sourceLabel(entry['source']?.toString());
      if (source != null) {
        sourceCounts[source] = (sourceCounts[source] ?? 0) + 1;
      }
      totalWords += words;
      final mood = _normalizedScore(entry['mood_score']);
      final severity = _normalizedScore(entry['severity_score']);
      if (mood != null) moodScores.add(mood);
      if (severity != null) severityScores.add(severity);
    }

    final uniqueDates = dateCounts.keys.toList()..sort();
    final firstDate = uniqueDates.isEmpty ? null : uniqueDates.first;
    final latestDate = uniqueDates.isEmpty ? null : uniqueDates.last;
    final last30Days = dates
        .where((date) => !date.isBefore(last30Start) && !date.isAfter(today))
        .length;
    final prev30Start = last30Start.subtract(const Duration(days: 30));
    final prev30Days = dates
        .where((date) =>
            !date.isBefore(prev30Start) && date.isBefore(last30Start))
        .length;
    final activeLast30 = dateCounts.keys
        .where((date) => !date.isBefore(last30Start) && !date.isAfter(today))
        .length;
    final thisMonth = dates
        .where((date) => date.year == now.year && date.month == now.month)
        .length;
    final prevMonth = DateTime(now.year, now.month - 1);
    final prevMonthToDate = dates
        .where((date) =>
            date.year == prevMonth.year &&
            date.month == prevMonth.month &&
            date.day <= now.day)
        .length;
    final thisYear = dates.where((date) => date.year == now.year).length;

    final months = <JournalStatsMonth>[];
    for (var offset = 11; offset >= 0; offset--) {
      final monthDate = DateTime(now.year, now.month - offset);
      final count = dates
          .where((date) =>
              date.year == monthDate.year && date.month == monthDate.month)
          .length;
      months.add(JournalStatsMonth(
        year: monthDate.year,
        month: monthDate.month,
        count: count,
      ));
    }

    final recentDays = List<JournalStatsDay>.generate(30, (index) {
      final date = last30Start.add(Duration(days: index));
      return JournalStatsDay(date: date, count: dateCounts[date] ?? 0);
    });

    final knownTotal = collections.fold<int>(
      0,
      (sum, collection) => sum + (collection.count ?? 0),
    );

    final longestStreakInfo = _longestStreakInfo(uniqueDates);
    final topSourceInfo = _topSource(sourceCounts);

    return JournalStatsSnapshot(
      generatedAt: now,
      journalEntries: entries.length,
      totalTrackedRecords: knownTotal,
      totalWords: totalWords,
      averageWords: entries.isEmpty ? 0 : (totalWords / entries.length).round(),
      activeDays: uniqueDates.length,
      currentStreak: _currentStreak(uniqueDates, today),
      longestStreak: longestStreakInfo.$1,
      longestStreakEnd: longestStreakInfo.$2,
      last30Days: last30Days,
      prev30Days: prev30Days,
      thisMonth: thisMonth,
      prevMonthToDate: prevMonthToDate,
      thisYear: thisYear,
      consistencyPercent: ((activeLast30 / 30) * 100).round(),
      averageMood: _coveredAverage(moodScores),
      moodScoredCount: moodScores.length,
      averageSeverity: _coveredAverage(severityScores),
      severityScoredCount: severityScores.length,
      averageWords30d: entries30d == 0 ? 0 : (words30d / entries30d).round(),
      firstEntryDate: firstDate,
      latestEntryDate: latestDate,
      busiestWeekday: _busiestWeekday(weekdayCounts),
      topSource: topSourceInfo?.$1,
      topSourceSharePercent: topSourceInfo?.$2,
      collections: collections,
      months: months,
      recentDays: recentDays,
      entriesByDay: entriesByDay,
    );
  }

  DateTime? _entryDate(Map<String, dynamic> entry) {
    final raw = entry['entry_date']?.toString().trim();
    final fallback = entry['ingested_at']?.toString().trim();
    final parsed = DateTime.tryParse(
      raw?.isNotEmpty == true ? raw! : fallback ?? '',
    );
    if (parsed == null) return null;
    final local = parsed.isUtc ? parsed.toLocal() : parsed;
    return DateTime(local.year, local.month, local.day);
  }

  int _wordCount(Map<String, dynamic> entry) {
    final stored = (entry['word_count'] as num?)?.toInt();
    if (stored != null && stored >= 0) return stored;
    final text = (entry['normalized_text'] ?? entry['text'] ?? '').toString();
    if (text.trim().isEmpty) return 0;
    return text.trim().split(RegExp(r'\s+')).length;
  }

  int _currentStreak(List<DateTime> dates, DateTime today) {
    if (dates.isEmpty) return 0;
    final unique = dates.toSet();
    var cursor = unique.contains(today)
        ? today
        : today.subtract(const Duration(days: 1));
    if (!unique.contains(cursor)) return 0;
    var count = 0;
    while (unique.contains(cursor)) {
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  /// Longest streak length plus the date the streak ended.
  (int, DateTime?) _longestStreakInfo(List<DateTime> dates) {
    if (dates.isEmpty) return (0, null);
    final unique = dates.toSet().toList()..sort();
    var longest = 1;
    var longestEnd = unique.first;
    var current = 1;
    for (var i = 1; i < unique.length; i++) {
      if (unique[i].difference(unique[i - 1]).inDays == 1) {
        current++;
        if (current > longest) {
          longest = current;
          longestEnd = unique[i];
        }
      } else {
        current = 1;
      }
    }
    return (longest, longestEnd);
  }

  /// Minimum scored entries before an average is shown. Applies identically
  /// to mood and severity so the two rows can never disagree on coverage.
  static const _minScoredEntries = 3;

  double? _coveredAverage(List<double> values) {
    if (values.length < _minScoredEntries) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Normalizes a raw mood/severity score onto a 0–1 scale. Entries written
  /// by different backend versions carry 0–1, 0–10, or 0–100 scales; without
  /// normalization the average is meaningless (this caused "318 / 100").
  double? _normalizedScore(dynamic raw) {
    final value = (raw as num?)?.toDouble();
    if (value == null || value < 0) return null;
    if (value <= 1) return value;
    if (value <= 10) return value / 10;
    if (value <= 100) return value / 100;
    return null;
  }

  String _busiestWeekday(List<int> counts) {
    if (counts.every((count) => count == 0)) return 'No data yet';
    const labels = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    var bestIndex = 0;
    for (var i = 1; i < counts.length; i++) {
      if (counts[i] > counts[bestIndex]) bestIndex = i;
    }
    return labels[bestIndex];
  }

  /// Winning source label plus its share of sourced entries, or null when
  /// nothing usable exists. Never surfaces "Unknown" as a stat value.
  (String, int)? _topSource(Map<String, int> counts) {
    if (counts.isEmpty) return null;
    final total = counts.values.reduce((a, b) => a + b);
    final winner = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return (winner.key, ((winner.value / total) * 100).round());
  }

  /// Returns null for missing/unknown sources so they never enter the tally.
  String? _sourceLabel(String? source) {
    final normalized = source?.trim().toLowerCase() ?? '';
    return switch (normalized) {
      'ios_app' => 'iPhone app',
      'siri' || 'siri_shortcut' => 'Siri',
      'sms' => 'Text message',
      'web' => 'Web',
      'shortcut' => 'Shortcut',
      '' || 'unknown' => null,
      _ => normalized
          .split('_')
          .map((part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' '),
    };
  }
}
