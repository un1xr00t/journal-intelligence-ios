// lib/screens/timeline_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'entry_detail_screen.dart';

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

  Map<String, dynamic>? _masterSummary;
  bool _summaryLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSummary();
    _scroll.addListener(_onScroll);
  }

  Future<void> _loadSummary() async {
    try {
      final data = await _api.getLivingSummary();
      if (mounted) setState(() { _masterSummary = data; _summaryLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _summaryLoading = false; });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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
      setState(() {
        _entries = data.cast<Map<String, dynamic>>();
        _loading = false;
        _hasMore = data.length == 20;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadNext() async {
    setState(() { _loadMore = true; });
    try {
      final data = await _api.getTimeline(page: _page + 1);
      setState(() {
        _entries.addAll(data.cast<Map<String, dynamic>>());
        _page++;
        _loadMore = false;
        _hasMore  = data.length == 20;
      });
    } catch (_) {
      setState(() { _loadMore = false; });
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
              child: Center(child: CupertinoActivityIndicator(color: JournalColors.accent)),
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
                    Icon(CupertinoIcons.book, color: JournalColors.textMuted, size: 56),
                    SizedBox(height: 16),
                    Text('No entries yet.',
                        style: TextStyle(color: JournalColors.textSecondary, fontSize: 16)),
                    SizedBox(height: 8),
                    Text('Start writing in the Write tab.',
                        style: TextStyle(color: JournalColors.textMuted, fontSize: 14)),
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
                    // Index 0 is always the master summary card
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: _MasterSummaryCard(
                          summary: _masterSummary,
                          loading: _summaryLoading,
                          onGenerated: _loadSummary,
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
                        onTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => EntryDetailScreen(
                              entryId: entry['id'] as int,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: _entries.length + 2, // +1 summary +1 spinner/spacer
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Master Summary Card ───────────────────────────────────────────────────────

class _MasterSummaryCard extends StatefulWidget {
  const _MasterSummaryCard({required this.summary, required this.loading, required this.onGenerated});
  final Map<String, dynamic>? summary;
  final bool loading;
  final VoidCallback onGenerated;

  @override
  State<_MasterSummaryCard> createState() => _MasterSummaryCardState();
}

class _MasterSummaryCardState extends State<_MasterSummaryCard> {
  final _api = ApiService();
  bool _generating = false;

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      await _api.generateMasterSummary();
      if (mounted) {
        setState(() => _generating = false);
        widget.onGenerated();
      }
    } catch (_) {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return GlassCard(
        child: Row(children: const [
          CupertinoActivityIndicator(color: JournalColors.accent, radius: 8),
          SizedBox(width: 12),
          Text('Loading summary…',
              style: TextStyle(color: JournalColors.textMuted, fontSize: 14)),
        ]),
      );
    }

    // Response is already unwrapped to the row dict (or empty map if null)
    // Try common column names for the summary text
    final text = (widget.summary?['summary_text']
        ?? widget.summary?['summary']
        ?? widget.summary?['content']
        ?? widget.summary?['text']) as String?;
    final count = (widget.summary?['entry_count']
        ?? widget.summary?['entries_count']) as int?;

    if (text == null || text.isEmpty) {
      return GlassCard(
        child: Row(children: [
          const Icon(CupertinoIcons.doc_text, color: JournalColors.textMuted, size: 18),
          const SizedBox(width: 12),
          const Expanded(child: Text('No master summary yet.',
              style: TextStyle(color: JournalColors.textMuted, fontSize: 14))),
          GestureDetector(
            onTap: _generating ? null : _generate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: JournalColors.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: JournalColors.borderBright),
              ),
              child: _generating
                  ? const CupertinoActivityIndicator(color: JournalColors.accent, radius: 7)
                  : const Text('Generate', style: TextStyle(
                      color: JournalColors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      );
    }

    return GlassCard(
      accentBorder: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(CupertinoIcons.sparkles, color: JournalColors.accent, size: 14),
          const SizedBox(width: 8),
          const Text('MASTER SUMMARY', style: TextStyle(
              color: JournalColors.textMuted, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const Spacer(),
          if (count != null)
            Text('$count entries', style: const TextStyle(
                color: JournalColors.textMuted, fontSize: 11)),
        ]),
        const SizedBox(height: 10),
        Text(text, style: const TextStyle(
            color: JournalColors.textSecondary, fontSize: 14, height: 1.6)),
      ]),
    );
  }
}

// ── Entry Tile ────────────────────────────────────────────────────────────────

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final Map<String, dynamic> entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    debugPrint('--- summary_text: ${entry['summary_text']}');
    final rawDate = entry['entry_date'] ?? entry['ingested_at'] ?? '';
    final date = _parseDate(rawDate);
    final text  = (entry['text'] as String? ?? '').trim();
    // summary_text is the AI narrative; fall back to normalized_text then raw text
    final displayText = ((entry['summary_text']
        ?? entry['normalized_text']
        ?? entry['text']) as String? ?? '').trim();
    final preview = displayText.length > 200 ? '${displayText.substring(0, 200)}…' : displayText;
    final wordCount = (entry['word_count'] as num?)?.toInt() ??
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    date,
                    style: const TextStyle(
                      color: JournalColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '$wordCount words',
                  style: const TextStyle(
                      color: JournalColors.textMuted, fontSize: 12),
                ),
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
      final dt = DateTime.parse(raw);
      return DateFormat('EEE, MMM d, y').format(dt);
    } catch (_) {
      return raw;
    }
  }
}
