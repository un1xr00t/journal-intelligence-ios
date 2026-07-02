import 'package:flutter/cupertino.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/sage_voice_conversation_controller.dart';
import '../theme/app_theme.dart';

/// Full-screen hands-free conversation mode for Sage.
///
/// The screen is deliberately sparse and high-contrast so it stays glanceable
/// while driving (CarPlay-adjacent use): one big orb, one status line, the
/// live transcript, and an end button.
class SageVoiceModeScreen extends StatefulWidget {
  const SageVoiceModeScreen({super.key, required this.controller});

  final SageVoiceConversationController controller;

  @override
  State<SageVoiceModeScreen> createState() => _SageVoiceModeScreenState();
}

class _SageVoiceModeScreenState extends State<SageVoiceModeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _popped = false;

  SageVoiceConversationController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _controller.addListener(_handleControllerChanged);
    // Hands-free means no touches — keep the screen from sleeping mid-chat.
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.start();
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _controller.removeListener(_handleControllerChanged);
    _pulse.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    if (_controller.phase == SageVoicePhase.ended && !_popped) {
      _popped = true;
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  Future<void> _handleOrbTap() async {
    switch (_controller.phase) {
      case SageVoicePhase.listening:
        await _controller.sendNow();
      case SageVoicePhase.speaking:
        await _controller.interrupt();
      case SageVoicePhase.error:
        await _controller.retry();
      case SageVoicePhase.idle:
      case SageVoicePhase.thinking:
      case SageVoicePhase.ended:
        break;
    }
  }

  Future<void> _endSession() async {
    await _controller.endSession();
  }

  String get _statusLabel {
    switch (_controller.phase) {
      case SageVoicePhase.idle:
        return 'Starting…';
      case SageVoicePhase.listening:
        return _controller.transcript.trim().isEmpty
            ? 'Listening — just start talking'
            : 'Listening…';
      case SageVoicePhase.thinking:
        return 'Sage is thinking…';
      case SageVoicePhase.speaking:
        return 'Sage is speaking';
      case SageVoicePhase.error:
        return 'Something went wrong';
      case SageVoicePhase.ended:
        return 'Session ended';
    }
  }

  String get _hintLabel {
    switch (_controller.phase) {
      case SageVoicePhase.listening:
        return _controller.transcript.trim().isEmpty
            ? 'Sage sends your turn after a short pause.\nStay quiet to end the session.'
            : 'Pause to send, or tap the orb to send now.';
      case SageVoicePhase.speaking:
        return 'Tap the orb to interrupt and talk.';
      case SageVoicePhase.error:
        return 'Tap the orb to try again.';
      case SageVoicePhase.idle:
      case SageVoicePhase.thinking:
      case SageVoicePhase.ended:
        return '';
    }
  }

  Color get _orbColor {
    switch (_controller.phase) {
      case SageVoicePhase.listening:
        return JournalColors.accent;
      case SageVoicePhase.speaking:
        return JournalColors.borderBright;
      case SageVoicePhase.error:
        return const Color(0xFFE0708A);
      case SageVoicePhase.idle:
      case SageVoicePhase.thinking:
      case SageVoicePhase.ended:
        return JournalColors.textMuted;
    }
  }

  IconData get _orbIcon {
    switch (_controller.phase) {
      case SageVoicePhase.listening:
        return CupertinoIcons.mic_fill;
      case SageVoicePhase.thinking:
        return CupertinoIcons.ellipsis;
      case SageVoicePhase.speaking:
        return CupertinoIcons.speaker_2_fill;
      case SageVoicePhase.error:
        return CupertinoIcons.arrow_clockwise;
      case SageVoicePhase.idle:
      case SageVoicePhase.ended:
        return CupertinoIcons.mic;
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = _controller.phase;
    final transcript = _controller.transcript.trim();
    final reply = _controller.lastReply.trim();
    final error = _controller.errorText;
    final animateOrb = phase == SageVoicePhase.listening ||
        phase == SageVoicePhase.speaking ||
        phase == SageVoicePhase.thinking;

    final displayText = switch (phase) {
      SageVoicePhase.error => error ?? 'Something went wrong.',
      SageVoicePhase.speaking => reply,
      _ => transcript.isNotEmpty ? '“$transcript”' : '',
    };

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      // Yellow-underline fix: outside a Material ancestor, Text falls back to
      // a style with a yellow double underline. Pin the decoration here so
      // every Text in this screen inherits a clean baseline.
      child: DefaultTextStyle(
        style: const TextStyle(
          color: JournalColors.textPrimary,
          decoration: TextDecoration.none,
        ),
        child: SafeArea(
          child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  const Text(
                    'Voice conversation',
                    style: TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _endSession,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: JournalColors.bgSurface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: JournalColors.border),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.xmark,
                            size: 13,
                            color: JournalColors.textPrimary,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'End',
                            style: TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _handleOrbTap,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  final t = animateOrb ? _pulse.value : 0.0;
                  final scale = 1.0 + 0.06 * t;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 148,
                      height: 148,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: JournalColors.bgCardAlt,
                        border: Border.all(color: _orbColor, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: _orbColor.withValues(
                              alpha: 0.18 + 0.22 * t,
                            ),
                            blurRadius: 40 + 30 * t,
                            spreadRadius: 4 + 10 * t,
                          ),
                        ],
                      ),
                      child: phase == SageVoicePhase.thinking
                          ? const Center(
                              child: CupertinoActivityIndicator(
                                radius: 16,
                                color: JournalColors.textPrimary,
                              ),
                            )
                          : Icon(_orbIcon, size: 46, color: _orbColor),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 28),
            Text(
              _statusLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_hintLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  _hintLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            const Spacer(),
            if (displayText.isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                padding: const EdgeInsets.all(16),
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: JournalColors.bgCardAlt.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: JournalColors.border),
                ),
                child: SingleChildScrollView(
                  reverse: phase == SageVoicePhase.listening,
                  child: Text(
                    displayText,
                    style: TextStyle(
                      color: phase == SageVoicePhase.error
                          ? const Color(0xFFE0708A)
                          : JournalColors.textSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 244),
          ],
          ),
        ),
      ),
    );
  }
}
