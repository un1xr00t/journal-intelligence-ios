// lib/screens/ask_journal_screen.dart
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

class AskJournalScreen extends StatefulWidget {
  const AskJournalScreen({super.key});

  @override
  State<AskJournalScreen> createState() => _AskJournalScreenState();
}

class _AskJournalScreenState extends State<AskJournalScreen> {
  final _api   = ApiService();
  final _ctrl  = TextEditingController();
  final _scroll = ScrollController();

  List<_Message> _messages = const [];
  bool _thinking = false;

  static const _starters = [
    'What patterns have I noticed lately?',
    'How have I been feeling this week?',
    'What am I most stressed about?',
    'What have I been grateful for?',
    'When do I feel most like myself?',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final q = (text ?? _ctrl.text).trim();
    if (q.isEmpty || _thinking) return;

    _ctrl.clear();
    setState(() {
      _messages = [..._messages, _Message(role: 'user', text: q)];
      _thinking  = true;
    });
    _scrollDown();

    try {
      final res  = await _api.askJournal(q);
      final answer = res['answer'] as String? ??
          res['response'] as String? ?? '…';
      final sources = (res['sources'] as List?)?.cast<Map<String, dynamic>>();

      setState(() {
        _messages = [
          ..._messages,
          _Message(role: 'assistant', text: answer, sources: sources),
        ];
        _thinking = false;
      });
    } catch (e) {
      setState(() {
        _messages = [
          ..._messages,
          const _Message(
              role: 'assistant',
              text: 'Sorry, I couldn\'t reach the server. Check your connection.'),
        ];
        _thinking = false;
      });
    }
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: Column(
        children: [
          // ── Nav bar ───────────────────────────────────────────────
          CupertinoNavigationBar(
            backgroundColor: JournalColors.bgBase.withOpacity(0.9),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
            middle: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(CupertinoIcons.sparkles, color: JournalColors.accent, size: 16),
                SizedBox(width: 8),
                Text('Ask My Journal',
                    style: TextStyle(color: JournalColors.textPrimary)),
              ],
            ),
            trailing: _messages.isNotEmpty
                ? GestureDetector(
                    onTap: () => setState(() => _messages = const []),
                    child: const Text('Clear',
                        style: TextStyle(color: JournalColors.textMuted, fontSize: 14)),
                  )
                : null,
          ),

          // ── Messages / starters ───────────────────────────────────
          Expanded(
            child: _messages.isEmpty
                ? _StarterView(starters: _starters, onTap: _send)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    itemCount: _messages.length + (_thinking ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _messages.length) return const _ThinkingBubble();
                      return _ChatBubble(message: _messages[i]);
                    },
                  ),
          ),

          // ── Input bar ─────────────────────────────────────────────
          _InputBar(
            ctrl: _ctrl,
            thinking: _thinking,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _Message {
  const _Message({
    required this.role,
    required this.text,
    this.sources,
  });
  final String role;
  final String text;
  final List<Map<String, dynamic>>? sources;
}

// ── Starter prompts ───────────────────────────────────────────────────────────

class _StarterView extends StatelessWidget {
  const _StarterView({required this.starters, required this.onTap});
  final List<String> starters;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [JournalColors.accent, JournalColors.accent2],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(color: JournalColors.accentGlow, blurRadius: 20),
              ],
            ),
            child: const Icon(CupertinoIcons.sparkles, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 20),
          const Text('Ask anything about your journal',
              style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3)),
          const SizedBox(height: 8),
          const Text('Powered by RAG — searches your actual entries.',
              style: TextStyle(color: JournalColors.textSecondary, fontSize: 15)),
          const SizedBox(height: 32),
          const Text('SUGGESTED',
              style: TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),
          ...starters.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () => onTap(s),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: JournalColors.bgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: JournalColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(s,
                              style: const TextStyle(
                                  color: JournalColors.textPrimary, fontSize: 15)),
                        ),
                        const Icon(CupertinoIcons.arrow_right,
                            color: JournalColors.textMuted, size: 16),
                      ],
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

// ── Chat bubble ───────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});
  final _Message message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Padding(
      padding: EdgeInsets.only(
        top: 8, bottom: 8,
        left: isUser ? 60 : 0,
        right: isUser ? 0 : 60,
      ),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: isUser
                  ? JournalColors.accent.withOpacity(0.18)
                  : JournalColors.bgCard,
              borderRadius: BorderRadius.only(
                topLeft:     const Radius.circular(20),
                topRight:    const Radius.circular(20),
                bottomLeft:  Radius.circular(isUser ? 20 : 6),
                bottomRight: Radius.circular(isUser ? 6 : 20),
              ),
              border: Border.all(
                color: isUser ? JournalColors.borderBright : JournalColors.border,
              ),
            ),
            child: isUser
                ? Text(message.text,
                    style: const TextStyle(
                        color: JournalColors.textPrimary, fontSize: 15, height: 1.5))
                : MarkdownBody(
                    data: message.text,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(
                          color: JournalColors.textPrimary, fontSize: 15, height: 1.6),
                      strong: const TextStyle(
                          color: JournalColors.textPrimary, fontWeight: FontWeight.w700),
                      em: const TextStyle(
                          color: JournalColors.textSecondary,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
          ),
          if (!isUser && message.sources != null && message.sources!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                '${message.sources!.length} source${message.sources!.length > 1 ? 's' : ''} from your journal',
                style: const TextStyle(color: JournalColors.textMuted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Thinking bubble ───────────────────────────────────────────────────────────

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8, right: 60),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: JournalColors.bgCard,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(color: JournalColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CupertinoActivityIndicator(color: JournalColors.accent, radius: 8),
            SizedBox(width: 10),
            Text('Searching your journal…',
                style: TextStyle(color: JournalColors.textMuted, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.ctrl,
    required this.thinking,
    required this.onSend,
  });

  final TextEditingController ctrl;
  final bool thinking;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: JournalColors.bgSurface,
        border: const Border(top: BorderSide(color: JournalColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: CupertinoTextField(
              controller: ctrl,
              placeholder: 'Ask anything about your journal…',
              placeholderStyle:
                  const TextStyle(color: JournalColors.textMuted, fontSize: 15),
              style: const TextStyle(color: JournalColors.textPrimary, fontSize: 15),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: JournalColors.bgCard,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: JournalColors.border),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              maxLines: 3,
              minLines: 1,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: thinking ? null : onSend,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: thinking
                    ? JournalColors.bgCard
                    : JournalColors.accent,
                shape: BoxShape.circle,
                boxShadow: thinking
                    ? null
                    : const [
                        BoxShadow(
                            color: JournalColors.accentGlow, blurRadius: 12),
                      ],
              ),
              child: Icon(
                CupertinoIcons.arrow_up,
                color: thinking ? JournalColors.textMuted : Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
