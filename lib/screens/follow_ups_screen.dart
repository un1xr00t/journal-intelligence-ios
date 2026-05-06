import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../services/follow_up_tasks_service.dart';
import '../services/local_storage_paths.dart';
import '../services/notification_nudge_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';
import 'sage_screen.dart';

const _followUpBuckets = <String>[
  'apartment',
  'housing',
  'legal',
  'finance',
  'support',
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

const _followUpPriorities = <String>[
  'urgent',
  'high',
  'normal',
  'low',
];

const _filterLabels = <String>[
  'Due',
  'Active',
  'Waiting',
  'Done',
];

const _quickFollowUps = <({
  String label,
  String title,
  String bucket,
  String status,
  String action
})>[
  (
    label: 'Apartment',
    title: 'Follow up on an apartment lead',
    bucket: 'apartment',
    status: 'active',
    action: 'Send the message, book the tour, or submit the application',
  ),
  (
    label: 'Housing',
    title: 'Move a housing thread forward',
    bucket: 'housing',
    status: 'active',
    action: 'Make the call, send the documents, or widen the search',
  ),
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

final _followUpPreviewByteCache = <String, Uint8List>{};

enum _FollowUpAttachmentSource {
  photoLibrary,
  camera,
  files,
}

Widget _followUpTaskSwipeBackground({
  required Alignment alignment,
  required Color color,
  required IconData icon,
  required String label,
}) {
  final isRight = alignment == Alignment.centerRight;
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      color: _withAlpha(color, 0.14),
    ),
    padding: EdgeInsets.only(left: isRight ? 0 : 20, right: isRight ? 20 : 0),
    alignment: alignment,
    child: Row(
      mainAxisAlignment:
          isRight ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!isRight) Icon(icon, color: color, size: 18),
        if (!isRight) const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (isRight) const SizedBox(width: 8),
        if (isRight) Icon(icon, color: color, size: 18),
      ],
    ),
  );
}

String _attachmentExtensionFromName(String name) {
  final trimmed = name.trim();
  final dot = trimmed.lastIndexOf('.');
  if (dot <= 0 || dot == trimmed.length - 1) return '';
  return trimmed.substring(dot + 1).toLowerCase();
}

String _attachmentNameFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash >= 0 ? normalized.substring(slash + 1) : normalized;
}

String _sanitizeAttachmentFileName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'attachment';
  return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

Future<FollowUpAttachment?> _persistFollowUpAttachment(
  FollowUpAttachment attachment,
) async {
  final sourcePath = attachment.path.trim();
  if (sourcePath.isEmpty) return null;
  final source = File(sourcePath);
  if (!await source.exists()) return null;

  final supportDir = await resolveAppSupportDirectory();
  final attachmentsDir = Directory('${supportDir.path}/follow_up_attachments');
  await attachmentsDir.create(recursive: true);

  final extension = attachment.extension.trim().toLowerCase();
  final rawName = attachment.name.trim().isNotEmpty
      ? attachment.name.trim()
      : _attachmentNameFromPath(sourcePath);
  final safeName = _sanitizeAttachmentFileName(rawName);
  final dot = safeName.lastIndexOf('.');
  final baseName = dot > 0 ? safeName.substring(0, dot) : safeName;
  final fileName = extension.isEmpty
      ? safeName
      : '${baseName}_${DateTime.now().microsecondsSinceEpoch}.$extension';
  final targetPath = '${attachmentsDir.path}/$fileName';

  if (source.absolute.path == targetPath) {
    return attachment;
  }

  final copied = await source.copy(targetPath);
  String? previewPath = attachment.previewPath;
  String? previewBase64 = attachment.previewBase64;
  if (attachment.isImage) {
    final previewBytes = await _generateFollowUpPreviewBytes(copied);
    if (previewBytes != null && previewBytes.isNotEmpty) {
      previewBase64 = base64Encode(previewBytes);
      final previewFile = File(
        '${attachmentsDir.path}/${baseName}_${DateTime.now().microsecondsSinceEpoch}_preview.jpg',
      );
      await previewFile.writeAsBytes(previewBytes, flush: true);
      previewPath = previewFile.path;
    }
  }
  return FollowUpAttachment(
    name: rawName,
    path: copied.path,
    extension: extension,
    remoteId: attachment.remoteId,
    previewPath: previewPath,
    previewBase64: previewBase64,
    imageBase64: attachment.imageBase64,
  );
}

Future<Uint8List?> _generateFollowUpPreviewBytes(File file) async {
  try {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final baked = img.bakeOrientation(decoded);
    final resized = img.copyResize(
      baked,
      width: baked.width >= baked.height ? 320 : null,
      height: baked.height > baked.width ? 320 : null,
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodeJpg(resized, quality: 72));
  } catch (_) {
    return null;
  }
}

Uint8List? _attachmentPreviewBytes(FollowUpAttachment attachment) {
  final preview = attachment.previewBase64?.trim();
  final previewPath = attachment.previewPath?.trim();
  final cacheKey = [
    attachment.path.trim(),
    previewPath ?? '',
    preview == null ? '' : '${preview.length}:${preview.hashCode}',
  ].join('|');
  final cached = _followUpPreviewByteCache[cacheKey];
  if (cached != null) return cached;

  if (previewPath != null && previewPath.isNotEmpty) {
    final previewFile = File(previewPath);
    if (previewFile.existsSync()) {
      try {
        final bytes = previewFile.readAsBytesSync();
        _followUpPreviewByteCache[cacheKey] = bytes;
        return bytes;
      } catch (_) {}
    }
  }
  if (preview == null || preview.isEmpty) return null;
  try {
    final bytes = base64Decode(preview);
    _followUpPreviewByteCache[cacheKey] = bytes;
    return bytes;
  } catch (_) {
    return null;
  }
}

class FollowUpsScreen extends StatefulWidget {
  const FollowUpsScreen({super.key});

  @override
  State<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends State<FollowUpsScreen> {
  final _service = FollowUpTaskService();
  final _nudgeService = NotificationNudgeService();
  final _dateTimeFormat = DateFormat('MMM d, yyyy · h:mm a');

  String? _error;
  bool _showExitPlanNote = true;
  int _filterIndex = 0;
  List<FollowUpTask> _tasks = const [];
  final Set<String> _expandedTaskIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);

    try {
      final tasks = await _service.loadTasks();
      if (!mounted) return;
      setState(() => _tasks = tasks);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load your follow-ups right now.');
    }
  }

  Future<void> _saveTasks(List<FollowUpTask> tasks) async {
    final sorted = List<FollowUpTask>.from(tasks)
      ..sort(FollowUpTaskService.compareTasks);
    if (!mounted) return;
    setState(() => _tasks = sorted);

    try {
      await _service.saveTasks(sorted);
      unawaited(_refreshFollowUpReminders());
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not save your follow-ups right now.');
    }
  }

  Future<void> _refreshFollowUpReminders() async {
    try {
      await _nudgeService.refreshFollowUpReminders();
    } catch (_) {}
  }

  Future<void> _openEditor(
      {FollowUpTask? existing, FollowUpTask? draft}) async {
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

  Future<FollowUpTask> _addComment(
    FollowUpTask task, {
    required String body,
    required List<FollowUpAttachment> attachments,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return task;
    final now = DateTime.now();
    final comment = FollowUpComment(
      id: now.microsecondsSinceEpoch.toString(),
      body: trimmed,
      createdAt: now,
      attachments: attachments,
    );
    final updated = task.copyWith(
      comments: [...task.comments, comment],
      lastTouchedAt: now,
    );
    await _updateTask(updated);
    return updated;
  }

  Future<FollowUpTask> _editComment(
    FollowUpTask task, {
    required FollowUpComment comment,
    required String body,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return task;
    final now = DateTime.now();
    final nextComments = task.comments
        .map(
          (item) => item.id == comment.id
              ? item.copyWith(body: trimmed, createdAt: item.createdAt)
              : item,
        )
        .toList();
    final updated = task.copyWith(
      comments: nextComments,
      lastTouchedAt: now,
    );
    await _updateTask(updated);
    return updated;
  }

  Future<FollowUpTask> _saveTaskFromWorkspace(FollowUpTask task) async {
    await _updateTask(task);
    return task;
  }

  Future<void> _openWorkspace(FollowUpTask task) async {
    await Navigator.push<void>(
      context,
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: _FollowUpWorkspaceScreen(
            task: task,
            onSaveTask: _saveTaskFromWorkspace,
            onAddComment: (
                {required task, required body, required attachments}) async {
              return _addComment(
                task,
                body: body,
                attachments: attachments,
              );
            },
            onEditComment: (
                {required task, required comment, required body}) async {
              return _editComment(
                task,
                comment: comment,
                body: body,
              );
            },
            onDeleteTask: () => _deleteTask(task),
            onAskSage: (item) => _openSagePressure(task: item),
          ),
        ),
      ),
    );
  }

  Future<void> _openSagePressure({FollowUpTask? task}) {
    final prefill = task == null
        ? 'Use my Follow-Ups context and tell me what is overdue, what I am avoiding, and exactly what I need to follow up on next.'
        : FollowUpTaskService.sagePressurePrompt(
            task,
            frame: 'Pressure me about this follow-up item.',
          );
    return pushSageScreen(
      context,
      handoff: SageHandoff(
        prefillText: prefill,
        initialAttachments: task == null
            ? const []
            : task.attachments
                .map(
                  (item) => SageHandoffAttachment(
                    name: item.name,
                    path: item.path,
                    extension: item.extension,
                  ),
                )
                .toList(),
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
        priority: 'normal',
        createdAt: now,
        lastTouchedAt: now,
        nextAction: preset.action,
        followUpAt: DateTime(now.year, now.month, now.day + 3),
      ),
    );
  }

  List<FollowUpTask> get _openTasks =>
      _tasks.where((task) => task.isOpen).toList();

  int get _overdueCount => _openTasks.where((task) => task.isOverdue()).length;

  int get _dueSoonCount => _openTasks.where((task) => task.isDueSoon()).length;

  int get _waitingCount => _openTasks.where((task) => task.isWaiting).length;

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
            .where(
                (task) => task.isOverdue() || task.isDueSoon() || task.isActive)
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
        .where(
            (task) => task.isActive && !task.isOverdue() && !task.isDueSoon())
        .toList();
    final waiting = filtered
        .where(
            (task) => task.isWaiting && !task.isOverdue() && !task.isDueSoon())
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
            child: Dismissible(
              key: ValueKey('follow-up-task-${task.id}'),
              direction: DismissDirection.horizontal,
              confirmDismiss: (direction) async {
                if (direction == DismissDirection.startToEnd) {
                  await _deleteTask(task);
                } else {
                  _openEditor(existing: task);
                }
                return false;
              },
              background: _followUpTaskSwipeBackground(
                alignment: Alignment.centerLeft,
                color: JournalColors.danger,
                icon: CupertinoIcons.trash,
                label: 'Delete',
              ),
              secondaryBackground: _followUpTaskSwipeBackground(
                alignment: Alignment.centerRight,
                color: JournalColors.accent,
                icon: CupertinoIcons.pencil,
                label: 'Edit',
              ),
              child: _FollowUpTaskCard(
                task: task,
                dateTimeFormat: _dateTimeFormat,
                onDelete: () => _deleteTask(task),
                onAskSage: () => _openSagePressure(task: task),
                onOpenWorkspace: () => _openWorkspace(task),
                expanded: _expandedTaskIds.contains(task.id),
                onToggleExpanded: () {
                  setState(() {
                    if (!_expandedTaskIds.remove(task.id)) {
                      _expandedTaskIds.add(task.id);
                    }
                  });
                },
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
                  if (_error != null) ...[
                    const SizedBox(height: 24),
                    GlassCard(
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
                              style:
                                  TextStyle(color: JournalColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
    required this.dateTimeFormat,
    required this.onDelete,
    required this.onAskSage,
    required this.onOpenWorkspace,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onStatusChanged,
  });

  final FollowUpTask task;
  final DateFormat dateTimeFormat;
  final VoidCallback onDelete;
  final VoidCallback onAskSage;
  final VoidCallback onOpenWorkspace;
  final bool expanded;
  final VoidCallback onToggleExpanded;
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
    final heroPhoto = task.attachments.where((item) => item.isImage).isNotEmpty
        ? task.attachments.firstWhere((item) => item.isImage)
        : null;
    final nextAction = task.nextAction?.trim();
    final notes = task.notes?.trim();

    return GlassCard(
      accentBorder: overdue || dueSoon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (heroPhoto != null) ...[
                _FollowUpTaskPhotoPeek(attachment: heroPhoto),
                const SizedBox(width: 14),
              ],
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
                          label:
                              FollowUpTaskService.priorityLabel(task.priority),
                          color: _priorityColor(task.priority),
                        ),
                        _StatusPill(
                          label: FollowUpTaskService.bucketLabel(task.bucket),
                          color: JournalColors.info,
                        ),
                        if (task.effectiveFollowUpAt != null)
                          _StatusPill(
                            label: overdue
                                ? 'Overdue'
                                : 'Follow up ${dateTimeFormat.format(task.effectiveFollowUpAt!)}',
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
                    if (nextAction != null && nextAction.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        nextAction,
                        maxLines: expanded ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 14,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if ((task.counterparty ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
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
              Column(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(34, 34),
                    onPressed: onToggleExpanded,
                    child: Icon(
                      expanded
                          ? CupertinoIcons.chevron_up
                          : CupertinoIcons.chevron_down,
                      color: JournalColors.textSecondary,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                'Last touched ${dateTimeFormat.format(task.lastTouchedAt)}',
                style: const TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 12,
                ),
              ),
              if (task.completedAt != null)
                Text(
                  'Completed ${dateTimeFormat.format(task.completedAt!)}',
                  style: const TextStyle(
                    color: JournalColors.success,
                    fontSize: 12,
                  ),
                ),
              if (task.attachments.isNotEmpty)
                Text(
                  '${task.attachments.length} ${task.attachments.length == 1 ? 'photo' : 'photos'}',
                  style: const TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              if (task.comments.isNotEmpty)
                Text(
                  '${task.comments.length} ${task.comments.length == 1 ? 'update' : 'updates'}',
                  style: const TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onToggleExpanded,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: _withAlpha(JournalColors.bgSurface, 0.78),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: JournalColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    expanded ? 'Hide full task' : 'Show full task',
                    style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    color: JournalColors.textSecondary,
                    size: 13,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (nextAction != null && nextAction.isNotEmpty) ...[
                  const SizedBox(height: 16),
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
                    nextAction,
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ],
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    notes,
                    style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: onOpenWorkspace,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: _withAlpha(JournalColors.bgCardAlt, 0.88),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: JournalColors.borderBright),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: _withAlpha(JournalColors.accent, 0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _withAlpha(JournalColors.accent, 0.4),
                            ),
                          ),
                          child: const Icon(
                            CupertinoIcons.square_grid_2x2,
                            color: JournalColors.accent,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Open workspace',
                                style: TextStyle(
                                  color: JournalColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${task.attachments.length} ${task.attachments.length == 1 ? 'photo' : 'photos'} · ${task.comments.length} ${task.comments.length == 1 ? 'update' : 'updates'}',
                                style: const TextStyle(
                                  color: JournalColors.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          CupertinoIcons.chevron_right,
                          color: JournalColors.textSecondary,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
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
            crossFadeState:
                expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

class _FollowUpTaskPhotoPeek extends StatelessWidget {
  const _FollowUpTaskPhotoPeek({required this.attachment});

  final FollowUpAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final previewBytes = _attachmentPreviewBytes(attachment);
    return Container(
      width: 72,
      height: 82,
      decoration: BoxDecoration(
        color: JournalColors.bgCardAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: JournalColors.borderBright),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (previewBytes != null)
            Image.memory(previewBytes, fit: BoxFit.cover)
          else if (attachment.path.isNotEmpty)
            Image.file(
              File(attachment.path),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const _FollowUpAttachmentIcon(
                isImage: true,
                size: 72,
                iconSize: 24,
              ),
            )
          else
            const _FollowUpAttachmentIcon(
              isImage: true,
              size: 72,
              iconSize: 24,
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _withAlpha(JournalColors.bgBase, 0),
                    _withAlpha(JournalColors.bgBase, 0.54),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned(
            left: 7,
            bottom: 7,
            child: _FollowUpAttachmentBadge(label: attachment.displayExtension),
          ),
        ],
      ),
    );
  }
}

class _FollowUpWorkspaceScreen extends StatefulWidget {
  const _FollowUpWorkspaceScreen({
    required this.task,
    required this.onSaveTask,
    required this.onAddComment,
    required this.onEditComment,
    required this.onDeleteTask,
    required this.onAskSage,
  });

  final FollowUpTask task;
  final Future<FollowUpTask> Function(FollowUpTask task) onSaveTask;
  final Future<FollowUpTask> Function({
    required FollowUpTask task,
    required String body,
    required List<FollowUpAttachment> attachments,
  }) onAddComment;
  final Future<FollowUpTask> Function({
    required FollowUpTask task,
    required FollowUpComment comment,
    required String body,
  }) onEditComment;
  final Future<void> Function() onDeleteTask;
  final Future<void> Function(FollowUpTask task) onAskSage;

  @override
  State<_FollowUpWorkspaceScreen> createState() =>
      _FollowUpWorkspaceScreenState();
}

class _FollowUpWorkspaceScreenState extends State<_FollowUpWorkspaceScreen> {
  late FollowUpTask _task;
  final _dateTimeFormat = DateFormat('MMM d, yyyy · h:mm a');

  @override
  void initState() {
    super.initState();
    _task = widget.task;
  }

  Future<void> _saveTask(FollowUpTask updated) async {
    final saved = await widget.onSaveTask(updated);
    if (!mounted) return;
    setState(() => _task = saved);
  }

  Future<void> _editTask() async {
    final result = await Navigator.push<FollowUpTask>(
      context,
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: _FollowUpEditorScreen(task: _task),
        ),
      ),
    );
    if (result == null) return;
    await _saveTask(result);
  }

  @override
  Widget build(BuildContext context) {
    final overdue = _task.isOverdue();
    final dueSoon = _task.isDueSoon();
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final bottomSafeArea = mediaQuery.padding.bottom;
    final listBottomPadding = bottomSafeArea + keyboardInset + 32;

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
        border: const Border(
          bottom: BorderSide(color: JournalColors.border, width: 0.5),
        ),
        middle: const Text(
          'Task Workspace',
          style: TextStyle(
            color: JournalColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _editTask,
          child: const Icon(
            CupertinoIcons.pencil,
            color: JournalColors.textSecondary,
            size: 18,
          ),
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 12, 20, listBottomPadding),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              GlassCard(
                accentBorder: overdue || dueSoon,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatusPill(
                          label: FollowUpTaskService.statusLabel(_task.status),
                          color: overdue
                              ? JournalColors.danger
                              : dueSoon
                                  ? JournalColors.severity
                                  : JournalColors.accent,
                        ),
                        _StatusPill(
                          label: FollowUpTaskService.priorityLabel(
                            _task.priority,
                          ),
                          color: _priorityColor(_task.priority),
                        ),
                        _StatusPill(
                          label: FollowUpTaskService.bucketLabel(_task.bucket),
                          color: JournalColors.info,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _task.title,
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    if ((_task.counterparty ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _task.counterparty!.trim(),
                        style: const TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if ((_task.nextAction ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
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
                        _task.nextAction!.trim(),
                        style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 16,
                          height: 1.45,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if ((_task.notes ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        _task.notes!.trim(),
                        style: const TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_task.attachments.isNotEmpty) ...[
                const SizedBox(height: 24),
                const SectionHeader(title: 'Photos'),
                const SizedBox(height: 12),
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _task.attachments.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, index) => _FollowUpAttachmentTile(
                      attachment: _task.attachments[index],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Text(
                          'Last touched ${_dateTimeFormat.format(_task.lastTouchedAt)}',
                          style: const TextStyle(
                            color: JournalColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        if (_task.effectiveFollowUpAt != null)
                          Text(
                            'Follow up ${_dateTimeFormat.format(_task.effectiveFollowUpAt!)}',
                            style: const TextStyle(
                              color: JournalColors.textMuted,
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
                          selected: _task.status == 'active',
                          onTap: () => _saveTask(
                            _task.copyWith(
                              status: 'active',
                              lastTouchedAt: DateTime.now(),
                              clearCompletedAt: true,
                            ),
                          ),
                        ),
                        _MiniActionChip(
                          label: 'Waiting',
                          selected: _task.status == 'waiting',
                          onTap: () => _saveTask(
                            _task.copyWith(
                              status: 'waiting',
                              lastTouchedAt: DateTime.now(),
                              clearCompletedAt: true,
                            ),
                          ),
                        ),
                        _MiniActionChip(
                          label: 'Done',
                          selected: _task.status == 'done',
                          onTap: () => _saveTask(
                            _task.copyWith(
                              status: 'done',
                              lastTouchedAt: DateTime.now(),
                              completedAt: DateTime.now(),
                            ),
                          ),
                        ),
                        _MiniActionChip(
                          label: 'Ask Sage',
                          selected: false,
                          onTap: () => widget.onAskSage(_task),
                        ),
                        _MiniActionChip(
                          label: 'Delete',
                          selected: false,
                          destructive: true,
                          onTap: () async {
                            await widget.onDeleteTask();
                            if (!mounted) return;
                            Navigator.of(this.context).pop();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              GlassCard(
                child: _FollowUpCommentsSection(
                  comments: _task.comments,
                  dateTimeFormat: _dateTimeFormat,
                  onSubmit: ({required body, required attachments}) async {
                    final updated = await widget.onAddComment(
                      task: _task,
                      body: body,
                      attachments: attachments,
                    );
                    if (!mounted) return;
                    setState(() => _task = updated);
                  },
                  onEdit: (comment, body) async {
                    final updated = await widget.onEditComment(
                      task: _task,
                      comment: comment,
                      body: body,
                    );
                    if (!mounted) return;
                    setState(() => _task = updated);
                  },
                ),
              ),
            ],
          ),
        ),
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

class _FollowUpCommentsSection extends StatefulWidget {
  const _FollowUpCommentsSection({
    required this.comments,
    required this.dateTimeFormat,
    required this.onSubmit,
    required this.onEdit,
  });

  final List<FollowUpComment> comments;
  final DateFormat dateTimeFormat;
  final Future<void> Function({
    required String body,
    required List<FollowUpAttachment> attachments,
  }) onSubmit;
  final Future<void> Function(FollowUpComment comment, String body) onEdit;

  @override
  State<_FollowUpCommentsSection> createState() =>
      _FollowUpCommentsSectionState();
}

class _FollowUpCommentsSectionState extends State<_FollowUpCommentsSection> {
  final _commentController = TextEditingController();
  final _imagePicker = ImagePicker();

  List<FollowUpAttachment> _attachments = const [];
  bool _submitting = false;
  bool _pickingAttachments = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _chooseAttachmentSource() async {
    if (_submitting || _pickingAttachments) return;
    final source = await showCupertinoModalPopup<_FollowUpAttachmentSource>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Add Comment Photo'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(context, _FollowUpAttachmentSource.photoLibrary),
            child: const Text('Photo Library'),
          ),
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(context, _FollowUpAttachmentSource.camera),
            child: const Text('Take Photo'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (source == null) return;
    switch (source) {
      case _FollowUpAttachmentSource.photoLibrary:
        await _pickPhotosFromLibrary();
        break;
      case _FollowUpAttachmentSource.camera:
        await _pickPhotoFromCamera();
        break;
      case _FollowUpAttachmentSource.files:
        break;
    }
  }

  Future<void> _pickPhotosFromLibrary() async {
    setState(() => _pickingAttachments = true);
    try {
      final picked = await _imagePicker.pickMultiImage(imageQuality: 85);
      await _addAttachments(
        picked
            .map(
              (item) => FollowUpAttachment(
                name: item.name,
                path: item.path,
                extension: _attachmentExtensionFromName(item.name),
              ),
            )
            .toList(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _pickingAttachments = false);
    }
  }

  Future<void> _pickPhotoFromCamera() async {
    setState(() => _pickingAttachments = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      await _addAttachments([
        if (picked != null)
          FollowUpAttachment(
            name: picked.name,
            path: picked.path,
            extension: _attachmentExtensionFromName(picked.name),
          ),
      ]);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pickingAttachments = false);
    }
  }

  Future<void> _addAttachments(List<FollowUpAttachment> items) async {
    if (items.isEmpty) {
      if (!mounted) return;
      setState(() => _pickingAttachments = false);
      return;
    }
    final persisted = <FollowUpAttachment>[];
    for (final item in items) {
      final stable = await _persistFollowUpAttachment(item);
      if (stable != null) persisted.add(stable);
    }
    if (!mounted) return;
    setState(() {
      _attachments = [
        ..._attachments,
        ...persisted.where(
          (item) => !_attachments.any((existing) => existing.path == item.path),
        ),
      ];
      _pickingAttachments = false;
    });
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments = List<FollowUpAttachment>.from(_attachments)
        ..removeAt(index);
    });
  }

  Future<void> _submit() async {
    final body = _commentController.text.trim();
    if ((body.isEmpty && _attachments.isEmpty) || _submitting) return;
    setState(() => _submitting = true);
    await widget.onSubmit(body: body, attachments: _attachments);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _attachments = const [];
    });
    _commentController.clear();
  }

  Future<void> _editComment(FollowUpComment comment) async {
    final controller = TextEditingController(text: comment.body);
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Edit Comment'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            minLines: 3,
            maxLines: 6,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 14,
            ),
            placeholder: 'Update this comment',
            placeholderStyle: const TextStyle(color: JournalColors.textMuted),
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: JournalColors.border),
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = result?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == comment.body.trim()) {
      return;
    }
    await widget.onEdit(comment, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'COMMENTS',
              style: TextStyle(
                color: JournalColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            Text(
              '${widget.comments.length}',
              style: const TextStyle(
                color: JournalColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (widget.comments.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final comment in widget.comments.reversed) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _withAlpha(JournalColors.bgSurface, 0.86),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: JournalColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.dateTimeFormat.format(comment.createdAt),
                          style: const TextStyle(
                            color: JournalColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(30, 24),
                        onPressed: () => _editComment(comment),
                        child: const Icon(
                          CupertinoIcons.pencil,
                          color: JournalColors.textMuted,
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                  if (comment.body.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      comment.body.trim(),
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                  if (comment.attachments.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: comment.attachments.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, index) => _FollowUpAttachmentTile(
                          attachment: comment.attachments[index],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
        const SizedBox(height: 10),
        if (_attachments.isNotEmpty) ...[
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _attachments.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, index) => _FollowUpAttachmentTile(
                attachment: _attachments[index],
                onRemove: () => _removeAttachment(index),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        CupertinoTextField(
          controller: _commentController,
          minLines: 2,
          maxLines: 5,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          style: const TextStyle(
            color: JournalColors.textPrimary,
            fontSize: 14,
          ),
          placeholder: 'Add a comment, update, or call note',
          placeholderStyle: const TextStyle(color: JournalColors.textMuted),
          decoration: BoxDecoration(
            color: JournalColors.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: JournalColors.border),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            GestureDetector(
              onTap: _pickingAttachments ? null : _chooseAttachmentSource,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.bgSurface, 0.92),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: JournalColors.border),
                ),
                child: _pickingAttachments
                    ? const CupertinoActivityIndicator(
                        color: JournalColors.accent,
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.photo,
                            color: JournalColors.textSecondary,
                            size: 15,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Photo',
                            style: TextStyle(
                              color: JournalColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _submitting ? null : _submit,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.accent, 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: JournalColors.borderBright),
                ),
                child: _submitting
                    ? const CupertinoActivityIndicator(
                        color: JournalColors.accent,
                      )
                    : const Text(
                        'Add Comment',
                        style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
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
  final _imagePicker = ImagePicker();
  late final TextEditingController _titleController;
  late final TextEditingController _counterpartyController;
  late final TextEditingController _nextActionController;
  late final TextEditingController _notesController;

  List<FollowUpAttachment> _attachments = const [];
  late String _bucket;
  late String _status;
  late String _priority;
  late DateTime _lastTouchedAt;
  DateTime? _followUpAt;
  bool _followUpTimeSet = false;
  bool _pickingAttachments = false;
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
    _priority = task?.priority ?? 'normal';
    _lastTouchedAt = task?.lastTouchedAt ?? now;
    _followUpTimeSet = task?.followUpTimeSet ?? false;
    _followUpAt =
        task?.followUpAt ?? DateTime(now.year, now.month, now.day + 3);
    _attachments = List<FollowUpAttachment>.from(task?.attachments ?? const []);
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

  Future<void> _pickTime({
    required DateTime initialDate,
    required ValueChanged<DateTime> onChanged,
  }) async {
    var selected = DateTime(2024, 1, 1, initialDate.hour, initialDate.minute);
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
                mode: CupertinoDatePickerMode.time,
                initialDateTime: selected,
                use24hFormat: false,
                onDateTimeChanged: (value) => selected = value,
              ),
            ),
          ],
        ),
      ),
    );

    if (picked != null) {
      onChanged(
        DateTime(
          initialDate.year,
          initialDate.month,
          initialDate.day,
          picked.hour,
          picked.minute,
        ),
      );
    }
  }

  DateTime _defaultFollowUpForPriority(DateTime date, String priority) {
    final day = DateTime(date.year, date.month, date.day);
    final (hour, minute) = switch (priority) {
      'urgent' => (8, 30),
      'high' => (10, 0),
      'low' => (18, 0),
      _ => (13, 0),
    };
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  DateTime? get _effectiveFollowUpAt {
    final followUp = _followUpAt;
    if (followUp == null) return null;
    if (_followUpTimeSet) return followUp;
    return _defaultFollowUpForPriority(followUp, _priority);
  }

  void _save() {
    final title = _titleController.text.trim();
    final nextAction = _nextActionController.text.trim();

    if (title.isEmpty) {
      setState(() => _error = 'Give this follow-up a title.');
      return;
    }

    if ((_status == 'active' || _status == 'waiting') && nextAction.isEmpty) {
      setState(() => _error = 'Name the exact next action.');
      return;
    }

    if ((_status == 'active' || _status == 'waiting') && _followUpAt == null) {
      setState(() => _error = 'Pick when this follow-up should hit you.');
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
      priority: _priority,
      createdAt: existing?.createdAt ?? now,
      lastTouchedAt: _lastTouchedAt,
      counterparty: _normalizedValue(_counterpartyController.text),
      nextAction: _normalizedValue(nextAction),
      notes: _normalizedValue(_notesController.text),
      followUpAt: (_status == 'done' || _status == 'archived')
          ? null
          : _effectiveFollowUpAt,
      followUpTimeSet: _followUpTimeSet,
      completedAt: _status == 'done' ? (existing?.completedAt ?? now) : null,
      attachments: _attachments,
    );

    Navigator.of(context).pop(task);
  }

  Future<void> _chooseAttachmentSource() async {
    if (_saving || _pickingAttachments) return;
    final source = await showCupertinoModalPopup<_FollowUpAttachmentSource>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Add Attachment'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(context, _FollowUpAttachmentSource.photoLibrary),
            child: const Text('Photo Library'),
          ),
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(context, _FollowUpAttachmentSource.camera),
            child: const Text('Take Photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(context, _FollowUpAttachmentSource.files),
            child: const Text('Browse Files'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (source == null) return;
    switch (source) {
      case _FollowUpAttachmentSource.photoLibrary:
        await _pickPhotosFromLibrary();
        break;
      case _FollowUpAttachmentSource.camera:
        await _pickPhotoFromCamera();
        break;
      case _FollowUpAttachmentSource.files:
        await _pickFileAttachments();
        break;
    }
  }

  Future<void> _pickPhotosFromLibrary() async {
    if (_saving || _pickingAttachments) return;
    setState(() => _pickingAttachments = true);
    try {
      final picked = await _imagePicker.pickMultiImage(imageQuality: 85);
      await _addAttachmentsFromPaths(
        picked
            .map(
              (item) => FollowUpAttachment(
                name: item.name,
                path: item.path,
                extension: _attachmentExtensionFromName(item.name),
              ),
            )
            .toList(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _pickingAttachments = false);
    }
  }

  Future<void> _pickPhotoFromCamera() async {
    if (_saving || _pickingAttachments) return;
    setState(() => _pickingAttachments = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      await _addAttachmentsFromPaths([
        if (picked != null)
          FollowUpAttachment(
            name: picked.name,
            path: picked.path,
            extension: _attachmentExtensionFromName(picked.name),
          ),
      ]);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pickingAttachments = false);
    }
  }

  Future<void> _pickFileAttachments() async {
    if (_saving || _pickingAttachments) return;
    setState(() => _pickingAttachments = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
        type: FileType.any,
      );
      final selected = result?.files ?? const <PlatformFile>[];
      await _addAttachmentsFromPaths(
        selected
            .where((file) => (file.path ?? '').trim().isNotEmpty)
            .map(
              (file) => FollowUpAttachment(
                name: file.name.trim().isNotEmpty
                    ? file.name
                    : _attachmentNameFromPath(file.path!),
                path: file.path!,
                extension: _attachmentExtensionFromName(file.name),
              ),
            )
            .toList(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _pickingAttachments = false);
    }
  }

  Future<void> _addAttachmentsFromPaths(List<FollowUpAttachment> items) async {
    if (items.isEmpty) {
      if (!mounted) return;
      setState(() => _pickingAttachments = false);
      return;
    }
    final persisted = <FollowUpAttachment>[];
    for (final item in items) {
      final stable = await _persistFollowUpAttachment(item);
      if (stable != null) persisted.add(stable);
    }
    if (!mounted) return;
    final next = List<FollowUpAttachment>.from(_attachments);
    for (final item in persisted) {
      if (item.path.trim().isEmpty) continue;
      final exists = next.any((existing) => existing.path == item.path);
      if (!exists) next.add(item);
    }
    setState(() {
      _attachments = next;
      _pickingAttachments = false;
    });
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments = List<FollowUpAttachment>.from(_attachments)
        ..removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');

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
                    'Keep this scoped to something that needs another touch, response, deadline, or push. This can be job search, apartment hunting, housing, legal, money, or personal logistics. Priority controls how hard the app nudges you. If you do not set a time, the reminder defaults from priority.',
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
                placeholder: 'Apartment tour follow-up with Oak Street',
              ),
            ),
            const SizedBox(height: 12),
            _LabeledField(
              label: 'Company or person',
              child: _FollowUpTextField(
                controller: _counterpartyController,
                placeholder: 'Leasing agent / recruiter / hiring manager',
              ),
            ),
            const SizedBox(height: 12),
            _LabeledField(
              label: 'Next action',
              child: _FollowUpTextField(
                controller: _nextActionController,
                placeholder: 'Send the message, book the tour, submit docs',
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
            const SectionHeader(title: 'Priority'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final priority in _followUpPriorities)
                  _SelectableChip(
                    label: FollowUpTaskService.priorityLabel(priority),
                    selected: _priority == priority,
                    onTap: () => setState(() {
                      _priority = priority;
                      if (!_followUpTimeSet && _followUpAt != null) {
                        _followUpAt = DateTime(
                          _followUpAt!.year,
                          _followUpAt!.month,
                          _followUpAt!.day,
                        );
                      }
                    }),
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
                    value:
                        '${dateFormat.format(_lastTouchedAt)} · ${timeFormat.format(_lastTouchedAt)}',
                    onTap: () => _pickDate(
                      initialDate: _lastTouchedAt,
                      onChanged: (value) => setState(
                        () => _lastTouchedAt = DateTime(
                          value.year,
                          value.month,
                          value.day,
                          _lastTouchedAt.hour,
                          _lastTouchedAt.minute,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DateRow(
                    label: 'Follow up date',
                    value: _effectiveFollowUpAt == null
                        ? 'No date'
                        : dateFormat.format(_effectiveFollowUpAt!),
                    onTap: _status == 'done' || _status == 'archived'
                        ? null
                        : () => _pickDate(
                              initialDate:
                                  _effectiveFollowUpAt ?? DateTime.now(),
                              onChanged: (value) => setState(() {
                                final current = _effectiveFollowUpAt ??
                                    _defaultFollowUpForPriority(
                                        value, _priority);
                                _followUpAt = DateTime(
                                  value.year,
                                  value.month,
                                  value.day,
                                  current.hour,
                                  current.minute,
                                );
                              }),
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
                  const SizedBox(height: 12),
                  _DateRow(
                    label: 'Reminder time',
                    value: _effectiveFollowUpAt == null
                        ? 'No time'
                        : timeFormat.format(_effectiveFollowUpAt!),
                    onTap: (_status == 'done' || _status == 'archived')
                        ? null
                        : () => _pickTime(
                              initialDate:
                                  _effectiveFollowUpAt ?? DateTime.now(),
                              onChanged: (value) => setState(() {
                                _followUpAt = value;
                                _followUpTimeSet = true;
                              }),
                            ),
                    trailing: (_status == 'done' ||
                            _status == 'archived' ||
                            _followUpAt == null)
                        ? null
                        : CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            onPressed: () => setState(() {
                              _followUpTimeSet = false;
                              _followUpAt = DateTime(
                                _followUpAt!.year,
                                _followUpAt!.month,
                                _followUpAt!.day,
                              );
                            }),
                            child: const Text(
                              'Auto',
                              style: TextStyle(color: JournalColors.textMuted),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Attachments'),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_attachments.isNotEmpty) ...[
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _attachments.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, index) => _FollowUpAttachmentTile(
                          attachment: _attachments[index],
                          onRemove: () => _removeAttachment(index),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  GestureDetector(
                    onTap: _pickingAttachments ? null : _chooseAttachmentSource,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: _withAlpha(JournalColors.bgCardAlt, 0.94),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _attachments.isNotEmpty
                              ? JournalColors.borderBright
                              : JournalColors.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _attachments.isNotEmpty
                                  ? _withAlpha(JournalColors.accent, 0.16)
                                  : _withAlpha(JournalColors.bgSurface, 0.92),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _attachments.isNotEmpty
                                    ? JournalColors.borderBright
                                    : JournalColors.border,
                              ),
                            ),
                            child: _pickingAttachments
                                ? const CupertinoActivityIndicator(
                                    color: JournalColors.accent,
                                  )
                                : const Icon(
                                    CupertinoIcons.paperclip,
                                    color: JournalColors.textSecondary,
                                    size: 18,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _attachments.isEmpty
                                  ? 'Add screenshots, lease PDFs, application docs, or photos'
                                  : 'Add more attachments',
                              style: const TextStyle(
                                color: JournalColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_attachments.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _withAlpha(JournalColors.accent, 0.18),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${_attachments.length}',
                                style: const TextStyle(
                                  color: JournalColors.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
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
            color: selected
                ? JournalColors.textPrimary
                : JournalColors.textSecondary,
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

class _FollowUpAttachmentTile extends StatelessWidget {
  const _FollowUpAttachmentTile({
    required this.attachment,
    this.onRemove,
  });

  final FollowUpAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.isImage;
    final previewBytes = _attachmentPreviewBytes(attachment);
    final tile = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: isImage ? 108 : 94,
          height: 112,
          decoration: BoxDecoration(
            color: _withAlpha(JournalColors.bgCardAlt, 0.94),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: JournalColors.borderBright),
            boxShadow: isImage
                ? [
                    BoxShadow(
                      color: _withAlpha(JournalColors.bgBase, 0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: isImage
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      if (previewBytes != null)
                        Image.memory(previewBytes, fit: BoxFit.cover)
                      else if (attachment.path.isNotEmpty)
                        Image.file(
                          File(attachment.path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const _FollowUpAttachmentIcon(
                            isImage: true,
                            size: 108,
                            iconSize: 28,
                          ),
                        )
                      else
                        const _FollowUpAttachmentIcon(
                          isImage: true,
                          size: 108,
                          iconSize: 28,
                        ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _withAlpha(JournalColors.bgBase, 0),
                                _withAlpha(JournalColors.bgBase, 0.74),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: _FollowUpAttachmentBadge(
                          label: attachment.displayExtension,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: _withAlpha(JournalColors.bgBase, 0.72),
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: JournalColors.borderBright),
                          ),
                          child: const Icon(
                            CupertinoIcons.arrow_up_left_arrow_down_right,
                            color: JournalColors.textPrimary,
                            size: 12,
                          ),
                        ),
                      ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.all(9),
                    child: Column(
                      children: [
                        const _FollowUpAttachmentIcon(
                          isImage: false,
                          size: 40,
                          iconSize: 16,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          attachment.displayExtension,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: JournalColors.accent,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Expanded(
                          child: Center(
                            child: Text(
                              attachment.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: JournalColors.textSecondary,
                                fontSize: 10,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: -4,
            right: -4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.bgBase, 0.92),
                  shape: BoxShape.circle,
                  border: Border.all(color: JournalColors.borderBright),
                ),
                child: const Icon(
                  CupertinoIcons.xmark,
                  size: 12,
                  color: JournalColors.textPrimary,
                ),
              ),
            ),
          ),
      ],
    );

    if (!isImage || attachment.path.isEmpty) return tile;
    return GestureDetector(
      onTap: () => _showFollowUpImageLightbox(context, attachment),
      child: tile,
    );
  }
}

class _FollowUpAttachmentBadge extends StatelessWidget {
  const _FollowUpAttachmentBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgBase, 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: JournalColors.borderBright),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: JournalColors.textPrimary,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _FollowUpAttachmentIcon extends StatelessWidget {
  const _FollowUpAttachmentIcon({
    required this.isImage,
    this.size = 34,
    this.iconSize = 18,
  });

  final bool isImage;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.accent, 0.16),
        borderRadius: BorderRadius.circular(size >= 34 ? 12 : 10),
        border: Border.all(color: JournalColors.borderBright),
      ),
      child: Icon(
        isImage ? CupertinoIcons.photo : CupertinoIcons.doc_text,
        color: JournalColors.textPrimary,
        size: iconSize,
      ),
    );
  }
}

Future<void> _showFollowUpImageLightbox(
  BuildContext context,
  FollowUpAttachment attachment,
) {
  return showCupertinoDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return CupertinoPopupSurface(
        isSurfacePainted: false,
        child: Container(
          color: _withAlpha(JournalColors.bgBase, 0.96),
          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 0.9,
                    maxScale: 4,
                    child: () {
                      final previewBytes = _attachmentPreviewBytes(attachment);
                      if (attachment.path.isNotEmpty) {
                        return Image.file(
                          File(attachment.path),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => previewBytes != null
                              ? Image.memory(previewBytes, fit: BoxFit.contain)
                              : const _FollowUpAttachmentIcon(
                                  isImage: true,
                                  size: 120,
                                  iconSize: 42,
                                ),
                        );
                      }
                      if (previewBytes != null) {
                        return Image.memory(previewBytes, fit: BoxFit.contain);
                      }
                      return const _FollowUpAttachmentIcon(
                        isImage: true,
                        size: 120,
                        iconSize: 42,
                      );
                    }(),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 10,
                  right: 64,
                  child: Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 12,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(40, 40),
                    onPressed: () => Navigator.pop(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _withAlpha(JournalColors.bgSurface, 0.82),
                        shape: BoxShape.circle,
                        border: Border.all(color: JournalColors.borderBright),
                      ),
                      child: const Icon(
                        CupertinoIcons.xmark,
                        color: JournalColors.textPrimary,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Color _priorityColor(String priority) {
  switch (priority) {
    case 'urgent':
      return JournalColors.danger;
    case 'high':
      return JournalColors.severity;
    case 'low':
      return JournalColors.info;
    default:
      return JournalColors.accent;
  }
}
