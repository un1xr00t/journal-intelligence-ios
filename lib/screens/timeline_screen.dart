// lib/screens/timeline_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';


// ── Timeline Screen ───────────────────────────────────────────────────────────

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  final _api    = ApiService();
  final _scroll = ScrollController();

  List<Map<String, dynamic>> _entries = [];
  bool _loading  = true;
  bool _loadMore = false;
  bool _hasMore  = true;
  int  _page     = 1;
  String? _error;

  // summary is the unwrapped data object:
  // { current_state, overall_arc, key_themes, key_people, active_threads, notable_patterns }
  Map<String, dynamic>? _masterSummary;
  bool _summaryLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSummary();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<String> _getPreferredTone() async {
    try {
      final data = await _api.getMemory();
      final m = (data['memory'] ?? data) as Map<String, dynamic>;
      return m['preferred_tone'] as String? ?? 'therapist';
    } catch (_) {
      return 'therapist';
    }
  }

  Future<void> _loadSummary() async {
    if (_masterSummary != null) return;
    if (mounted) setState(() => _summaryLoading = true);
    try {
      final tone = await _getPreferredTone();
      final data = await _api.getTherapistInsightStatus(tone: tone);
      final hasContent = (data['insight'] as String?)?.isNotEmpty == true;
      if (mounted) setState(() {
        _masterSummary = hasContent ? data : null;
        _summaryLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _masterSummary = null; _summaryLoading = false; });
    }
  }

  Future<void> _regenerateSummary() async {
    if (mounted) setState(() { _masterSummary = null; _summaryLoading = true; });
    try {
      final tone = await _getPreferredTone();
      final data = await _api.generateTherapistInsight(tone: tone, force: true);
      final hasContent = (data['insight'] as String?)?.isNotEmpty == true;
      if (mounted) setState(() {
        _masterSummary = hasContent ? data : null;
        _summaryLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _masterSummary = null; _summaryLoading = false; });
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 &&
        !_loadMore && _hasMore) {
      _loadNext();
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _page = 1; _hasMore = true; _error = null; });
    try {
      final data = await _api.getTimeline(page: 1);
      if (mounted) setState(() {
        _entries = data.cast<Map<String, dynamic>>();
        _loading = false;
        _hasMore = data.length == 20;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadNext() async {
    setState(() => _loadMore = true);
    try {
      final data = await _api.getTimeline(page: _page + 1);
      if (mounted) setState(() {
        _entries.addAll(data.cast<Map<String, dynamic>>());
        _page++;
        _loadMore = false;
        _hasMore  = data.length == 20;
      });
    } catch (_) {
      if (mounted) setState(() => _loadMore = false);
    }
  }

  Future<void> _deleteEntry(int index, int entryId) async {
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
    if (confirm == true) {
      try {
        await _api.deleteEntry(entryId);
        if (mounted) setState(() => _entries.removeAt(index));
      } catch (_) {}
    }
  }

  Future<void> _editEntry(int index, Map<String, dynamic> entry) async {
    final updated = await Navigator.push<Map<String, dynamic>>(
      context,
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: _EditEntryScreen(entry: entry, api: _api),
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _entries[index] = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Timeline'),
            backgroundColor: JournalColors.bgBase.withOpacity(0.9),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
            trailing: GestureDetector(
              onTap: _load,
              child: const Icon(CupertinoIcons.refresh, color: JournalColors.accent),
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.wifi_slash,
                        color: JournalColors.textMuted, size: 48),
                    const SizedBox(height: 16),
                    Text(_error!,
                        style: const TextStyle(color: JournalColors.textSecondary)),
                    const SizedBox(height: 20),
                    CupertinoButton(
                      color: JournalColors.accent,
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )

          else if (_entries.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.book,
                        color: JournalColors.textMuted, size: 56),
                    SizedBox(height: 16),
                    Text('No entries yet.',
                        style: TextStyle(
                            color: JournalColors.textSecondary, fontSize: 16)),
                    SizedBox(height: 8),
                    Text('Start writing in the Write tab.',
                        style: TextStyle(
                            color: JournalColors.textMuted, fontSize: 14)),
                  ],
                ),
              ),
            )

          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    // index 0 = living summary card
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: _MasterSummaryCard(
                          summary: _masterSummary,
                          loading: _summaryLoading,
                          onRefresh: _regenerateSummary,
                        ),
                      );
                    }
                    final entryIndex = index - 1;
                    if (entryIndex == _entries.length) {
                      return _loadMore
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(
                                child: CupertinoActivityIndicator(
                                    color: JournalColors.accent),
                              ),
                            )
                          : const SizedBox(height: 40);
                    }
                    final entry = _entries[entryIndex];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _EntryTile(
                        entry: entry,
                        onDelete: () => _deleteEntry(entryIndex, entry['id'] as int),
                        onEdit: () => _editEntry(entryIndex, entry),
                      ),
                    );
                  },
                  childCount: _entries.length + 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Master Summary Card ───────────────────────────────────────────────────────
// API: GET /api/summary/master
//   Returns: { message, data: { current_state, overall_arc, key_themes,
//              key_people, active_threads, notable_patterns } | null }
//   getLivingSummary() unwraps body['data'] → {} when null.
//   Swipe right to regenerate. No auto-generation on load.

class _MasterSummaryCard extends StatefulWidget {
  const _MasterSummaryCard({
    required this.summary,
    required this.loading,
    required this.onRefresh,
  });

  final Map<String, dynamic>? summary;
  final bool loading;
  final Future<void> Function() onRefresh;

  @override
  State<_MasterSummaryCard> createState() => _MasterSummaryCardState();
}

class _MasterSummaryCardState extends State<_MasterSummaryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // Loading
    if (widget.loading) {
      return GlassCard(
        child: Row(
          children: const [
            CupertinoActivityIndicator(color: JournalColors.accent, radius: 8),
            SizedBox(width: 12),
            Text('Loading summary...',
                style: TextStyle(color: JournalColors.textMuted, fontSize: 14)),
          ],
        ),
      );
    }

    final insight = widget.summary?['insight'] as String?;

    // No insight yet — swipe right to generate
    if (insight == null || insight.isEmpty) {
      return Dismissible(
        key: const ValueKey('summary-empty'),
        direction: DismissDirection.startToEnd,
        confirmDismiss: (_) async {
          await widget.onRefresh();
          return false;
        },
        background: Container(
          decoration: BoxDecoration(
            color: JournalColors.accent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          child: const Row(
            children: [
              Icon(CupertinoIcons.refresh, color: JournalColors.accent, size: 18),
              SizedBox(width: 8),
              Text('Generate',
                  style: TextStyle(
                      color: JournalColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        child: GlassCard(
          child: Row(
            children: const [
              Icon(CupertinoIcons.doc_text,
                  color: JournalColors.textMuted, size: 18),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No living summary yet. Swipe right to generate.',
                  style: TextStyle(color: JournalColors.textMuted, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Populated — real fields from GET /api/therapist/insight/status
    final entryDate  = widget.summary?['entry_date'] as String?;
    final entryCount = (widget.summary?['entry_count'] as num?)?.toInt();
    final cached     = widget.summary?['cached'] as bool? ?? false;

    return Dismissible(
      key: const ValueKey('summary-populated'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        await widget.onRefresh();
        return false;
      },
      background: Container(
        decoration: BoxDecoration(
          color: JournalColors.accent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Row(
          children: [
            Icon(CupertinoIcons.refresh, color: JournalColors.accent, size: 18),
            SizedBox(width: 8),
            Text('Refresh',
                style: TextStyle(
                    color: JournalColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      child: GlassCard(
        accentBorder: true,
        onTap: () => setState(() => _expanded = !_expanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(CupertinoIcons.sparkles,
                    color: JournalColors.accent, size: 14),
                const SizedBox(width: 8),
                Text(
                  '${((widget.summary?['tone_name'] as String?) ?? 'Therapist').toUpperCase()} INSIGHT',
                  style: const TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                if (cached)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: JournalColors.accent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('cached',
                        style: TextStyle(
                            color: JournalColors.textMuted,
                            fontSize: 9,
                            letterSpacing: 0.5)),
                  ),
                const Spacer(),
                Icon(
                  _expanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  color: JournalColors.textMuted,
                  size: 12,
                ),
              ],
            ),

            // Date range + entry count
            if (entryDate != null || entryCount != null) ...[
              const SizedBox(height: 4),
              Text(
                [
                  if (entryDate != null) entryDate,
                  if (entryCount != null) '$entryCount entries',
                ].join(' · '),
                style: const TextStyle(
                    color: JournalColors.textMuted, fontSize: 11),
              ),
            ],

            const SizedBox(height: 10),

            // Insight text — collapsed to 4 lines, expands on tap
            Text(
              insight,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
                height: 1.65,
              ),
              maxLines: _expanded ? null : 4,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Entry Tile ────────────────────────────────────────────────────────────────

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.onDelete,
    required this.onEdit,
  });

  final Map<String, dynamic> entry;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final rawDate     = (entry['entry_date'] ?? entry['ingested_at'] ?? '') as String;
    final date        = _parseDate(rawDate);
    final text        = (entry['text'] as String? ?? '').trim();
    final displayText = ((entry['summary_text'] ??
            entry['normalized_text'] ??
            entry['text']) as String? ?? '').trim();
    final preview     = displayText.length > 200
        ? '${displayText.substring(0, 200)}...'
        : displayText;
    final wordCount   = (entry['word_count'] as num?)?.toInt() ??
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    return Dismissible(
      key: ValueKey('entry-${entry['id']}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Swipe right → delete
          onDelete();
          return false; // We handle removal ourselves after confirm
        } else {
          // Swipe left → edit
          onEdit();
          return false;
        }
      },
      // Swipe right = delete (red)
      background: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Row(
          children: [
            Icon(CupertinoIcons.trash, color: Color(0xFFEF4444), size: 20),
            SizedBox(width: 8),
            Text('Delete',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      // Swipe left = edit (accent)
      secondaryBackground: Container(
        decoration: BoxDecoration(
          color: JournalColors.accent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Edit',
                style: TextStyle(
                    color: JournalColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            SizedBox(width: 8),
            Icon(CupertinoIcons.pencil, color: JournalColors.accent, size: 20),
          ],
        ),
      ),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(date,
                      style: const TextStyle(
                          color: JournalColors.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
                Text('$wordCount words',
                    style: const TextStyle(
                        color: JournalColors.textMuted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              preview,
              style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 15,
                height: 1.55,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _parseDate(String raw) {
    try {
      return DateFormat('EEE, MMM d, y').format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }
}

// ── Edit Entry Screen ─────────────────────────────────────────────────────────

class _EditEntryScreen extends StatefulWidget {
  const _EditEntryScreen({required this.entry, required this.api});
  final Map<String, dynamic> entry;
  final ApiService api;

  @override
  State<_EditEntryScreen> createState() => _EditEntryScreenState();
}

class _EditEntryScreenState extends State<_EditEntryScreen> {
  TextEditingController? _ctrl;
  bool _loading = true;
  bool _saving  = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRaw();
  }

  Future<void> _loadRaw() async {
    try {
      final data = await widget.api.getEntry(widget.entry['id'] as int);
      final raw = (data['normalized_text'] as String? ?? '').trim();
      if (mounted) {
        setState(() {
          _ctrl = TextEditingController(text: raw);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Failed to load entry.'; });
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newText = _ctrl?.text.trim() ?? '';
    if (newText.isEmpty) return;
    setState(() { _saving = true; _error = null; });
    try {
      final updated = await widget.api.updateEntry(widget.entry['id'] as int, newText);
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = 'Failed to save.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: JournalColors.bgBase.withOpacity(0.9),
        border: const Border(
          bottom: BorderSide(color: JournalColors.border, width: 0.5),
        ),
        middle: const Text('Edit Entry',
            style: TextStyle(color: JournalColors.textPrimary)),
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: JournalColors.textMuted)),
        ),
        trailing: _saving
            ? const CupertinoActivityIndicator(
                color: JournalColors.accent, radius: 9)
            : GestureDetector(
                onTap: _save,
                child: const Text('Save',
                    style: TextStyle(
                        color: JournalColors.accent,
                        fontWeight: FontWeight.w600)),
              ),
      ),
      child: _loading
          ? const Center(
              child: CupertinoActivityIndicator(
                  color: JournalColors.accent, radius: 12),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      Text(_error!,
                          style: const TextStyle(
                              color: Color(0xFFEF4444), fontSize: 13)),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: CupertinoTextField(
                        controller: _ctrl,
                        maxLines: null,
                        minLines: 10,
                        autofocus: true,
                        style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 16,
                          height: 1.6,
                        ),
                        placeholder: 'Write your entry...',
                        placeholderStyle: const TextStyle(
                            color: JournalColors.textMuted, fontSize: 16),
                        decoration: const BoxDecoration(color: Colors.transparent),
                        keyboardAppearance: Brightness.dark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}