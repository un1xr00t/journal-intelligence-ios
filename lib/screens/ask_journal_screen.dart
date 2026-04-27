import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

class AskJournalScreen extends StatefulWidget {
  const AskJournalScreen({super.key});

  @override
  State<AskJournalScreen> createState() => _AskJournalScreenState();
}

class _AskJournalScreenState extends State<AskJournalScreen> {
  final _api = ApiService();
  final _ctrl = TextEditingController();
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

  bool get _hasConversation => _messages.isNotEmpty;
  int get _sourceCount => _messages.fold(
        0,
        (sum, message) => sum + (message.sources?.length ?? 0),
      );

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_handleComposerChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_handleComposerChanged);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _handleComposerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _send([String? text]) async {
    final q = (text ?? _ctrl.text).trim();
    if (q.isEmpty || _thinking) return;

    _ctrl.clear();
    setState(() {
      _messages = [..._messages, _Message(role: 'user', text: q)];
      _thinking = true;
    });
    _scrollDown();

    try {
      final res = await _api.askJournal(q);
      final answer =
          res['answer'] as String? ?? res['response'] as String? ?? '…';
      final sources = (res['sources'] as List?)?.cast<Map<String, dynamic>>();

      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          _Message(role: 'assistant', text: answer, sources: sources),
        ];
        _thinking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          const _Message(
            role: 'assistant',
            text:
                'Sorry, I could not reach the server. Check your connection and try again.',
          ),
        ];
        _thinking = false;
      });
    }
    _scrollDown();
  }

  void _clearConversation() {
    setState(() => _messages = const []);
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: Stack(
        children: [
          const Positioned.fill(child: _AskBackdrop()),
          Column(
            children: [
              CupertinoNavigationBar(
                backgroundColor: _withAlpha(JournalColors.bgBase, 0.82),
                border: const Border(
                  bottom: BorderSide(color: JournalColors.border, width: 0.5),
                ),
                middle: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.sparkles,
                      color: JournalColors.accent,
                      size: 17,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Ask My Journal',
                      style: TextStyle(color: JournalColors.textPrimary),
                    ),
                  ],
                ),
                trailing: _hasConversation
                    ? GestureDetector(
                        onTap: _clearConversation,
                        child: const Text(
                          'Clear',
                          style: TextStyle(
                            color: JournalColors.accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: _UnifiedAskView(
                  scrollController: _scroll,
                  starters: _starters,
                  messages: _messages,
                  thinking: _thinking,
                  sourceCount: _sourceCount,
                  onTapStarter: _send,
                ),
              ),
              _InputBar(
                ctrl: _ctrl,
                thinking: _thinking,
                hasConversation: _hasConversation,
                onSend: _send,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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

class _AskBackdrop extends StatelessWidget {
  const _AskBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                JournalColors.bgBase,
                JournalColors.bgSurface,
                JournalColors.bgBase,
              ],
            ),
          ),
        ),
        Positioned(
          top: -120,
          left: -40,
          child: IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _withAlpha(JournalColors.accent, 0.28),
                    _withAlpha(JournalColors.accent, 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: -70,
          top: 120,
          child: IgnorePointer(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _withAlpha(JournalColors.info, 0.16),
                    _withAlpha(JournalColors.info, 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 36,
          right: 36,
          top: 160,
          child: IgnorePointer(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _withAlpha(JournalColors.borderBright, 0.0),
                    _withAlpha(JournalColors.borderBright, 1),
                    _withAlpha(JournalColors.borderBright, 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UnifiedAskView extends StatelessWidget {
  const _UnifiedAskView({
    required this.scrollController,
    required this.starters,
    required this.messages,
    required this.thinking,
    required this.sourceCount,
    required this.onTapStarter,
  });

  final ScrollController scrollController;
  final List<String> starters;
  final List<_Message> messages;
  final bool thinking;
  final int sourceCount;
  final void Function(String) onTapStarter;

  bool get _hasConversation => messages.isNotEmpty || thinking;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 18,
        20,
        24,
      ),
      itemCount: _conversationStartIndex + messages.length + (thinking ? 1 : 0),
      itemBuilder: (_, index) {
        if (index == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 18),
            child: _AskHero(),
          );
        }
        if (index == 1) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: _PromptDeck(
              starters: starters,
              hasConversation: _hasConversation,
              onTap: onTapStarter,
            ),
          );
        }
        if (_hasConversation && index == 2) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _ConversationHeader(
              messageCount: messages.length,
              sourceCount: sourceCount,
            ),
          );
        }

        final messageIndex = index - _conversationStartIndex;
        if (messageIndex == messages.length && thinking) {
          return const _ThinkingBubble();
        }
        return _ChatBubble(message: messages[messageIndex]);
      },
    );
  }

  int get _conversationStartIndex => _hasConversation ? 3 : 2;
}

class _AskHero extends StatelessWidget {
  const _AskHero();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _withAlpha(JournalColors.bgCard, 0.98),
              _withAlpha(JournalColors.bgCardAlt, 0.94),
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [JournalColors.accent, JournalColors.accent2],
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: JournalColors.accentGlow,
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    CupertinoIcons.sparkles,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const Spacer(),
                const _Pill(
                  label: 'PRIVATE',
                  icon: CupertinoIcons.lock_shield,
                  tint: JournalColors.success,
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Ask about your entries.',
              style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Search across your journal, compare periods, or look for repeated themes without leaving the thread.',
              style: TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 15,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 18),
            const Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricChip(
                  icon: CupertinoIcons.waveform_path_ecg,
                  title: 'Patterns',
                  subtitle: 'find repeats',
                ),
                _MetricChip(
                  icon: CupertinoIcons.heart,
                  title: 'Mood',
                  subtitle: 'track shifts',
                ),
                _MetricChip(
                  icon: CupertinoIcons.time,
                  title: 'Seasons',
                  subtitle: 'compare periods',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptDeck extends StatelessWidget {
  const _PromptDeck({
    required this.starters,
    required this.hasConversation,
    required this.onTap,
  });

  final List<String> starters;
  final bool hasConversation;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          accentBorder: !hasConversation,
          padding: const EdgeInsets.all(0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _withAlpha(JournalColors.bgCardAlt, 0.98),
                  _withAlpha(JournalColors.bgCard, 0.92),
                ],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ASK',
                            style: TextStyle(
                              color: JournalColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Everything stays in one thread now.',
                            style: TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _Pill(
                      label: hasConversation ? 'LIVE' : 'READY',
                      icon: hasConversation
                          ? CupertinoIcons.chat_bubble_text_fill
                          : CupertinoIcons.sparkles,
                      tint: hasConversation
                          ? JournalColors.info
                          : JournalColors.accent,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _withAlpha(JournalColors.bgSurface, 0.72),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: JournalColors.border),
                  ),
                  child: Text(
                    hasConversation
                        ? 'Jump off what you already asked, or tap a prompt to take the conversation in a new direction.'
                        : 'Specific questions work best. Ask about a time period, a repeated issue, or a person.',
                    style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'STARTERS',
                  style: TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                ...starters.take(3).map(
                      (starter) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _StarterCard(
                          prompt: starter,
                          onTap: () => onTap(starter),
                          compact: hasConversation,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.messageCount,
    required this.sourceCount,
  });

  final int messageCount;
  final int sourceCount;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _withAlpha(JournalColors.bgCardAlt, 0.95),
              _withAlpha(JournalColors.bgCard, 0.82),
            ],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _withAlpha(JournalColors.accent, 0.18),
                border: Border.all(color: JournalColors.borderBright),
              ),
              child: const Icon(
                CupertinoIcons.chat_bubble_2_fill,
                color: JournalColors.textPrimary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Conversation active',
                    style: TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$messageCount message${messageCount == 1 ? '' : 's'} so far • $sourceCount journal source${sourceCount == 1 ? '' : 's'} surfaced',
                    style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 13,
                      height: 1.45,
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

class _StarterCard extends StatelessWidget {
  const _StarterCard({
    required this.prompt,
    required this.onTap,
    this.compact = false,
  });

  final String prompt;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _withAlpha(JournalColors.bgCard, 0.98),
              _withAlpha(JournalColors.bgCardAlt, 0.92),
            ],
          ),
        ),
        padding:
            EdgeInsets.fromLTRB(18, compact ? 14 : 16, 18, compact ? 14 : 16),
        child: Row(
          children: [
            Container(
              width: compact ? 36 : 40,
              height: compact ? 36 : 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: _withAlpha(JournalColors.accent, 0.14),
                border: Border.all(color: JournalColors.borderBright),
              ),
              child: const Icon(
                CupertinoIcons.arrow_turn_down_right,
                color: JournalColors.textPrimary,
                size: 18,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                prompt,
                style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: compact ? 30 : 34,
              height: compact ? 30 : 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _withAlpha(JournalColors.bgSurface, 0.82),
                border: Border.all(color: JournalColors.border),
              ),
              child: const Icon(
                CupertinoIcons.arrow_up_right,
                color: JournalColors.textSecondary,
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _Message message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Padding(
      padding: EdgeInsets.only(
        top: 8,
        bottom: 8,
        left: isUser ? 54 : 0,
        right: isUser ? 0 : 22,
      ),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        _withAlpha(JournalColors.accent, 0.72),
                        _withAlpha(JournalColors.accent2, 0.72),
                      ],
                    ),
                    border: Border.all(color: JournalColors.borderBright),
                  ),
                  child: const Icon(
                    CupertinoIcons.sparkles,
                    color: Colors.white,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                isUser ? 'You' : 'Journal Intelligence',
                style: TextStyle(
                  color: isUser
                      ? JournalColors.textSecondary
                      : JournalColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(22),
                topRight: const Radius.circular(22),
                bottomLeft: Radius.circular(isUser ? 22 : 8),
                bottomRight: Radius.circular(isUser ? 8 : 22),
              ),
              gradient: isUser
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _withAlpha(JournalColors.accent, 0.28),
                        _withAlpha(JournalColors.accent2, 0.18),
                      ],
                    )
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _withAlpha(JournalColors.bgCardAlt, 0.98),
                        _withAlpha(JournalColors.bgCard, 0.94),
                      ],
                    ),
              border: Border.all(
                color:
                    isUser ? JournalColors.borderBright : JournalColors.border,
              ),
              boxShadow: [
                if (isUser)
                  const BoxShadow(
                    color: JournalColors.accentGlow,
                    blurRadius: 14,
                    offset: Offset(0, 8),
                  ),
              ],
            ),
            child: isUser
                ? Text(
                    message.text,
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 15,
                      height: 1.6,
                    ),
                  )
                : MarkdownBody(
                    data: message.text,
                    shrinkWrap: true,
                    selectable: false,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 15,
                        height: 1.65,
                      ),
                      strong: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      em: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                      listBullet: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 15,
                      ),
                      blockquote: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                  ),
          ),
          if (!isUser && message.sources != null && message.sources!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SourceChip(
                    label:
                        '${message.sources!.length} source${message.sources!.length == 1 ? '' : 's'} from your journal',
                  ),
                  ...message.sources!.take(2).map(
                        (source) => _SourceChip(
                          label: _sourceLabel(source),
                        ),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _sourceLabel(Map<String, dynamic> source) {
    final title = source['title'] as String?;
    final date = source['entry_date'] as String?;
    final text = source['text'] as String?;
    if (title != null && title.trim().isNotEmpty) return title.trim();
    if (date != null && date.trim().isNotEmpty) return date.trim();
    if (text != null && text.trim().isNotEmpty) {
      final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
      return normalized.length > 38
          ? '${normalized.substring(0, 38)}...'
          : normalized;
    }
    return 'Journal entry';
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8, right: 22),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _withAlpha(JournalColors.info, 0.18),
              border: Border.all(color: JournalColors.borderBright),
            ),
            child: const Icon(
              CupertinoIcons.search,
              color: JournalColors.textPrimary,
              size: 15,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: _withAlpha(JournalColors.bgCardAlt, 0.96),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(22),
                  topRight: Radius.circular(22),
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(22),
                ),
                border: Border.all(color: JournalColors.border),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoActivityIndicator(
                    color: JournalColors.accent,
                    radius: 8,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Searching your journal for the signal underneath the noise...',
                      style: TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.ctrl,
    required this.thinking,
    required this.hasConversation,
    required this.onSend,
  });

  final TextEditingController ctrl;
  final bool thinking;
  final bool hasConversation;
  final void Function() onSend;

  @override
  Widget build(BuildContext context) {
    final canSend = ctrl.text.trim().isNotEmpty && !thinking;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.84),
        border: const Border(top: BorderSide(color: JournalColors.border)),
      ),
      child: GlassCard(
        accentBorder: canSend,
        padding: const EdgeInsets.all(0),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _withAlpha(JournalColors.bgCardAlt, 0.96),
                _withAlpha(JournalColors.bgCard, 0.92),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _Pill(
                    label: 'ASK',
                    icon: CupertinoIcons.sparkles,
                    tint: JournalColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasConversation
                          ? 'Keep pulling on the thread.'
                          : 'Ask about patterns, people, or a specific season.',
                      style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.bgSurface, 0.72),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: canSend
                        ? JournalColors.borderBright
                        : JournalColors.border,
                  ),
                ),
                child: CupertinoTextField(
                  controller: ctrl,
                  placeholder:
                      'Ask anything about your journal, your patterns, or what keeps repeating...',
                  placeholderStyle: const TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 15,
                    height: 1.45,
                  ),
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    height: 1.55,
                  ),
                  decoration: null,
                  textInputAction: TextInputAction.send,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      thinking
                          ? 'Thinking through your archive...'
                          : 'The sharper the question, the better the read.',
                      style: const TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    child: GestureDetector(
                      onTap: canSend ? onSend : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: canSend
                              ? const LinearGradient(
                                  colors: [
                                    JournalColors.accent,
                                    JournalColors.accent2,
                                  ],
                                )
                              : null,
                          color: canSend
                              ? null
                              : _withAlpha(JournalColors.bgSurface, 0.86),
                          border: Border.all(
                            color: canSend
                                ? JournalColors.borderBright
                                : JournalColors.border,
                          ),
                          boxShadow: canSend
                              ? const [
                                  BoxShadow(
                                    color: JournalColors.accentGlow,
                                    blurRadius: 16,
                                    offset: Offset(0, 8),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          thinking ? 'Thinking...' : 'Send',
                          style: TextStyle(
                            color: canSend
                                ? Colors.white
                                : JournalColors.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.icon,
    required this.tint,
  });

  final String label;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _withAlpha(tint, 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _withAlpha(tint, 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: JournalColors.textPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JournalColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: JournalColors.accent),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: JournalColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: JournalColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
