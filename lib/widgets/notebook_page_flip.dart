// lib/widgets/notebook_page_flip.dart
//
// Interactive, drag-driven page curl for Notebook Mode.
// The sheet physically bends around a cylinder that tracks your finger
// (fragment shader: assets/shaders/page_curl.frag) — front rolls away,
// the paper's back wraps over the crest with ink bleed-through, and a
// soft shadow travels across the page beneath. Release settles with
// velocity-aware physics, exactly like turning a real paper page.

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

class NotebookPageFlip extends StatefulWidget {
  const NotebookPageFlip({
    super.key,
    required this.pageCount,
    required this.pageBuilder,
    required this.backBuilder,
    this.initialIndex = 0,
    this.onPageChanged,
  });

  final int pageCount;

  /// Builds the front (content) face of page [index].
  final IndexedWidgetBuilder pageBuilder;

  /// Builds the back face shown while a page is mid-flip (blank ruled paper).
  final WidgetBuilder backBuilder;

  final int initialIndex;
  final ValueChanged<int>? onPageChanged;

  @override
  State<NotebookPageFlip> createState() => _NotebookPageFlipState();
}

class _NotebookPageFlipState extends State<NotebookPageFlip>
    with SingleTickerProviderStateMixin {
  // _turn ∈ [-1, 1]. 0 = at rest on _index.
  // > 0 → current page lifting toward the spine (flipping forward).
  // < 0 → previous page folding back over (flipping backward).
  late final AnimationController _turn;
  late int _index;

  @override
  void initState() {
    super.initState();
    final maxIndex = widget.pageCount > 0 ? widget.pageCount - 1 : 0;
    _index = math.max(0, math.min(widget.initialIndex, maxIndex));
    _turn = AnimationController(
      vsync: this,
      lowerBound: -1.0,
      upperBound: 1.0,
      value: 0.0,
      duration: const Duration(milliseconds: 450),
    );
    _turn.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  bool get _canForward => _index < widget.pageCount - 1;
  bool get _canBackward => _index > 0;

  // ── Gestures ─────────────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails details) {
    if (_turn.isAnimating) _turn.stop();
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    var value = _turn.value - details.delta.dx / (width * 0.92);
    // Soft resistance at the covers.
    if (!_canForward && value > 0) value = math.min(value, 0.05);
    if (!_canBackward && value < 0) value = math.max(value, -0.05);
    _turn.value = value.clamp(-1.0, 1.0);
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    final vx = details.velocity.pixelsPerSecond.dx;
    final t = _turn.value;

    double target = 0.0;
    if (t > 0 && _canForward) {
      final commit = (t > 0.42 && vx < 300) || vx < -600;
      target = commit ? 1.0 : 0.0;
    } else if (t < 0 && _canBackward) {
      final commit = (t < -0.42 && vx > -300) || vx > 600;
      target = commit ? -1.0 : 0.0;
    }
    await _settle(target);
  }

  Future<void> _settle(double target) async {
    final distance = (target - _turn.value).abs();
    await _turn.animateTo(
      target,
      duration: Duration(
        milliseconds: math.max(150, (430 * distance).round()),
      ),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    if (target == 1.0) {
      setState(() {
        _index++;
        _turn.value = 0.0;
      });
      HapticFeedback.lightImpact();
      widget.onPageChanged?.call(_index);
    } else if (target == -1.0) {
      setState(() {
        _index--;
        _turn.value = 0.0;
      });
      HapticFeedback.lightImpact();
      widget.onPageChanged?.call(_index);
    }
  }

  /// Animated flip triggered by tapping near the page edges.
  void _tapFlip(TapUpDetails details, double width) {
    if (_turn.isAnimating || _turn.value != 0.0) return;
    final x = details.localPosition.dx;
    if (x > width * 0.82 && _canForward) {
      _turn.value = 0.001;
      _settle(1.0);
    } else if (x < width * 0.18 && _canBackward) {
      _turn.value = -0.001;
      _settle(-1.0);
    }
  }

  // ── Layers ───────────────────────────────────────────────────────────────

  Widget _page(int index) {
    if (index < 0 || index >= widget.pageCount) {
      return widget.backBuilder(context);
    }
    return widget.pageBuilder(context, index);
  }

  /// The sheet mid-curl. [progress] 0 → flat on the book, 1 → fully turned.
  Widget _curlingPage(int index, double progress) {
    return IgnorePointer(
      child: ShaderBuilder(
        assetKey: 'assets/shaders/page_curl.frag',
        (context, shader, _) => AnimatedSampler(
          (image, size, canvas) {
            final r = math.min(size.width * 0.20, 150.0);
            final travel = size.width + (math.pi * r) / 2.0 + 6.0;
            final curlX = size.width - progress * travel;
            shader
              ..setFloat(0, size.width)
              ..setFloat(1, size.height)
              ..setFloat(2, curlX)
              ..setFloat(3, r)
              ..setImageSampler(0, image);
            canvas.drawRect(
              Rect.fromLTWH(0, 0, size.width, size.height),
              Paint()..shader = shader,
            );
          },
          child: _page(index),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pageCount == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final t = _turn.value;

        final layers = <Widget>[];
        if (t > 0) {
          // Forward: next page revealed underneath, current sheet curling.
          layers.add(_page(_index + 1));
          layers.add(_curlingPage(_index, t));
        } else if (t < 0) {
          // Backward: current page stays put, previous sheet un-curls
          // back over it from the left.
          layers.add(_page(_index));
          layers.add(_curlingPage(_index - 1, 1 + t));
        } else {
          layers.add(_page(_index));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
          onHorizontalDragEnd: _onDragEnd,
          onTapUp: (d) => _tapFlip(d, width),
          child: Stack(fit: StackFit.expand, children: layers),
        );
      },
    );
  }
}
