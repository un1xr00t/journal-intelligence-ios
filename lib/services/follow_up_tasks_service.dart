import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime _startOfDay(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

String? _normalizedText(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

class FollowUpTask {
  const FollowUpTask({
    required this.id,
    required this.title,
    required this.bucket,
    required this.status,
    required this.priority,
    required this.createdAt,
    required this.lastTouchedAt,
    this.counterparty,
    this.nextAction,
    this.notes,
    this.followUpAt,
    this.followUpTimeSet = false,
    this.completedAt,
  });

  final String id;
  final String title;
  final String bucket;
  final String status;
  final String priority;
  final DateTime createdAt;
  final DateTime lastTouchedAt;
  final String? counterparty;
  final String? nextAction;
  final String? notes;
  final DateTime? followUpAt;
  final bool followUpTimeSet;
  final DateTime? completedAt;

  bool get isDone => status == 'done';
  bool get isArchived => status == 'archived';
  bool get isWaiting => status == 'waiting';
  bool get isActive => status == 'active';
  bool get isOpen => !isDone && !isArchived;

  DateTime? get effectiveFollowUpAt {
    final followUp = followUpAt;
    if (followUp == null) return null;
    if (followUpTimeSet) return followUp;
    return _defaultReminderDateTime(followUp, priority);
  }

  bool isOverdue([DateTime? now]) {
    final followUp = effectiveFollowUpAt;
    if (!isOpen || followUp == null) return false;
    final current = now ?? DateTime.now();
    return followUp.isBefore(current);
  }

  bool isDueSoon([DateTime? now, int withinDays = 3]) {
    final followUp = effectiveFollowUpAt;
    if (!isOpen || followUp == null) return false;
    final current = now ?? DateTime.now();
    if (followUp.isBefore(current)) return false;
    return !followUp.isAfter(current.add(Duration(days: withinDays)));
  }

  FollowUpTask copyWith({
    String? id,
    String? title,
    String? bucket,
    String? status,
    String? priority,
    DateTime? createdAt,
    DateTime? lastTouchedAt,
    String? counterparty,
    String? nextAction,
    String? notes,
    DateTime? followUpAt,
    bool clearFollowUpAt = false,
    bool? followUpTimeSet,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return FollowUpTask(
      id: id ?? this.id,
      title: title ?? this.title,
      bucket: bucket ?? this.bucket,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      createdAt: createdAt ?? this.createdAt,
      lastTouchedAt: lastTouchedAt ?? this.lastTouchedAt,
      counterparty: counterparty ?? this.counterparty,
      nextAction: nextAction ?? this.nextAction,
      notes: notes ?? this.notes,
      followUpAt: clearFollowUpAt ? null : (followUpAt ?? this.followUpAt),
      followUpTimeSet: followUpTimeSet ?? this.followUpTimeSet,
      completedAt:
          clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'bucket': bucket,
        'status': status,
        'priority': priority,
        'created_at': createdAt.toIso8601String(),
        'last_touched_at': lastTouchedAt.toIso8601String(),
        'counterparty': counterparty,
        'next_action': nextAction,
        'notes': notes,
        'follow_up_at': followUpAt?.toIso8601String(),
        'follow_up_time_set': followUpTimeSet,
        'completed_at': completedAt?.toIso8601String(),
      };

  factory FollowUpTask.fromJson(Map<String, dynamic> json) {
    return FollowUpTask(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      bucket: json['bucket']?.toString() ?? 'job_application',
      status: json['status']?.toString() ?? 'active',
      priority: json['priority']?.toString() ?? 'normal',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      lastTouchedAt:
          DateTime.tryParse(json['last_touched_at']?.toString() ?? '') ??
              DateTime.now(),
      counterparty: _normalizedText(json['counterparty']),
      nextAction: _normalizedText(json['next_action']),
      notes: _normalizedText(json['notes']),
      followUpAt: DateTime.tryParse(json['follow_up_at']?.toString() ?? ''),
      followUpTimeSet: (json['follow_up_time_set'] as bool?) ??
          _hasMeaningfulTime(
            DateTime.tryParse(json['follow_up_at']?.toString() ?? ''),
          ),
      completedAt: DateTime.tryParse(json['completed_at']?.toString() ?? ''),
    );
  }
}

class FollowUpTaskService {
  static const _storageKey = 'follow_up_tasks.v1';

  Future<List<FollowUpTask>> loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];

    final tasks = decoded
        .whereType<Map>()
        .map((item) => FollowUpTask.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.title.trim().isNotEmpty)
        .toList();
    tasks.sort(compareTasks);
    return tasks;
  }

  Future<void> saveTasks(List<FollowUpTask> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = List<FollowUpTask>.from(tasks)..sort(compareTasks);
    await prefs.setString(
      _storageKey,
      jsonEncode(sorted.map((task) => task.toJson()).toList()),
    );
  }

  String buildSageContext(List<FollowUpTask> tasks) {
    if (tasks.isEmpty) return '';

    final now = DateTime.now();
    final open = tasks.where((task) => task.isOpen).toList();
    final overdue = open.where((task) => task.isOverdue(now)).toList();
    final dueSoon = open.where((task) => task.isDueSoon(now)).toList();
    final waiting = open.where((task) => task.isWaiting).toList();
    final active = open.where((task) => task.isActive).toList();
    final recentDone = tasks.where((task) => task.isDone).take(3).toList();
    final topLines = open.take(8).map((task) => _sageTaskLine(task)).join('\n');

    final lines = <String>[
      '[FOLLOW-UPS]',
      'This list is separate from Exit Plan. Use it for active pipelines, callbacks, job applications, waiting threads, and practical follow-up pressure.',
      'Open items: ${open.length}',
      'Overdue follow-ups: ${overdue.length}',
      'Due within 3 days: ${dueSoon.length}',
      'Waiting on someone else: ${waiting.length}',
      'Needs direct action: ${active.length}',
      if (topLines.isNotEmpty) 'Priority items:\n$topLines',
    ];

    if (recentDone.isNotEmpty) {
      lines.add(
        'Recently completed:\n${recentDone.map((task) => _sageTaskLine(task)).join('\n')}',
      );
    }

    return '${lines.join('\n')}\n';
  }

  String buildClipboardSummary(List<FollowUpTask> tasks) {
    if (tasks.isEmpty) {
      return 'Follow-Ups\nNo tasks logged yet.';
    }

    final open = tasks.where((task) => task.isOpen).toList();
    final overdue = open.where((task) => task.isOverdue()).toList();
    final dueSoon = open.where((task) => task.isDueSoon()).toList();

    return [
      'Follow-Ups',
      'Separate from Exit Plan. Use for living follow-up pressure and response tracking.',
      'Open items: ${open.length}',
      'Overdue: ${overdue.length}',
      'Due soon: ${dueSoon.length}',
      if (open.isNotEmpty)
        'Most urgent:\n${open.take(8).map(formatTaskSummary).join('\n')}',
    ].join('\n');
  }

  FollowUpTaskSummary summarize(List<FollowUpTask> tasks) {
    final open = tasks.where((task) => task.isOpen).toList();
    final overdue = open.where((task) => task.isOverdue()).toList();
    final dueSoon = open.where((task) => task.isDueSoon()).toList();
    final waiting = open.where((task) => task.isWaiting).toList();
    final staleWaiting = waiting.where((task) {
      final cutoff = DateTime.now().subtract(const Duration(days: 6));
      return task.lastTouchedAt.isBefore(cutoff);
    }).toList();

    return FollowUpTaskSummary(
      openCount: open.length,
      overdueCount: overdue.length,
      dueSoonCount: dueSoon.length,
      waitingCount: waiting.length,
      nextTask: open.isEmpty ? null : open.first,
      overdueTasks: overdue,
      dueSoonTasks: dueSoon,
      staleWaitingTasks: staleWaiting,
    );
  }

  static int compareTasks(FollowUpTask a, FollowUpTask b) {
    final scoreA = _sortScore(a);
    final scoreB = _sortScore(b);
    if (scoreA != scoreB) return scoreA.compareTo(scoreB);

    final priorityCompare = _priorityRank(a.priority).compareTo(
      _priorityRank(b.priority),
    );
    if (priorityCompare != 0) return priorityCompare;

    final followA = a.effectiveFollowUpAt;
    final followB = b.effectiveFollowUpAt;
    if (followA != null && followB != null) {
      final compareFollow = followA.compareTo(followB);
      if (compareFollow != 0) return compareFollow;
    } else if (followA != null) {
      return -1;
    } else if (followB != null) {
      return 1;
    }

    return b.lastTouchedAt.compareTo(a.lastTouchedAt);
  }

  static int _sortScore(FollowUpTask task) {
    if (task.isOverdue()) return 0;
    if (task.isDueSoon()) return 1;
    if (task.isActive) return 2;
    if (task.isWaiting) return 3;
    if (task.isDone) return 4;
    return 5;
  }

  static String formatTaskSummary(FollowUpTask task) {
    final date = DateFormat('MMM d');
    final pieces = <String>[
      '- ${task.title}',
      if ((task.counterparty ?? '').trim().isNotEmpty)
        '@ ${task.counterparty!.trim()}',
      '[${bucketLabel(task.bucket)} | ${statusLabel(task.status)} | ${priorityLabel(task.priority)}]',
      if (task.effectiveFollowUpAt != null)
        'follow up ${date.format(task.effectiveFollowUpAt!)}',
      if ((task.nextAction ?? '').trim().isNotEmpty)
        'next: ${task.nextAction!.trim()}',
    ];
    return pieces.join(' ');
  }

  static String _sageTaskLine(FollowUpTask task) {
    final date = DateFormat('MMM d, yyyy');
    final bits = <String>[
      '- ${task.title}',
      if ((task.counterparty ?? '').trim().isNotEmpty)
        '@ ${task.counterparty!.trim()}',
      '| ${bucketLabel(task.bucket)}',
      '| ${statusLabel(task.status)}',
      '| ${priorityLabel(task.priority)} priority',
      if (task.effectiveFollowUpAt != null)
        '| follow up ${date.format(task.effectiveFollowUpAt!)}',
      '| last touched ${date.format(task.lastTouchedAt)}',
      if ((task.nextAction ?? '').trim().isNotEmpty)
        '| next ${task.nextAction!.trim()}',
    ];
    return bits.join(' ');
  }

  static String bucketLabel(String bucket) {
    switch (bucket) {
      case 'job_application':
        return 'Job application';
      case 'recruiter':
        return 'Recruiter';
      case 'networking':
        return 'Networking';
      case 'interview':
        return 'Interview';
      case 'admin':
        return 'Admin';
      default:
        return 'Personal';
    }
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'waiting':
        return 'Waiting';
      case 'done':
        return 'Done';
      case 'archived':
        return 'Archived';
      default:
        return 'Active';
    }
  }

  static String priorityLabel(String priority) {
    switch (priority) {
      case 'urgent':
        return 'Urgent';
      case 'high':
        return 'High';
      case 'low':
        return 'Low';
      default:
        return 'Normal';
    }
  }

  static int _priorityRank(String priority) {
    switch (priority) {
      case 'urgent':
        return 0;
      case 'high':
        return 1;
      case 'normal':
        return 2;
      default:
        return 3;
    }
  }
}

class FollowUpTaskSummary {
  const FollowUpTaskSummary({
    required this.openCount,
    required this.overdueCount,
    required this.dueSoonCount,
    required this.waitingCount,
    required this.nextTask,
    required this.overdueTasks,
    required this.dueSoonTasks,
    required this.staleWaitingTasks,
  });

  final int openCount;
  final int overdueCount;
  final int dueSoonCount;
  final int waitingCount;
  final FollowUpTask? nextTask;
  final List<FollowUpTask> overdueTasks;
  final List<FollowUpTask> dueSoonTasks;
  final List<FollowUpTask> staleWaitingTasks;

  bool get hasPressure =>
      overdueCount > 0 || dueSoonCount > 0 || waitingCount > 0;
}

bool _hasMeaningfulTime(DateTime? date) {
  if (date == null) return false;
  return date.hour != 0 || date.minute != 0;
}

DateTime _defaultReminderDateTime(DateTime date, String priority) {
  final day = _startOfDay(date);
  final (hour, minute) = switch (priority) {
    'urgent' => (8, 30),
    'high' => (10, 0),
    'low' => (18, 0),
    _ => (13, 0),
  };
  return DateTime(day.year, day.month, day.day, hour, minute);
}
