import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'ai_response_limits.dart';
import 'follow_up_tasks_service.dart';
import 'sage_profile_service.dart';

enum SageInboxPriority { urgent, high, normal, low }

enum SageInboxStatus { unread, read, archived }

enum SageInboxReplyRole { user, assistant }

enum SageInboxTaskStatus { open, done, synced }

class SageInboxActionItem {
  const SageInboxActionItem({
    required this.label,
    this.detail,
    this.route,
    this.sagePrompt,
  });

  final String label;
  final String? detail;
  final String? route;
  final String? sagePrompt;

  Map<String, dynamic> toJson() => {
        'label': label,
        if (detail != null && detail!.trim().isNotEmpty) 'detail': detail,
        if (route != null && route!.trim().isNotEmpty) 'route': route,
        if (sagePrompt != null && sagePrompt!.trim().isNotEmpty)
          'sage_prompt': sagePrompt,
      };

  factory SageInboxActionItem.fromJson(Map<String, dynamic> json) {
    return SageInboxActionItem(
      label: json['label']?.toString() ?? '',
      detail: json['detail']?.toString(),
      route: json['route']?.toString(),
      sagePrompt: json['sage_prompt']?.toString(),
    );
  }
}

class SageInboxReply {
  const SageInboxReply({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final SageInboxReplyRole role;
  final String text;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'text': text,
        'created_at': createdAt.toIso8601String(),
      };

  factory SageInboxReply.fromJson(Map<String, dynamic> json) {
    return SageInboxReply(
      id: json['id']?.toString() ?? '',
      role: SageInboxReplyRole.values.firstWhere(
        (item) => item.name == json['role'],
        orElse: () => SageInboxReplyRole.assistant,
      ),
      text: json['text']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class SageInboxTask {
  const SageInboxTask({
    required this.id,
    required this.messageId,
    required this.title,
    required this.createdAt,
    required this.status,
    this.detail,
    this.followUpTaskId,
  });

  final String id;
  final String messageId;
  final String title;
  final String? detail;
  final DateTime createdAt;
  final SageInboxTaskStatus status;
  final String? followUpTaskId;

  bool get isDone => status == SageInboxTaskStatus.done;
  bool get isSynced => status == SageInboxTaskStatus.synced;
  bool get isOpen => status == SageInboxTaskStatus.open;

  SageInboxTask copyWith({
    SageInboxTaskStatus? status,
    String? followUpTaskId,
  }) {
    return SageInboxTask(
      id: id,
      messageId: messageId,
      title: title,
      detail: detail,
      createdAt: createdAt,
      status: status ?? this.status,
      followUpTaskId: followUpTaskId ?? this.followUpTaskId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'message_id': messageId,
        'title': title,
        if (detail != null && detail!.trim().isNotEmpty) 'detail': detail,
        'created_at': createdAt.toIso8601String(),
        'status': status.name,
        if (followUpTaskId != null && followUpTaskId!.trim().isNotEmpty)
          'follow_up_task_id': followUpTaskId,
      };

  factory SageInboxTask.fromJson(Map<String, dynamic> json) {
    return SageInboxTask(
      id: json['id']?.toString() ?? '',
      messageId: json['message_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      detail: json['detail']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      status: SageInboxTaskStatus.values.firstWhere(
        (item) => item.name == json['status'],
        orElse: () => SageInboxTaskStatus.open,
      ),
      followUpTaskId: json['follow_up_task_id']?.toString(),
    );
  }
}

class SageInboxDetail {
  const SageInboxDetail({
    required this.message,
    required this.replies,
    required this.tasks,
  });

  final SageInboxMessage message;
  final List<SageInboxReply> replies;
  final List<SageInboxTask> tasks;
}

class SageInboxDataPoint {
  const SageInboxDataPoint({
    required this.label,
    required this.value,
    this.detail,
  });

  final String label;
  final String value;
  final String? detail;

  Map<String, dynamic> toJson() => {
        'label': label,
        'value': value,
        if (detail != null && detail!.trim().isNotEmpty) 'detail': detail,
      };

  factory SageInboxDataPoint.fromJson(Map<String, dynamic> json) {
    return SageInboxDataPoint(
      label: json['label']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      detail: json['detail']?.toString(),
    );
  }
}

class SageInboxMessage {
  const SageInboxMessage({
    required this.id,
    required this.subject,
    required this.preview,
    required this.body,
    required this.createdAt,
    required this.priority,
    required this.status,
    required this.source,
    required this.reason,
    required this.actionItems,
    this.dataPoints = const [],
    this.relatedRoute,
    this.expiresAt,
  });

  final String id;
  final String subject;
  final String preview;
  final String body;
  final DateTime createdAt;
  final SageInboxPriority priority;
  final SageInboxStatus status;
  final String source;
  final String reason;
  final List<SageInboxActionItem> actionItems;
  final List<SageInboxDataPoint> dataPoints;
  final String? relatedRoute;
  final DateTime? expiresAt;

  bool get isUnread => status == SageInboxStatus.unread;
  bool get isArchived => status == SageInboxStatus.archived;

  SageInboxMessage copyWith({
    String? subject,
    String? preview,
    String? body,
    SageInboxStatus? status,
    DateTime? expiresAt,
  }) {
    return SageInboxMessage(
      id: id,
      subject: subject ?? this.subject,
      preview: preview ?? this.preview,
      body: body ?? this.body,
      createdAt: createdAt,
      priority: priority,
      status: status ?? this.status,
      source: source,
      reason: reason,
      actionItems: actionItems,
      dataPoints: dataPoints,
      relatedRoute: relatedRoute,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'preview': preview,
        'body': body,
        'created_at': createdAt.toIso8601String(),
        'priority': priority.name,
        'status': status.name,
        'source': source,
        'reason': reason,
        'action_items': actionItems.map((item) => item.toJson()).toList(),
        'data_points': dataPoints.map((item) => item.toJson()).toList(),
        if (relatedRoute != null && relatedRoute!.trim().isNotEmpty)
          'related_route': relatedRoute,
        if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      };

  factory SageInboxMessage.fromJson(Map<String, dynamic> json) {
    return SageInboxMessage(
      id: json['id']?.toString() ?? '',
      subject: json['subject']?.toString() ?? 'Sage message',
      preview: json['preview']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      priority: SageInboxPriority.values.firstWhere(
        (item) => item.name == json['priority'],
        orElse: () => SageInboxPriority.normal,
      ),
      status: SageInboxStatus.values.firstWhere(
        (item) => item.name == json['status'],
        orElse: () => SageInboxStatus.unread,
      ),
      source: json['source']?.toString() ?? 'Sage',
      reason: json['reason']?.toString() ?? 'Generated from local signals',
      actionItems: (json['action_items'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => SageInboxActionItem.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((item) => item.label.trim().isNotEmpty)
              .toList() ??
          const [],
      dataPoints: (json['data_points'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => SageInboxDataPoint.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((item) =>
                  item.label.trim().isNotEmpty && item.value.trim().isNotEmpty)
              .toList() ??
          const [],
      relatedRoute: json['related_route']?.toString(),
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
    );
  }
}

class SageInboxSnapshot {
  const SageInboxSnapshot({
    required this.messages,
    required this.generatedAt,
  });

  final List<SageInboxMessage> messages;
  final DateTime generatedAt;

  int get unreadCount => messages
      .where((message) => message.status == SageInboxStatus.unread)
      .length;

  int get activeCount =>
      messages.where((message) => !message.isArchived).length;
}

class SageInboxService {
  static const _storageKey = 'sage_inbox.messages.v1';
  static const _repliesStorageKey = 'sage_inbox.replies.v1';
  static const _tasksStorageKey = 'sage_inbox.tasks.v1';
  static const _generatedAtKey = 'sage_inbox.generated_at.v1';
  static const _welcomeId = 'sage_inbox.welcome.v1';
  static const _followUpPressureId = 'sage_inbox.followups.pressure.v1';
  static const _followUpCleanId = 'sage_inbox.followups.clean.v1';
  static const _orbitPressureId = 'sage_inbox.orbit.pressure.v1';
  static const _contextMapId = 'sage_inbox.context.map.v1';
  static const _conversationFollowUpId = 'sage_inbox.conversation_followup.v1';
  static const _dailyDispatchPrefix = 'sage_inbox.daily_dispatch.v3';
  static const _journalSupportPrefix = 'sage_inbox.journal_support';
  static const _journalSupportLastCreatedKey =
      'sage_inbox.journal_support.last_created_at.v1';

  final FollowUpTaskService _followUps;
  final SageProfileService _sageProfile;
  final ApiService _api;

  SageInboxService({
    FollowUpTaskService? followUps,
    SageProfileService? sageProfile,
    ApiService? api,
  })  : _followUps = followUps ?? FollowUpTaskService(),
        _sageProfile = sageProfile ?? SageProfileService(),
        _api = api ?? ApiService();

  Future<SageInboxSnapshot> loadInbox() async {
    final prefs = await SharedPreferences.getInstance();
    final messages = _decodeMessages(prefs.getString(_storageKey));
    if (messages.isEmpty && !prefs.containsKey(_storageKey)) {
      final seeded = [_welcomeMessage(DateTime.now())];
      await _saveMessages(seeded);
      return SageInboxSnapshot(messages: seeded, generatedAt: DateTime.now());
    }

    return SageInboxSnapshot(
      messages: _sorted(messages),
      generatedAt: DateTime.tryParse(prefs.getString(_generatedAtKey) ?? '') ??
          DateTime.now(),
    );
  }

  Future<SageInboxSnapshot> refreshAdaptiveMessages() async {
    final current = (await loadInbox()).messages;
    final now = DateTime.now();
    final retained = current
        .where((message) =>
            message.id != _followUpPressureId &&
            message.id != _followUpCleanId &&
            message.id != _orbitPressureId &&
            message.id != _contextMapId &&
            message.id != _conversationFollowUpId &&
            !_isOutdatedDailyDispatch(message.id) &&
            (message.expiresAt == null || message.expiresAt!.isAfter(now)))
        .toList();

    final dailyDispatchId =
        '$_dailyDispatchPrefix.${DateFormat('yyyyMMdd').format(now)}';
    final hasTodayDispatch =
        retained.any((message) => message.id == dailyDispatchId);

    final adaptive = <SageInboxMessage>[];
    if (!hasTodayDispatch) {
      // Compose with AI at most once per calendar day.
      final sageMemories = await _sageProfile.loadMemoryItems();
      final sageSettings = await _sageProfile.loadSettings();
      final recentJournalSignal = await _loadRecentJournalSignal();
      final dailyMessage = await _composeMessageWithSage(
        _dailyDispatchMessage(now: now),
        sageSettings: sageSettings,
        signals: _composerSignals(
          sageMemories: sageMemories,
          recentJournalSignal: recentJournalSignal,
        ),
      );
      if (dailyMessage != null) adaptive.add(dailyMessage);
    }
    final merged = _mergeById([...retained, ...adaptive]);
    await _saveMessages(merged);
    return SageInboxSnapshot(messages: _sorted(merged), generatedAt: now);
  }

  bool _isOutdatedDailyDispatch(String id) {
    return id.startsWith('sage_inbox.daily_dispatch') &&
        !id.startsWith(_dailyDispatchPrefix);
  }

  Future<SageInboxSnapshot> markRead(String id) async {
    return _updateStatus(id, SageInboxStatus.read);
  }

  Future<SageInboxSnapshot> markUnread(String id) async {
    return _updateStatus(id, SageInboxStatus.unread);
  }

  Future<SageInboxSnapshot> archive(String id) async {
    return _updateStatus(id, SageInboxStatus.archived);
  }

  Future<SageInboxSnapshot> deleteMessage(String id) async {
    final snapshot = await loadInbox();
    final messages =
        snapshot.messages.where((message) => message.id != id).toList();
    await _saveMessages(messages);

    final prefs = await SharedPreferences.getInstance();
    final rawReplies = prefs.getString(_repliesStorageKey);
    if (rawReplies != null && rawReplies.trim().isNotEmpty) {
      try {
        final replies =
            Map<String, dynamic>.from(jsonDecode(rawReplies) as Map);
        replies.remove(id);
        await prefs.setString(_repliesStorageKey, jsonEncode(replies));
      } catch (_) {}
    }

    final tasks = await _loadAllTasks();
    await _saveTasks(tasks.where((task) => task.messageId != id).toList());
    return SageInboxSnapshot(
      messages: _sorted(messages),
      generatedAt: DateTime.now(),
    );
  }

  Future<SageInboxSnapshot> markAllRead() async {
    final snapshot = await loadInbox();
    final next = snapshot.messages
        .map((message) => message.isArchived
            ? message
            : message.copyWith(status: SageInboxStatus.read))
        .toList();
    await _saveMessages(next);
    return SageInboxSnapshot(
        messages: _sorted(next), generatedAt: DateTime.now());
  }

  Future<SageInboxSnapshot?> createAdaptiveJournalCheckIn({
    required String entryText,
    int? entryId,
  }) async {
    final text = entryText.trim();
    if (text.isEmpty) return null;

    final signal = _journalSupportSignal(text);
    if (signal == null) return null;

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastCreated = DateTime.tryParse(
      prefs.getString(_journalSupportLastCreatedKey) ?? '',
    );
    if (lastCreated != null &&
        now.difference(lastCreated) < const Duration(hours: 6)) {
      return null;
    }

    final snapshot = await loadInbox();
    final message = await _composeJournalSupportMessage(
      now: now,
      signal: signal,
      entryText: text,
      entryId: entryId,
    );
    if (message == null) return null;
    final merged = _mergeById([...snapshot.messages, message]);
    await _saveMessages(merged);
    await prefs.setString(
      _journalSupportLastCreatedKey,
      now.toIso8601String(),
    );
    return SageInboxSnapshot(messages: _sorted(merged), generatedAt: now);
  }

  Future<SageInboxDetail?> loadDetail(String messageId) async {
    final snapshot = await loadInbox();
    final message =
        snapshot.messages.where((item) => item.id == messageId).firstOrNull;
    if (message == null) return null;
    return SageInboxDetail(
      message: message,
      replies: await _loadReplies(messageId),
      tasks: await _loadTasks(messageId),
    );
  }

  Future<SageInboxDetail> sendReply({
    required String messageId,
    required String text,
  }) async {
    final detail = await loadDetail(messageId);
    if (detail == null) {
      throw StateError('Inbox message not found.');
    }

    final now = DateTime.now();
    final userReply = SageInboxReply(
      id: 'reply_${now.microsecondsSinceEpoch}_user',
      role: SageInboxReplyRole.user,
      text: text.trim(),
      createdAt: now,
    );
    await _appendReply(messageId, userReply);

    final response = await _api.sendFloatchatMessage(
      messages: _messagesForSage(detail.message, [
        ...detail.replies,
        userReply,
      ]),
      contextString: _contextForInboxMessage(detail.message),
      maxTokens: AiResponseLimits.sageReplyMaxTokens,
    );
    final replyText = response['reply']?.toString().trim();
    final assistantReply = SageInboxReply(
      id: 'reply_${DateTime.now().microsecondsSinceEpoch}_sage',
      role: SageInboxReplyRole.assistant,
      text: replyText == null || replyText.isEmpty
          ? 'I got that. Open Sage if you want the deeper version.'
          : replyText,
      createdAt: DateTime.now(),
    );
    await _appendReply(messageId, assistantReply);
    final next = await loadDetail(messageId);
    return next!;
  }

  Future<SageInboxDetail> createTask({
    required String messageId,
    required String title,
    String? detail,
  }) async {
    final now = DateTime.now();
    final task = SageInboxTask(
      id: 'inbox_task_${now.microsecondsSinceEpoch}',
      messageId: messageId,
      title: title.trim(),
      detail: detail?.trim(),
      createdAt: now,
      status: SageInboxTaskStatus.open,
    );
    final tasks = await _loadAllTasks();
    await _saveTasks([...tasks, task]);
    final next = await loadDetail(messageId);
    return next!;
  }

  Future<SageInboxDetail> toggleTaskDone(SageInboxTask task) async {
    final tasks = await _loadAllTasks();
    final nextStatus =
        task.isDone ? SageInboxTaskStatus.open : SageInboxTaskStatus.done;
    final next = tasks
        .map((item) =>
            item.id == task.id ? item.copyWith(status: nextStatus) : item)
        .toList();
    await _saveTasks(next);
    final detail = await loadDetail(task.messageId);
    return detail!;
  }

  Future<SageInboxDetail> syncTaskToFollowUps(SageInboxTask task) async {
    final followUps = await _followUps.loadTasks();
    final now = DateTime.now();
    final followUpTask = FollowUpTask(
      id: 'sage_inbox_${task.id}',
      title: task.title,
      bucket: 'admin',
      status: 'active',
      priority: 'normal',
      createdAt: now,
      lastTouchedAt: now,
      counterparty: 'Sage Inbox',
      nextAction: task.detail,
      notes: 'Created from Sage Inbox message ${task.messageId}.',
    );
    await _followUps.saveTasks([...followUps, followUpTask]);

    final tasks = await _loadAllTasks();
    final next = tasks
        .map((item) => item.id == task.id
            ? item.copyWith(
                status: SageInboxTaskStatus.synced,
                followUpTaskId: followUpTask.id,
              )
            : item)
        .toList();
    await _saveTasks(next);
    final detail = await loadDetail(task.messageId);
    return detail!;
  }

  Future<SageInboxSnapshot> _updateStatus(
    String id,
    SageInboxStatus status,
  ) async {
    final snapshot = await loadInbox();
    final next = snapshot.messages
        .map((message) =>
            message.id == id ? message.copyWith(status: status) : message)
        .toList();
    await _saveMessages(next);
    return SageInboxSnapshot(
        messages: _sorted(next), generatedAt: DateTime.now());
  }

  Future<void> _saveMessages(List<SageInboxMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_sorted(messages).map((message) => message.toJson()).toList()),
    );
    await prefs.setString(_generatedAtKey, DateTime.now().toIso8601String());
  }

  Future<List<SageInboxReply>> _loadReplies(String messageId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_repliesStorageKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as Map;
      final items = decoded[messageId] as List?;
      return (items ?? const [])
          .whereType<Map>()
          .map(
            (item) => SageInboxReply.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) => item.id.trim().isNotEmpty && item.text.isNotEmpty)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _appendReply(String messageId, SageInboxReply reply) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_repliesStorageKey);
    final byMessage = <String, dynamic>{};
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        byMessage.addAll(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {
        byMessage.clear();
      }
    }
    final existing = (byMessage[messageId] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        <Map<String, dynamic>>[];
    existing.add(reply.toJson());
    byMessage[messageId] = existing;
    await prefs.setString(_repliesStorageKey, jsonEncode(byMessage));
  }

  Future<List<SageInboxTask>> _loadTasks(String messageId) async {
    final tasks = await _loadAllTasks();
    return tasks.where((task) => task.messageId == messageId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<SageInboxTask>> _loadAllTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tasksStorageKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map(
            (item) => SageInboxTask.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) =>
              item.id.trim().isNotEmpty &&
              item.messageId.trim().isNotEmpty &&
              item.title.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveTasks(List<SageInboxTask> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = List<SageInboxTask>.from(tasks)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await prefs.setString(
      _tasksStorageKey,
      jsonEncode(sorted.map((task) => task.toJson()).toList()),
    );
  }

  List<Map<String, dynamic>> _messagesForSage(
    SageInboxMessage message,
    List<SageInboxReply> replies,
  ) {
    final context = _contextForInboxMessage(message);
    final thread = replies.take(12).map((reply) {
      return {
        'role': reply.role == SageInboxReplyRole.user ? 'user' : 'assistant',
        'content': reply.text,
      };
    }).toList();
    return [
      {
        'role': 'system',
        'content':
            'You are Sage replying inside the Sage Inbox, like answering an email from someone you know well. Be concise, personal, and tied to the thread. Talk about his life like a person, not a productivity system: never bring up task counts, overdue items, or follow-up lists unless William brings them up first. If he asks a question, answer directly.',
      },
      {
        'role': 'assistant',
        'content': context,
      },
      ...thread,
    ];
  }

  String _contextForInboxMessage(SageInboxMessage message) {
    final dataPoints = message.dataPoints
        .map((item) =>
            '- ${item.label}: ${item.value}${item.detail == null ? '' : ' (${item.detail})'}')
        .join('\n');
    final actions = message.actionItems
        .map((item) =>
            '- ${item.label}${item.detail == null ? '' : ': ${item.detail}'}')
        .join('\n');
    return [
      'Sage Inbox message:',
      'Subject: ${message.subject}',
      'Preview: ${message.preview}',
      'Full message: ${message.body}',
      'Why sent: ${message.reason}',
      if (dataPoints.trim().isNotEmpty) 'Data points:\n$dataPoints',
      if (actions.trim().isNotEmpty) 'Useful next moves:\n$actions',
    ].join('\n\n');
  }

  List<SageInboxMessage> _decodeMessages(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map(
            (item) => SageInboxMessage.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((message) =>
              message.id.trim().isNotEmpty &&
              message.subject.trim().isNotEmpty &&
              message.body.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<SageInboxMessage> _mergeById(List<SageInboxMessage> messages) {
    final byId = <String, SageInboxMessage>{};
    for (final message in messages) {
      final previous = byId[message.id];
      byId[message.id] = previous == null
          ? message
          : message.copyWith(status: previous.status);
    }
    return byId.values.toList();
  }

  List<SageInboxMessage> _sorted(List<SageInboxMessage> messages) {
    final sorted = List<SageInboxMessage>.from(messages);
    sorted.sort((a, b) {
      final unreadCompare = (b.isUnread ? 1 : 0).compareTo(a.isUnread ? 1 : 0);
      if (unreadCompare != 0) return unreadCompare;
      final priorityCompare = _priorityRank(a.priority).compareTo(
        _priorityRank(b.priority),
      );
      if (priorityCompare != 0) return priorityCompare;
      return b.createdAt.compareTo(a.createdAt);
    });
    return sorted;
  }

  int _priorityRank(SageInboxPriority priority) {
    return switch (priority) {
      SageInboxPriority.urgent => 0,
      SageInboxPriority.high => 1,
      SageInboxPriority.normal => 2,
      SageInboxPriority.low => 3,
    };
  }

  SageInboxMessage _welcomeMessage(DateTime now) {
    return SageInboxMessage(
      id: _welcomeId,
      subject: 'Your Sage Inbox is live',
      preview: 'This becomes the place Sage can leave full messages for you.',
      body:
          'This is the new message layer: subject, full note, why it exists, and action items. The cheap version runs from local signals first, so you can get useful prompts without asking the model to reread your life every time.\n\nWhen the backend phase is added, server-side Sage can drop richer messages into this same inbox and push you only when something is worth interrupting you.',
      createdAt: now,
      priority: SageInboxPriority.normal,
      status: SageInboxStatus.unread,
      source: 'Sage',
      reason: 'First-run inbox setup',
      relatedRoute: '/sage',
      actionItems: const [
        SageInboxActionItem(
          label: 'Check this inbox when a notification lands',
          detail: 'Treat it like mail from Sage, not a chat thread.',
          route: '/inbox',
        ),
        SageInboxActionItem(
          label: 'Open a Sage strategy thread',
          detail: 'Inbox should summarize and route; chat should think deeply.',
          route: '/sage',
          sagePrompt:
              'Walk me through how to use Sage Inbox as my action layer without turning it into another place I avoid.',
        ),
      ],
      dataPoints: const [
        SageInboxDataPoint(
          label: 'Message type',
          value: 'System setup',
          detail: 'No AI generation was used for this welcome note.',
        ),
      ],
    );
  }

  SageInboxMessage _dailyDispatchMessage({required DateTime now}) {
    final dateId = DateFormat('yyyyMMdd').format(now);
    return SageInboxMessage(
      id: '$_dailyDispatchPrefix.$dateId',
      subject: 'A note from Sage',
      preview: 'A personal message from Sage.',
      body: 'Pending Sage response.',
      createdAt: now,
      priority: SageInboxPriority.normal,
      status: SageInboxStatus.unread,
      source: 'Sage daily note',
      reason: 'Daily note from Sage.',
      relatedRoute: '/inbox',
      expiresAt: now.add(const Duration(days: 7)),
      actionItems: const [
        SageInboxActionItem(
          label: 'Reply to Sage',
          detail: 'Answer here like you would answer a real message.',
          route: '/inbox',
        ),
      ],
      dataPoints: const [],
    );
  }

  Future<SageInboxMessage?> _composeMessageWithSage(
    SageInboxMessage message, {
    required SageSettings sageSettings,
    String signals = '',
  }) async {
    try {
      final contextString = await _api.getFloatchatContext();
      final response = await _api.sendFloatchatMessage(
        messages: [
          {
            'role': 'system',
            'content': [
              "You are Sage writing a short personal note into William's inbox, like a letter from someone who knows him.",
              'Write directly about his life and the specific human thread that matters today.',
              'Pick the single strongest human thread from the signals — a person, a feeling, a journal line — name it specifically, and give your actual read on it. Ignore everything else.',
              'Plain conversational first person. Make the message substantive and natural, with no headers or bullets.',
              'Do not mention writing style, formatting, productivity, dashboards, metrics, tasks, lists, what you are avoiding, or what kind of message this is. Do not announce your approach. Just write the message.',
              'Return strict JSON only with keys subject, preview, body. Subject under 62 chars. Preview under 170 chars. Body 70-160 words. End with one natural question or invitation to reply.',
              sageSettings.toPromptInstruction(),
            ].join('\n'),
          },
          {
            'role': 'user',
            'content': _composerPrompt(message, signals),
          },
        ],
        contextString: contextString,
        maxTokens: 350,
      );
      final composed = _decodeComposedMessage(response['reply']?.toString());
      if (composed == null) return null;
      return message.copyWith(
        subject: composed.$1,
        preview: composed.$2,
        body: composed.$3,
      );
    } catch (_) {
      return null;
    }
  }

  String _composerPrompt(SageInboxMessage message, String signals) {
    return [
      'Note type: ${message.source}',
      'Why it exists: ${message.reason}',
      if (signals.trim().isNotEmpty)
        "Today's signals:\n$signals"
      else
        'No recent journal signal is available. Use the durable context to ask or say something genuinely relevant to William today.',
      "Write today's message. Anchor it in one specific detail when available, vary the opener and rhythm day to day, and spend the full body talking to William rather than explaining the message.",
    ].join('\n\n');
  }

  String _composerSignals({
    required List<SageMemoryItem> sageMemories,
    required String? recentJournalSignal,
  }) {
    final memoryLines =
        sageMemories.take(3).map((item) => '- ${item.text}').join('\n');
    return [
      if (recentJournalSignal != null)
        'Latest journal entry (excerpt): $recentJournalSignal',
      if (memoryLines.isNotEmpty) 'Durable notes about William:\n$memoryLines',
    ].join('\n\n');
  }

  (String, String, String)? _decodeComposedMessage(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final trimmed = raw.trim();
    final jsonStart = trimmed.indexOf('{');
    final jsonEnd = trimmed.lastIndexOf('}');
    if (jsonStart < 0 || jsonEnd <= jsonStart) return null;
    try {
      final decoded = jsonDecode(trimmed.substring(jsonStart, jsonEnd + 1));
      if (decoded is! Map) return null;
      final subject = decoded['subject']?.toString().trim();
      final preview = decoded['preview']?.toString().trim();
      final body = decoded['body']?.toString().trim();
      if (subject == null ||
          subject.isEmpty ||
          preview == null ||
          preview.isEmpty ||
          body == null ||
          body.isEmpty) {
        return null;
      }
      return (
        _collapseWhitespace(subject, maxChars: 90),
        _collapseWhitespace(preview, maxChars: 220),
        body,
      );
    } catch (_) {
      return null;
    }
  }

  String _collapseWhitespace(String value, {required int maxChars}) {
    final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= maxChars) return collapsed;
    return '${collapsed.substring(0, maxChars - 3)}...';
  }

  Future<String?> _loadRecentJournalSignal() async {
    try {
      final page = await _api.getTimelinePage(page: 1, limit: 1);
      if (page.entries.isEmpty) return null;
      final entry = page.entries.first;
      final raw = (entry['summary_text'] ??
              entry['normalized_text'] ??
              entry['text'] ??
              '')
          .toString()
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ');
      if (raw.isEmpty) return null;
      return raw.length <= 180 ? raw : '${raw.substring(0, 180)}...';
    } catch (_) {
      return null;
    }
  }

  ({String label, String reason, SageInboxPriority priority})?
      _journalSupportSignal(String text) {
    final lower = text.toLowerCase();
    final crisis = RegExp(
      r"\b(kill myself|suicide|suicidal|end it all|can't go on|cannot go on|hurt myself|self harm|self-harm)\b",
    );
    if (crisis.hasMatch(lower)) {
      return (
        label: 'Safety language',
        reason:
            'Your journal entry used language that can mean immediate risk.',
        priority: SageInboxPriority.urgent,
      );
    }

    final heavySignals = <RegExp>[
      RegExp(r"\b(i need someone|need someone to talk|can someone talk)\b"),
      RegExp(r"\b(i'm not okay|i am not okay|not doing okay)\b"),
      RegExp(r"\b(breaking down|breakdown|spiraling|panic attack)\b"),
      RegExp(r"\b(i feel alone|i'm alone|so alone|completely alone)\b"),
      RegExp(r"\b(can't handle this|cannot handle this|too much)\b"),
      RegExp(r"\b(i'm scared|i am scared|terrified)\b"),
    ];
    if (heavySignals.any((pattern) => pattern.hasMatch(lower))) {
      return (
        label: 'Needs connection',
        reason:
            'Your journal entry sounded like you might need a real-time check-in.',
        priority: SageInboxPriority.high,
      );
    }

    final emotionalCount = <RegExp>[
      RegExp(r"\b(crying|cried|tears|shaking|panic|anxious|anxiety)\b"),
      RegExp(r"\b(overwhelmed|exhausted|hopeless|numb|lonely)\b"),
      RegExp(r"\b(afraid|scared|unsafe|trapped|stuck)\b"),
      RegExp(r"\b(please help|help me|need help)\b"),
    ].where((pattern) => pattern.hasMatch(lower)).length;

    if (emotionalCount >= 2) {
      return (
        label: 'Heavy emotional load',
        reason: 'Multiple distress signals showed up in one journal entry.',
        priority: SageInboxPriority.high,
      );
    }

    return null;
  }

  Future<SageInboxMessage?> _composeJournalSupportMessage({
    required DateTime now,
    required ({String label, String reason, SageInboxPriority priority}) signal,
    required String entryText,
    required int? entryId,
  }) async {
    try {
      final settings = await _sageProfile.loadSettings();
      final contextString = await _api.getFloatchatContext();
      final isUrgent = signal.priority == SageInboxPriority.urgent;
      final response = await _api.sendFloatchatMessage(
        messages: [
          {
            'role': 'system',
            'content': [
              "You are Sage sending William a private inbox message in direct response to the journal entry he just saved.",
              'Actually respond to what he said. Refer naturally to the specific person, event, fear, or sentence that matters. Give your honest read instead of announcing that you detected emotions.',
              'Sound like one person writing to another person who knows him well. Use natural uneven conversational rhythm. Do not use headings, bullets, numbered advice, a three-part structure, therapy-script language, motivational filler, or repeated reassurance.',
              'Do not say "I noticed your entry," "the shape of that entry," "it sounds like," "what I am hearing," "no performance," or "the part that feels loudest." Do not explain that you are an AI or describe the inbox feature.',
              'The body should be a genuine reply, not a summary of his writing. Ask a question only when it is the question you would naturally ask next.',
              if (isUrgent)
                'The entry contains possible self-harm or suicide language. Be warm and direct, ask whether he is in immediate danger, and urge immediate contact with emergency services or a trusted nearby person when appropriate. Do not bury safety guidance in polished prose.',
              'Return strict JSON only with keys subject, preview, body. The subject must feel like a real email subject, the preview must be one natural sentence, and the body must be 60-180 words of plain prose.',
              settings.toPromptInstruction(),
            ].join('\n'),
          },
          {
            'role': 'user',
            'content': 'Journal entry:\n\n$entryText',
          },
        ],
        contextString: contextString,
        maxTokens: 500,
      );
      final composed = _decodeComposedMessage(response['reply']?.toString());
      if (composed == null) return null;
      return SageInboxMessage(
        id: '$_journalSupportPrefix.${entryId ?? now.microsecondsSinceEpoch}.${DateFormat('yyyyMMddHH').format(now)}',
        subject: composed.$1,
        preview: composed.$2,
        body: composed.$3,
        createdAt: now,
        priority: signal.priority,
        status: SageInboxStatus.unread,
        source: 'Sage',
        reason: signal.reason,
        relatedRoute: '/inbox',
        expiresAt: now.add(const Duration(days: 3)),
        actionItems: const [
          SageInboxActionItem(
            label: 'Reply',
            route: '/inbox',
          ),
        ],
        dataPoints: const [],
      );
    } catch (_) {
      return null;
    }
  }
}
