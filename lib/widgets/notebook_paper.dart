// lib/widgets/notebook_paper.dart
//
// Ruled-paper page for Notebook Mode: cream paper, blue rules the text sits
// on, red margin line, punched holes, entry header with title + date, and a
// polaroid photo fan that spreads out when tapped.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

// ── Shared metrics (paginator in NotebookScreen must use the same numbers) ──

class NotebookMetrics {
  NotebookMetrics._();

  static const double lineHeight = 26.0;
  static const double fontSize = 16.0;

  /// Outer margin between the flip area and the paper sheet.
  static const EdgeInsets sheetMargin = EdgeInsets.fromLTRB(10, 8, 14, 12);

  static const double marginLineX = 46.0; // red vertical rule
  static const double contentLeft = 58.0;
  static const double contentRight = 26.0;
  static const double headerHeight = 92.0; // title + date + divider
  static const double topPad = 34.0; // continuation pages
  static const double bottomPad = 46.0; // page-number strip

  /// Where the rule sits inside each 26px line box (just under baseline).
  static const double ruleOffset = 20.0;

  static const TextStyle body = TextStyle(
    color: JournalColors.ink,
    fontSize: fontSize,
    height: lineHeight / fontSize,
    letterSpacing: 0.1,
    decoration: TextDecoration.none,
  );

  static const StrutStyle strut = StrutStyle(
    fontSize: fontSize,
    height: lineHeight / fontSize,
    forceStrutHeight: true,
  );

  static double bodyTop({required bool firstPage}) =>
      firstPage ? headerHeight : topPad;

  static double contentWidth(double sheetWidth) =>
      sheetWidth - contentLeft - contentRight;

  static int linesPerPage(double sheetHeight, {required bool firstPage}) {
    final available = sheetHeight - bottomPad - bodyTop(firstPage: firstPage);
    return math.max(1, (available / lineHeight).floor());
  }
}

// ── Page (front face) ──────────────────────────────────────────────────────

class NotebookPaperPage extends StatelessWidget {
  const NotebookPaperPage({
    super.key,
    required this.title,
    required this.dateLabel,
    required this.body,
    required this.isFirstPage,
    required this.pageNumber,
    this.photoFan,
  });

  final String title;
  final String dateLabel;
  final String body;
  final bool isFirstPage;
  final int pageNumber;
  final Widget? photoFan;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: NotebookMetrics.sheetMargin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: JournalColors.paper,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(3),
          bottomLeft: Radius.circular(3),
          topRight: Radius.circular(10),
          bottomRight: Radius.circular(10),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 18,
            offset: Offset(2, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _PaperPainter(firstPage: isFirstPage),
            ),
          ),

          // ── Header (first page of an entry) ──
          if (isFirstPage)
            Positioned(
              top: 18,
              left: NotebookMetrics.contentLeft,
              right: NotebookMetrics.contentRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: JournalColors.ink,
                      fontFamily: 'Noteworthy',
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    dateLabel.toUpperCase(),
                    style: const TextStyle(
                      color: JournalColors.inkSoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.4,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            )
          else
            Positioned(
              top: 12,
              right: 20,
              child: Text(
                '$title · continued',
                style: const TextStyle(
                  color: JournalColors.inkSoft,
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  decoration: TextDecoration.none,
                ),
              ),
            ),

          // ── Body text, aligned to the rules ──
          Positioned(
            top: NotebookMetrics.bodyTop(firstPage: isFirstPage),
            left: NotebookMetrics.contentLeft,
            right: NotebookMetrics.contentRight,
            bottom: NotebookMetrics.bottomPad,
            child: ClipRect(
              child: Text(
                body,
                style: NotebookMetrics.body,
                strutStyle: NotebookMetrics.strut,
              ),
            ),
          ),

          if (photoFan != null) photoFan!,

          // ── Page number ──
          Positioned(
            bottom: 14,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '– $pageNumber –',
                style: const TextStyle(
                  color: JournalColors.inkSoft,
                  fontSize: 11,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Page back (shown mid-flip) ─────────────────────────────────────────────

class NotebookPaperBack extends StatelessWidget {
  const NotebookPaperBack({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: NotebookMetrics.sheetMargin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: JournalColors.paperShade,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const SizedBox.expand(
        child: CustomPaint(painter: _PaperBackPainter()),
      ),
    );
  }
}

// ── Painters ───────────────────────────────────────────────────────────────

class _PaperPainter extends CustomPainter {
  const _PaperPainter({required this.firstPage});

  final bool firstPage;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Subtle shading toward the spine + bottom, so the sheet reads as paper.
    final shade = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        stops: [0.0, 0.14, 1.0],
        colors: [JournalColors.paperShade, JournalColors.paper, JournalColors.paper],
      ).createShader(rect);
    canvas.drawRect(rect, shade);

    // Horizontal rules.
    final rule = Paint()
      ..color = JournalColors.paperLine
      ..strokeWidth = 1.0;
    final startY = NotebookMetrics.bodyTop(firstPage: firstPage);
    final endY = size.height - NotebookMetrics.bottomPad;
    for (var y = startY + NotebookMetrics.ruleOffset;
        y <= endY;
        y += NotebookMetrics.lineHeight) {
      canvas.drawLine(
        Offset(NotebookMetrics.marginLineX - 30, y),
        Offset(size.width - 14, y),
        rule,
      );
    }

    // Red margin line.
    final margin = Paint()
      ..color = JournalColors.paperMargin
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(NotebookMetrics.marginLineX, 0),
      Offset(NotebookMetrics.marginLineX, size.height),
      margin,
    );

    // Double divider under the header.
    if (firstPage) {
      final y = NotebookMetrics.headerHeight - 14;
      canvas.drawLine(
        Offset(NotebookMetrics.contentLeft - 10, y),
        Offset(size.width - 20, y),
        rule,
      );
      canvas.drawLine(
        Offset(NotebookMetrics.contentLeft - 10, y + 3),
        Offset(size.width - 20, y + 3),
        rule,
      );
    }

    // Punched holes along the spine.
    final hole = Paint()..color = const Color(0xFF11111C);
    final holeRim = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final f in const [0.18, 0.5, 0.82]) {
      final c = Offset(20, size.height * f);
      canvas.drawCircle(c, 6.5, hole);
      canvas.drawCircle(c, 7.5, holeRim);
    }
  }

  @override
  bool shouldRepaint(covariant _PaperPainter oldDelegate) =>
      oldDelegate.firstPage != firstPage;
}

class _PaperBackPainter extends CustomPainter {
  const _PaperBackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Rules bleed through faintly, margin mirrored to the right edge.
    final rule = Paint()
      ..color = const Color(0x268094B8)
      ..strokeWidth = 1.0;
    for (var y = NotebookMetrics.topPad + NotebookMetrics.ruleOffset;
        y <= size.height - NotebookMetrics.bottomPad;
        y += NotebookMetrics.lineHeight) {
      canvas.drawLine(Offset(14, y), Offset(size.width - 16, y), rule);
    }
    final margin = Paint()
      ..color = const Color(0x40C0564B)
      ..strokeWidth = 1.2;
    final x = size.width - NotebookMetrics.marginLineX;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), margin);
  }

  @override
  bool shouldRepaint(covariant _PaperBackPainter oldDelegate) => false;
}

// ── Polaroid photo fan ─────────────────────────────────────────────────────

class NotebookPhotoFan extends StatefulWidget {
  const NotebookPhotoFan({
    super.key,
    required this.attachmentIds,
    required this.onOpen,
  });

  final List<String> attachmentIds;
  final void Function(int index) onOpen;

  @override
  State<NotebookPhotoFan> createState() => _NotebookPhotoFanState();
}

class _NotebookPhotoFanState extends State<NotebookPhotoFan> {
  bool _expanded = false;

  static const _collapsedTurns = [-0.018, 0.014, -0.032, 0.026, -0.010];
  static const _duration = Duration(milliseconds: 340);

  @override
  Widget build(BuildContext context) {
    final ids = widget.attachmentIds.take(5).toList();

    return Positioned(
      left: NotebookMetrics.contentLeft - 24,
      right: 18,
      bottom: 32,
      height: 118,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final spread = ids.length <= 1
              ? 0.0
              : math.min(
                  94.0,
                  (constraints.maxWidth - 92) / (ids.length - 1),
                );
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = ids.length - 1; i >= 0; i--)
                AnimatedPositioned(
                  duration: _duration,
                  curve: Curves.easeOutBack,
                  right: _expanded ? i * spread : i * 7.0,
                  bottom: _expanded ? 0.0 : i * 5.0,
                  child: AnimatedRotation(
                    duration: _duration,
                    curve: Curves.easeOutBack,
                    turns: _expanded
                        ? (i.isEven ? 0.005 : -0.007)
                        : _collapsedTurns[i % _collapsedTurns.length],
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (!_expanded) {
                          setState(() => _expanded = true);
                        } else {
                          widget.onOpen(i);
                        }
                      },
                      onLongPress: () => setState(() => _expanded = !_expanded),
                      child: _Polaroid(attachmentId: ids[i]),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Polaroid extends StatelessWidget {
  const _Polaroid({required this.attachmentId});

  final String attachmentId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 5, 5, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFBF4),
        borderRadius: BorderRadius.circular(2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: SizedBox(
        width: 76,
        height: 76,
        child: NotebookAuthImage(
          path: '/api/entry-attachments/$attachmentId/file',
          decodeWidth: 240, // 76 logical px @3x — tiny decode, huge RAM win
        ),
      ),
    );
  }
}

// ── Authenticated image (Dio bytes — Image.network caches auth failures) ───
//
// IMPORTANT: bytes are converted to a Uint8List ONCE and reused. Building a
// new Uint8List on every build gives Image.memory a new cache key each
// frame, forcing a full re-decode of the photo 60×/sec during the flip
// animation — which balloons memory until iOS jetsams the app.

class NotebookAuthImage extends StatefulWidget {
  const NotebookAuthImage({
    super.key,
    required this.path,
    this.decodeWidth,
    this.fit = BoxFit.cover,
  });

  final String path;

  /// Caps the decoded bitmap width (logical px × dpr handled by caller).
  /// A camera photo decodes to ~48 MB at full size; a 76px polaroid
  /// needs a tiny fraction of that.
  final int? decodeWidth;
  final BoxFit fit;

  @override
  State<NotebookAuthImage> createState() => _NotebookAuthImageState();
}

class _NotebookAuthImageState extends State<NotebookAuthImage> {
  final _api = ApiService();
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
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
        child: CupertinoActivityIndicator(color: JournalColors.inkSoft),
      );
    }
    if (_bytes == null) {
      return const ColoredBox(
        color: Color(0xFFE7DFCC),
        child: Center(
          child: Icon(
            CupertinoIcons.photo,
            color: JournalColors.inkSoft,
            size: 22,
          ),
        ),
      );
    }
    return Image.memory(
      _bytes!,
      fit: widget.fit,
      gaplessPlayback: true,
      cacheWidth: widget.decodeWidth,
    );
  }
}
