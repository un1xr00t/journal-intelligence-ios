import 'dart:io';
import 'dart:typed_data';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/launch_intent_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

const double _kQuietJournalPickedImageMaxDimension = 2000;

enum _QuietJournalView {
  list('List'),
  calendar('Calendar'),
  media('Media');

  const _QuietJournalView(this.label);
  final String label;
}

class QuietJournalShell extends StatefulWidget {
  const QuietJournalShell({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<QuietJournalShell> createState() => _QuietJournalShellState();
}

class _QuietJournalShellState extends State<QuietJournalShell> {
  late int _selectedIndex;
  int _journalRevision = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _mapInitialTab(widget.initialTab);
  }

  @override
  void didUpdateWidget(covariant QuietJournalShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _selectedIndex = _mapInitialTab(widget.initialTab);
    }
  }

  int _mapInitialTab(int index) {
    return switch (index) {
      2 => 1,
      4 => 2,
      _ => 0,
    };
  }

  void _selectTab(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedIndex = index);

    final launchIntent = context.read<LaunchIntentProvider>();
    switch (index) {
      case 0:
        launchIntent.setActiveTab(0);
      case 1:
        launchIntent.setActiveTab(2);
      case 2:
        launchIntent.setActiveTab(4);
    }
  }

  void _handleEntrySaved() {
    setState(() {
      _journalRevision += 1;
    });
    _selectTab(0);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      _QuietJournalHomeScreen(
        refreshRevision: _journalRevision,
        onComposeTap: () => _selectTab(1),
      ),
      _QuietJournalComposeScreen(onEntrySaved: _handleEntrySaved),
      const SettingsScreen(),
    ];

    return AdaptiveScaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          for (var index = 0; index < screens.length; index += 1)
            TickerMode(
              enabled: index == _selectedIndex,
              child: HeroMode(
                enabled: index == _selectedIndex,
                child: screens[index],
              ),
            ),
        ],
      ),
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        selectedIndex: _selectedIndex,
        onTap: _selectTab,
        items: [
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS26OrHigher()
                ? 'book.closed'
                : CupertinoIcons.book,
            selectedIcon: PlatformInfo.isIOS26OrHigher()
                ? 'book.closed.fill'
                : CupertinoIcons.book_fill,
            label: 'Journal',
          ),
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS26OrHigher()
                ? 'square.and.pencil'
                : CupertinoIcons.pencil,
            selectedIcon: PlatformInfo.isIOS26OrHigher()
                ? 'square.and.pencil'
                : CupertinoIcons.pencil_circle_fill,
            label: 'Write',
          ),
          AdaptiveNavigationDestination(
            icon: PlatformInfo.isIOS26OrHigher()
                ? 'gearshape'
                : CupertinoIcons.settings,
            selectedIcon: PlatformInfo.isIOS26OrHigher()
                ? 'gearshape.fill'
                : CupertinoIcons.settings,
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _QuietJournalHomeScreen extends StatefulWidget {
  const _QuietJournalHomeScreen({
    required this.refreshRevision,
    required this.onComposeTap,
  });

  final int refreshRevision;
  final VoidCallback onComposeTap;

  @override
  State<_QuietJournalHomeScreen> createState() =>
      _QuietJournalHomeScreenState();
}

class _QuietJournalHomeScreenState extends State<_QuietJournalHomeScreen> {
  final _api = ApiService();
  final _scrollController = ScrollController();

  List<Map<String, dynamic>> _entries = [];
  Map<int, List<_QuietImageAttachment>> _imageAttachmentsByEntry = {};
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  _QuietJournalView _activeView = _QuietJournalView.list;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _QuietJournalHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshRevision != widget.refreshRevision) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasMore = true;
      _page = 1;
      _error = null;
      _imageAttachmentsByEntry = {};
    });

    try {
      final page = await _api.getTimelinePage(page: 1, limit: 24);
      final entries = [...page.entries]..sort(_sortEntriesDesc);
      if (!mounted) return;

      setState(() {
        _entries = entries;
        _hasMore = page.hasMore;
        _page = page.page;
        _loading = false;
      });

      _loadPreviewImages(entries);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _parseError(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;

    setState(() => _loadingMore = true);

    try {
      final page = await _api.getTimelinePage(page: _page + 1, limit: 24);
      final existingIds =
          _entries.map((entry) => _entryId(entry)).whereType<int>().toSet();
      final incoming = page.entries.where((entry) {
        final id = _entryId(entry);
        return id != null && !existingIds.contains(id);
      }).toList();
      final merged = [..._entries, ...incoming]..sort(_sortEntriesDesc);

      if (!mounted) return;
      setState(() {
        _entries = merged;
        _hasMore = page.hasMore;
        _page = page.page;
        _loadingMore = false;
      });

      if (incoming.isNotEmpty) {
        _loadPreviewImages(incoming);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      _loadMore();
    }
  }

  Future<void> _loadPreviewImages(List<Map<String, dynamic>> entries) async {
    final attachmentsByEntry = <int, List<_QuietImageAttachment>>{};

    await Future.wait(
      entries.map((entry) async {
        final entryId = _entryId(entry);
        if (entryId == null) return;
        try {
          final attachments = await _api.getEntryAttachments(entryId);
          final images = attachments
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where(
                (item) =>
                    item['media_type']
                        ?.toString()
                        .toLowerCase()
                        .startsWith('image/') ??
                    false,
              )
              .map((item) => _QuietImageAttachment.fromJson(entry, item))
              .whereType<_QuietImageAttachment>()
              .toList();
          attachmentsByEntry[entryId] = images;
        } catch (_) {
          attachmentsByEntry[entryId] = const [];
        }
      }),
    );

    if (!mounted) return;
    setState(
      () => _imageAttachmentsByEntry = {
        ..._imageAttachmentsByEntry,
        ...attachmentsByEntry,
      },
    );
  }

  Future<void> _deleteEntry(Map<String, dynamic> entry) async {
    final entryId = _entryId(entry);
    if (entryId == null) return;

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('This cannot be undone.'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _api.deleteEntry(entryId);
      if (!mounted) return;
      setState(() {
        _entries = _entries.where((item) => _entryId(item) != entryId).toList();
        _imageAttachmentsByEntry = Map<int, List<_QuietImageAttachment>>.from(
          _imageAttachmentsByEntry,
        )..remove(entryId);
      });
    } catch (_) {}
  }

  Future<void> _editEntry(Map<String, dynamic> entry) async {
    final entryId = _entryId(entry);
    if (entryId == null) return;

    final updated = await Navigator.of(context).push<Map<String, dynamic>>(
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: _QuietEditEntryScreen(entry: entry, api: _api),
        ),
      ),
    );

    if (updated == null || !mounted) return;
    setState(() {
      _entries = _entries
          .map((item) => _entryId(item) == entryId ? updated : item)
          .toList()
        ..sort(_sortEntriesDesc);
    });
    _loadPreviewImages([updated]);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  _QuietJournalHeader(
                    activeView: _activeView,
                    onViewChanged: (view) {
                      setState(() => _activeView = view);
                    },
                    onRefresh: _load,
                  ),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
            Positioned(
              right: 20,
              bottom: 24,
              child: _ComposeFab(onTap: widget.onComposeTap),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CupertinoActivityIndicator(color: JournalColors.accent),
      );
    }

    if (_error != null) {
      return _QuietStateView(
        icon: CupertinoIcons.exclamationmark_circle,
        title: 'Could not load your journal',
        message: _error!,
        actionLabel: 'Try again',
        onTap: _load,
      );
    }

    if (_entries.isEmpty) {
      return _QuietStateView(
        icon: CupertinoIcons.book,
        title: 'Nothing here yet',
        message:
            'Start with a short entry or a photo and let this space stay simple.',
        actionLabel: 'Write your first entry',
        onTap: widget.onComposeTap,
      );
    }

    return switch (_activeView) {
      _QuietJournalView.list => _QuietListView(
          entries: _entries,
          imageAttachmentsByEntry: _imageAttachmentsByEntry,
          controller: _scrollController,
          loadingMore: _loadingMore,
          onDeleteEntry: _deleteEntry,
          onEditEntry: _editEntry,
        ),
      _QuietJournalView.calendar => _QuietCalendarView(
          entries: _entries,
          imageAttachmentsByEntry: _imageAttachmentsByEntry,
          controller: _scrollController,
          loadingMore: _loadingMore,
        ),
      _QuietJournalView.media => _QuietMediaView(
          entries: _entries,
          imageAttachmentsByEntry: _imageAttachmentsByEntry,
          onComposeTap: widget.onComposeTap,
          controller: _scrollController,
          loadingMore: _loadingMore,
        ),
    };
  }
}

class _QuietJournalHeader extends StatelessWidget {
  const _QuietJournalHeader({
    required this.activeView,
    required this.onViewChanged,
    required this.onRefresh,
  });

  final _QuietJournalView activeView;
  final ValueChanged<_QuietJournalView> onViewChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                CupertinoIcons.line_horizontal_3,
                color: JournalColors.info,
                size: 24,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Quiet Journal',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _HeaderIconButton(
                icon: CupertinoIcons.arrow_clockwise,
                onTap: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'A memory-first view of your entries and photos.',
            style: TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: _QuietJournalView.values.map((view) {
              final active = view == activeView;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onViewChanged(view),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      children: [
                        Text(
                          view.label,
                          style: TextStyle(
                            color: active
                                ? JournalColors.info
                                : JournalColors.textSecondary,
                            fontSize: 15,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          width: 52,
                          height: 3,
                          decoration: BoxDecoration(
                            color: active
                                ? JournalColors.info
                                : CupertinoColors.transparent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          Container(
            height: 1,
            color: _withAlpha(JournalColors.border, 1),
          ),
        ],
      ),
    );
  }
}

class _QuietListView extends StatelessWidget {
  const _QuietListView({
    required this.entries,
    required this.imageAttachmentsByEntry,
    required this.controller,
    required this.loadingMore,
    required this.onDeleteEntry,
    required this.onEditEntry,
  });

  final List<Map<String, dynamic>> entries;
  final Map<int, List<_QuietImageAttachment>> imageAttachmentsByEntry;
  final ScrollController controller;
  final bool loadingMore;
  final ValueChanged<Map<String, dynamic>> onDeleteEntry;
  final ValueChanged<Map<String, dynamic>> onEditEntry;

  @override
  Widget build(BuildContext context) {
    final grouped = _groupEntriesByMonth(entries);
    final sections = grouped.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 110),
      itemCount: sections.length + (loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == sections.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CupertinoActivityIndicator(color: JournalColors.accent),
            ),
          );
        }
        final month = sections[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 18, bottom: 0),
              child: Container(
                width: double.infinity,
                color: _withAlpha(JournalColors.bgSurface, 0.9),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                child: Text(
                  DateFormat('MMMM yyyy').format(month.key),
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            ...month.value.map(
              (entry) => _QuietListEntryRow(
                entry: entry,
                previewPath: _firstImagePath(entry, imageAttachmentsByEntry),
                onDelete: () => onDeleteEntry(entry),
                onEdit: () => onEditEntry(entry),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuietListEntryRow extends StatelessWidget {
  const _QuietListEntryRow({
    required this.entry,
    required this.previewPath,
    required this.onDelete,
    required this.onEdit,
  });

  final Map<String, dynamic> entry;
  final String? previewPath;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final date = _entryDate(entry) ?? DateTime.now();
    final parts = _entryTextParts(entry);
    final wordCount =
        entry['word_count']?.toString() ?? '${_wordCount(parts.full)}';
    final detailLine =
        parts.preview.isNotEmpty ? parts.preview : '$wordCount words';
    final metaLine = _entryMetaLine(entry);
    final hasPhoto = previewPath != null && previewPath!.isNotEmpty;

    return Dismissible(
      key: ValueKey('quiet-entry-${_entryId(entry) ?? entry.hashCode}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onDelete();
        } else {
          onEdit();
        }
        return false;
      },
      background: const _QuietSwipeBackground(
        alignment: Alignment.centerLeft,
        color: JournalColors.danger,
        icon: CupertinoIcons.trash,
        label: 'Delete',
      ),
      secondaryBackground: const _QuietSwipeBackground(
        alignment: Alignment.centerRight,
        color: JournalColors.accent,
        icon: CupertinoIcons.pencil,
        label: 'Edit',
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openEntry(context, entry),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: _withAlpha(JournalColors.border, 1)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEE').format(date).toUpperCase(),
                      style: const TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${date.day}',
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 0.95,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        parts.title,
                        maxLines: hasPhoto ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          height: 1.24,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        detailLine,
                        maxLines: hasPhoto ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 14,
                          height: 1.42,
                        ),
                      ),
                      if (metaLine.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          metaLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: JournalColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (hasPhoto) ...[
                const SizedBox(width: 16),
                _PreviewThumb(
                  path: previewPath,
                  width: 96,
                  height: 96,
                  radius: 14,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuietSwipeBackground extends StatelessWidget {
  const _QuietSwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isRight = alignment == Alignment.centerRight;
    return Container(
      color: _withAlpha(color, 0.14),
      padding: EdgeInsets.only(left: isRight ? 0 : 22, right: isRight ? 22 : 0),
      alignment: alignment,
      child: Row(
        mainAxisAlignment:
            isRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isRight) Icon(icon, color: color, size: 19),
          if (!isRight) const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none,
            ),
          ),
          if (isRight) const SizedBox(width: 8),
          if (isRight) Icon(icon, color: color, size: 19),
        ],
      ),
    );
  }
}

class _QuietCalendarView extends StatelessWidget {
  const _QuietCalendarView({
    required this.entries,
    required this.imageAttachmentsByEntry,
    required this.controller,
    required this.loadingMore,
  });

  final List<Map<String, dynamic>> entries;
  final Map<int, List<_QuietImageAttachment>> imageAttachmentsByEntry;
  final ScrollController controller;
  final bool loadingMore;

  @override
  Widget build(BuildContext context) {
    final grouped = _groupEntriesByMonth(entries);
    final months = grouped.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
      itemCount: months.length + (loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == months.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CupertinoActivityIndicator(color: JournalColors.accent),
            ),
          );
        }
        final month = months[index];
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 2 : 20),
          child: _CalendarMonthCard(
            month: month.key,
            entries: month.value,
            imageAttachmentsByEntry: imageAttachmentsByEntry,
          ),
        );
      },
    );
  }
}

class _CalendarMonthCard extends StatelessWidget {
  const _CalendarMonthCard({
    required this.month,
    required this.entries,
    required this.imageAttachmentsByEntry,
  });

  final DateTime month;
  final List<Map<String, dynamic>> entries;
  final Map<int, List<_QuietImageAttachment>> imageAttachmentsByEntry;

  @override
  Widget build(BuildContext context) {
    final dayCount = DateTime(month.year, month.month + 1, 0).day;
    final cells = <_CalendarCellData>[];
    final byDay = <int, List<Map<String, dynamic>>>{};

    for (final entry in entries) {
      final date = _entryDate(entry);
      if (date == null) continue;
      byDay.putIfAbsent(date.day, () => []).add(entry);
    }

    for (var day = 1; day <= dayCount; day += 1) {
      final cellDate = DateTime(month.year, month.month, day);
      final dayEntries = byDay[day] ?? const <Map<String, dynamic>>[];
      final firstEntry = dayEntries.isEmpty ? null : dayEntries.first;
      final dayImages = dayEntries
          .expand((entry) => _entryImages(entry, imageAttachmentsByEntry))
          .toList();
      cells.add(
        _CalendarCellData(
          day: day,
          weekdayLabel: DateFormat('EEE').format(cellDate).toUpperCase(),
          entry: firstEntry,
          entryCount: dayEntries.length,
          photoCount: dayImages.length,
          previewPath: dayImages.isEmpty ? null : dayImages.first.path,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgCard, 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('MMMM yyyy').format(month),
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: cells.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.92,
            ),
            itemBuilder: (context, index) {
              return _CalendarDayCell(data: cells[index]);
            },
          ),
        ],
      ),
    );
  }
}

class _QuietMediaView extends StatelessWidget {
  const _QuietMediaView({
    required this.entries,
    required this.imageAttachmentsByEntry,
    required this.onComposeTap,
    required this.controller,
    required this.loadingMore,
  });

  final List<Map<String, dynamic>> entries;
  final Map<int, List<_QuietImageAttachment>> imageAttachmentsByEntry;
  final VoidCallback onComposeTap;
  final ScrollController controller;
  final bool loadingMore;

  @override
  Widget build(BuildContext context) {
    final mediaItems = entries
        .expand((entry) => _entryImages(entry, imageAttachmentsByEntry))
        .toList();

    if (mediaItems.isEmpty) {
      return _QuietStateView(
        icon: CupertinoIcons.photo_on_rectangle,
        title: 'No photo memories yet',
        message:
            'Add photos to entries and they will collect here automatically.',
        actionLabel: 'Write with photos',
        onTap: onComposeTap,
      );
    }

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _withAlpha(JournalColors.bgCard, 0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: JournalColors.border),
          ),
          child: const Row(
            children: [
              _FilterChip(label: 'All', active: true),
              SizedBox(width: 8),
              _FilterChip(label: 'Photos', active: true),
              SizedBox(width: 8),
              _FilterChip(label: 'Journal', active: false),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: mediaItems.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.92,
          ),
          itemBuilder: (context, index) {
            return _MediaTile(
              item: mediaItems[index],
            );
          },
        ),
        if (loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CupertinoActivityIndicator(color: JournalColors.accent),
            ),
          ),
      ],
    );
  }
}

class _CalendarCellData {
  const _CalendarCellData({
    required this.day,
    required this.weekdayLabel,
    required this.entry,
    required this.entryCount,
    required this.photoCount,
    required this.previewPath,
  });

  final int day;
  final String weekdayLabel;
  final Map<String, dynamic>? entry;
  final int entryCount;
  final int photoCount;
  final String? previewPath;
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({required this.data});

  final _CalendarCellData data;

  @override
  Widget build(BuildContext context) {
    final hasEntry = data.entry != null;
    final hasImage = data.previewPath != null && data.previewPath!.isNotEmpty;

    return GestureDetector(
      onTap: hasEntry ? () => _openEntry(context, data.entry!) : null,
      child: Container(
        decoration: BoxDecoration(
          color: hasEntry
              ? _withAlpha(JournalColors.bgSurface, 0.92)
              : _withAlpha(JournalColors.bgBase, 0.50),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasEntry ? JournalColors.borderBright : JournalColors.border,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                _QuietAuthImage(path: data.previewPath!)
              else
                const SizedBox.shrink(),
              if (hasImage)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        CupertinoColors.black.withValues(alpha: 0.12),
                        CupertinoColors.black.withValues(alpha: 0.38),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.weekdayLabel,
                      style: TextStyle(
                        color: hasImage
                            ? CupertinoColors.white.withValues(alpha: 0.72)
                            : JournalColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.9,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${data.day}',
                      style: TextStyle(
                        color: hasImage
                            ? CupertinoColors.white
                            : JournalColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 0.95,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const Spacer(),
                    if (data.photoCount > 1)
                      Align(
                        alignment: Alignment.bottomRight,
                        child: _CalendarCountPill(
                          label: '${data.photoCount}',
                          icon: CupertinoIcons.photo,
                        ),
                      )
                    else if (data.entryCount > 1)
                      Align(
                        alignment: Alignment.bottomRight,
                        child: _CalendarCountPill(
                          label: '${data.entryCount}',
                          icon: CupertinoIcons.doc_text,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarCountPill extends StatelessWidget {
  const _CalendarCountPill({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: CupertinoColors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: CupertinoColors.white.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: CupertinoColors.white, size: 10),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: CupertinoColors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.item,
  });

  final _QuietImageAttachment item;

  @override
  Widget build(BuildContext context) {
    final entry = item.entry;
    final date = _entryDate(entry) ?? DateTime.now();
    final title = _entryTextParts(entry).title;
    final day = DateFormat('d').format(date);
    final monthYear = DateFormat('MMMM yyyy').format(date);

    return GestureDetector(
      onTap: () => _openEntry(context, entry),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _QuietAuthImage(path: item.path),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    CupertinoColors.black.withValues(alpha: 0.06),
                    CupertinoColors.black.withValues(alpha: 0.58),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          day,
                          style: const TextStyle(
                            color: CupertinoColors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                        Text(
                          monthYear,
                          style: TextStyle(
                            color:
                                CupertinoColors.white.withValues(alpha: 0.82),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuietJournalComposeScreen extends StatefulWidget {
  const _QuietJournalComposeScreen({
    required this.onEntrySaved,
  });

  final VoidCallback onEntrySaved;

  @override
  State<_QuietJournalComposeScreen> createState() =>
      _QuietJournalComposeScreenState();
}

class _QuietJournalComposeScreenState
    extends State<_QuietJournalComposeScreen> {
  final _api = ApiService();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _picker = ImagePicker();
  final _scrollController = ScrollController();

  bool _saving = false;
  bool _saved = false;
  String? _error;
  final List<XFile> _pendingImages = [];
  double _lastKeyboardInset = 0;

  bool get _canSave => !_saving && _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      _scheduleComposerReveal();
    }
  }

  void _scheduleComposerReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      const revealNudge = 120.0;
      final target =
          (position.pixels + revealNudge).clamp(0.0, position.maxScrollExtent);
      if ((target - position.pixels).abs() < 12) return;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickImage() async {
    final source = await showCupertinoModalPopup<ImageSource>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Add Photo'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: const Text('Take Photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Text('Choose from Library'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );

    if (source == null) return;

    try {
      if (source == ImageSource.gallery) {
        final picked = await _picker.pickMultiImage(
          imageQuality: 86,
          maxWidth: _kQuietJournalPickedImageMaxDimension,
          maxHeight: _kQuietJournalPickedImageMaxDimension,
        );
        if (picked.isNotEmpty && mounted) {
          setState(() => _pendingImages.addAll(picked));
        }
      } else {
        final picked = await _picker.pickImage(
          source: source,
          imageQuality: 86,
          maxWidth: _kQuietJournalPickedImageMaxDimension,
          maxHeight: _kQuietJournalPickedImageMaxDimension,
        );
        if (picked != null && mounted) {
          setState(() => _pendingImages.add(picked));
        }
      }
    } catch (_) {}
  }

  void _removeImage(int index) {
    setState(() => _pendingImages.removeAt(index));
  }

  Future<void> _save() async {
    if (!_canSave) return;

    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });

    try {
      for (final image in _pendingImages) {
        await _api.validateEntryAttachmentForUpload(
          filePath: image.path,
          filename: image.name,
        );
      }

      final result = await _api.createEntry(text: _controller.text.trim());
      final entryId = result['entry_id'] as int?;

      if (entryId != null && _pendingImages.isNotEmpty) {
        for (final image in _pendingImages) {
          await _api.uploadEntryAttachment(
            entryId: entryId,
            filePath: image.path,
            filename: image.name,
          );
        }
      }

      _controller.clear();
      if (!mounted) return;
      setState(() {
        _pendingImages.clear();
        _saving = false;
        _saved = true;
      });
      widget.onEntrySaved();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _parseError(e);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayLabel = DateFormat('EEEE, MMMM d').format(DateTime.now());
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomComposerPadding = keyboardInset > 0 ? keyboardInset + 28 : 32.0;
    if (keyboardInset > _lastKeyboardInset && _focusNode.hasFocus) {
      _scheduleComposerReveal();
    }
    _lastKeyboardInset = keyboardInset;

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardInset > 0 ? 10 : 0),
        child: CustomScrollView(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            CupertinoSliverNavigationBar(
              largeTitle: const Text('Write'),
              backgroundColor: _withAlpha(JournalColors.bgBase, 0.94),
              border: const Border(
                bottom: BorderSide(color: JournalColors.border, width: 0.5),
              ),
              trailing: GestureDetector(
                onTap: _canSave ? _save : null,
                child: Text(
                  _saving ? 'Saving…' : 'Save',
                  style: TextStyle(
                    color: _canSave
                        ? JournalColors.accent
                        : JournalColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                bottomComposerPadding,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: _withAlpha(JournalColors.bgCardAlt, 0.86),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: JournalColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          todayLabel,
                          style: const TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'What do you want to remember from today?',
                          style: TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          decoration: BoxDecoration(
                            color: _withAlpha(JournalColors.bgSurface, 0.72),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: _focusNode.hasFocus
                                  ? JournalColors.borderBright
                                  : JournalColors.border,
                            ),
                          ),
                          child: Column(
                            children: [
                              CupertinoTextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                padding:
                                    const EdgeInsets.fromLTRB(18, 18, 18, 8),
                                decoration: null,
                                minLines: 10,
                                maxLines: null,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                placeholder:
                                    'A moment, a feeling, a small scene, a photo, a sentence. It all counts.',
                                placeholderStyle: const TextStyle(
                                  color: JournalColors.textMuted,
                                  fontSize: 16,
                                  height: 1.55,
                                  decoration: TextDecoration.none,
                                ),
                                style: const TextStyle(
                                  color: JournalColors.textPrimary,
                                  fontSize: 17,
                                  height: 1.7,
                                  decoration: TextDecoration.none,
                                ),
                                onChanged: (_) =>
                                    setState(() => _saved = false),
                              ),
                              if (_pendingImages.isNotEmpty) ...[
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(14, 6, 14, 10),
                                  child: _InlineComposerPhotoGrid(
                                    images: _pendingImages,
                                    onRemove: _removeImage,
                                  ),
                                ),
                              ],
                              Container(
                                decoration: const BoxDecoration(
                                  border: Border(
                                    top:
                                        BorderSide(color: JournalColors.border),
                                  ),
                                ),
                                padding:
                                    const EdgeInsets.fromLTRB(10, 8, 10, 10),
                                child: Row(
                                  children: [
                                    _ComposerToolButton(
                                      icon: CupertinoIcons.photo_on_rectangle,
                                      label: 'Photo',
                                      onTap: _saving ? null : _pickImage,
                                      active: _pendingImages.isNotEmpty,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text(
                              '${_wordCount(_controller.text)} words',
                              style: const TextStyle(
                                color: JournalColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_saved || _error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _withAlpha(
                          _saved ? JournalColors.success : JournalColors.danger,
                          0.12,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _withAlpha(
                            _saved
                                ? JournalColors.success
                                : JournalColors.danger,
                            0.28,
                          ),
                        ),
                      ),
                      child: Text(
                        _saved
                            ? 'Saved. Your entry is now in Quiet Journal.'
                            : _error!,
                        style: TextStyle(
                          color: _saved
                              ? JournalColors.success
                              : JournalColors.danger,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _withAlpha(JournalColors.bgSurface, 0.76),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: JournalColors.border),
        ),
        child: Icon(icon, color: JournalColors.textPrimary, size: 18),
      ),
    );
  }
}

class _ComposerToolButton extends StatelessWidget {
  const _ComposerToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? JournalColors.accent : JournalColors.textPrimary;
    return CupertinoButton(
      minimumSize: const Size(38, 38),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Semantics(
        label: label,
        button: true,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: active
                ? _withAlpha(JournalColors.accent, 0.14)
                : CupertinoColors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
      ),
    );
  }
}

class _InlineComposerPhotoGrid extends StatelessWidget {
  const _InlineComposerPhotoGrid({
    required this.images,
    required this.onRemove,
  });

  final List<XFile> images;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: images.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.08,
      ),
      itemBuilder: (context, index) {
        final image = images[index];
        return Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.file(File(image.path), fit: BoxFit.cover),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => onRemove(index),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _withAlpha(JournalColors.bgBase, 0.84),
                    shape: BoxShape.circle,
                    border: Border.all(color: JournalColors.border),
                  ),
                  child: const Icon(
                    CupertinoIcons.xmark,
                    color: JournalColors.textPrimary,
                    size: 14,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ComposeFab extends StatelessWidget {
  const _ComposeFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [JournalColors.info, JournalColors.accent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: JournalColors.accentGlow,
              blurRadius: 22,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: const Icon(
          CupertinoIcons.add,
          color: CupertinoColors.white,
          size: 28,
        ),
      ),
    );
  }
}

class _PreviewThumb extends StatelessWidget {
  const _PreviewThumb({
    required this.path,
    required this.width,
    required this.height,
    required this.radius,
  });

  final String? path;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (path == null || path!.isEmpty) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: _QuietAuthImage(path: path!),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
  });

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? _withAlpha(JournalColors.accent, 0.16)
            : _withAlpha(JournalColors.bgSurface, 0.74),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? JournalColors.borderBright : JournalColors.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color:
              active ? JournalColors.textPrimary : JournalColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _QuietAuthImage extends StatefulWidget {
  const _QuietAuthImage({required this.path});

  final String path;

  @override
  State<_QuietAuthImage> createState() => _QuietAuthImageState();
}

class _QuietAuthImageState extends State<_QuietAuthImage> {
  final _api = ApiService();
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant _QuietAuthImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _bytes = null;
      _loading = true;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    try {
      final bytes = await _api.fetchImageBytes(widget.path);
      if (mounted) {
        setState(() {
          _bytes = Uint8List.fromList(bytes);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CupertinoActivityIndicator(color: JournalColors.accent),
      );
    }
    if (_bytes == null) {
      return Container(
        color: JournalColors.bgSurface,
        alignment: Alignment.center,
        child: const Icon(
          CupertinoIcons.photo,
          color: JournalColors.textMuted,
          size: 28,
        ),
      );
    }
    return Image.memory(
      _bytes!,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: JournalColors.bgSurface,
        alignment: Alignment.center,
        child: const Icon(
          CupertinoIcons.photo,
          color: JournalColors.textMuted,
          size: 28,
        ),
      ),
    );
  }
}

class _QuietStateView extends StatelessWidget {
  const _QuietStateView({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _withAlpha(JournalColors.bgCard, 0.92),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: JournalColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: JournalColors.textSecondary, size: 24),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              AdaptiveButton(
                style: AdaptiveButtonStyle.prominentGlass,
                onPressed: onTap,
                label: actionLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryTextParts {
  const _EntryTextParts({
    required this.title,
    required this.preview,
    required this.full,
  });

  final String title;
  final String preview;
  final String full;
}

class _QuietImageAttachment {
  const _QuietImageAttachment({
    required this.entry,
    required this.entryId,
    required this.attachmentId,
    required this.path,
    this.filename,
    this.uploadedAt,
  });

  final Map<String, dynamic> entry;
  final int entryId;
  final String attachmentId;
  final String path;
  final String? filename;
  final DateTime? uploadedAt;

  static _QuietImageAttachment? fromJson(
    Map<String, dynamic> entry,
    Map<String, dynamic> attachment,
  ) {
    final entryId = _entryId(entry);
    final attachmentId = attachment['id']?.toString();
    if (entryId == null || attachmentId == null || attachmentId.isEmpty) {
      return null;
    }

    return _QuietImageAttachment(
      entry: Map<String, dynamic>.from(entry),
      entryId: entryId,
      attachmentId: attachmentId,
      path: '/api/entry-attachments/$attachmentId/file',
      filename: attachment['filename']?.toString(),
      uploadedAt: DateTime.tryParse(
        attachment['uploaded_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }
}

_EntryTextParts _entryTextParts(Map<String, dynamic> entry) {
  final raw = (_entrySummaryText(entry).isNotEmpty
          ? _entrySummaryText(entry)
          : _entryOriginalText(entry))
      .trim();
  if (raw.isEmpty) {
    return const _EntryTextParts(
      title: 'Untitled memory',
      preview: '',
      full: '',
    );
  }

  final normalized = raw.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ');
  final sentences = normalized
      .split(RegExp(r'(?<=[.!?])\s+'))
      .where((part) => part.trim().isNotEmpty)
      .toList();
  final title = sentences.isNotEmpty ? sentences.first.trim() : normalized;
  final preview = sentences.length > 1
      ? sentences.skip(1).join(' ').trim()
      : normalized == title
          ? ''
          : normalized;

  return _EntryTextParts(
    title: title,
    preview: preview,
    full: normalized,
  );
}

String _entrySummaryText(Map<String, dynamic> entry) {
  return (entry['summary_text'] as String? ?? '').trim();
}

String _entryOriginalText(Map<String, dynamic> entry) {
  return (entry['normalized_text'] as String? ?? entry['text'] as String? ?? '')
      .trim();
}

String _entryMetaLine(Map<String, dynamic> entry) {
  final tagsValue = entry['tags'];
  final tags = <String>[];
  if (tagsValue is List) {
    for (final item in tagsValue) {
      final text = item?.toString().trim() ?? '';
      if (text.isNotEmpty) tags.add(text);
    }
  }

  final source = (entry['source']?.toString() ?? '').trim();
  final pieces = <String>[
    if (tags.isNotEmpty) tags.take(3).join(', '),
    if (source.isNotEmpty && source.toLowerCase() != 'journal') source,
  ];

  return pieces.join(' · ');
}

List<_QuietImageAttachment> _entryImages(
  Map<String, dynamic> entry,
  Map<int, List<_QuietImageAttachment>> imageAttachmentsByEntry,
) {
  final entryId = _entryId(entry);
  if (entryId == null) return const [];
  return imageAttachmentsByEntry[entryId] ?? const [];
}

String? _firstImagePath(
  Map<String, dynamic> entry,
  Map<int, List<_QuietImageAttachment>> imageAttachmentsByEntry,
) {
  final images = _entryImages(entry, imageAttachmentsByEntry);
  return images.isEmpty ? null : images.first.path;
}

Map<DateTime, List<Map<String, dynamic>>> _groupEntriesByMonth(
  List<Map<String, dynamic>> entries,
) {
  final grouped = <DateTime, List<Map<String, dynamic>>>{};
  for (final entry in entries) {
    final date = _entryDate(entry);
    if (date == null) continue;
    final month = DateTime(date.year, date.month);
    grouped.putIfAbsent(month, () => []).add(entry);
  }
  return grouped;
}

DateTime? _entryDate(Map<String, dynamic> entry) {
  final raw =
      entry['entry_date']?.toString() ?? entry['ingested_at']?.toString();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

int? _entryId(Map<String, dynamic> entry) {
  return (entry['id'] as num?)?.toInt();
}

int _sortEntriesDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aDate = _entryDate(a);
  final bDate = _entryDate(b);
  if (aDate == null && bDate == null) return 0;
  if (aDate == null) return 1;
  if (bDate == null) return -1;
  return bDate.compareTo(aDate);
}

void _openEntry(BuildContext context, Map<String, dynamic> entry) {
  final entryId = _entryId(entry);
  if (entryId == null) return;
  Navigator.of(context).push(
    CupertinoPageRoute(
      builder: (_) => DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: _QuietJournalEntryScreen(
          entryId: entryId,
          initialEntry: Map<String, dynamic>.from(entry),
        ),
      ),
    ),
  );
}

int _wordCount(String value) {
  return value
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .length;
}

String _parseError(dynamic e) {
  if (e is EntryAttachmentUploadException) {
    return e.message;
  }
  final str = e.toString();
  final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
  if (str.contains('413')) {
    return 'A photo is too large. Journal photos must be under 8 MB each.';
  }
  return match?.group(1) ?? 'Something went wrong.';
}

class _QuietEditEntryScreen extends StatefulWidget {
  const _QuietEditEntryScreen({
    required this.entry,
    required this.api,
  });

  final Map<String, dynamic> entry;
  final ApiService api;

  @override
  State<_QuietEditEntryScreen> createState() => _QuietEditEntryScreenState();
}

class _QuietEditEntryScreenState extends State<_QuietEditEntryScreen> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRaw();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadRaw() async {
    final entryId = _entryId(widget.entry);
    if (entryId == null) {
      setState(() {
        _controller.text = _entryOriginalText(widget.entry);
        _loading = false;
      });
      return;
    }

    try {
      final data = await widget.api.getEntry(entryId);
      if (!mounted) return;
      setState(() {
        _controller.text = _entryOriginalText(data);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _controller.text = _entryOriginalText(widget.entry);
        _loading = false;
        _error = 'Could not load the full entry. Editing the cached text.';
      });
    }
  }

  Future<void> _save() async {
    final entryId = _entryId(widget.entry);
    final text = _controller.text.trim();
    if (entryId == null || text.isEmpty || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final updated = await widget.api.updateEntry(entryId, text);
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _parseError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: _withAlpha(JournalColors.bgBase, 0.94),
        border: const Border(
          bottom: BorderSide(color: JournalColors.border, width: 0.5),
        ),
        middle: const Text(
          'Edit Entry',
          style: TextStyle(
            color: JournalColors.textPrimary,
            decoration: TextDecoration.none,
          ),
        ),
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: JournalColors.textMuted,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        trailing: _saving
            ? const CupertinoActivityIndicator(
                color: JournalColors.accent,
                radius: 9,
              )
            : GestureDetector(
                onTap: _save,
                child: const Text(
                  'Save',
                  style: TextStyle(
                    color: JournalColors.accent,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
      ),
      child: _loading
          ? const Center(
              child: CupertinoActivityIndicator(color: JournalColors.accent),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: JournalColors.danger,
                          fontSize: 13,
                          height: 1.4,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: _withAlpha(JournalColors.bgSurface, 0.76),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: JournalColors.border),
                        ),
                        child: CupertinoTextField(
                          controller: _controller,
                          padding: const EdgeInsets.all(18),
                          maxLines: null,
                          minLines: 12,
                          autofocus: true,
                          style: const TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 16,
                            height: 1.62,
                            decoration: TextDecoration.none,
                          ),
                          placeholder: 'Write your entry...',
                          placeholderStyle: const TextStyle(
                            color: JournalColors.textMuted,
                            fontSize: 16,
                            decoration: TextDecoration.none,
                          ),
                          decoration: null,
                          keyboardAppearance: Brightness.dark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _QuietJournalEntryScreen extends StatefulWidget {
  const _QuietJournalEntryScreen({
    required this.entryId,
    required this.initialEntry,
  });

  final int entryId;
  final Map<String, dynamic> initialEntry;

  @override
  State<_QuietJournalEntryScreen> createState() =>
      _QuietJournalEntryScreenState();
}

class _QuietJournalEntryScreenState extends State<_QuietJournalEntryScreen> {
  final _api = ApiService();

  late Map<String, dynamic> _entry;
  bool _attachmentsLoading = true;
  List<Map<String, dynamic>> _attachments = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _entry = Map<String, dynamic>.from(widget.initialEntry);
    _loadAttachments();
  }

  Future<void> _loadAttachments() async {
    try {
      final attachments = (await _api.getEntryAttachments(widget.entryId))
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where(
            (item) => (item['media_type']?.toString() ?? '')
                .toLowerCase()
                .startsWith('image/'),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _attachments = attachments;
        _attachmentsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _parseError(e);
        _attachmentsLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = _entryDate(_entry);
    final summary = _entrySummaryText(_entry);
    final hasSummary = summary.isNotEmpty;

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: JournalColors.bgBase.withValues(alpha: 0.94),
        border: const Border(
          bottom: BorderSide(color: JournalColors.border, width: 0.5),
        ),
        middle: Text(
          date == null ? 'Entry' : DateFormat('MMM d, yyyy').format(date),
          style: const TextStyle(
            color: JournalColors.textPrimary,
            decoration: TextDecoration.none,
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
          children: [
            _QuietEntryHeroSummary(
              summary: hasSummary
                  ? summary
                  : 'This entry does not have an AI summary yet.',
              isAiSummary: hasSummary,
            ),
            if (_error != null) ...[
              const SizedBox(height: 20),
              Text(
                _error!,
                style: const TextStyle(
                  color: JournalColors.danger,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
            if (_attachmentsLoading) ...[
              const SizedBox(height: 20),
              const Center(
                child: CupertinoActivityIndicator(color: JournalColors.accent),
              ),
            ] else if (_attachments.isNotEmpty) ...[
              const SizedBox(height: 24),
              _QuietEntrySectionLabel(
                label: _attachments.length == 1
                    ? '1 Photo'
                    : '${_attachments.length} Photos',
              ),
              const SizedBox(height: 12),
              GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: _attachments.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.92,
                ),
                itemBuilder: (context, index) {
                  final attachment = _attachments[index];
                  final path =
                      '/api/entry-attachments/${attachment['id']}/file';
                  return GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => DefaultTextStyle.merge(
                          style: const TextStyle(
                            decoration: TextDecoration.none,
                          ),
                          child: _QuietImageLightbox(path: path),
                        ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: _QuietAuthImage(path: path),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuietEntryHeroSummary extends StatelessWidget {
  const _QuietEntryHeroSummary({
    required this.summary,
    required this.isAiSummary,
  });

  final String summary;
  final bool isAiSummary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _withAlpha(JournalColors.accent, 0.14),
            _withAlpha(JournalColors.bgCard, 0.96),
            _withAlpha(JournalColors.bgCardAlt, 0.94),
          ],
        ),
        border: Border.all(
          color:
              isAiSummary ? JournalColors.borderBright : JournalColors.border,
        ),
        boxShadow: const [
          BoxShadow(
            color: JournalColors.accentGlow,
            blurRadius: 20,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isAiSummary ? CupertinoIcons.sparkles : CupertinoIcons.book,
                color: JournalColors.accent,
                size: 17,
              ),
              const SizedBox(width: 8),
              Text(
                isAiSummary ? 'AI SUMMARY' : 'ENTRY PREVIEW',
                style: const TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            summary,
            style: TextStyle(
              color: isAiSummary
                  ? JournalColors.textPrimary
                  : JournalColors.textSecondary,
              fontSize: isAiSummary ? 18 : 15,
              fontWeight: isAiSummary ? FontWeight.w600 : FontWeight.w500,
              height: 1.55,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuietEntrySectionLabel extends StatelessWidget {
  const _QuietEntrySectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: JournalColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        decoration: TextDecoration.none,
      ),
    );
  }
}

class _QuietImageLightbox extends StatelessWidget {
  const _QuietImageLightbox({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black.withValues(alpha: 0.94),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: _QuietAuthImage(path: path),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 20,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: CupertinoColors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: CupertinoColors.white.withValues(alpha: 0.14),
                    ),
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
    );
  }
}
