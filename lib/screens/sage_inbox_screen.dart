import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../services/notification_nudge_service.dart';
import '../services/sage_inbox_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';
import 'follow_ups_screen.dart';
import 'orbit_ledger_screen.dart';
import 'sage_screen.dart';

class SageInboxScreen extends StatefulWidget {
  const SageInboxScreen({super.key});

  @override
  State<SageInboxScreen> createState() => _SageInboxScreenState();
}

class _SageInboxScreenState extends State<SageInboxScreen> {
  final _service = SageInboxService();
  final _notifications = NotificationNudgeService();

  List<SageInboxMessage> _messages = const [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  int _filterIndex = 0;

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
      final snapshot = await _service.loadInbox();
      if (mounted) {
        setState(() {
          _messages = snapshot.messages;
          _loading = false;
        });
      }
      await _refreshAdaptive(silent: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _parseError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshAdaptive({bool silent = false}) async {
    if (!silent && mounted) setState(() => _refreshing = true);
    try {
      final snapshot = await _service.refreshAdaptiveMessages();
      await _notifications.refreshSageInboxNotifications(snapshot.messages);
      if (mounted) {
        setState(() {
          _messages = snapshot.messages;
          _refreshing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _parseError(e);
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _markAllRead() async {
    final snapshot = await _service.markAllRead();
    if (mounted) setState(() => _messages = snapshot.messages);
  }

  Future<void> _openMessage(SageInboxMessage message) async {
    if (message.isUnread) {
      final snapshot = await _service.markRead(message.id);
      if (mounted) setState(() => _messages = snapshot.messages);
    }

    if (!mounted) return;
    await Navigator.push<void>(
      context,
      CupertinoPageRoute(
        builder: (_) => SageInboxDetailScreen(
          message: _messages.firstWhere(
            (item) => item.id == message.id,
            orElse: () => message.copyWith(status: SageInboxStatus.read),
          ),
          onArchive: () => _archiveMessage(message.id),
        ),
      ),
    );
    final snapshot = await _service.loadInbox();
    if (mounted) setState(() => _messages = snapshot.messages);
  }

  Future<void> _archiveMessage(String id) async {
    final snapshot = await _service.archive(id);
    if (mounted) setState(() => _messages = snapshot.messages);
  }

  List<SageInboxMessage> get _visibleMessages {
    return switch (_filterIndex) {
      1 => _messages
          .where((message) => message.isUnread && !message.isArchived)
          .toList(),
      2 => _messages.where((message) => message.isArchived).toList(),
      _ => _messages.where((message) => !message.isArchived).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _messages
        .where((message) => message.isUnread && !message.isArchived)
        .length;
    final activeCount =
        _messages.where((message) => !message.isArchived).length;

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Inbox'),
            backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _refreshing ? null : () => _refreshAdaptive(),
              child: _refreshing
                  ? const CupertinoActivityIndicator(
                      color: JournalColors.accent,
                    )
                  : const Icon(
                      CupertinoIcons.arrow_clockwise,
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
              child: _InboxErrorView(error: _error!, onRetry: _load),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: _InboxHero(
                  unreadCount: unreadCount,
                  activeCount: activeCount,
                  onMarkAllRead: unreadCount == 0 ? null : _markAllRead,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: CupertinoSlidingSegmentedControl<int>(
                  groupValue: _filterIndex,
                  backgroundColor: JournalColors.bgSurface,
                  thumbColor: JournalColors.bgCardAlt,
                  children: const {
                    0: _FilterLabel('All'),
                    1: _FilterLabel('Unread'),
                    2: _FilterLabel('Archive'),
                  },
                  onValueChanged: (value) {
                    if (value == null) return;
                    setState(() => _filterIndex = value);
                  },
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(
                  title: _filterIndex == 1
                      ? 'Unread messages'
                      : _filterIndex == 2
                          ? 'Archived messages'
                          : 'Sage messages',
                ),
              ),
            ),
            if (_visibleMessages.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyInbox(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                sliver: SliverList.separated(
                  itemCount: _visibleMessages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final message = _visibleMessages[index];
                    return _InboxMessageCard(
                      message: message,
                      onTap: () => _openMessage(message),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class SageInboxDetailScreen extends StatefulWidget {
  const SageInboxDetailScreen({
    super.key,
    required this.message,
    required this.onArchive,
  });

  final SageInboxMessage message;
  final Future<void> Function() onArchive;

  @override
  State<SageInboxDetailScreen> createState() => _SageInboxDetailScreenState();
}

class _SageInboxDetailScreenState extends State<SageInboxDetailScreen> {
  final _service = SageInboxService();
  final _replyController = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  String? _error;
  SageInboxDetail? _detail;

  SageInboxMessage get _message => _detail?.message ?? widget.message;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _service.loadDetail(widget.message.id);
      if (mounted) {
        setState(() {
          _detail = detail;
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

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      _replyController.clear();
      final detail = await _service.sendReply(
        messageId: widget.message.id,
        text: text,
      );
      if (mounted) {
        setState(() {
          _detail = detail;
          _sending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _parseError(e);
          _sending = false;
        });
      }
    }
  }

  Future<void> _createTaskFromMessage() async {
    final detail = await _service.createTask(
      messageId: widget.message.id,
      title: _message.subject,
      detail: _message.preview,
    );
    if (mounted) setState(() => _detail = detail);
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      CupertinoPageRoute(
        builder: (_) => SageInboxTasksScreen(messageId: widget.message.id),
      ),
    );
    await _loadDetail();
  }

  Future<void> _openTasks() async {
    await Navigator.push<void>(
      context,
      CupertinoPageRoute(
        builder: (_) => SageInboxTasksScreen(messageId: widget.message.id),
      ),
    );
    await _loadDetail();
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    final detail = _detail;
    return DefaultTextStyle.merge(
      style: const TextStyle(
        color: JournalColors.textPrimary,
        decoration: TextDecoration.none,
      ),
      child: CupertinoPageScaffold(
        backgroundColor: JournalColors.bgBase,
        child: CustomScrollView(
          slivers: [
            CupertinoSliverNavigationBar(
              largeTitle: const Text('Message'),
              backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
              border: const Border(
                bottom: BorderSide(color: JournalColors.border, width: 0.5),
              ),
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () async {
                  await widget.onArchive();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Icon(
                  CupertinoIcons.archivebox,
                  color: JournalColors.textSecondary,
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
            else if (_error != null && detail == null)
              SliverFillRemaining(
                child: _InboxErrorView(error: _error!, onRetry: _loadDetail),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(
                    [
                      _MessageLetterCard(message: message),
                      const SizedBox(height: 18),
                      _ReplyPanel(
                        replies: detail?.replies ?? const [],
                        controller: _replyController,
                        sending: _sending,
                        error: _error,
                        onSend: _sendReply,
                      ),
                      if (message.actionItems.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const SectionHeader(title: 'Useful ways in'),
                        const SizedBox(height: 8),
                        ...message.actionItems.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ActionItemTile(item: item),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _InboxTaskPanel(
                        tasks: detail?.tasks ?? const [],
                        onCreateTask: _createTaskFromMessage,
                        onOpenTasks: _openTasks,
                      ),
                      if (message.dataPoints.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const SectionHeader(title: 'Context Sage used'),
                        const SizedBox(height: 8),
                        _DataPointGrid(dataPoints: message.dataPoints),
                      ],
                      const SizedBox(height: 8),
                      _MessageMetadata(message: message),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InboxHero extends StatelessWidget {
  const _InboxHero({
    required this.unreadCount,
    required this.activeCount,
    required this.onMarkAllRead,
  });

  final int unreadCount;
  final int activeCount;
  final VoidCallback? onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accentBorder: unreadCount > 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: JournalColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: JournalColors.borderBright),
                ),
                child: const Icon(
                  CupertinoIcons.tray_full,
                  color: JournalColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sage Inbox',
                      style: TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      unreadCount == 0
                          ? 'No unread Sage messages.'
                          : '$unreadCount unread. $activeCount active total.',
                      style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onMarkAllRead != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 11),
                color: JournalColors.accent,
                onPressed: onMarkAllRead,
                child: const Text(
                  'Mark all read',
                  style: TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageLetterCard extends StatelessWidget {
  const _MessageLetterCard({required this.message});

  final SageInboxMessage message;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accentBorder: message.priority == SageInboxPriority.urgent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PriorityPill(priority: message.priority),
              const Spacer(),
              Text(
                DateFormat.MMMd().add_jm().format(message.createdAt),
                style: const TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            message.subject,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 24,
              height: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (message.preview.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              message.preview,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            height: 1,
            color: JournalColors.border,
          ),
          const SizedBox(height: 18),
          Text(
            message.body,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 16,
              height: 1.62,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class SageInboxTasksScreen extends StatefulWidget {
  const SageInboxTasksScreen({super.key, required this.messageId});

  final String messageId;

  @override
  State<SageInboxTasksScreen> createState() => _SageInboxTasksScreenState();
}

class _SageInboxTasksScreenState extends State<SageInboxTasksScreen> {
  final _service = SageInboxService();
  final _titleController = TextEditingController();
  final _detailController = TextEditingController();
  SageInboxDetail? _detail;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _service.loadDetail(widget.messageId);
      if (mounted) {
        setState(() {
          _detail = detail;
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

  Future<void> _createTask() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final detail = await _service.createTask(
        messageId: widget.messageId,
        title: title,
        detail: _detailController.text.trim(),
      );
      _titleController.clear();
      _detailController.clear();
      if (mounted) {
        setState(() {
          _detail = detail;
          _saving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _parseError(e);
          _saving = false;
        });
      }
    }
  }

  Future<void> _toggleTask(SageInboxTask task) async {
    final detail = await _service.toggleTaskDone(task);
    if (mounted) setState(() => _detail = detail);
  }

  Future<void> _syncTask(SageInboxTask task) async {
    final detail = await _service.syncTaskToFollowUps(task);
    if (mounted) setState(() => _detail = detail);
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final tasks = detail?.tasks ?? const <SageInboxTask>[];
    final openCount = tasks.where((task) => task.isOpen).length;

    return DefaultTextStyle.merge(
      style: const TextStyle(
        color: JournalColors.textPrimary,
        decoration: TextDecoration.none,
      ),
      child: CupertinoPageScaffold(
        backgroundColor: JournalColors.bgBase,
        child: CustomScrollView(
          slivers: [
            CupertinoSliverNavigationBar(
              largeTitle: const Text('Inbox Tasks'),
              backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
              border: const Border(
                bottom: BorderSide(color: JournalColors.border, width: 0.5),
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
            else if (_error != null && detail == null)
              SliverFillRemaining(
                child: _InboxErrorView(error: _error!, onRetry: _load),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(
                    [
                      GlassCard(
                        accentBorder: openCount > 0,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              detail?.message.subject ?? 'Inbox task stack',
                              style: const TextStyle(
                                color: JournalColors.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$openCount open task ${openCount == 1 ? 'needs' : 'need'} attention. Sync anything important into Follow-Ups when it needs durable tracking.',
                              style: const TextStyle(
                                color: JournalColors.textSecondary,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const SectionHeader(title: 'Create task'),
                      const SizedBox(height: 8),
                      GlassCard(
                        child: Column(
                          children: [
                            CupertinoTextField(
                              controller: _titleController,
                              placeholder: 'Task title',
                              placeholderStyle: const TextStyle(
                                  color: JournalColors.textMuted),
                              style: const TextStyle(
                                color: JournalColors.textPrimary,
                                fontSize: 15,
                              ),
                              decoration: BoxDecoration(
                                color: JournalColors.bgSurface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: JournalColors.border),
                              ),
                              padding: const EdgeInsets.all(14),
                            ),
                            const SizedBox(height: 10),
                            CupertinoTextField(
                              controller: _detailController,
                              minLines: 2,
                              maxLines: 4,
                              placeholder: 'Optional next action or detail',
                              placeholderStyle: const TextStyle(
                                  color: JournalColors.textMuted),
                              style: const TextStyle(
                                color: JournalColors.textPrimary,
                                fontSize: 15,
                                height: 1.35,
                              ),
                              decoration: BoxDecoration(
                                color: JournalColors.bgSurface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: JournalColors.border),
                              ),
                              padding: const EdgeInsets.all(14),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: CupertinoButton(
                                color: JournalColors.accent,
                                onPressed: _saving ? null : _createTask,
                                child: Text(
                                  _saving ? 'Saving...' : 'Add inbox task',
                                  style: const TextStyle(
                                    color: CupertinoColors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const SectionHeader(title: 'Task stack'),
                      const SizedBox(height: 8),
                      if (tasks.isEmpty)
                        const GlassCard(
                          child: Text(
                            'No inbox tasks yet.',
                            style: TextStyle(
                              color: JournalColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        )
                      else
                        ...tasks.map(
                          (task) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _InboxTaskCard(
                              task: task,
                              onToggle: () => _toggleTask(task),
                              onSync:
                                  task.isSynced ? null : () => _syncTask(task),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InboxTaskCard extends StatelessWidget {
  const _InboxTaskCard({
    required this.task,
    required this.onToggle,
    required this.onSync,
  });

  final SageInboxTask task;
  final VoidCallback onToggle;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final statusLabel = task.isSynced
        ? 'Synced'
        : task.isDone
            ? 'Done'
            : 'Open';
    return GlassCard(
      accentBorder: task.isOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                task.isOpen
                    ? CupertinoIcons.circle
                    : CupertinoIcons.checkmark_circle_fill,
                color: task.isOpen
                    ? JournalColors.textMuted
                    : JournalColors.success,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (task.detail != null &&
                        task.detail!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        task.detail!,
                        style: const TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _StatusPill(label: statusLabel),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  color: JournalColors.bgSurface,
                  onPressed: onToggle,
                  child: Text(
                    task.isDone ? 'Reopen' : 'Mark done',
                    style: const TextStyle(
                      color: JournalColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  color: onSync == null ? null : JournalColors.accent,
                  onPressed: onSync,
                  child: Text(
                    task.isSynced ? 'In Follow-Ups' : 'Sync',
                    style: TextStyle(
                      color: onSync == null
                          ? JournalColors.textMuted
                          : CupertinoColors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: JournalColors.bgSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: JournalColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: JournalColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: JournalColors.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxMessageCard extends StatelessWidget {
  const _InboxMessageCard({required this.message, required this.onTap});

  final SageInboxMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      accentBorder:
          message.isUnread || message.priority == SageInboxPriority.urgent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              color: message.isUnread
                  ? _priorityColor(message.priority)
                  : JournalColors.textMuted,
              shape: BoxShape.circle,
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
                        message.subject,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 17,
                          fontWeight: message.isUnread
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat.MMMd().format(message.createdAt),
                      style: const TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  message.preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 14,
                    height: 1.42,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _PriorityPill(priority: message.priority),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(
                      CupertinoIcons.chevron_right,
                      color: JournalColors.textMuted,
                      size: 16,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionItemTile extends StatelessWidget {
  const _ActionItemTile({required this.item});

  final SageInboxActionItem item;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: item.route == null ? null : () => _openRoute(context, item.route!),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            CupertinoIcons.checkmark_circle,
            color: JournalColors.success,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (item.detail != null && item.detail!.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    item.detail!,
                    style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (item.route != null)
            const Icon(
              CupertinoIcons.arrow_up_right,
              color: JournalColors.textMuted,
              size: 16,
            ),
        ],
      ),
    );
  }

  void _openRoute(BuildContext context, String route) {
    final screen = switch (route) {
      '/follow-ups' => const FollowUpsScreen(),
      '/orbit-ledger' => const OrbitLedgerScreen(),
      '/sage' => SageScreen(
          handoff: SageHandoff(
            prefillText: item.sagePrompt,
            autoSendPrefill: false,
            autoStartGreeting: false,
            showDefaultWelcome: true,
          ),
        ),
      _ => null,
    };
    if (screen == null) return;
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: screen,
        ),
      ),
    );
  }
}

class _ReplyPanel extends StatelessWidget {
  const _ReplyPanel({
    required this.replies,
    required this.controller,
    required this.sending,
    required this.error,
    required this.onSend,
  });

  final List<SageInboxReply> replies;
  final TextEditingController controller;
  final bool sending;
  final String? error;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accentBorder: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replies.isNotEmpty) ...[
            for (var i = 0; i < replies.length; i++) ...[
              if (i > 0) const _ThreadDivider(),
              _ReplyEntry(reply: replies[i]),
            ],
            const _ThreadDivider(),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: JournalColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      CupertinoIcons.arrowshape_turn_up_left,
                      size: 14,
                      color: JournalColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Reply to Sage',
                        style: TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (sending)
                      const CupertinoActivityIndicator(
                          color: JournalColors.accent),
                  ],
                ),
                CupertinoTextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 8,
                  enabled: !sending,
                  placeholder: 'Write your reply...',
                  placeholderStyle:
                      const TextStyle(color: JournalColors.textMuted),
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    height: 1.45,
                  ),
                  decoration: const BoxDecoration(),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                if (error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: JournalColors.danger,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    CupertinoButton(
                      color: JournalColors.accent,
                      borderRadius: BorderRadius.circular(20),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 8),
                      onPressed: sending ? null : onSend,
                      child: Text(
                        sending ? 'Sending...' : 'Send',
                        style: const TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadDivider extends StatelessWidget {
  const _ThreadDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 14),
      color: JournalColors.border,
    );
  }
}

class _ReplyEntry extends StatelessWidget {
  const _ReplyEntry({required this.reply});

  final SageInboxReply reply;

  @override
  Widget build(BuildContext context) {
    final isUser = reply.role == SageInboxReplyRole.user;
    final name = isUser ? 'William' : 'Sage';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isUser
                    ? JournalColors.bgSurface
                    : JournalColors.accent.withValues(alpha: 0.22),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isUser
                      ? JournalColors.border
                      : JournalColors.borderBright,
                ),
              ),
              child: Text(
                isUser ? 'W' : 'S',
                style: TextStyle(
                  color: isUser
                      ? JournalColors.textSecondary
                      : JournalColors.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    isUser ? 'to Sage' : 'to me',
                    style: const TextStyle(
                      color: JournalColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              DateFormat.MMMd().add_jm().format(reply.createdAt),
              style: const TextStyle(
                color: JournalColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          reply.text,
          style: const TextStyle(
            color: JournalColors.textPrimary,
            fontSize: 15,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _InboxTaskPanel extends StatelessWidget {
  const _InboxTaskPanel({
    required this.tasks,
    required this.onCreateTask,
    required this.onOpenTasks,
  });

  final List<SageInboxTask> tasks;
  final VoidCallback onCreateTask;
  final VoidCallback onOpenTasks;

  @override
  Widget build(BuildContext context) {
    final openCount = tasks.where((task) => task.isOpen).length;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Inbox tasks',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _HeroStat(value: '$openCount', label: 'Open'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            tasks.isEmpty
                ? 'Create a task from this message, then manage it full-screen without crowding the thread.'
                : '${tasks.length} task ${tasks.length == 1 ? 'exists' : 'exist'} for this message.',
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  color: JournalColors.bgSurface,
                  onPressed: onCreateTask,
                  child: const Text(
                    'Create task',
                    style: TextStyle(
                      color: JournalColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  color: JournalColors.accent,
                  onPressed: onOpenTasks,
                  child: const Text(
                    'Open tasks',
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DataPointGrid extends StatelessWidget {
  const _DataPointGrid({required this.dataPoints});

  final List<SageInboxDataPoint> dataPoints;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth < 340
            ? constraints.maxWidth
            : (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: dataPoints
              .map(
                (point) => _DataPointChip(
                  dataPoint: point,
                  width: itemWidth,
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _DataPointChip extends StatelessWidget {
  const _DataPointChip({required this.dataPoint, required this.width});

  final SageInboxDataPoint dataPoint;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: JournalColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dataPoint.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            dataPoint.value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (dataPoint.detail != null &&
              dataPoint.detail!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              dataPoint.detail!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageMetadata extends StatelessWidget {
  const _MessageMetadata({required this.message});

  final SageInboxMessage message;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Why Sage sent this',
            style: TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message.reason,
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Source: ${message.source}',
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityPill extends StatelessWidget {
  const _PriorityPill({required this.priority});

  final SageInboxPriority priority;

  @override
  Widget build(BuildContext context) {
    final color = _priorityColor(priority);
    final label = switch (priority) {
      SageInboxPriority.urgent => 'Urgent',
      SageInboxPriority.high => 'High',
      SageInboxPriority.normal => 'Normal',
      SageInboxPriority.low => 'Low',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: JournalColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Center(
        child: Text(
          'No messages in this view.',
          style: TextStyle(
            color: JournalColors.textSecondary,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class _InboxErrorView extends StatelessWidget {
  const _InboxErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle,
              color: JournalColors.textMuted,
              size: 34,
            ),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            CupertinoButton(
              color: JournalColors.accent,
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

Color _priorityColor(SageInboxPriority priority) {
  return switch (priority) {
    SageInboxPriority.urgent => JournalColors.danger,
    SageInboxPriority.high => JournalColors.severity,
    SageInboxPriority.normal => JournalColors.accent,
    SageInboxPriority.low => JournalColors.info,
  };
}

String _parseError(dynamic e) {
  final str = e.toString();
  final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
  return match?.group(1) ?? 'Something went wrong.';
}
