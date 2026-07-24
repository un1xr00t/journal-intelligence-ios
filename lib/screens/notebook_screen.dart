// lib/screens/notebook_screen.dart
//
// Notebook Mode — flip through every journal entry like a real paper
// notebook. Entries run oldest → newest; the book opens on the most recent
// entry so flipping backward walks into the past. Long entries continue
// across pages; text is measured with the exact paper metrics so every
// line sits on a rule.

import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/notebook_page_flip.dart';
import '../widgets/notebook_paper.dart';

class NotebookScreen extends StatefulWidget {
  const NotebookScreen({super.key});

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NbPage {
  const _NbPage({
    required this.entryId,
    required this.title,
    required this.dateLabel,
    required this.body,
    required this.isFirstPage,
  });

  final int entryId;
  final String title;
  final String dateLabel;
  final String body;
  final bool isFirstPage;
}

class _NotebookScreenState extends State<NotebookScreen> {
  final _api = ApiService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _entries = [];

  List<_NbPage>? _pages;
  Size? _pagedSize;
  int _initialIndex = 0;
  int _current = 0;

  final Map<int, List<String>> _photos = {};
  final Set<int> _photosRequested = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await _api.getAllEntriesForExport();
      entries.sort((a, b) => _entryDate(a).compareTo(_entryDate(b)));
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _pages = null; // repaginate on next layout
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Couldn’t load your journal. Pull yourself back later.';
        _loading = false;
      });
    }
  }

  // ── Entry helpers ────────────────────────────────────────────────────────

  DateTime _entryDate(Map<String, dynamic> e) {
    final raw = (e['entry_date'] ?? e['ingested_at'] ?? '').toString();
    return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _entryText(Map<String, dynamic> e) {
    return (e['normalized_text'] as String? ?? e['text'] as String? ?? '')
        .trim();
  }

  String _titleFor(String text, DateTime date) {
    final firstLine = text
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return DateFormat('MMMM d').format(date);

    var title = '';
    for (final word in firstLine.split(RegExp(r'\s+'))) {
      final next = title.isEmpty ? word : '$title $word';
      if (next.length > 34) break;
      title = next;
    }
    if (title.isEmpty) title = firstLine;
    if (title.length < firstLine.length) title = '$title…';
    return title;
  }

  // ── Pagination ───────────────────────────────────────────────────────────

  List<_NbPage> _buildPages(Size flipArea) {
    final margin = NotebookMetrics.sheetMargin;
    final sheetW = flipArea.width - margin.horizontal;
    final sheetH = flipArea.height - margin.vertical;
    final textWidth = NotebookMetrics.contentWidth(sheetW);
    final firstLines = NotebookMetrics.linesPerPage(sheetH, firstPage: true);
    final contLines = NotebookMetrics.linesPerPage(sheetH, firstPage: false);

    final pages = <_NbPage>[];
    for (final entry in _entries) {
      final id = entry['id'] as int? ?? -1;
      if (id < 0) continue;
      final date = _entryDate(entry);
      final text = _entryText(entry);
      final title = _titleFor(text, date);
      final dateLabel = DateFormat('EEEE, MMMM d, y').format(date);

      final chunks = _splitByLines(text, textWidth, firstLines, contLines);
      for (var i = 0; i < chunks.length; i++) {
        pages.add(_NbPage(
          entryId: id,
          title: title,
          dateLabel: dateLabel,
          body: chunks[i],
          isFirstPage: i == 0,
        ));
      }
    }
    return pages;
  }

  List<String> _splitByLines(
    String text,
    double width,
    int firstLines,
    int contLines,
  ) {
    if (text.isEmpty) return [''];

    final chunks = <String>[];
    var remaining = text;
    var isFirst = true;

    while (remaining.isNotEmpty) {
      final allowed = isFirst ? firstLines : contLines;
      final painter = TextPainter(
        text: TextSpan(text: remaining, style: NotebookMetrics.body),
        textDirection: TextDirection.ltr,
        strutStyle: NotebookMetrics.strut,
      )..layout(maxWidth: width);

      final lines = painter.computeLineMetrics();
      if (lines.length <= allowed) {
        painter.dispose();
        chunks.add(remaining);
        break;
      }

      final lastVisible = lines[allowed - 1];
      final cut = painter
          .getPositionForOffset(Offset(width, lastVisible.baseline))
          .offset;
      painter.dispose();

      if (cut <= 0 || cut >= remaining.length) {
        chunks.add(remaining);
        break;
      }
      chunks.add(remaining.substring(0, cut).trimRight());
      remaining = remaining.substring(cut).trimLeft();
      isFirst = false;
    }
    return chunks;
  }

  // ── Photos (lazy, per entry) ─────────────────────────────────────────────

  void _prefetchPhotosAround(int pageIndex) {
    final pages = _pages;
    if (pages == null) return;
    for (var i = pageIndex - 1; i <= pageIndex + 1; i++) {
      if (i < 0 || i >= pages.length) continue;
      _fetchPhotos(pages[i].entryId);
    }
  }

  Future<void> _fetchPhotos(int entryId) async {
    if (_photosRequested.contains(entryId)) return;
    _photosRequested.add(entryId);
    try {
      final attachments = await _api.getEntryAttachments(entryId);
      final ids = attachments
          .whereType<Map>()
          .where(
            (a) => a['media_type']?.toString().startsWith('image/') ?? false,
          )
          .map((a) => a['id'].toString())
          .toList();
      if (mounted && ids.isNotEmpty) {
        setState(() => _photos[entryId] = ids);
      }
    } catch (_) {
      _photosRequested.remove(entryId); // retry next time it's visible
    }
  }

  void _openLightbox(List<String> attachmentIds, int initialIndex) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: _NotebookLightbox(
            attachmentIds: attachmentIds,
            initialIndex: initialIndex,
          ),
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  Widget _buildPage(BuildContext context, int index) {
    final page = _pages![index];
    final photoIds = _photos[page.entryId];

    return NotebookPaperPage(
      title: page.title,
      dateLabel: page.dateLabel,
      body: page.body,
      isFirstPage: page.isFirstPage,
      pageNumber: index + 1,
      photoFan: (page.isFirstPage && photoIds != null && photoIds.isNotEmpty)
          ? NotebookPhotoFan(
              attachmentIds: photoIds,
              onOpen: (index) => _openLightbox(photoIds, index),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CupertinoActivityIndicator(color: JournalColors.accent),
      );
    }
    if (_error != null || _entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _error ?? 'No entries yet. Your notebook is waiting.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final area = Size(constraints.maxWidth, constraints.maxHeight);
        if (_pages == null || _pagedSize != area) {
          _pages = _buildPages(area);
          _pagedSize = area;
          final lastEntryStart = _pages!.lastIndexWhere((p) => p.isFirstPage);
          _initialIndex = lastEntryStart < 0 ? 0 : lastEntryStart;
          _current = _initialIndex;
          Future(() {
            if (mounted) {
              setState(() {}); // refresh the page counter in the nav bar
              _prefetchPhotosAround(_initialIndex);
            }
          });
        }
        final pages = _pages!;
        if (pages.isEmpty) return const SizedBox.shrink();

        return NotebookPageFlip(
          key: ValueKey('nb-${pages.length}-${area.width}x${area.height}'),
          pageCount: pages.length,
          initialIndex: _initialIndex,
          pageBuilder: _buildPage,
          backBuilder: (_) => const NotebookPaperBack(),
          onPageChanged: (index) {
            setState(() => _current = index);
            _prefetchPhotosAround(index);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _pages?.length ?? 0;

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: JournalColors.bgBase.withValues(alpha: 0.9),
        border: const Border(
          bottom: BorderSide(color: JournalColors.border, width: 0.5),
        ),
        middle: const Text(
          'Notebook',
          style: TextStyle(color: JournalColors.textPrimary),
        ),
        trailing: total > 0
            ? Text(
                '${_current + 1} / $total',
                style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 13,
                ),
              )
            : null,
      ),
      child: SafeArea(child: _buildBody()),
    );
  }
}

// ── Lightbox ───────────────────────────────────────────────────────────────

class _NotebookLightbox extends StatefulWidget {
  const _NotebookLightbox({
    required this.attachmentIds,
    required this.initialIndex,
  });

  final List<String> attachmentIds;
  final int initialIndex;

  @override
  State<_NotebookLightbox> createState() => _NotebookLightboxState();
}

class _NotebookLightboxState extends State<_NotebookLightbox> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showPrevious() {
    if (_currentIndex == 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _showNext() {
    if (_currentIndex == widget.attachmentIds.length - 1) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  String _pathFor(int index) {
    return '/api/entry-attachments/${widget.attachmentIds[index]}/file';
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.attachmentIds.length;

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.15,
                    colors: [JournalColors.bgSurface, JournalColors.bgBase],
                  ),
                ),
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: total,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index);
                  },
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 76, 16, 84),
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 720),
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                          decoration: BoxDecoration(
                            color: JournalColors.paper,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: JournalColors.paperShade),
                            boxShadow: const [
                              BoxShadow(
                                color: JournalColors.accentGlow,
                                blurRadius: 32,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: SizedBox.expand(
                              child: NotebookAuthImage(
                                path: _pathFor(index),
                                decodeWidth: 2000,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 16,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: JournalColors.bgCard,
                    borderRadius: BorderRadius.circular(999),
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
            Positioned(
              top: 12,
              left: 72,
              right: 72,
              child: Column(
                children: [
                  const Text(
                    'ENTRY PHOTOS',
                    style: TextStyle(
                      color: JournalColors.inkSoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_currentIndex + 1} of $total',
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (total > 1) ...[
              Positioned(
                left: 14,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _NotebookPhotoNavButton(
                    icon: CupertinoIcons.chevron_left,
                    enabled: _currentIndex > 0,
                    onPressed: _showPrevious,
                  ),
                ),
              ),
              Positioned(
                right: 14,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _NotebookPhotoNavButton(
                    icon: CupertinoIcons.chevron_right,
                    enabled: _currentIndex < total - 1,
                    onPressed: _showNext,
                  ),
                ),
              ),
              if (total <= 12)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(total, (index) {
                      final selected = index == _currentIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: selected ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: selected
                              ? JournalColors.paper
                              : JournalColors.textMuted,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotebookPhotoNavButton extends StatelessWidget {
  const _NotebookPhotoNavButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !enabled,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled ? 1 : 0,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          child: Container(
            width: 38,
            height: 54,
            decoration: BoxDecoration(
              color: JournalColors.bgCard.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: JournalColors.borderBright),
            ),
            child: Icon(icon, color: JournalColors.textPrimary, size: 20),
          ),
        ),
      ),
    );
  }
}
