import 'api_service.dart';
import 'follow_up_tasks_service.dart';
import 'orbit_ledger_service.dart';

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
    required this.thisMonth,
    required this.thisYear,
    required this.consistencyPercent,
    required this.averageMood,
    required this.averageSeverity,
    required this.firstEntryDate,
    required this.latestEntryDate,
    required this.busiestWeekday,
    required this.topSource,
    required this.collections,
    required this.months,
    required this.recentDays,
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
  final int thisMonth;
  final int thisYear;
  final int consistencyPercent;
  final double? averageMood;
  final double? averageSeverity;
  final DateTime? firstEntryDate;
  final DateTime? latestEntryDate;
  final String busiestWeekday;
  final String topSource;
  final List<JournalStatsCollection> collections;
  final List<JournalStatsMonth> months;
  final List<JournalStatsDay> recentDays;
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
      return (reports.length, '${reports.length} saved case reports');
    });
    final followUpsFuture = _safeCollection(() async {
      final tasks = await FollowUpTaskService(api: _api).loadTasks();
      final comments = tasks.fold<int>(
        0,
        (sum, task) => sum + task.comments.length,
      );
      return (
        tasks.length + comments,
        '${tasks.length} follow-ups + $comments comments'
      );
    });
    final orbitFuture = _safeCollection(() async {
      final entries = await OrbitLedgerService(api: _api).loadEntries();
      return (entries.length, '${entries.length} logged requests');
    });
    final exitPlanFuture = _safeCollection(() async {
      final response = await _api.exitPlanGetNotes();
      final notes = response['notes'] as List? ?? const [];
      return (notes.length, '${notes.length} plan notes');
    });
    final storyFuture = _safeCollection(() async {
      final drafts = await _api.myStoryGetDrafts();
      return (drafts.length, '${drafts.length} saved narrative drafts');
    });
    final sageFuture = _safeCollection(() async {
      final conversations = await _api.listSavedFloatchatConversations();
      return (
        conversations.length,
        '${conversations.length} saved conversations'
      );
    });
    final evidenceFuture = _safeCollection(() async {
      final evidence = await _api.getEvidenceRecords();
      return (evidence.length, '${evidence.length} evidence records');
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
        detail: '${entries.length} timeline entries',
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
    return (total, '$total entries across ${cases.length} cases');
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
    return (total, '$total entries across ${folders.length} folders');
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
    final sourceCounts = <String, int>{};
    final weekdayCounts = List<int>.filled(7, 0);
    final moodScores = <double>[];
    final severityScores = <double>[];
    var totalWords = 0;

    for (final entry in entries) {
      final date = _entryDate(entry);
      if (date != null) {
        dateCounts[date] = (dateCounts[date] ?? 0) + 1;
        weekdayCounts[date.weekday - 1]++;
      }
      final source = _sourceLabel(entry['source']?.toString());
      sourceCounts[source] = (sourceCounts[source] ?? 0) + 1;
      totalWords += _wordCount(entry);
      final mood = (entry['mood_score'] as num?)?.toDouble();
      final severity = (entry['severity_score'] as num?)?.toDouble();
      if (mood != null) moodScores.add(mood);
      if (severity != null) severityScores.add(severity);
    }

    final uniqueDates = dateCounts.keys.toList()..sort();
    final firstDate = uniqueDates.isEmpty ? null : uniqueDates.first;
    final latestDate = uniqueDates.isEmpty ? null : uniqueDates.last;
    final last30Start = today.subtract(const Duration(days: 29));
    final last30Days = dates
        .where((date) => !date.isBefore(last30Start) && !date.isAfter(today))
        .length;
    final activeLast30 = dateCounts.keys
        .where((date) => !date.isBefore(last30Start) && !date.isAfter(today))
        .length;
    final thisMonth = dates
        .where((date) => date.year == now.year && date.month == now.month)
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

    return JournalStatsSnapshot(
      generatedAt: now,
      journalEntries: entries.length,
      totalTrackedRecords: knownTotal,
      totalWords: totalWords,
      averageWords: entries.isEmpty ? 0 : (totalWords / entries.length).round(),
      activeDays: uniqueDates.length,
      currentStreak: _currentStreak(uniqueDates, today),
      longestStreak: _longestStreak(uniqueDates),
      last30Days: last30Days,
      thisMonth: thisMonth,
      thisYear: thisYear,
      consistencyPercent: ((activeLast30 / 30) * 100).round(),
      averageMood: _average(moodScores),
      averageSeverity: _average(severityScores),
      firstEntryDate: firstDate,
      latestEntryDate: latestDate,
      busiestWeekday: _busiestWeekday(weekdayCounts),
      topSource: _topSource(sourceCounts),
      collections: collections,
      months: months,
      recentDays: recentDays,
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

  int _longestStreak(List<DateTime> dates) {
    if (dates.isEmpty) return 0;
    final unique = dates.toSet().toList()..sort();
    var longest = 1;
    var current = 1;
    for (var i = 1; i < unique.length; i++) {
      if (unique[i].difference(unique[i - 1]).inDays == 1) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 1;
      }
    }
    return longest;
  }

  double? _average(List<double> values) {
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
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

  String _topSource(Map<String, int> counts) {
    if (counts.isEmpty) return 'No data yet';
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  String _sourceLabel(String? source) {
    final normalized = source?.trim().toLowerCase() ?? '';
    return switch (normalized) {
      'ios_app' => 'iPhone app',
      'siri' || 'siri_shortcut' => 'Siri',
      'sms' => 'Text message',
      'web' => 'Web',
      'shortcut' => 'Shortcut',
      '' => 'Unknown',
      _ => normalized
          .split('_')
          .map((part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' '),
    };
  }
}
