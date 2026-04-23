import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/api_service.dart';
import '../services/sage_profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'admin_screen.dart';
import 'ask_journal_screen.dart';
import 'budget_planner_screen.dart';
import 'detective_screen.dart';
import 'early_warning_screen.dart';
import 'exit_plan_screen.dart';
import 'fairness_ledger_screen.dart';
import 'invite_access_screen.dart';
import 'mental_health_screen.dart';
import 'proof_vault_screen.dart';
import 'resources_screen.dart';
import 'sage_settings_screen.dart';
import 'settings_screen.dart';
import 'timeline_screen.dart';
import 'today_screen.dart';
import 'war_room_screen.dart';
import 'write_screen.dart';

const _kSageSystemPrompt = '''
You are Sage — the user's personal assistant and best friend who lives inside
their journal. You have full context on their life: their entries, their
emotional patterns, their open cases, their plans, their money situation, and
everything they've ever written. You speak like a close friend who's sharp,
honest, and actually pays attention. Never be sycophantic. Never be clinical.
You can swear if it fits the moment. You remember what they're dealing with.
When they ask for budget help, reference their actual budget data. When they
mention a person, reference how that person shows up in their journal. When they
need to think something through, be a real thinking partner, not a FAQ bot.
Be warm, direct, and actually useful.
''';

const _kSageKnowledgeChips = <({String label, String prompt})>[
  (
    label: 'Journal entries & mood trends',
    prompt: 'What mood and stress patterns have been showing up lately?'
  ),
  (
    label: 'Narrative summary',
    prompt:
        'Give me the clearest read on what chapter of life I am in right now.'
  ),
  (
    label: 'Active alerts',
    prompt: 'What active alerts or warning patterns matter most right now?'
  ),
  (
    label: 'Evidence vault',
    prompt: 'What evidence or documentation should I be collecting next?'
  ),
  (
    label: 'Detective cases',
    prompt: 'What case-building threads or contradictions should I review next?'
  ),
  (
    label: 'Exit plan progress',
    prompt: 'How is my exit plan actually progressing, and where am I stuck?'
  ),
  (
    label: 'Fairness ledger',
    prompt:
        'What does the fairness ledger say about load, effort, or imbalance?'
  ),
  (
    label: 'Budget & spending',
    prompt: 'Based on my budget, what financial pressure points need attention?'
  ),
  (
    label: 'People intelligence',
    prompt:
        'What should I notice about the people showing up most in my journal?'
  ),
  (
    label: 'User memory/profile',
    prompt: 'Use what you know about me and tell me what I may be overlooking.'
  ),
];

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

class SageScreen extends StatefulWidget {
  const SageScreen({super.key});

  @override
  State<SageScreen> createState() => _SageScreenState();
}

class _SageScreenState extends State<SageScreen> {
  final _api = ApiService();
  final _profile = SageProfileService();
  final _composerCtrl = TextEditingController();
  final _scroll = ScrollController();
  final _focusNode = FocusNode();
  final _audioPlayer = AudioPlayer();

  List<_SageMessage> _messages = const [];
  List<SageMemoryItem> _memoryItems = const [];
  SageSettings _settings = SageSettings.defaults;
  String? _contextString;
  String? _contextError;
  String? _replyError;
  bool _contextLoading = true;
  bool _replyLoading = false;
  bool _profileLoading = true;
  String? _speakingMessageId;
  String? _ttsLoadingMessageId;
  int _messageCounter = 0;

  bool get _canSend =>
      !_replyLoading &&
      !_contextLoading &&
      _composerCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _composerCtrl.addListener(_handleComposerChanged);
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _speakingMessageId = null);
      }
    });
    _loadSageProfile();
    _loadContextAndStart();
  }

  @override
  void dispose() {
    _composerCtrl.removeListener(_handleComposerChanged);
    _composerCtrl.dispose();
    _scroll.dispose();
    _focusNode.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _handleComposerChanged() {
    if (mounted) setState(() {});
  }

  String _parseError(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is String && detail.trim().isNotEmpty) return detail.trim();
        if (detail is List && detail.isNotEmpty) {
          return detail.map((item) {
            if (item is Map && item['msg'] != null) {
              return item['msg'].toString();
            }
            return item.toString();
          }).join(', ');
        }
      }
      if (data is String && data.trim().isNotEmpty) return data.trim();
      final status = e.response?.statusCode;
      if (status != null) {
        return 'Server error ($status). Check the Sage vision request.';
      }
    }
    final str = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    return match?.group(1) ?? 'Something went wrong.';
  }

  Future<void> _loadSageProfile() async {
    try {
      final settings = await _profile.loadSettings();
      final memory = await _profile.loadMemoryItems();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _memoryItems = memory;
        _profileLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _profileLoading = false);
    }
  }

  String _buildContextPayload(String contextString) {
    final memoryContext = _profile.buildMemoryContext(_memoryItems);
    return '''
$contextString

$memoryContext

[SYSTEM INSTRUCTION]
$_kSageSystemPrompt

${_settings.toPromptInstruction()}
''';
  }

  Future<void> _loadContextAndStart({bool forceRefresh = false}) async {
    setState(() {
      _contextLoading = true;
      _contextError = null;
      _replyError = null;
      _messages = const [];
      _speakingMessageId = null;
      _ttsLoadingMessageId = null;
    });

    try {
      final contextString =
          await _api.getFloatchatContext(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _contextString = contextString;
        _contextLoading = false;
      });
      if (_settings.autoGreeting) {
        await _send(text: '[SESSION_START]', hiddenUserMessage: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _contextLoading = false;
        _contextError = 'Couldn’t reach the server. Check your connection.';
      });
    }
  }

  String _nextMessageId() {
    _messageCounter += 1;
    return 'sage_${DateTime.now().microsecondsSinceEpoch}_$_messageCounter';
  }

  Future<void> _send({
    String? text,
    bool hiddenUserMessage = false,
  }) async {
    final prompt = (text ?? _composerCtrl.text).trim();
    if (prompt.isEmpty || _replyLoading || _contextString == null) return;

    final outgoing = _SageMessage.user(_nextMessageId(), prompt);
    final visibleMessages =
        hiddenUserMessage ? _messages : [..._messages, outgoing];

    if (!hiddenUserMessage) {
      _composerCtrl.clear();
    }

    setState(() {
      _messages = visibleMessages;
      _replyLoading = true;
      _replyError = null;
    });
    _scrollDown();

    final requestMessages = [
      ..._messages.map((message) => message.toApiMessage()),
      outgoing.toApiMessage(),
    ];

    try {
      final response = await _api.sendFloatchatMessage(
        messages: requestMessages,
        contextString: _buildContextPayload(_contextString!),
      );
      final reply = response['reply']?.toString().trim();
      final actions = (response['actions'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList() ??
          const <Map<String, dynamic>>[];

      if (!mounted) return;
      final assistantMessage = _SageMessage.assistant(
        _nextMessageId(),
        reply?.isNotEmpty == true
            ? reply!
            : 'I have your context loaded. What do you want to work through first?',
        actions: actions,
      );
      setState(() {
        _messages = [...visibleMessages, assistantMessage];
        _replyLoading = false;
      });

      if (!hiddenUserMessage &&
          _settings.autoRemember &&
          assistantMessage.text.trim().isNotEmpty) {
        unawaited(_captureMemoryFromExchange(prompt, assistantMessage.text));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = visibleMessages;
        _replyLoading = false;
        _replyError = _parseError(e);
      });
    }

    _scrollDown();
  }

  Future<void> _captureMemoryFromExchange(
    String userPrompt,
    String assistantReply,
  ) async {
    if (_contextString == null) return;

    final extractionPrompt = '''
You are extracting durable memory for future assistant context.

Only keep facts that are likely to matter in future conversations:
- ongoing life context
- repeated preferences
- important people dynamics
- recurring goals or constraints

Ignore one-off planning details, generic feelings, and anything already obvious from the current message alone.

Return strict JSON only:
{"facts":[{"text":"...", "confidence":0.0}]}

At most 3 facts.

User message:
$userPrompt

Assistant reply:
$assistantReply
''';

    try {
      final response = await _api.sendFloatchatMessage(
        messages: [
          {
            'role': 'user',
            'content': extractionPrompt,
          }
        ],
        contextString: '${_buildContextPayload(_contextString!)}\n'
            '[MEMORY EXTRACTION MODE]\n'
            'Return JSON only.',
      );
      final reply = response['reply']?.toString() ?? '';
      final parsed = _extractFacts(reply);
      if (parsed.isEmpty) return;
      final next = await _profile.addMemoryTexts(parsed, source: 'learned');
      if (!mounted) return;
      setState(() => _memoryItems = next);
    } catch (_) {}
  }

  List<String> _extractFacts(String raw) {
    if (raw.trim().isEmpty) return const [];
    String candidate = raw.trim();
    final fenced =
        RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(candidate);
    if (fenced != null) candidate = fenced.group(1)?.trim() ?? candidate;

    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(candidate) as Map);
      final facts = (decoded['facts'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where((item) => (item['confidence'] as num?)?.toDouble() != null)
              .where((item) => ((item['confidence'] as num).toDouble()) >= 0.72)
              .map((item) => item['text']?.toString().trim() ?? '')
              .where((text) => text.isNotEmpty)
              .toList() ??
          const <String>[];
      return facts;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _clearChat() async {
    if (_replyLoading || _contextLoading) return;
    await _audioPlayer.stop();
    if (mounted) {
      setState(() {
        _speakingMessageId = null;
        _ttsLoadingMessageId = null;
      });
    }
    await _loadContextAndStart();
  }

  Future<void> _openSageSettings() async {
    await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: const SageSettingsScreen(),
        ),
      ),
    );
    await _loadSageProfile();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _toggleSpeak(_SageMessage message) async {
    if (message.role != 'assistant' || message.text.trim().isEmpty) return;

    if (_speakingMessageId == message.id ||
        _ttsLoadingMessageId == message.id) {
      await _audioPlayer.stop();
      if (!mounted) return;
      setState(() {
        _speakingMessageId = null;
        _ttsLoadingMessageId = null;
      });
      return;
    }

    setState(() {
      _ttsLoadingMessageId = message.id;
      _speakingMessageId = null;
    });

    try {
      await _audioPlayer.stop();
      final bytes = await _api.voiceSpeak(
        text: message.text,
        voiceId: _settings.voiceId,
      );
      if (!mounted) return;
      await _audioPlayer.play(
        BytesSource(Uint8List.fromList(bytes), mimeType: 'audio/mpeg'),
      );
      if (!mounted) return;
      setState(() {
        _ttsLoadingMessageId = null;
        _speakingMessageId = message.id;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ttsLoadingMessageId = null;
        _speakingMessageId = null;
      });
    }
  }

  Future<void> _openAction(Map<String, dynamic> action) async {
    final destination = _screenForAction(action);
    if (destination == null) return;

    if (!mounted) return;
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: destination,
        ),
      ),
    );
  }

  Widget? _screenForAction(Map<String, dynamic> action) {
    final fields = <String>[
      action['tool']?.toString() ?? '',
      action['route']?.toString() ?? '',
      action['screen']?.toString() ?? '',
      action['destination']?.toString() ?? '',
      action['target']?.toString() ?? '',
      action['title']?.toString() ?? '',
      action['label']?.toString() ?? '',
      action['name']?.toString() ?? '',
      action['description']?.toString() ?? '',
    ].join(' ').toLowerCase();

    if (fields.contains('war room') || fields.contains('war_room')) {
      return const WarRoomScreen();
    }
    if (fields.contains('proof vault') || fields.contains('proof_vault')) {
      return const ProofVaultScreen();
    }
    if (fields.contains('budget')) {
      return const BudgetPlannerScreen();
    }
    if (fields.contains('detective')) {
      return const DetectiveScreen();
    }
    if (fields.contains('exit plan') || fields.contains('exit_plan')) {
      return const ExitPlanScreen();
    }
    if (fields.contains('fairness')) {
      return const FairnessLedgerScreen();
    }
    if (fields.contains('mental health') || fields.contains('mental_health')) {
      return const MentalHealthScreen();
    }
    if (fields.contains('ask my journal') ||
        fields.contains('ask_journal') ||
        fields.contains('/ask')) {
      return const AskJournalScreen();
    }
    if (fields.contains('today')) {
      return const TodayScreen();
    }
    if (fields.contains('timeline')) {
      return const TimelineScreen();
    }
    if (fields.contains('write')) {
      return const WriteScreen();
    }
    if (fields.contains('early warning') || fields.contains('early_warning')) {
      return const EarlyWarningScreen();
    }
    if (fields.contains('settings')) {
      return const SettingsScreen();
    }
    if (fields.contains('resources')) {
      return const ResourcesScreen();
    }
    if (fields.contains('invite')) {
      if (fields.contains('admin')) return const AdminScreen();
      return const InviteAccessScreen();
    }
    if (fields.contains('admin')) {
      return const AdminScreen();
    }
    return null;
  }

  List<Map<String, dynamic>> _resolvableActions(
      List<Map<String, dynamic>> raw) {
    return raw.where((item) => _screenForAction(item) != null).toList();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: Stack(
        children: [
          const Positioned.fill(child: _SageBackdrop()),
          Column(
            children: [
              _SageHeader(
                hasConversation: _messages.isNotEmpty,
                busy: _replyLoading || _contextLoading,
                onClear: _clearChat,
                onOpenSettings: _openSageSettings,
              ),
              Expanded(
                child: _SageThread(
                  scrollController: _scroll,
                  contextLoading: _contextLoading,
                  contextError: _contextError,
                  replyLoading: _replyLoading,
                  replyError: _replyError,
                  messages: _messages,
                  onRetryContext: _loadContextAndStart,
                  onActionTap: _openAction,
                  resolveActions: _resolvableActions,
                  onToggleSpeak: _toggleSpeak,
                  speakingMessageId: _speakingMessageId,
                  ttsLoadingMessageId: _ttsLoadingMessageId,
                  settings: _settings,
                  profileLoading: _profileLoading,
                  memoryCount: _memoryItems.length,
                ),
              ),
              _SageInputBar(
                controller: _composerCtrl,
                focusNode: _focusNode,
                canSend: _canSend,
                loading: _replyLoading,
                onSend: () => _send(),
                onSuggestionTap: (prompt) => _send(text: prompt),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SageMessage {
  const _SageMessage({
    this.id,
    required this.role,
    required this.text,
    this.actions = const [],
  });

  const _SageMessage.user(String id, String text)
      : this(
          id: id,
          role: 'user',
          text: text,
        );

  const _SageMessage.assistant(
    String id,
    String text, {
    List<Map<String, dynamic>> actions = const [],
  }) : this(
          id: id,
          role: 'assistant',
          text: text,
          actions: actions,
        );

  final String? id;
  final String role;
  final String text;
  final List<Map<String, dynamic>> actions;

  Map<String, String> toApiMessage() => {
        'role': role,
        'content': text,
      };
}

class _SageBackdrop extends StatelessWidget {
  const _SageBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
      child: Stack(
        children: [
          Positioned(
            top: -80,
            left: -20,
            child: _GlowOrb(
              size: 240,
              color: _withAlpha(JournalColors.accent, 0.22),
            ),
          ),
          Positioned(
            top: 100,
            right: -70,
            child: _GlowOrb(
              size: 220,
              color: _withAlpha(JournalColors.accent2, 0.14),
            ),
          ),
          Positioned(
            bottom: 80,
            left: 40,
            child: _GlowOrb(
              size: 180,
              color: _withAlpha(JournalColors.info, 0.08),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: size * 0.42,
              spreadRadius: size * 0.08,
            ),
          ],
        ),
      ),
    );
  }
}

class _SageHeader extends StatelessWidget {
  const _SageHeader({
    required this.hasConversation,
    required this.busy,
    required this.onClear,
    required this.onOpenSettings,
  });

  final bool hasConversation;
  final bool busy;
  final VoidCallback onClear;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding + 10, 20, 14),
      decoration: BoxDecoration(
        color: JournalColors.bgBase.withValues(alpha: 0.84),
        border: const Border(
          bottom: BorderSide(color: JournalColors.border, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sage',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'your personal assistant',
                  style: TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeaderButton(
                icon: CupertinoIcons.slider_horizontal_3,
                onTap: onOpenSettings,
              ),
              const SizedBox(width: 10),
              _HeaderButton(
                icon: CupertinoIcons.refresh,
                onTap: hasConversation && !busy ? onClear : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(36, 36),
      onPressed: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: JournalColors.bgCard
              .withValues(alpha: onTap != null ? 0.82 : 0.36),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JournalColors.border),
        ),
        child: Icon(
          icon,
          color: onTap != null ? JournalColors.accent : JournalColors.textMuted,
          size: 18,
        ),
      ),
    );
  }
}

class _SageThread extends StatelessWidget {
  const _SageThread({
    required this.scrollController,
    required this.contextLoading,
    required this.contextError,
    required this.replyLoading,
    required this.replyError,
    required this.messages,
    required this.onRetryContext,
    required this.onActionTap,
    required this.resolveActions,
    required this.onToggleSpeak,
    required this.speakingMessageId,
    required this.ttsLoadingMessageId,
    required this.settings,
    required this.profileLoading,
    required this.memoryCount,
  });

  final ScrollController scrollController;
  final bool contextLoading;
  final String? contextError;
  final bool replyLoading;
  final String? replyError;
  final List<_SageMessage> messages;
  final Future<void> Function({bool forceRefresh}) onRetryContext;
  final Future<void> Function(Map<String, dynamic>) onActionTap;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>>)
      resolveActions;
  final Future<void> Function(_SageMessage) onToggleSpeak;
  final String? speakingMessageId;
  final String? ttsLoadingMessageId;
  final SageSettings settings;
  final bool profileLoading;
  final int memoryCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (contextLoading) {
          return const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoActivityIndicator(color: JournalColors.accent),
                SizedBox(width: 10),
                Text(
                  'Loading your context…',
                  style: TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        if (contextError != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GlassCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.wifi_slash,
                      color: JournalColors.textMuted,
                      size: 28,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      contextError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      color: JournalColors.accent,
                      onPressed: () => onRetryContext(forceRefresh: true),
                      child: const Text(
                        'Retry',
                        style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return SingleChildScrollView(
          controller: scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SageIntroCard(
                  settings: settings,
                  profileLoading: profileLoading,
                  memoryCount: memoryCount,
                ),
                const SizedBox(height: 16),
                ...messages.map(
                  (message) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _MessageBubble(
                      message: message,
                      actions: resolveActions(message.actions),
                      onActionTap: onActionTap,
                      onToggleSpeak: onToggleSpeak,
                      speaking: speakingMessageId == message.id,
                      ttsLoading: ttsLoadingMessageId == message.id,
                    ),
                  ),
                ),
                if (replyLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: _ThinkingBubble(),
                  ),
                if (replyError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10, top: 2),
                      child: Text(
                        replyError!,
                        style: const TextStyle(
                          color: JournalColors.danger,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SageIntroCard extends StatelessWidget {
  const _SageIntroCard({
    required this.settings,
    required this.profileLoading,
    required this.memoryCount,
  });

  final SageSettings settings;
  final bool profileLoading;
  final int memoryCount;

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
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [
                        _withAlpha(JournalColors.accent, 0.26),
                        _withAlpha(JournalColors.accent2, 0.16),
                      ],
                    ),
                    border: Border.all(color: JournalColors.borderBright),
                  ),
                  child: const Icon(
                    CupertinoIcons.sparkles,
                    color: JournalColors.textPrimary,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Loaded for this session',
                    style: TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Sage responds with your current journal context plus your saved Sage settings and private memory notes from this device.',
              style: TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaPill(
                  label: profileLoading
                      ? 'Loading profile…'
                      : 'Voice ${settings.voiceId}',
                ),
                _MetaPill(
                  label: profileLoading
                      ? '…'
                      : '$memoryCount saved ${memoryCount == 1 ? 'memory' : 'memories'}',
                ),
                _MetaPill(label: '${settings.warmth} / ${settings.directness}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.82),
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.actions,
    required this.onActionTap,
    required this.onToggleSpeak,
    required this.speaking,
    required this.ttsLoading,
  });

  final _SageMessage message;
  final List<Map<String, dynamic>> actions;
  final Future<void> Function(Map<String, dynamic>) onActionTap;
  final Future<void> Function(_SageMessage) onToggleSpeak;
  final bool speaking;
  final bool ttsLoading;

  bool get _isUser => message.role == 'user';

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Column(
          crossAxisAlignment:
              _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _isUser
                    ? _withAlpha(JournalColors.accent, 0.86)
                    : _withAlpha(JournalColors.bgCard, 0.92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isUser
                      ? _withAlpha(JournalColors.borderBright, 0.9)
                      : JournalColors.border,
                ),
                boxShadow: _isUser
                    ? const [
                        BoxShadow(
                          color: JournalColors.accentGlow,
                          blurRadius: 16,
                          offset: Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: _isUser
                  ? Text(
                      message.text,
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 15,
                        height: 1.45,
                      ),
                    )
                  : MarkdownBody(
                      data: message.text,
                      selectable: false,
                      softLineBreak: true,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 15,
                          height: 1.5,
                        ),
                        strong: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        listBullet: const TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 15,
                        ),
                        blockSpacing: 8,
                      ),
                    ),
            ),
            if (!_isUser) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  GestureDetector(
                    onTap: () => onToggleSpeak(message),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: (speaking || ttsLoading)
                            ? _withAlpha(JournalColors.accent, 0.18)
                            : _withAlpha(JournalColors.bgSurface, 0.9),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: (speaking || ttsLoading)
                              ? JournalColors.borderBright
                              : JournalColors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (ttsLoading)
                            const CupertinoActivityIndicator(
                              color: JournalColors.accent,
                            )
                          else
                            Icon(
                              speaking
                                  ? CupertinoIcons.stop_fill
                                  : CupertinoIcons.speaker_2_fill,
                              color: JournalColors.accent,
                              size: 14,
                            ),
                          const SizedBox(width: 6),
                          Text(
                            ttsLoading
                                ? 'Generating…'
                                : speaking
                                    ? 'Stop'
                                    : 'Listen',
                            style: const TextStyle(
                              color: JournalColors.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ...actions.map((action) {
                    final label = action['label']
                                ?.toString()
                                .trim()
                                .isNotEmpty ==
                            true
                        ? action['label'].toString().trim()
                        : action['title']?.toString().trim().isNotEmpty == true
                            ? action['title'].toString().trim()
                            : action['name']?.toString().trim().isNotEmpty ==
                                    true
                                ? action['name'].toString().trim()
                                : 'Open';

                    return GestureDetector(
                      onTap: () => onActionTap(action),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _withAlpha(JournalColors.bgSurface, 0.9),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: JournalColors.borderBright),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: JournalColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _withAlpha(JournalColors.bgCard, 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: JournalColors.border),
        ),
        child: const CupertinoActivityIndicator(color: JournalColors.accent),
      ),
    );
  }
}

class _SageInputBar extends StatelessWidget {
  const _SageInputBar({
    required this.controller,
    required this.focusNode,
    required this.canSend,
    required this.loading,
    required this.onSend,
    required this.onSuggestionTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSend;
  final bool loading;
  final VoidCallback onSend;
  final ValueChanged<String> onSuggestionTap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        (bottomInset > 0 ? 8 : safeBottom + 10),
      ),
      decoration: BoxDecoration(
        color: JournalColors.bgBase.withValues(alpha: 0.9),
        border: const Border(
          top: BorderSide(color: JournalColors.border, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: focusNode.requestFocus,
            child: Container(
              constraints: const BoxConstraints(minHeight: 72),
              decoration: BoxDecoration(
                color: _withAlpha(JournalColors.bgCardAlt, 0.94),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: focusNode.hasFocus
                      ? JournalColors.borderBright
                      : JournalColors.border,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: CupertinoTextField(
                      controller: controller,
                      focusNode: focusNode,
                      placeholder: 'Ask Sage anything…',
                      placeholderStyle: const TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 15,
                      ),
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 15,
                        height: 1.35,
                      ),
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      textAlignVertical: TextAlignVertical.top,
                      padding: const EdgeInsets.only(top: 5, bottom: 7),
                      cursorColor: JournalColors.accent,
                      decoration: const BoxDecoration(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: canSend ? onSend : null,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: canSend
                            ? JournalColors.accent
                            : JournalColors.bgSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: canSend
                              ? JournalColors.borderBright
                              : JournalColors.border,
                        ),
                      ),
                      child: loading
                          ? const CupertinoActivityIndicator(
                              color: JournalColors.textPrimary,
                            )
                          : Icon(
                              CupertinoIcons.arrow_up,
                              color: canSend
                                  ? JournalColors.textPrimary
                                  : JournalColors.textMuted,
                              size: 18,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 30,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (_, index) => GestureDetector(
                onTap: () =>
                    onSuggestionTap(_kSageKnowledgeChips[index].prompt),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: _withAlpha(JournalColors.bgSurface, 0.82),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: JournalColors.border),
                  ),
                  child: Text(
                    _kSageKnowledgeChips[index].label,
                    style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: _kSageKnowledgeChips.length,
            ),
          ),
        ],
      ),
    );
  }
}
