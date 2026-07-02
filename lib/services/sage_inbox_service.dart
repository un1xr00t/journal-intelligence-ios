import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'ai_response_limits.dart';
import 'follow_up_tasks_service.dart';
import 'identity_memory_service.dart';
import 'orbit_ledger_service.dart';
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
  static const _dailyDispatchPrefix = 'sage_inbox.daily_dispatch';

  final FollowUpTaskService _followUps;
  final OrbitLedgerService _orbitLedger;
  final IdentityMemoryService _identityMemory;
  final SageProfileService _sageProfile;
  final ApiService _api;

  SageInboxService({
    FollowUpTaskService? followUps,
    OrbitLedgerService? orbitLedger,
    IdentityMemoryService? identityMemory,
    SageProfileService? sageProfile,
    ApiService? api,
  })  : _followUps = followUps ?? FollowUpTaskService(),
        _orbitLedger = orbitLedger ?? OrbitLedgerService(),
        _identityMemory = identityMemory ?? IdentityMemoryService(),
        _sageProfile = sageProfile ?? SageProfileService(),
        _api = api ?? ApiService();

  Future<SageInboxSnapshot> loadInbox() async {
    final prefs = await SharedPreferences.getInstance();
    final messages = _decodeMessages(prefs.getString(_storageKey));
    if (messages.isEmpty) {
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
            (message.expiresAt == null || message.expiresAt!.isAfter(now)))
        .toList();

    final tasks = await _followUps.loadTasks();
    final summary = _followUps.summarize(tasks);
    final orbitEntries = await _orbitLedger.loadEntries();
    final identityEntities = await _identityMemory.loadEntities();
    final sageMemories = await _sageProfile.loadMemoryItems();
    final sageSettings = await _sageProfile.loadSettings();
    final recentJournalSignal = await _loadRecentJournalSignal();
    final adaptive = <SageInboxMessage>[];
    adaptive.add(
      await _composeMessageWithSage(
        _dailyDispatchMessage(
          now: now,
          followUpSummary: summary,
          orbitEntries: orbitEntries,
          identityCount: identityEntities.length,
          sageMemoryCount: sageMemories.length,
          sageSettings: sageSettings,
          recentJournalSignal: recentJournalSignal,
        ),
        sageSettings: sageSettings,
      ),
    );
    final followUpMessage = await _conversationFollowUpMessage(current, now);
    if (followUpMessage != null) {
      adaptive.add(
        await _composeMessageWithSage(
          followUpMessage,
          sageSettings: sageSettings,
        ),
      );
    }
    if (summary.overdueCount > 0 ||
        summary.dueSoonCount > 0 ||
        summary.staleWaitingTasks.isNotEmpty) {
      adaptive.add(_followUpPressureMessage(summary, now));
    } else if (summary.openCount == 0 && tasks.isNotEmpty) {
      adaptive.add(_followUpCleanMessage(now));
    }
    final orbitMessage = _orbitPressureMessage(orbitEntries, now);
    if (orbitMessage != null) adaptive.add(orbitMessage);
    adaptive.add(
      _contextMapMessage(
        now: now,
        followUpSummary: summary,
        orbitEntries: orbitEntries,
        identityCount: identityEntities.length,
        sageMemoryCount: sageMemories.length,
        sageSettings: sageSettings,
        recentJournalSignal: recentJournalSignal,
      ),
    );

    final merged = _mergeById([...retained, ...adaptive]);
    await _saveMessages(merged);
    return SageInboxSnapshot(messages: _sorted(merged), generatedAt: now);
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
            'You are Sage replying inside the Sage Inbox. Be concise, personal, practical, and tied to the inbox message. If the user says they completed something, acknowledge it and suggest the next clean move. If they ask a question, answer directly.',
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

  SageInboxMessage _followUpPressureMessage(
    FollowUpTaskSummary summary,
    DateTime now,
  ) {
    final task = summary.nextTask;
    final subject = FollowUpTaskService.pressureHeadline(summary);
    final body = [
      FollowUpTaskService.pressureBody(summary),
      '',
      if (summary.overdueCount > 0)
        'Overdue: ${summary.overdueCount}. That is the part Sage should be louder about.',
      if (summary.dueSoonCount > 0)
        'Due soon: ${summary.dueSoonCount}. This is where handling it early saves stress.',
      if (summary.staleWaitingTasks.isNotEmpty)
        'Stale waiting threads: ${summary.staleWaitingTasks.length}. Decide whether to ping, park, or close them.',
      '',
      'I’m bringing this up because silence turns overdue tasks into background dread. Pick one concrete move and make it smaller than your brain is making it.',
    ].where((line) => line.trim().isNotEmpty || line.isEmpty).join('\n');

    return SageInboxMessage(
      id: _followUpPressureId,
      subject: subject,
      preview: task == null
          ? 'Open Follow-Ups and choose the first real move.'
          : FollowUpTaskService.pressureBody(summary),
      body: body,
      createdAt: now,
      priority: summary.overdueCount > 0
          ? SageInboxPriority.urgent
          : SageInboxPriority.high,
      status: SageInboxStatus.unread,
      source: 'Sage local signal',
      reason: 'Follow-Ups has overdue, due-soon, or stale waiting pressure.',
      relatedRoute: '/follow-ups',
      expiresAt: now.add(const Duration(hours: 18)),
      actionItems: [
        SageInboxActionItem(
          label: task == null ? 'Open Follow-Ups' : task.title,
          detail: task?.nextAction?.trim().isNotEmpty == true
              ? task!.nextAction
              : 'Pick one concrete next move and do not leave it abstract.',
          route: '/follow-ups',
        ),
        SageInboxActionItem(
          label: 'Open a Sage strategy thread',
          detail:
              'Use chat only if you need strategy, wording, or prioritizing.',
          route: '/sage',
          sagePrompt: task == null
              ? 'Use my Follow-Ups context and help me choose the highest-leverage next move.'
              : 'Use my Follow-Ups context and help me act on "${task.title}" without overthinking it.',
        ),
      ],
      dataPoints: [
        SageInboxDataPoint(
          label: 'Open follow-ups',
          value: '${summary.openCount}',
          detail: 'Total active pressure in the local Follow-Ups queue.',
        ),
        SageInboxDataPoint(
          label: 'Overdue',
          value: '${summary.overdueCount}',
          detail:
              'These get urgent priority because delay has already started.',
        ),
        SageInboxDataPoint(
          label: 'Due soon',
          value: '${summary.dueSoonCount}',
          detail: 'Early action here prevents another overdue loop.',
        ),
        if (summary.staleWaitingTasks.isNotEmpty)
          SageInboxDataPoint(
            label: 'Stale waiting',
            value: '${summary.staleWaitingTasks.length}',
            detail: 'Threads quiet for nearly a week or more.',
          ),
      ],
    );
  }

  SageInboxMessage _followUpCleanMessage(DateTime now) {
    final date = DateFormat.MMMd().format(now);
    return SageInboxMessage(
      id: _followUpCleanId,
      subject: 'Follow-Ups are clear',
      preview: 'No active follow-up pressure is sitting in the queue.',
      body:
          'As of $date, Follow-Ups does not have open pressure. That is useful information too: today can be about writing, proof capture, checking in with yourself, or one bigger life-admin move instead of chasing stale tasks.',
      createdAt: now,
      priority: SageInboxPriority.low,
      status: SageInboxStatus.unread,
      source: 'Sage local signal',
      reason: 'Follow-Ups local cache has no open tasks.',
      relatedRoute: '/follow-ups',
      expiresAt: now.add(const Duration(hours: 24)),
      actionItems: const [
        SageInboxActionItem(
          label: 'Keep the queue clean',
          detail: 'Add a follow-up only when there is a real next action.',
          route: '/follow-ups',
        ),
      ],
      dataPoints: const [
        SageInboxDataPoint(
          label: 'Open follow-ups',
          value: '0',
          detail: 'Local Follow-Ups cache has no active tasks.',
        ),
      ],
    );
  }

  SageInboxMessage _dailyDispatchMessage({
    required DateTime now,
    required FollowUpTaskSummary followUpSummary,
    required List<OrbitLedgerEntry> orbitEntries,
    required int identityCount,
    required int sageMemoryCount,
    required SageSettings sageSettings,
    required String? recentJournalSignal,
  }) {
    final dateId = DateFormat('yyyyMMdd').format(now);
    final displayDate = DateFormat.MMMMEEEEd().format(now);
    final recentOrbit = orbitEntries
        .where(
          (entry) => entry.loggedAt.isAfter(
            now.subtract(const Duration(days: 7)),
          ),
        )
        .length;
    final leadSignal = _dailyLeadSignal(
      followUpSummary: followUpSummary,
      recentOrbit: recentOrbit,
      identityCount: identityCount,
      sageMemoryCount: sageMemoryCount,
    );

    return SageInboxMessage(
      id: '$_dailyDispatchPrefix.$dateId',
      subject: 'Sage Daily Dispatch',
      preview: 'Hey William, $leadSignal',
      body:
          'Hey William,\n\nDaily Dispatch for $displayDate.\n\n$leadSignal\n\n${recentJournalSignal == null ? '' : 'From your recent journal context: $recentJournalSignal\n\n'}I checked the signal stack before you had to: active follow-up pressure, recent attention pulls, known identity context, saved Sage memory, and your current Sage tone. I’m not trying to flood you. I’m trying to be the friend who notices the pattern, taps you on the shoulder, and helps you move one thing.\n\nCadence: I’ll aim for one real message a day, then only interrupt again if something genuinely deserves pressure.',
      createdAt: now,
      priority: followUpSummary.overdueCount > 0
          ? SageInboxPriority.high
          : SageInboxPriority.normal,
      status: SageInboxStatus.unread,
      source: 'Sage daily dispatch',
      reason:
          'Daily structured sweep across local app context, generated once per calendar day.',
      relatedRoute: '/inbox',
      expiresAt: now.add(const Duration(days: 7)),
      actionItems: [
        const SageInboxActionItem(
          label: 'Review the signal stack',
          detail:
              'Use the data points below to decide whether today needs action, reflection, or restraint.',
          route: '/inbox',
        ),
        const SageInboxActionItem(
          label: 'Discuss today’s dispatch with Sage',
          detail:
              'Open Sage with this exact context when you want the deeper read.',
          route: '/sage',
          sagePrompt:
              'Use my current app context, recent journal context, and today’s Sage Daily Dispatch. Talk to me like a close friend. Tell me what deserves action today, what is noise, and what I should stop carrying.',
        ),
        if (followUpSummary.openCount > 0)
          const SageInboxActionItem(
            label: 'Move one follow-up',
            detail: 'Pick one real-world thread and create motion.',
            route: '/follow-ups',
          ),
      ],
      dataPoints: [
        const SageInboxDataPoint(
          label: 'Cadence',
          value: 'Daily',
          detail: 'One Daily Dispatch per calendar day.',
        ),
        SageInboxDataPoint(
          label: 'Follow-Ups',
          value: '${followUpSummary.openCount} open',
          detail:
              '${followUpSummary.overdueCount} overdue, ${followUpSummary.dueSoonCount} due soon.',
        ),
        SageInboxDataPoint(
          label: 'Attention pulls',
          value: '$recentOrbit recent',
          detail: 'Orbit Ledger entries from the last 7 days.',
        ),
        SageInboxDataPoint(
          label: 'Known context',
          value: '$identityCount facts',
          detail: 'Identity memory facts Sage can use when relevant.',
        ),
        SageInboxDataPoint(
          label: 'Sage memory',
          value: '$sageMemoryCount notes',
          detail: 'Saved durable notes for Sage.',
        ),
        SageInboxDataPoint(
          label: 'Tone',
          value: sageSettings.toneMode,
          detail:
              '${sageSettings.directness} directness, ${sageSettings.warmth} warmth.',
        ),
        if (recentJournalSignal != null)
          SageInboxDataPoint(
            label: 'Recent journal',
            value: 'Included',
            detail: recentJournalSignal,
          ),
      ],
    );
  }

  String _dailyLeadSignal({
    required FollowUpTaskSummary followUpSummary,
    required int recentOrbit,
    required int identityCount,
    required int sageMemoryCount,
  }) {
    if (followUpSummary.overdueCount > 0) {
      return 'Lead signal: ${followUpSummary.overdueCount} overdue follow-up ${followUpSummary.overdueCount == 1 ? 'needs' : 'need'} action before the day turns into avoidance.';
    }
    if (followUpSummary.dueSoonCount > 0) {
      return 'Lead signal: ${followUpSummary.dueSoonCount} follow-up ${followUpSummary.dueSoonCount == 1 ? 'is' : 'are'} coming due soon, so today is a good day to get ahead of pressure.';
    }
    if (recentOrbit >= 5) {
      return 'Lead signal: Orbit Ledger shows $recentOrbit recent attention pulls, so the move is sorting obligation from noise.';
    }
    if (identityCount > 0 || sageMemoryCount > 0) {
      return 'Lead signal: Sage has enough stored context to make today’s message personal instead of generic.';
    }
    return 'Lead signal: no major pressure spike detected, so today can stay clean and deliberate.';
  }

  Future<SageInboxMessage> _composeMessageWithSage(
    SageInboxMessage message, {
    required SageSettings sageSettings,
  }) async {
    try {
      final contextString = await _api.getFloatchatContext();
      final response = await _api.sendFloatchatMessage(
        messages: [
          {
            'role': 'system',
            'content':
                'You write Sage Inbox messages. Compose like Sage: close, blunt when useful, personal, alive, and not repetitive. Do not mention token policy, templates, local metadata, or implementation. Return strict JSON only with keys subject, preview, body. Subject under 70 chars. Preview under 180 chars. Body 120-260 words. Address the user as William when natural. End with a reply invitation.',
          },
          {
            'role': 'user',
            'content': _composerPrompt(message, sageSettings),
          },
        ],
        contextString: contextString,
        maxTokens: 450,
      );
      final composed = _decodeComposedMessage(response['reply']?.toString());
      if (composed == null) return message;
      return message.copyWith(
        subject: composed.$1,
        preview: composed.$2,
        body: composed.$3,
      );
    } catch (_) {
      return message;
    }
  }

  String _composerPrompt(SageInboxMessage message, SageSettings settings) {
    final dataPoints = message.dataPoints
        .map((item) =>
            '- ${item.label}: ${item.value}${item.detail == null ? '' : ' (${item.detail})'}')
        .join('\n');
    final actions = message.actionItems
        .map((item) =>
            '- ${item.label}${item.detail == null ? '' : ': ${item.detail}'}')
        .join('\n');
    return [
      'Write the final Sage Inbox message from this structured draft.',
      'Message type/source: ${message.source}',
      'Reason: ${message.reason}',
      'Fallback subject: ${message.subject}',
      'Fallback preview: ${message.preview}',
      'Fallback body: ${message.body}',
      if (dataPoints.trim().isNotEmpty) 'Data points:\n$dataPoints',
      if (actions.trim().isNotEmpty) 'Possible next moves:\n$actions',
      'Sage settings: tone=${settings.toneMode}, warmth=${settings.warmth}, directness=${settings.directness}, swearing=${settings.allowSwearing}.',
      'Make it feel like a real message from Sage, not a report. It should be varied, specific, emotionally intelligent, and useful.',
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

  Future<SageInboxMessage?> _conversationFollowUpMessage(
    List<SageInboxMessage> messages,
    DateTime now,
  ) async {
    final candidates = messages
        .where((message) =>
            !message.isArchived &&
            message.id != _welcomeId &&
            message.id != _contextMapId &&
            message.id != _conversationFollowUpId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (candidates.isEmpty) return null;

    for (final message in candidates.take(8)) {
      final replies = await _loadReplies(message.id);
      final lastTouch =
          replies.isEmpty ? message.createdAt : replies.last.createdAt;
      final quietHours = now.difference(lastTouch).inHours;
      final lastWasSage =
          replies.isEmpty || replies.last.role == SageInboxReplyRole.assistant;
      if (quietHours < 12 || !lastWasSage) continue;

      return SageInboxMessage(
        id: _conversationFollowUpId,
        subject: 'Hey William, checking back on this',
        preview:
            'I haven’t heard back about "${message.subject}". Do you want to act, talk it through, or call it handled?',
        body:
            'Hey William,\n\nI’m checking back in because I haven’t heard from you on "${message.subject}".\n\nYou don’t have to make this dramatic. Either tell me you handled it, ask me the question that’s blocking you, or turn it into an inbox task so it stops floating around.\n\nMy read: if this still matters after $quietHours quiet hours, it deserves a clean next move or a clean dismissal.',
        createdAt: now,
        priority: SageInboxPriority.normal,
        status: SageInboxStatus.unread,
        source: 'Sage follow-up',
        reason:
            'Sage sent a follow-up because a prior inbox thread went quiet.',
        relatedRoute: '/inbox',
        expiresAt: now.add(const Duration(days: 2)),
        actionItems: [
          SageInboxActionItem(
            label: 'Reply to Sage',
            detail: 'Ask the blocking question or say what happened.',
            route: '/sage',
            sagePrompt:
                'Follow up with me about the Sage Inbox message "${message.subject}". Help me decide whether to act, dismiss it, or turn it into a task.',
          ),
          const SageInboxActionItem(
            label: 'Make it a task',
            detail: 'If it still matters, give it a real place to live.',
            route: '/inbox',
          ),
        ],
        dataPoints: [
          SageInboxDataPoint(
            label: 'Quiet time',
            value: '$quietHours hours',
            detail: 'Time since the last reply or message touch.',
          ),
          SageInboxDataPoint(
            label: 'Original message',
            value: message.subject,
            detail: message.preview,
          ),
        ],
      );
    }

    return null;
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

  SageInboxMessage? _orbitPressureMessage(
    List<OrbitLedgerEntry> entries,
    DateTime now,
  ) {
    final recent = entries
        .where(
          (entry) => entry.loggedAt.isAfter(
            now.subtract(const Duration(days: 7)),
          ),
        )
        .toList();
    final highPressure = recent
        .where((entry) =>
            entry.urgency.toLowerCase().contains('urgent') ||
            entry.urgency.toLowerCase().contains('high'))
        .toList();
    if (recent.length < 5 && highPressure.isEmpty) return null;

    final first = highPressure.isNotEmpty ? highPressure.first : recent.first;
    return SageInboxMessage(
      id: _orbitPressureId,
      subject: 'Your attention ledger is getting noisy',
      preview:
          '${recent.length} Orbit Ledger items landed in the last week. Sage should help you separate real obligations from pressure.',
      body:
          'Orbit Ledger is showing recent demand on your attention. The useful move is not to answer everything; it is to sort what is actually yours, what needs a boundary, and what can be ignored.\n\nMost recent pressure: ${first.request}.',
      createdAt: now,
      priority: highPressure.isNotEmpty
          ? SageInboxPriority.high
          : SageInboxPriority.normal,
      status: SageInboxStatus.unread,
      source: 'Sage local signal',
      reason:
          'Orbit Ledger has recent requests or high-urgency attention pulls.',
      relatedRoute: '/more',
      expiresAt: now.add(const Duration(hours: 20)),
      actionItems: [
        const SageInboxActionItem(
          label: 'Review attention pulls',
          detail:
              'Decide what is yours, what needs a boundary, and what can wait.',
          route: '/orbit-ledger',
        ),
        const SageInboxActionItem(
          label: 'Open a Sage boundary thread',
          detail: 'Use Sage to sort obligation, guilt, urgency, and wording.',
          route: '/sage',
          sagePrompt:
              'Use my Orbit Ledger context and help me sort recent attention pulls into: mine to handle, boundary needed, can wait, or ignore.',
        ),
      ],
      dataPoints: [
        SageInboxDataPoint(
          label: 'Recent pulls',
          value: '${recent.length}',
          detail: 'Orbit Ledger entries from the last 7 days.',
        ),
        SageInboxDataPoint(
          label: 'High pressure',
          value: '${highPressure.length}',
          detail: 'Recent entries marked high or urgent.',
        ),
      ],
    );
  }

  SageInboxMessage _contextMapMessage({
    required DateTime now,
    required FollowUpTaskSummary followUpSummary,
    required List<OrbitLedgerEntry> orbitEntries,
    required int identityCount,
    required int sageMemoryCount,
    required SageSettings sageSettings,
    required String? recentJournalSignal,
  }) {
    final recentOrbit = orbitEntries
        .where(
          (entry) => entry.loggedAt.isAfter(
            now.subtract(const Duration(days: 14)),
          ),
        )
        .length;
    return SageInboxMessage(
      id: _contextMapId,
      subject: 'Sage checked the local context map',
      preview:
          'Inbox considered Follow-Ups, Orbit Ledger, identity memory, Sage memory, Sage settings, and recent journal context.',
      body:
          'This is the lightweight context sweep. It checks structured local signals and recent journal context so Inbox can feel personal without asking the model to reread everything.\n\nCurrent read: ${followUpSummary.openCount} open follow-ups, $recentOrbit recent Orbit Ledger entries, $identityCount known identity facts, and $sageMemoryCount saved Sage memory notes. Sage tone is ${sageSettings.toneMode}.${recentJournalSignal == null ? '' : '\n\nRecent journal signal: $recentJournalSignal'}',
      createdAt: now,
      priority: SageInboxPriority.low,
      status: SageInboxStatus.unread,
      source: 'Sage context map',
      reason:
          'A lightweight local sweep keeps Inbox aware without spending tokens.',
      relatedRoute: '/sage',
      expiresAt: now.add(const Duration(days: 2)),
      actionItems: const [
        SageInboxActionItem(
          label: 'Open a Sage context thread',
          detail:
              'Ask Sage what these signals suggest when you want deeper analysis.',
          route: '/sage',
          sagePrompt:
              'Use my current app context and tell me what matters most across Follow-Ups, Orbit Ledger, identity memory, and Sage memory. Be practical and prioritize action.',
        ),
      ],
      dataPoints: [
        SageInboxDataPoint(
          label: 'Follow-Ups',
          value: '${followUpSummary.openCount} open',
          detail:
              '${followUpSummary.overdueCount} overdue, ${followUpSummary.dueSoonCount} due soon.',
        ),
        SageInboxDataPoint(
          label: 'Orbit Ledger',
          value: '$recentOrbit recent',
          detail: 'Entries logged in the last 14 days.',
        ),
        SageInboxDataPoint(
          label: 'Identity memory',
          value: '$identityCount facts',
          detail: 'Known people and durable user-corrected/inferred context.',
        ),
        SageInboxDataPoint(
          label: 'Sage memory',
          value: '$sageMemoryCount notes',
          detail: 'Private Sage memory items saved on this device.',
        ),
        SageInboxDataPoint(
          label: 'Sage tone',
          value: sageSettings.toneMode,
          detail: 'Inbox can match your saved Sage personality settings.',
        ),
        if (recentJournalSignal != null)
          SageInboxDataPoint(
            label: 'Recent journal',
            value: 'Checked',
            detail: recentJournalSignal,
          ),
      ],
    );
  }
}
