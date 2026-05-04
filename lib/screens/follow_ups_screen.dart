import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../services/follow_up_tasks_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';
import 'sage_screen.dart';

const _followUpBuckets = <String>[
  'job_application',
  'recruiter',
  'networking',
  'interview',
  'admin',
  'personal',
];

const _followUpStatuses = <String>[
  'active',
  'waiting',
  'done',
  'archived',
];

const _filterLabels = <String>[
  'Due',
  'Active',
  'Waiting',
  'Done',
];

const _quickFollowUps =
    <({String label, String title, String bucket, String status, String action})>[
  (
    label: 'Application',
    title: 'Follow up on a submitted application',
    bucket: 'job_application',
    status: 'waiting',
    action: 'Send a follow-up note and ask about timeline',
  ),
  (
    label: 'Recruiter',
    title: 'Ping recruiter',
    bucket: 'recruiter',
    status: 'active',
    action: 'Send the next follow-up message',
  ),
  (
    label: 'Interview',
    title: 'Prepare for interview',
    bucket: 'interview',
    status: 'active',
    action: 'Prepare talking points and examples',
  ),
  (
    label: 'Networking',
    title: 'Reconnect with a contact',
    bucket: 'networking',
    status: 'active',
    action: 'Send a check-in and ask for a next step',
  ),
  (
    label: 'Admin',
    title: 'Handle follow-up paperwork',
    bucket: 'admin',
    status: 'active',
    action: 'Close the admin loop',
  ),
];

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

class FollowUpsScreen extends StatefulWidget {
  const FollowUpsScreen({super.key});

  @override
  State<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends State<FollowUpsScreen> {
  final _service = FollowUpTaskService();
  final _dateFormat = DateFormat('MMM d, yyyy');

  bool _loading = true;
  String? _error;
  bool _showExitPlanNote = true;
  int _filterIndex = 0;
  List<FollowUpTask> _tasks = const [];

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
      final tasks = await _service.loadTasks();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your follow-ups right now.';
        _loading = false;
      });
    }
  }

  Future<void> _saveTasks(List<FollowUpTask> tasks) async {
    await _service.saveTasks(tasks);
    if (!mounted) return;
    setState(() {
      _tasks = List<FollowUpTask>.from(tasks)
        ..sort(FollowUpTaskService.compareTasks);
    });
  }

  Future<void> _openEditor({FollowUpTask? existing, FollowUpTask? draft}) async {
    final result = await Navigator.push<FollowUpTask>(
      context,
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: _FollowUpEditorScreen(task: existing ?? draft),
        ),
      ),
    );
    if (result == null) return;

    final next = [..._tasks];
    final index = next.indexWhere((item) => item.id == result.id);
    if (index >= 0) {
      next[index] = result;
    } else {
      next.add(result);
    }
    await _saveTasks(next);
  }

  Future<void> _deleteTask(FollowUpTask task) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete follow-up?'),
        content: const Text(
          'This removes the task from your follow-up tracker.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _saveTasks(_tasks.where((item) => item.id != task.id).toList());
  }

  Future<void> _updateTask(FollowUpTask task) async {
    final next = [..._tasks];
    final index = next.indexWhere((item) => item.id == task.id);
    if (index < 0) return;
    next[index] = task;
    await _saveTasks(next);
  }

  Future<void> _openSagePressure({FollowUpTask? task}) {
    final prefill = task == null
        ? 'Use my Follow-Ups context and tell me what is overdue, what I am avoiding, and exactly what I need to follow up on next.'
        : 'Pressure me about this follow-up item: ${task.title}'
            '${(task.counterparty ?? '').trim().isNotEmpty ? ' with ${task.counterparty!.trim()}' : ''}. '
            'Use my follow-up context, call out whether I am stalling, and tell me the exact next move.';
    return pushSageScreen(
      context,
      handoff: SageHandoff(
        prefillText: prefill,
        autoSendPrefill: true,
        autoStartGreeting: false,
        showDefaultWelcome: false,
      ),
    );
  }

  Future<void> _addQuickItem(
    ({
      String label,
      String title,
      String bucket,
      String status,
      String action,
    }) preset,
  ) {
    final now = DateTime.now();
    return _openEditor(
      draft: FollowUpTask(
        id: now.microsecondsSinceEpoch.toString(),
        title: preset.title,
        bucket: preset.bucket,
        status: preset.status,
        createdAt: now,
        lastTouchedAt: now,
        nextAction: preset.action,
        followUpAt: now.add(const Duration(days: 3)),
      ),
    );
  }

  List<FollowUpTask> get _openTasks => _tasks.where((task) => task.isOpen).toList();

  int get _overdueCount => _openTasks.where((task) => task.isOverdue()).length;

  int get _dueSoonCount =>
      _openTasks.where((task) => task.isDueSoon()).length;

  int get _waitingCount =>
      _openTasks.where((task) => task.isWaiting).length;

  int get _doneCount => _tasks.where((task) => task.isDone).length;

  List<FollowUpTask> _filteredTasks() {
    switch (_filterIndex) {
      case 1:
        return _tasks.where((task) => task.isActive).toList();
      case 2:
        return _tasks.where((task) => task.isWaiting && task.isOpen).toList();
      case 3:
        return _tasks.where((task) => task.isDone).toList();
      default:
        return _tasks
            .where((task) => task.isOverdue() || task.isDueSoon() || task.isActive)
            .toList();
    }
  }

  List<Widget> _buildTaskSections() {
    final filtered = _filteredTasks();
    if (filtered.isEmpty) {
      return const [
        GlassCard(
          child: Column(
            children: [
              Text(
                'No follow-ups in this view',
                style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Add a live thread here when you want something tracked, revisited, or pushed by Sage without cluttering Exit Plan.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ];
    }

    final overdue = filtered.where((task) => task.isOverdue()).toList();
    final dueSoon = filtered
        .where((task) => !task.isOverdue() && task.isDueSoon())
        .toList();
    final active = filtered
        .where((task) => task.isActive && !task.isOverdue() && !task.isDueSoon())
        .toList();
    final waiting = filtered
        .where((task) => task.isWaiting && !task.isOverdue() && !task.isDueSoon())
        .toList();
    final done = filtered.where((task) => task.isDone).toList();

    final widgets = <Widget>[];
    void addSection(String title, List<FollowUpTask> items) {
      if (items.isEmpty) return;
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 24));
      widgets.add(
        SectionHeader(
          title: title,
          trailing: Text(
            '${items.length}',
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
      );
      widgets.add(const SizedBox(height: 12));
      widgets.addAll(
        items.map(
          (task) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _FollowUpTaskCard(
              task: task,
              dateFormat: _dateFormat,
              onEdit: () => _openEditor(existing: task),
              onDelete: () => _deleteTask(task),
              onAskSage: () => _openSagePressure(task: task),
              onStatusChanged: (status) {
                final now = DateTime.now();
                return _updateTask(
                  task.copyWith(
                    status: status,
                    lastTouchedAt: now,
                    completedAt: status == 'done' ? now : null,
                    clearCompletedAt: status != 'done',
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    addSection('Overdue', overdue);
    addSection('Due Soon', dueSoon);
    addSection('Active', active);
    addSection('Waiting', waiting);
    addSection('Done', done);
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Follow-Ups'),
            previousPageTitle: 'More',
            backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CupertinoActivityIndicator(color: JournalColors.accent),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GlassCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          color: JournalColors.danger,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 14),
                        CupertinoButton(
                          color: JournalColors.accent,
                          onPressed: _load,
                          child: const Text(
                            'Retry',
                            style: TextStyle(color: JournalColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FollowUpHeroCard(
                      totalOpen: _openTasks.length,
                      overdueCount: _overdueCount,
                      dueSoonCount: _dueSoonCount,
                      waitingCount: _waitingCount,
                      onAddPressed: () => _openEditor(),
                      onAskSage: _openSagePressure,
                    ),
                    if (_showExitPlanNote) ...[
                      const SizedBox(height: 24),
                      GlassCard(
                        accentBorder: true,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Not the same as Exit Plan',
                                    style: TextStyle(
                                      color: JournalColors.textPrimary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Exit Plan is for roadmap steps. Follow-Ups is for live threads that need another touch, reply, or deadline.',
                                    style: TextStyle(
                                      color: JournalColors.textSecondary,
                                      fontSize: 14,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(28, 28),
                              onPressed: () {
                                setState(() => _showExitPlanNote = false);
                              },
                              child: const Icon(
                                CupertinoIcons.xmark,
                                color: JournalColors.textMuted,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Quick Start'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final item in _quickFollowUps)
                          _QuickFollowUpChip(
                            label: item.label,
                            onTap: () => _addQuickItem(item),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SectionHeader(
                      title: 'Queue',
                      trailing: Text(
                        '${_tasks.length} total',
                        style: const TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    AdaptiveSegmentedControl(
                      labels: _filterLabels,
                      selectedIndex: _filterIndex,
                      onValueChanged: (index) {
                        setState(() => _filterIndex = index);
                      },
                    ),
                    const SizedBox(height: 16),
                    ..._buildTaskSections(),
                    if (_doneCount > 0) const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FollowUpHeroCard extends StatelessWidget {
  const _FollowUpHeroCard({
    required this.totalOpen,
    required this.overdueCount,
    required this.dueSoonCount,
    required this.waitingCount,
    required this.onAddPressed,
    required this.onAskSage,
  });

  final int totalOpen;
  final int overdueCount;
  final int dueSoonCount;
  final int waitingCount;
  final VoidCallback onAddPressed;
  final VoidCallback onAskSage;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            JournalColors.info.withValues(alpha: 0.18),
            JournalColors.bgCard.withValues(alpha: 0.96),
            JournalColors.bgCardAlt.withValues(alpha: 0.94),
          ],
        ),
        border: Border.all(color: JournalColors.borderBright),
        boxShadow: const [
          BoxShadow(
            color: JournalColors.accentGlow,
            blurRadius: 22,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: JournalColors.info.withValues(alpha: 0.14),
                    border: Border.all(color: JournalColors.borderBright),
                  ),
                  child: const Icon(
                    CupertinoIcons.briefcase,
                    color: JournalColors.textPrimary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Operational Pressure',
                        style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Track live threads that need a reply, a follow-up, or a concrete next move.',
                        style: TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _FollowUpMetricPill(
                  label: 'Open',
                  value: '$totalOpen',
                  color: JournalColors.accent,
                ),
                _FollowUpMetricPill(
                  label: 'Overdue',
                  value: '$overdueCount',
                  color: JournalColors.danger,
                ),
                _FollowUpMetricPill(
                  label: 'Due soon',
                  value: '$dueSoonCount',
                  color: JournalColors.severity,
                ),
                _FollowUpMetricPill(
                  label: 'Waiting',
                  value: '$waitingCount',
                  color: JournalColors.info,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AdaptiveButton(
                    style: AdaptiveButtonStyle.prominentGlass,
                    onPressed: onAddPressed,
                    label: 'Add follow-up',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AdaptiveButton(
                    onPressed: onAskSage,
                    label: 'Ask Sage',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowUpMetricPill extends StatelessWidget {
  const _FollowUpMetricPill({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _withAlpha(color, 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _withAlpha(color, 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: _withAlpha(JournalColors.textSecondary, 0.95),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickFollowUpChip extends StatelessWidget {
  const _QuickFollowUpChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: JournalColors.bgCardAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: JournalColors.border),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: JournalColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _FollowUpTaskCard extends StatelessWidget {
  const _FollowUpTaskCard({
    required this.task,
    required this.dateFormat,
    required this.onEdit,
    required this.onDelete,
    required this.onAskSage,
    required this.onStatusChanged,
  });

  final FollowUpTask task;
  final DateFormat dateFormat;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAskSage;
  final Future<void> Function(String status) onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final overdue = task.isOverdue();
    final dueSoon = task.isDueSoon();
    final accent = overdue
        ? JournalColors.danger
        : dueSoon
            ? JournalColors.severity
            : task.isDone
                ? JournalColors.success
                : JournalColors.accent;

    return GlassCard(
      accentBorder: overdue || dueSoon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatusPill(
                          label: FollowUpTaskService.statusLabel(task.status),
                          color: accent,
                        ),
                        _StatusPill(
                          label: FollowUpTaskService.bucketLabel(task.bucket),
                          color: JournalColors.info,
                        ),
                        if (task.followUpAt != null)
                          _StatusPill(
                            label:
                                overdue ? 'Overdue' : 'Follow up ${dateFormat.format(task.followUpAt!)}',
                            color: overdue
                                ? JournalColors.danger
                                : dueSoon
                                    ? JournalColors.severity
                                    : JournalColors.textMuted,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      task.title,
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    if ((task.counterparty ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        task.counterparty!.trim(),
                        style: const TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(34, 34),
                onPressed: onEdit,
                child: const Icon(
                  CupertinoIcons.pencil,
                  color: JournalColors.textSecondary,
                  size: 18,
                ),
              ),
            ],
          ),
          if ((task.nextAction ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'NEXT ACTION',
              style: TextStyle(
                color: JournalColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              task.nextAction!.trim(),
              style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
          if ((task.notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              task.notes!.trim(),
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                'Last touched ${dateFormat.format(task.lastTouchedAt)}',
                style: const TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 12,
                ),
              ),
              if (task.completedAt != null)
                Text(
                  'Completed ${dateFormat.format(task.completedAt!)}',
                  style: const TextStyle(
                    color: JournalColors.success,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniActionChip(
                label: 'Active',
                selected: task.status == 'active',
                onTap: () => onStatusChanged('active'),
              ),
              _MiniActionChip(
                label: 'Waiting',
                selected: task.status == 'waiting',
                onTap: () => onStatusChanged('waiting'),
              ),
              _MiniActionChip(
                label: 'Done',
                selected: task.status == 'done',
                onTap: () => onStatusChanged('done'),
              ),
              _MiniActionChip(
                label: 'Ask Sage',
                selected: false,
                onTap: onAskSage,
              ),
              _MiniActionChip(
                label: 'Delete',
                selected: false,
                destructive: true,
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _withAlpha(color, 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _withAlpha(color, 0.34)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: JournalColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MiniActionChip extends StatelessWidget {
  const _MiniActionChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final bool selected;
  final bool destructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = destructive
        ? _withAlpha(JournalColors.danger, 0.4)
        : selected
            ? JournalColors.borderBright
            : JournalColors.border;
    final bgColor = destructive
        ? _withAlpha(JournalColors.danger, 0.12)
        : selected
            ? _withAlpha(JournalColors.accent, 0.16)
            : JournalColors.bgSurface;
    final textColor = destructive
        ? JournalColors.danger
        : selected
            ? JournalColors.textPrimary
            : JournalColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _FollowUpEditorScreen extends StatefulWidget {
  const _FollowUpEditorScreen({this.task});

  final FollowUpTask? task;

  @override
  State<_FollowUpEditorScreen> createState() => _FollowUpEditorScreenState();
}

class _FollowUpEditorScreenState extends State<_FollowUpEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _counterpartyController;
  late final TextEditingController _nextActionController;
  late final TextEditingController _notesController;

  late String _bucket;
  late String _status;
  late DateTime _lastTouchedAt;
  DateTime? _followUpAt;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    final now = DateTime.now();
    _titleController = TextEditingController(text: task?.title ?? '');
    _counterpartyController =
        TextEditingController(text: task?.counterparty ?? '');
    _nextActionController = TextEditingController(text: task?.nextAction ?? '');
    _notesController = TextEditingController(text: task?.notes ?? '');
    _bucket = task?.bucket ?? 'job_application';
    _status = task?.status ?? 'active';
    _lastTouchedAt = task?.lastTouchedAt ?? now;
    _followUpAt = task?.followUpAt ?? now.add(const Duration(days: 3));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _counterpartyController.dispose();
    _nextActionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required DateTime initialDate,
    required ValueChanged<DateTime> onChanged,
  }) async {
    var selected = initialDate;
    final picked = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (context) => Container(
        height: 320,
        color: JournalColors.bgCard,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: JournalColors.textSecondary),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(selected),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        color: JournalColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: initialDate,
                onDateTimeChanged: (value) => selected = value,
              ),
            ),
          ],
        ),
      ),
    );

    if (picked != null) {
      onChanged(DateTime(picked.year, picked.month, picked.day));
    }
  }

  void _save() {
    final title = _titleController.text.trim();
    final nextAction = _nextActionController.text.trim();

    if (title.isEmpty) {
      setState(() => _error = 'Give this follow-up a title.');
      return;
    }

    if ((_status == 'active' || _status == 'waiting') &&
        nextAction.isEmpty) {
      setState(() => _error = 'Name the exact next action.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final now = DateTime.now();
    final existing = widget.task;
    final task = FollowUpTask(
      id: existing?.id ?? now.microsecondsSinceEpoch.toString(),
      title: title,
      bucket: _bucket,
      status: _status,
      createdAt: existing?.createdAt ?? now,
      lastTouchedAt: _lastTouchedAt,
      counterparty: _normalizedValue(_counterpartyController.text),
      nextAction: _normalizedValue(nextAction),
      notes: _normalizedValue(_notesController.text),
      followUpAt:
          (_status == 'done' || _status == 'archived') ? null : _followUpAt,
      completedAt: _status == 'done' ? (existing?.completedAt ?? now) : null,
    );

    Navigator.of(context).pop(task);
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
        border: const Border(
          bottom: BorderSide(color: JournalColors.border, width: 0.5),
        ),
        middle: Text(
          _isEditing ? 'Edit Follow-Up' : 'New Follow-Up',
          style: const TextStyle(
            color: JournalColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: JournalColors.textSecondary),
          ),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : _save,
          child: const Text(
            'Save',
            style: TextStyle(
              color: JournalColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const GlassCard(
              accentBorder: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Live follow-up thread',
                    style: TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Keep this scoped to something that needs another touch, response, deadline, or push. If it is part of your bigger life-transition roadmap, it belongs in Exit Plan instead.',
                    style: TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Core'),
            const SizedBox(height: 12),
            _LabeledField(
              label: 'Title',
              child: _FollowUpTextField(
                controller: _titleController,
                placeholder: 'Senior Flutter role at Acme',
              ),
            ),
            const SizedBox(height: 12),
            _LabeledField(
              label: 'Company or person',
              child: _FollowUpTextField(
                controller: _counterpartyController,
                placeholder: 'Acme / recruiter / hiring manager',
              ),
            ),
            const SizedBox(height: 12),
            _LabeledField(
              label: 'Next action',
              child: _FollowUpTextField(
                controller: _nextActionController,
                placeholder: 'Email recruiter, send portfolio, prep answers',
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Type'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final bucket in _followUpBuckets)
                  _SelectableChip(
                    label: FollowUpTaskService.bucketLabel(bucket),
                    selected: _bucket == bucket,
                    onTap: () => setState(() => _bucket = bucket),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Status'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final status in _followUpStatuses)
                  _SelectableChip(
                    label: FollowUpTaskService.statusLabel(status),
                    selected: _status == status,
                    onTap: () => setState(() => _status = status),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Dates'),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(
                children: [
                  _DateRow(
                    label: 'Last touched',
                    value: dateFormat.format(_lastTouchedAt),
                    onTap: () => _pickDate(
                      initialDate: _lastTouchedAt,
                      onChanged: (value) => setState(() => _lastTouchedAt = value),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DateRow(
                    label: 'Follow up on',
                    value: _followUpAt == null
                        ? 'No date'
                        : dateFormat.format(_followUpAt!),
                    onTap: _status == 'done' || _status == 'archived'
                        ? null
                        : () => _pickDate(
                              initialDate: _followUpAt ?? DateTime.now(),
                              onChanged: (value) =>
                                  setState(() => _followUpAt = value),
                            ),
                    trailing: (_status == 'done' || _status == 'archived')
                        ? null
                        : CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            onPressed: () => setState(() => _followUpAt = null),
                            child: const Text(
                              'Clear',
                              style: TextStyle(color: JournalColors.textMuted),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Notes'),
            const SizedBox(height: 12),
            _LabeledField(
              label: 'Context',
              child: _FollowUpTextField(
                controller: _notesController,
                placeholder:
                    'What happened, what you sent, what you are waiting on, or what makes this hard to follow through on.',
                minLines: 5,
                maxLines: null,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: const TextStyle(
                  color: JournalColors.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? _normalizedValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: JournalColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _FollowUpTextField extends StatelessWidget {
  const _FollowUpTextField({
    required this.controller,
    required this.placeholder,
    this.minLines,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String placeholder;
  final int? minLines;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      style: const TextStyle(
        color: JournalColors.textPrimary,
        fontSize: 15,
      ),
      placeholder: placeholder,
      placeholderStyle: const TextStyle(color: JournalColors.textMuted),
      decoration: BoxDecoration(
        color: JournalColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JournalColors.border),
      ),
    );
  }
}

class _SelectableChip extends StatelessWidget {
  const _SelectableChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? _withAlpha(JournalColors.accent, 0.16)
              : JournalColors.bgCardAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? JournalColors.borderBright : JournalColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? JournalColors.textPrimary : JournalColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    this.onTap,
    this.trailing,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
        if (onTap != null)
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onTap,
            child: const Text(
              'Pick',
              style: TextStyle(color: JournalColors.accent),
            ),
          ),
      ],
    );
  }
}
