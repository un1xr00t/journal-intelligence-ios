import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/launch_intent_provider.dart';
import '../services/api_service.dart';
import '../services/notification_nudge_service.dart';
import '../services/sage_inbox_service.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

const double _kQuietJournalPickedImageMaxDimension = 2000;
const String _kQuietJournalImageAttachmentCacheKey =
    'quiet_journal_image_attachments_v1';
const String _kQuietJournalHideEmptyCalendarDaysKey =
    'quiet_journal_hide_empty_calendar_days_v1';
const String _kQuietJournalCalendarBlockScaleKey =
    'quiet_journal_calendar_block_scale_v1';
const String _kQuietJournalCalendarSortOrderKey =
    'quiet_journal_calendar_sort_order_v1';
const String _kQuietJournalShowCalendarPhotoPreviewsKey =
    'quiet_journal_show_calendar_photo_previews_v1';
const String _kQuietJournalAutoFocusCalendarMonthKey =
    'quiet_journal_auto_focus_calendar_month_v1';

enum _QuietJournalView {
  list('List'),
  calendar('Calendar'),
  media('Media');

  const _QuietJournalView(this.label);
  final String label;
}

enum _QuietJournalCalendarSortOrder {
  ascending('Oldest first'),
  descending('Newest first');

  const _QuietJournalCalendarSortOrder(this.label);
  final String label;
}

class _QuietJournalCalendarSettings {
  const _QuietJournalCalendarSettings({
    this.hideEmptyDays = false,
    this.blockScale = 1.0,
    this.sortOrder = _QuietJournalCalendarSortOrder.ascending,
    this.showPhotoPreviews = true,
    this.autoFocusCurrentMonth = true,
  });

  final bool hideEmptyDays;
  final double blockScale;
  final _QuietJournalCalendarSortOrder sortOrder;
  final bool showPhotoPreviews;
  final bool autoFocusCurrentMonth;

  _QuietJournalCalendarSettings copyWith({
    bool? hideEmptyDays,
    double? blockScale,
    _QuietJournalCalendarSortOrder? sortOrder,
    bool? showPhotoPreviews,
    bool? autoFocusCurrentMonth,
  }) {
    return _QuietJournalCalendarSettings(
      hideEmptyDays: hideEmptyDays ?? this.hideEmptyDays,
      blockScale: blockScale ?? this.blockScale,
      sortOrder: sortOrder ?? this.sortOrder,
      showPhotoPreviews: showPhotoPreviews ?? this.showPhotoPreviews,
      autoFocusCurrentMonth:
          autoFocusCurrentMonth ?? this.autoFocusCurrentMonth,
    );
  }
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
  final _listScrollController = ScrollController();
  final _calendarScrollController = ScrollController();
  final _mediaScrollController = ScrollController();
  final Map<DateTime, GlobalKey> _calendarMonthKeys = <DateTime, GlobalKey>{};

  List<Map<String, dynamic>> _entries = [];
  Map<int, List<_QuietImageAttachment>> _imageAttachmentsByEntry = {};
  _QuietJournalCalendarSettings _calendarSettings =
      const _QuietJournalCalendarSettings();
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  _QuietJournalView _activeView = _QuietJournalView.list;
  int _page = 1;
  bool _focusCalendarAfterBuild = false;
  bool _calendarHistoryHydrating = false;

  @override
  void initState() {
    super.initState();
    _listScrollController.addListener(() => _onScroll(_QuietJournalView.list));
    _calendarScrollController.addListener(
      () => _onScroll(_QuietJournalView.calendar),
    );
    _mediaScrollController
        .addListener(() => _onScroll(_QuietJournalView.media));
    _restoreCalendarSettings();
    _load();
  }

  @override
  void dispose() {
    _listScrollController.dispose();
    _calendarScrollController.dispose();
    _mediaScrollController.dispose();
    super.dispose();
  }

  ScrollController _controllerFor(_QuietJournalView view) {
    return switch (view) {
      _QuietJournalView.list => _listScrollController,
      _QuietJournalView.calendar => _calendarScrollController,
      _QuietJournalView.media => _mediaScrollController,
    };
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
      final entries = [...page.entries]..sort(_sortEntriesAsc);
      if (!mounted) return;

      setState(() {
        _entries = entries;
        _hasMore = page.hasMore;
        _page = page.page;
        _loading = false;
        _focusCalendarAfterBuild = _activeView == _QuietJournalView.calendar &&
            _calendarSettings.autoFocusCurrentMonth;
      });

      await _restoreCachedPreviewImages(entries);
      _loadPreviewImages(entries);
      _maybeHydrateCalendarHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _parseError(e);
        _loading = false;
      });
    }
  }

  Future<void> _restoreCalendarSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final restored = _QuietJournalCalendarSettings(
        hideEmptyDays:
            prefs.getBool(_kQuietJournalHideEmptyCalendarDaysKey) ?? false,
        blockScale:
            (prefs.getDouble(_kQuietJournalCalendarBlockScaleKey) ?? 1.0)
                .clamp(0.8, 1.2),
        sortOrder: _calendarSortOrderFromName(
              prefs.getString(_kQuietJournalCalendarSortOrderKey),
            ) ??
            _QuietJournalCalendarSortOrder.ascending,
        showPhotoPreviews:
            prefs.getBool(_kQuietJournalShowCalendarPhotoPreviewsKey) ?? true,
        autoFocusCurrentMonth:
            prefs.getBool(_kQuietJournalAutoFocusCalendarMonthKey) ?? true,
      );
      if (!mounted) return;
      setState(() {
        _calendarSettings = restored;
      });
    } catch (_) {}
  }

  Future<void> _persistCalendarSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        _kQuietJournalHideEmptyCalendarDaysKey,
        _calendarSettings.hideEmptyDays,
      );
      await prefs.setDouble(
        _kQuietJournalCalendarBlockScaleKey,
        _calendarSettings.blockScale,
      );
      await prefs.setString(
        _kQuietJournalCalendarSortOrderKey,
        _calendarSettings.sortOrder.name,
      );
      await prefs.setBool(
        _kQuietJournalShowCalendarPhotoPreviewsKey,
        _calendarSettings.showPhotoPreviews,
      );
      await prefs.setBool(
        _kQuietJournalAutoFocusCalendarMonthKey,
        _calendarSettings.autoFocusCurrentMonth,
      );
    } catch (_) {}
  }

  void _updateCalendarSettings(_QuietJournalCalendarSettings next) {
    final normalized = next.copyWith(
      blockScale: next.blockScale.clamp(0.8, 1.2),
    );
    final shouldRefocusCurrentMonth =
        _activeView == _QuietJournalView.calendar &&
            normalized.autoFocusCurrentMonth &&
            (normalized.hideEmptyDays != _calendarSettings.hideEmptyDays ||
                normalized.sortOrder != _calendarSettings.sortOrder);
    setState(() {
      _calendarSettings = normalized;
      if (!normalized.autoFocusCurrentMonth) {
        _focusCalendarAfterBuild = false;
      } else if (shouldRefocusCurrentMonth) {
        _focusCalendarAfterBuild = true;
      }
    });
    _persistCalendarSettings();
  }

  Future<void> _openMiniSettingsMenu() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: _QuietJournalMiniSettingsSheet(
          activeView: _activeView,
          calendarSettings: _calendarSettings,
          onCalendarSettingsChanged: _updateCalendarSettings,
          onJumpToCalendar: () {
            Navigator.of(sheetContext).pop();
            setState(() {
              _activeView = _QuietJournalView.calendar;
              if (_calendarSettings.autoFocusCurrentMonth) {
                _focusCalendarAfterBuild = true;
              }
            });
            _maybeHydrateCalendarHistory();
          },
          onResetCalendarDefaults: () {
            _updateCalendarSettings(const _QuietJournalCalendarSettings());
          },
        ),
      ),
    );
  }

  Future<void> _loadMore({
    bool preserveScrollPosition = true,
  }) async {
    if (_loading || _loadingMore || !_hasMore) return;

    final controller = _controllerFor(_activeView);

    final previousPixels = preserveScrollPosition && controller.hasClients
        ? controller.position.pixels
        : 0.0;
    final previousMaxScrollExtent =
        preserveScrollPosition && controller.hasClients
            ? controller.position.maxScrollExtent
            : 0.0;

    setState(() => _loadingMore = true);

    try {
      final page = await _api.getTimelinePage(page: _page + 1, limit: 24);
      final existingIds =
          _entries.map((entry) => _entryId(entry)).whereType<int>().toSet();
      final incoming = page.entries.where((entry) {
        final id = _entryId(entry);
        return id != null && !existingIds.contains(id);
      }).toList();
      final merged = [..._entries, ...incoming]..sort(_sortEntriesAsc);

      if (!mounted) return;
      setState(() {
        _entries = merged;
        _hasMore = page.hasMore;
        _page = page.page;
        _loadingMore = false;
      });

      if (preserveScrollPosition) {
        _maintainScrollOffsetAfterPrepend(
          controller: controller,
          previousPixels: previousPixels,
          previousMaxScrollExtent: previousMaxScrollExtent,
        );
      }

      if (incoming.isNotEmpty) {
        await _restoreCachedPreviewImages(incoming);
        _loadPreviewImages(incoming);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _onScroll(_QuietJournalView view) {
    if (_activeView != view) return;
    final controller = _controllerFor(view);
    if (!controller.hasClients) return;
    final position = controller.position;
    switch (view) {
      case _QuietJournalView.calendar:
        final shouldLoadMore = _calendarSettings.sortOrder ==
                _QuietJournalCalendarSortOrder.ascending
            ? position.pixels <= 320
            : position.pixels >= position.maxScrollExtent - 320;
        if (shouldLoadMore) {
          _loadMore();
        }
      case _QuietJournalView.list:
      case _QuietJournalView.media:
        if (position.pixels >= position.maxScrollExtent - 320) {
          _loadMore();
        }
    }
  }

  void _maintainScrollOffsetAfterPrepend({
    required ScrollController controller,
    required double previousPixels,
    required double previousMaxScrollExtent,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      final currentPosition = controller.position;
      final delta = currentPosition.maxScrollExtent - previousMaxScrollExtent;
      final target = (previousPixels + delta).clamp(
        0.0,
        currentPosition.maxScrollExtent,
      );
      if ((target - currentPosition.pixels).abs() < 1) return;
      controller.jumpTo(target);
    });
  }

  DateTime? _latestEntryMonth() {
    if (_entries.isEmpty) return null;
    for (final entry in _entries.reversed) {
      final date = _entryDate(entry);
      if (date != null) {
        return DateTime(date.year, date.month);
      }
    }
    return null;
  }

  void _scheduleCalendarFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusCalendarOnLatestMonth();
    });
  }

  void _maybeHydrateCalendarHistory() {
    if (_activeView != _QuietJournalView.calendar ||
        _loading ||
        _loadingMore ||
        _calendarHistoryHydrating ||
        !_hasMore) {
      return;
    }
    _hydrateCalendarHistory();
  }

  Future<void> _hydrateCalendarHistory() async {
    if (_calendarHistoryHydrating) return;
    setState(() {
      _calendarHistoryHydrating = true;
      _focusCalendarAfterBuild = false;
    });
    try {
      while (mounted && _activeView == _QuietJournalView.calendar && _hasMore) {
        final previousPage = _page;

        await _loadMore(preserveScrollPosition: false);

        if (!mounted || _page == previousPage) {
          break;
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _calendarHistoryHydrating = false;
          _focusCalendarAfterBuild = true;
        });
      }
    }
  }

  void _focusCalendarOnLatestMonth([int attempt = 0]) {
    if (!mounted ||
        _activeView != _QuietJournalView.calendar ||
        !_calendarScrollController.hasClients) {
      return;
    }

    final month = _latestEntryMonth();
    if (month == null) return;

    final key = _calendarMonthKeys[month];
    final context = key?.currentContext;

    if (context == null) {
      if (attempt == 0) {
        final position = _calendarScrollController.position;
        final target = _calendarSettings.sortOrder ==
                _QuietJournalCalendarSortOrder.ascending
            ? position.maxScrollExtent
            : position.minScrollExtent;
        _calendarScrollController.jumpTo(target);
      }
      if (attempt < 6) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusCalendarOnLatestMonth(attempt + 1);
        });
      }
      return;
    }

    Scrollable.ensureVisible(
      context,
      alignment: 0,
      duration: Duration.zero,
    );
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
    _persistPreviewImages();
  }

  Future<void> _restoreCachedPreviewImages(
    List<Map<String, dynamic>> entries,
  ) async {
    final restored = await _readCachedPreviewImages(entries);
    if (restored.isEmpty || !mounted) return;
    setState(() {
      _imageAttachmentsByEntry = {
        ..._imageAttachmentsByEntry,
        ...restored,
      };
    });
  }

  Future<Map<int, List<_QuietImageAttachment>>> _readCachedPreviewImages(
    List<Map<String, dynamic>> entries,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kQuietJournalImageAttachmentCacheKey);
      if (raw == null || raw.isEmpty) return const {};

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};

      final restored = <int, List<_QuietImageAttachment>>{};
      for (final entry in entries) {
        final entryId = _entryId(entry);
        if (entryId == null) continue;
        final cachedItems = decoded[entryId.toString()];
        if (cachedItems is! List) continue;
        final images = cachedItems
            .whereType<Map>()
            .map(
              (item) => _QuietImageAttachment.fromCache(
                entry,
                Map<String, dynamic>.from(item),
              ),
            )
            .whereType<_QuietImageAttachment>()
            .toList();
        if (images.isNotEmpty) {
          restored[entryId] = images;
        }
      }
      return restored;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _persistPreviewImages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{};
      for (final entry in _imageAttachmentsByEntry.entries) {
        if (entry.value.isEmpty) continue;
        payload[entry.key.toString()] =
            entry.value.map((image) => image.toCacheJson()).toList();
      }
      await prefs.setString(
        _kQuietJournalImageAttachmentCacheKey,
        jsonEncode(payload),
      );
    } catch (_) {}
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
      _persistPreviewImages();
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
        ..sort(_sortEntriesAsc);
    });
    _loadPreviewImages([updated]);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
        child: CupertinoPageScaffold(
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
                        onMenuTap: _openMiniSettingsMenu,
                        onViewChanged: (view) {
                          setState(() {
                            _activeView = view;
                            if (view == _QuietJournalView.calendar &&
                                _calendarSettings.autoFocusCurrentMonth) {
                              _focusCalendarAfterBuild = true;
                            }
                          });
                          if (view == _QuietJournalView.calendar) {
                            _maybeHydrateCalendarHistory();
                          }
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
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_focusCalendarAfterBuild &&
        !_loading &&
        _activeView == _QuietJournalView.calendar) {
      _focusCalendarAfterBuild = false;
      _scheduleCalendarFocus();
    }

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
          controller: _listScrollController,
          loadingMore: _loadingMore,
          onDeleteEntry: _deleteEntry,
          onEditEntry: _editEntry,
        ),
      _QuietJournalView.calendar => _QuietCalendarView(
          entries: _entries,
          imageAttachmentsByEntry: _imageAttachmentsByEntry,
          monthKeys: _calendarMonthKeys,
          controller: _calendarScrollController,
          loadingMore: _loadingMore,
          settings: _calendarSettings,
        ),
      _QuietJournalView.media => _QuietMediaView(
          entries: _entries,
          imageAttachmentsByEntry: _imageAttachmentsByEntry,
          onComposeTap: widget.onComposeTap,
          controller: _mediaScrollController,
          loadingMore: _loadingMore,
        ),
    };
  }
}

class _QuietJournalHeader extends StatelessWidget {
  const _QuietJournalHeader({
    required this.activeView,
    required this.onMenuTap,
    required this.onViewChanged,
    required this.onRefresh,
  });

  final _QuietJournalView activeView;
  final VoidCallback onMenuTap;
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
              _HeaderIconButton(
                icon: CupertinoIcons.line_horizontal_3,
                iconColor: JournalColors.info,
                onTap: onMenuTap,
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

class _QuietJournalMiniSettingsSheet extends StatefulWidget {
  const _QuietJournalMiniSettingsSheet({
    required this.activeView,
    required this.calendarSettings,
    required this.onCalendarSettingsChanged,
    required this.onJumpToCalendar,
    required this.onResetCalendarDefaults,
  });

  final _QuietJournalView activeView;
  final _QuietJournalCalendarSettings calendarSettings;
  final ValueChanged<_QuietJournalCalendarSettings> onCalendarSettingsChanged;
  final VoidCallback onJumpToCalendar;
  final VoidCallback onResetCalendarDefaults;

  @override
  State<_QuietJournalMiniSettingsSheet> createState() =>
      _QuietJournalMiniSettingsSheetState();
}

class _QuietJournalMiniSettingsSheetState
    extends State<_QuietJournalMiniSettingsSheet> {
  late _QuietJournalCalendarSettings _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.calendarSettings;
  }

  void _apply(_QuietJournalCalendarSettings next) {
    setState(() {
      _draft = next;
    });
    widget.onCalendarSettingsChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.82;
    return CupertinoPopupSurface(
      isSurfacePainted: false,
      child: Container(
        decoration: BoxDecoration(
          color: _withAlpha(JournalColors.bgCard, 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border.all(color: JournalColors.border),
        ),
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 16),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _withAlpha(JournalColors.textMuted, 0.6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Quiet Journal Controls',
                    style: TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tune the calendar without leaving the journal.',
                    style: TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SettingsSectionLabel(
                    title: 'Calendar',
                    trailing: widget.activeView != _QuietJournalView.calendar
                        ? 'Jump there'
                        : 'Live now',
                  ),
                  const SizedBox(height: 10),
                  _SettingsActionTile(
                    icon: CupertinoIcons.calendar,
                    title: 'Open calendar view',
                    subtitle: 'Jump straight into your month grid.',
                    onTap: widget.onJumpToCalendar,
                  ),
                  const SizedBox(height: 10),
                  _SettingsToggleTile(
                    title: 'Hide empty days',
                    subtitle: 'Only show saved days in each month grid.',
                    value: _draft.hideEmptyDays,
                    onChanged: (value) {
                      _apply(_draft.copyWith(hideEmptyDays: value));
                    },
                  ),
                  const SizedBox(height: 10),
                  _SettingsSegmentedTile(
                    title: 'Calendar order',
                    subtitle:
                        'Choose whether months stack from oldest to newest or newest to oldest.',
                    labels: _QuietJournalCalendarSortOrder.values
                        .map((order) => order.label)
                        .toList(),
                    selectedIndex: _draft.sortOrder.index,
                    onChanged: (index) {
                      _apply(
                        _draft.copyWith(
                          sortOrder:
                              _QuietJournalCalendarSortOrder.values[index],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _SettingsToggleTile(
                    title: 'Show photo previews',
                    subtitle: 'Use image thumbnails inside calendar blocks.',
                    value: _draft.showPhotoPreviews,
                    onChanged: (value) {
                      _apply(_draft.copyWith(showPhotoPreviews: value));
                    },
                  ),
                  const SizedBox(height: 10),
                  _SettingsToggleTile(
                    title: 'Jump to current month on open',
                    subtitle: 'Keep calendar landing on the latest month.',
                    value: _draft.autoFocusCurrentMonth,
                    onChanged: (value) {
                      _apply(_draft.copyWith(autoFocusCurrentMonth: value));
                    },
                  ),
                  const SizedBox(height: 10),
                  _SettingsSliderTile(
                    title: 'Calendar block size',
                    subtitle:
                        'Default is exactly what you have now. Slide for denser or bigger cards.',
                    value: _draft.blockScale,
                    min: 0.8,
                    max: 1.2,
                    valueLabel: _draft.blockScale == 1.0
                        ? 'Default'
                        : _draft.blockScale < 1.0
                            ? 'Smaller'
                            : 'Larger',
                    onChanged: (value) {
                      _apply(_draft.copyWith(blockScale: value));
                    },
                  ),
                  const SizedBox(height: 18),
                  const _SettingsSectionLabel(
                    title: 'Shortcuts',
                    trailing: 'Quick reset',
                  ),
                  const SizedBox(height: 10),
                  _SettingsActionTile(
                    icon: CupertinoIcons.arrow_counterclockwise,
                    title: 'Reset calendar defaults',
                    subtitle:
                        'Restore default day sizes and visibility settings.',
                    onTap: () {
                      widget.onResetCalendarDefaults();
                      setState(() {
                        _draft = const _QuietJournalCalendarSettings();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    color: _withAlpha(JournalColors.bgSurface, 0.92),
                    borderRadius: BorderRadius.circular(16),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Center(
                      child: Text(
                        'Done',
                        style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel({
    required this.title,
    required this.trailing,
  });

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: JournalColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        const Spacer(),
        Text(
          trailing,
          style: const TextStyle(
            color: JournalColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SettingsSegmentedTile extends StatelessWidget {
  const _SettingsSegmentedTile({
    required this.title,
    required this.subtitle,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          AdaptiveSegmentedControl(
            labels: labels,
            selectedIndex: selectedIndex,
            onValueChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingsToggleTile extends StatelessWidget {
  const _SettingsToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.86),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: JournalColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CupertinoSwitch(
            value: value,
            activeTrackColor: JournalColors.info,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingsSliderTile extends StatelessWidget {
  const _SettingsSliderTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.86),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.info, 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: JournalColors.borderBright),
                ),
                child: Text(
                  valueLabel,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          CupertinoSlider(
            value: value,
            min: min,
            max: max,
            divisions: 8,
            activeColor: JournalColors.info,
            thumbColor: JournalColors.textPrimary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _withAlpha(JournalColors.bgSurface, 0.86),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: JournalColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _withAlpha(JournalColors.info, 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: JournalColors.info, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              CupertinoIcons.chevron_right,
              color: JournalColors.textMuted,
              size: 16,
            ),
          ],
        ),
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
        final monthEntries = [...month.value]..sort(_sortEntriesDesc);
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
            ...monthEntries.map(
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
    required this.monthKeys,
    required this.controller,
    required this.loadingMore,
    required this.settings,
  });

  final List<Map<String, dynamic>> entries;
  final Map<int, List<_QuietImageAttachment>> imageAttachmentsByEntry;
  final Map<DateTime, GlobalKey> monthKeys;
  final ScrollController controller;
  final bool loadingMore;
  final _QuietJournalCalendarSettings settings;

  @override
  Widget build(BuildContext context) {
    final grouped = _groupEntriesByMonth(entries);
    final months = grouped.entries.toList()
      ..sort((a, b) {
        return settings.sortOrder == _QuietJournalCalendarSortOrder.ascending
            ? a.key.compareTo(b.key)
            : b.key.compareTo(a.key);
      });

    return LayoutBuilder(
      builder: (context, constraints) {
        final extraBottomPadding =
            settings.hideEmptyDays ? constraints.maxHeight * 0.58 : 0.0;

        return ListView.builder(
          controller: controller,
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            110 + extraBottomPadding,
          ),
          itemCount: months.length + (loadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == months.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: CupertinoActivityIndicator(
                    color: JournalColors.accent,
                  ),
                ),
              );
            }
            final month = months[index];
            final monthKey = monthKeys.putIfAbsent(
              DateTime(month.key.year, month.key.month),
              () => GlobalKey(),
            );
            return Padding(
              key: monthKey,
              padding: EdgeInsets.only(top: index == 0 ? 2 : 20),
              child: _CalendarMonthCard(
                month: month.key,
                entries: month.value,
                imageAttachmentsByEntry: imageAttachmentsByEntry,
                settings: settings,
              ),
            );
          },
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
    required this.settings,
  });

  final DateTime month;
  final List<Map<String, dynamic>> entries;
  final Map<int, List<_QuietImageAttachment>> imageAttachmentsByEntry;
  final _QuietJournalCalendarSettings settings;

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
      final dayImages = dayEntries
          .expand((entry) => _entryImages(entry, imageAttachmentsByEntry))
          .toList();
      cells.add(
        _CalendarCellData(
          date: cellDate,
          day: day,
          weekdayLabel: DateFormat('EEE').format(cellDate).toUpperCase(),
          entries: List<Map<String, dynamic>>.from(dayEntries),
          imageAttachmentsByEntry: imageAttachmentsByEntry,
          entryCount: dayEntries.length,
          photoCount: dayImages.length,
          previewPath: dayImages.isEmpty ? null : dayImages.first.path,
        ),
      );
    }

    final visibleCells = settings.hideEmptyDays
        ? cells.where((cell) => cell.entries.isNotEmpty).toList()
        : cells;
    final blockScale = settings.blockScale.clamp(0.8, 1.2);
    final gridSpacing = (12 / blockScale).clamp(8.0, 16.0);
    final childAspectRatio = 0.92 / blockScale;

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
          if (visibleCells.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                color: _withAlpha(JournalColors.bgSurface, 0.52),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: JournalColors.border),
              ),
              child: const Text(
                'No saved days in this month with the current filter.',
                style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            )
          else
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: visibleCells.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: gridSpacing,
                crossAxisSpacing: gridSpacing,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (context, index) {
                return _CalendarDayCell(
                  data: visibleCells[index],
                  settings: settings,
                );
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
    required this.date,
    required this.day,
    required this.weekdayLabel,
    required this.entries,
    required this.imageAttachmentsByEntry,
    required this.entryCount,
    required this.photoCount,
    required this.previewPath,
  });

  final DateTime date;
  final int day;
  final String weekdayLabel;
  final List<Map<String, dynamic>> entries;
  final Map<int, List<_QuietImageAttachment>> imageAttachmentsByEntry;
  final int entryCount;
  final int photoCount;
  final String? previewPath;
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.data,
    required this.settings,
  });

  final _CalendarCellData data;
  final _QuietJournalCalendarSettings settings;

  @override
  Widget build(BuildContext context) {
    final hasEntry = data.entries.isNotEmpty;
    final hasImage = data.previewPath != null && data.previewPath!.isNotEmpty;
    final showImagePreview = settings.showPhotoPreviews && hasImage;
    final overlay = data.photoCount > 0
        ? _CalendarStatsPill(
            entryCount: data.entryCount,
            photoCount: data.photoCount,
          )
        : hasEntry
            ? _CalendarTextPill(entryCount: data.entryCount)
            : null;

    return GestureDetector(
      onTap: hasEntry ? () => _openCalendarDay(context, data) : null,
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
              if (showImagePreview)
                _QuietAuthImage(
                  path: data.previewPath!,
                  cacheWidth: 360,
                )
              else
                const SizedBox.shrink(),
              if (showImagePreview)
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
                        color: showImagePreview
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
                        color: showImagePreview
                            ? CupertinoColors.white
                            : JournalColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 0.95,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const Spacer(),
                    if (overlay != null)
                      Align(
                        alignment: Alignment.bottomRight,
                        child: overlay,
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

class _CalendarTextPill extends StatelessWidget {
  const _CalendarTextPill({
    required this.entryCount,
  });

  final int entryCount;

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
          const Icon(
            CupertinoIcons.doc_text,
            color: CupertinoColors.white,
            size: 10,
          ),
          const SizedBox(width: 3),
          Text(
            '$entryCount',
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

class _CalendarStatsPill extends StatelessWidget {
  const _CalendarStatsPill({
    required this.entryCount,
    required this.photoCount,
  });

  final int entryCount;
  final int photoCount;

  @override
  Widget build(BuildContext context) {
    const itemTextStyle = TextStyle(
      color: CupertinoColors.white,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.none,
    );

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
          const Icon(CupertinoIcons.doc_text,
              color: CupertinoColors.white, size: 10),
          const SizedBox(width: 3),
          Text('$entryCount', style: itemTextStyle),
          const SizedBox(width: 6),
          Container(
            width: 1,
            height: 10,
            color: CupertinoColors.white.withValues(alpha: 0.18),
          ),
          const SizedBox(width: 6),
          const Icon(CupertinoIcons.photo,
              color: CupertinoColors.white, size: 10),
          const SizedBox(width: 3),
          Text(
            '$photoCount',
            style: itemTextStyle,
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
            _QuietAuthImage(
              path: item.path,
              cacheWidth: 720,
            ),
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
  final _sageInbox = SageInboxService();
  final _notifications = NotificationNudgeService();
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

      final entryText = _controller.text.trim();
      final result = await _api.createEntry(text: entryText);
      final entryId = result['entry_id'] as int?;
      final inboxSnapshot = await _sageInbox.createAdaptiveJournalCheckIn(
        entryText: entryText,
        entryId: entryId,
      );
      if (inboxSnapshot != null) {
        unawaited(
          _notifications.notifyNewSageInboxMessages(inboxSnapshot.messages),
        );
      }

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
    this.iconColor = JournalColors.textPrimary,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;

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
        child: Icon(icon, color: iconColor, size: 18),
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
        child: _QuietAuthImage(
          path: path!,
          cacheWidth: width.round() * 3,
        ),
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
  const _QuietAuthImage({
    required this.path,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  final String path;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  State<_QuietAuthImage> createState() => _QuietAuthImageState();
}

class _QuietAuthImageState extends State<_QuietAuthImage> {
  static final Map<String, Uint8List> _memoryCache = <String, Uint8List>{};
  static final Map<String, Future<Uint8List?>> _inFlight =
      <String, Future<Uint8List?>>{};

  final _api = ApiService();
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final cached = _memoryCache[widget.path];
    if (cached != null) {
      _bytes = cached;
      _loading = false;
      return;
    }
    _fetch();
  }

  @override
  void didUpdateWidget(covariant _QuietAuthImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      final cached = _memoryCache[widget.path];
      _bytes = cached;
      _loading = cached == null;
      if (cached == null) {
        _fetch();
      }
    }
  }

  Future<void> _fetch() async {
    try {
      final bytes = await _inFlight.putIfAbsent(widget.path, () async {
        final response = await _api.fetchImageBytes(widget.path);
        if (response.isEmpty) return null;
        return Uint8List.fromList(response);
      });
      _inFlight.remove(widget.path);
      if (bytes != null) {
        _memoryCache[widget.path] = bytes;
      }
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _loading = false;
        });
      }
    } catch (_) {
      _inFlight.remove(widget.path);
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
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      gaplessPlayback: true,
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

  static _QuietImageAttachment? fromCache(
    Map<String, dynamic> entry,
    Map<String, dynamic> cached,
  ) {
    final entryId = _entryId(entry);
    final attachmentId = cached['attachment_id']?.toString();
    if (entryId == null || attachmentId == null || attachmentId.isEmpty) {
      return null;
    }

    return _QuietImageAttachment(
      entry: Map<String, dynamic>.from(entry),
      entryId: entryId,
      attachmentId: attachmentId,
      path: '/api/entry-attachments/$attachmentId/file',
      filename: cached['filename']?.toString(),
      uploadedAt: DateTime.tryParse(cached['uploaded_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toCacheJson() {
    return {
      'attachment_id': attachmentId,
      if (filename != null && filename!.isNotEmpty) 'filename': filename,
      if (uploadedAt != null) 'uploaded_at': uploadedAt!.toIso8601String(),
    };
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

DateTime? _entrySortDate(Map<String, dynamic> entry) {
  final raw =
      entry['ingested_at']?.toString() ?? entry['entry_date']?.toString();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

int? _entryId(Map<String, dynamic> entry) {
  return (entry['id'] as num?)?.toInt();
}

int _sortEntriesAsc(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aDate = _entrySortDate(a);
  final bDate = _entrySortDate(b);
  if (aDate == null && bDate == null) {
    return (_entryId(a) ?? 0).compareTo(_entryId(b) ?? 0);
  }
  if (aDate == null) return -1;
  if (bDate == null) return 1;
  final byDate = aDate.compareTo(bDate);
  if (byDate != 0) return byDate;
  return (_entryId(a) ?? 0).compareTo(_entryId(b) ?? 0);
}

int _sortEntriesDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aDate = _entrySortDate(a);
  final bDate = _entrySortDate(b);
  if (aDate == null && bDate == null) {
    return (_entryId(b) ?? 0).compareTo(_entryId(a) ?? 0);
  }
  if (aDate == null) return 1;
  if (bDate == null) return -1;
  final byDate = bDate.compareTo(aDate);
  if (byDate != 0) return byDate;
  return (_entryId(b) ?? 0).compareTo(_entryId(a) ?? 0);
}

_QuietJournalCalendarSortOrder? _calendarSortOrderFromName(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  for (final value in _QuietJournalCalendarSortOrder.values) {
    if (value.name == raw) return value;
  }
  return null;
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

void _openCalendarDay(BuildContext context, _CalendarCellData data) {
  if (data.entries.isEmpty) return;
  Navigator.of(context).push(
    CupertinoPageRoute(
      builder: (_) => DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: _QuietJournalDayScreen(
          date: data.date,
          entries: List<Map<String, dynamic>>.from(data.entries),
          imageAttachmentsByEntry: data.imageAttachmentsByEntry,
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
      final results = await Future.wait<dynamic>([
        _api.getEntry(widget.entryId),
        _api.getEntryAttachments(widget.entryId),
      ]);
      final entry = Map<String, dynamic>.from(results[0] as Map);
      final attachments = (results[1] as List)
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
        _entry = entry;
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
    final fullText = _entryOriginalText(_entry);
    final hasFullText = fullText.isNotEmpty;

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
            _QuietEntrySwipeCard(
              summary: hasSummary
                  ? summary
                  : 'This entry does not have an AI summary yet.',
              rawText: hasFullText ? fullText : null,
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
                      child: _QuietAuthImage(
                        path: path,
                        cacheWidth: 640,
                      ),
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
    super.key,
    required this.summary,
    required this.isAiSummary,
    this.swipeHint,
  });

  final String summary;
  final bool isAiSummary;
  final String? swipeHint;

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
          if (swipeHint != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _withAlpha(JournalColors.bgBase, 0.28),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: JournalColors.border),
                  ),
                  child: Text(
                    swipeHint!,
                    style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ],
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

class _QuietEntrySwipeCard extends StatefulWidget {
  const _QuietEntrySwipeCard({
    required this.summary,
    required this.rawText,
    required this.isAiSummary,
  });

  final String summary;
  final String? rawText;
  final bool isAiSummary;

  @override
  State<_QuietEntrySwipeCard> createState() => _QuietEntrySwipeCardState();
}

class _QuietEntrySwipeCardState extends State<_QuietEntrySwipeCard> {
  bool _showRawText = false;

  bool get _canSwipe => (widget.rawText?.trim().isNotEmpty ?? false);

  void _showSummary() {
    if (!_showRawText) return;
    setState(() => _showRawText = false);
  }

  void _showRawTextCard() {
    if (!_canSwipe || _showRawText) return;
    setState(() => _showRawText = true);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -120) {
          _showRawTextCard();
        } else if (velocity > 120) {
          _showSummary();
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeOut,
        transitionBuilder: (child, animation) {
          final offsetTween = Tween<Offset>(
            begin:
                _showRawText ? const Offset(0.12, 0) : const Offset(-0.12, 0),
            end: Offset.zero,
          );
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: offsetTween.animate(animation),
              child: child,
            ),
          );
        },
        child: _showRawText && _canSwipe
            ? _QuietEntryTextSurface(
                key: const ValueKey('raw-text'),
                text: widget.rawText!,
                swipeHint: 'Swipe right for AI summary',
              )
            : _QuietEntryHeroSummary(
                key: const ValueKey('ai-summary'),
                summary: widget.summary,
                isAiSummary: widget.isAiSummary,
                swipeHint: _canSwipe ? 'Swipe left for raw entry' : null,
              ),
      ),
    );
  }
}

class _QuietEntryTextSurface extends StatelessWidget {
  const _QuietEntryTextSurface({
    super.key,
    required this.text,
    this.swipeHint,
  });

  final String text;
  final String? swipeHint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgCard, 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RAW ENTRY',
            style: TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            text,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.6,
              decoration: TextDecoration.none,
            ),
          ),
          if (swipeHint != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _withAlpha(JournalColors.bgBase, 0.28),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: JournalColors.border),
                  ),
                  child: Text(
                    swipeHint!,
                    style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _QuietDaySummaryCard extends StatelessWidget {
  const _QuietDaySummaryCard({
    required this.entryCount,
    required this.photoCount,
  });

  final int entryCount;
  final int photoCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgCardAlt, 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DAY VIEW',
            style: TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$entryCount ${entryCount == 1 ? 'post' : 'posts'} · $photoCount ${photoCount == 1 ? 'photo' : 'photos'}',
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Each card below is a separate journal post from this day. AI summaries are shown per post, not as one combined daily summary.',
            style: TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 14,
              height: 1.5,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuietJournalDayScreen extends StatelessWidget {
  const _QuietJournalDayScreen({
    required this.date,
    required this.entries,
    required this.imageAttachmentsByEntry,
  });

  final DateTime date;
  final List<Map<String, dynamic>> entries;
  final Map<int, List<_QuietImageAttachment>> imageAttachmentsByEntry;

  @override
  Widget build(BuildContext context) {
    final sortedEntries = [...entries]..sort(_sortEntriesDesc);
    final photoCount = sortedEntries.fold<int>(
      0,
      (sum, entry) => sum + _entryImages(entry, imageAttachmentsByEntry).length,
    );

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: JournalColors.bgBase.withValues(alpha: 0.94),
        border: const Border(
          bottom: BorderSide(color: JournalColors.border, width: 0.5),
        ),
        middle: Text(
          DateFormat('MMMM d, yyyy').format(date),
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
            _QuietDaySummaryCard(
              entryCount: sortedEntries.length,
              photoCount: photoCount,
            ),
            const SizedBox(height: 24),
            ...sortedEntries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: _QuietDayEntryCard(
                  entry: entry,
                  images: _entryImages(entry, imageAttachmentsByEntry),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuietDayEntryCard extends StatelessWidget {
  const _QuietDayEntryCard({
    required this.entry,
    required this.images,
  });

  final Map<String, dynamic> entry;
  final List<_QuietImageAttachment> images;

  @override
  Widget build(BuildContext context) {
    final timestamp = _entryDate(entry);
    final summary = _entrySummaryText(entry);
    final fullText = _entryOriginalText(entry);
    final metaParts = <String>[
      if (timestamp != null) DateFormat('h:mm a').format(timestamp),
      '${_wordCount(fullText)} words',
      if (images.isNotEmpty)
        '${images.length} ${images.length == 1 ? 'photo' : 'photos'}',
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgCard, 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metaParts.join(' · '),
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none,
            ),
          ),
          if (summary.isNotEmpty || fullText.isNotEmpty) ...[
            const SizedBox(height: 14),
            _QuietEntrySwipeCard(
              summary: summary.isNotEmpty
                  ? summary
                  : 'This entry does not have an AI summary yet.',
              rawText: fullText.isNotEmpty ? fullText : null,
              isAiSummary: summary.isNotEmpty,
            ),
          ],
          if (images.isNotEmpty) ...[
            const SizedBox(height: 16),
            _QuietEntrySectionLabel(
              label: images.length == 1 ? '1 Photo' : '${images.length} Photos',
            ),
            const SizedBox(height: 10),
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: images.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.92,
              ),
              itemBuilder: (context, index) {
                final image = images[index];
                return GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (_) => DefaultTextStyle.merge(
                        style: const TextStyle(
                          decoration: TextDecoration.none,
                        ),
                        child: _QuietImageLightbox(path: image.path),
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _QuietAuthImage(
                      path: image.path,
                      cacheWidth: 640,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
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
                      child: _QuietAuthImage(
                        path: path,
                        fit: BoxFit.contain,
                      ),
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
