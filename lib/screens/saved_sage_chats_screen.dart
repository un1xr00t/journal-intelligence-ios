import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

class SavedSageChatsResult {
  const SavedSageChatsResult({
    this.conversation,
    this.startNewChat = false,
  });

  final SavedFloatchatConversation? conversation;
  final bool startNewChat;

  const SavedSageChatsResult.newChat()
      : conversation = null,
        startNewChat = true;

  const SavedSageChatsResult.open(this.conversation) : startNewChat = false;
}

class SavedSageChatsScreen extends StatefulWidget {
  const SavedSageChatsScreen({super.key});

  @override
  State<SavedSageChatsScreen> createState() => _SavedSageChatsScreenState();
}

class _SavedSageChatsScreenState extends State<SavedSageChatsScreen> {
  final _api = ApiService();
  final _dateFormat = DateFormat('MMM d, yyyy • h:mm a');

  List<SavedFloatchatConversation> _conversations = const [];
  bool _loading = true;
  String? _error;
  String? _openingId;
  String? _deletingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conversations = await _api.listSavedFloatchatConversations();
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _parseError(e);
      });
    }
  }

  String _parseError(dynamic e) {
    final str = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    return match?.group(1) ?? 'Could not load saved conversations.';
  }

  String _formatDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return 'Saved conversation';
    return _dateFormat.format(parsed.toLocal());
  }

  Future<void> _openConversation(
      SavedFloatchatConversation conversation) async {
    if (_openingId != null || _deletingId != null) return;
    setState(() => _openingId = conversation.id);
    try {
      final detail = await _api.getSavedFloatchatConversation(conversation.id);
      if (!mounted) return;
      Navigator.pop(context, SavedSageChatsResult.open(detail));
    } catch (e) {
      if (!mounted) return;
      setState(() => _openingId = null);
      await showCupertinoDialog<void>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Could not open'),
          content: Text(_parseError(e)),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _deleteConversation(
    SavedFloatchatConversation conversation,
  ) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete saved conversation'),
        content: Text('Remove "${conversation.title}" from saved chats?'),
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

    setState(() => _deletingId = conversation.id);
    try {
      await _api.deleteSavedFloatchatConversation(conversation.id);
      if (!mounted) return;
      setState(() {
        _conversations =
            _conversations.where((item) => item.id != conversation.id).toList();
        _deletingId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingId = null);
      await showCupertinoDialog<void>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Delete failed'),
          content: Text(_parseError(e)),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: CupertinoPageScaffold(
        backgroundColor: JournalColors.bgBase,
        child: CustomScrollView(
          slivers: [
            CupertinoSliverNavigationBar(
              largeTitle: const Text('Saved Chats'),
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                onPressed: () => Navigator.pop(
                  context,
                  const SavedSageChatsResult.newChat(),
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _withAlpha(JournalColors.accent, 0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: JournalColors.borderBright),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.plus,
                        color: JournalColors.textPrimary,
                        size: 13,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'New Chat',
                        style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
              border: const Border(
                bottom: BorderSide(color: JournalColors.border, width: 0.5),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(
                  child:
                      CupertinoActivityIndicator(color: JournalColors.accent),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          CupertinoIcons.wifi_slash,
                          color: JournalColors.textMuted,
                          size: 28,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        CupertinoButton(
                          color: JournalColors.accent,
                          onPressed: _load,
                          child: const Text(
                            'Retry',
                            style: TextStyle(color: JournalColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_conversations.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.bookmark,
                          color: JournalColors.textMuted,
                          size: 28,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'No saved Sage conversations yet.',
                          style: TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Save a chat from Sage and it will show up here for quick retrieval later.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final conversation = _conversations[index];
                      final opening = _openingId == conversation.id;
                      final deleting = _deletingId == conversation.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassCard(
                          onTap: opening || deleting
                              ? null
                              : () => _openConversation(conversation),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          conversation.title,
                                          style: const TextStyle(
                                            color: JournalColors.textPrimary,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _formatDate(conversation.updatedAt),
                                          style: const TextStyle(
                                            color: JournalColors.textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(28, 28),
                                    onPressed: deleting || opening
                                        ? null
                                        : () =>
                                            _deleteConversation(conversation),
                                    child: deleting
                                        ? const CupertinoActivityIndicator(
                                            color: JournalColors.danger,
                                          )
                                        : const Icon(
                                            CupertinoIcons.delete,
                                            color: JournalColors.danger,
                                            size: 18,
                                          ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                conversation.preview,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: JournalColors.textSecondary,
                                  fontSize: 14,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _SavedChatPill(
                                    label:
                                        '${conversation.messageCount} ${conversation.messageCount == 1 ? 'message' : 'messages'}',
                                  ),
                                  _SavedChatPill(
                                    label: conversation.webSearchEnabled
                                        ? 'Web search on'
                                        : 'Web search off',
                                    accent: conversation.webSearchEnabled,
                                  ),
                                  _SavedChatPill(
                                    label: opening ? 'Opening…' : 'Tap to open',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: _conversations.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SavedChatPill extends StatelessWidget {
  const _SavedChatPill({
    required this.label,
    this.accent = false,
  });

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent
            ? _withAlpha(JournalColors.accent, 0.14)
            : _withAlpha(JournalColors.bgSurface, 0.84),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent ? JournalColors.borderBright : JournalColors.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color:
              accent ? JournalColors.textPrimary : JournalColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
