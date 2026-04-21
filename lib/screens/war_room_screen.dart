import 'package:flutter/cupertino.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'ask_journal_screen.dart';
import 'detective_screen.dart';
import 'exit_plan_screen.dart';
import 'fairness_ledger_screen.dart';
import 'mental_health_screen.dart';
import 'write_screen.dart';

class WarRoomScreen extends StatefulWidget {
  const WarRoomScreen({super.key});

  @override
  State<WarRoomScreen> createState() => _WarRoomScreenState();
}

class _WarRoomScreenState extends State<WarRoomScreen> {
  final _api = ApiService();
  final _brainDumpController = TextEditingController();

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;
  _WarRoomLevel _urgency = _WarRoomLevel.medium;
  _WarRoomLevel _impact = _WarRoomLevel.medium;
  _WarRoomLevel _control = _WarRoomLevel.medium;
  bool _safetyConcern = false;
  bool _waitingOnReply = false;
  bool _spiraling = false;

  @override
  void dispose() {
    _brainDumpController.dispose();
    super.dispose();
  }

  Future<void> _triage() async {
    final brainDump = _brainDumpController.text.trim();
    if (brainDump.length < 10) {
      setState(() {
        _error = 'Write at least a sentence. Just dump it — no structure needed.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _api.warRoomTriage(
        brainDump: _buildBrainDumpPayload(brainDump),
      );
      if (!mounted) return;
      setState(() {
        _result = result;
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

  void _applyPrompt(String prompt) {
    setState(() {
      _brainDumpController.text = prompt;
      _brainDumpController.selection = TextSelection.fromPosition(
        TextPosition(offset: _brainDumpController.text.length),
      );
    });
  }

  String _buildBrainDumpPayload(String brainDump) {
    final flags = <String>[
      'Urgency: ${_urgency.label}',
      'Impact: ${_impact.label}',
      'Control: ${_control.label}',
      if (_safetyConcern) 'Safety concern is present',
      if (_waitingOnReply) 'I am waiting on someone else to respond',
      if (_spiraling) 'I feel activated or spiraling',
    ];

    return '''
War Room signals:
${flags.map((flag) => '- $flag').join('\n')}

Brain dump:
$brainDump
''';
  }

  Future<void> _openTool(Map<String, dynamic> item) async {
    final tool = item['tool']?.toString();
    Widget? destination;

    switch (tool) {
      case 'exit_plan':
        destination = const ExitPlanScreen();
        break;
      case 'detective':
        destination = const DetectiveScreen();
        break;
      case 'fairness':
        destination = const FairnessLedgerScreen();
        break;
      case 'ask_journal':
        destination = const AskJournalScreen();
        break;
      case 'mental_health':
        destination = const MentalHealthScreen();
        break;
      case 'write':
        destination = const WriteScreen();
        break;
      default:
        destination = null;
    }

    if (destination == null) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Tool not wired yet'),
          content: Text(
            (item['tool_label']?.toString().trim().isNotEmpty ?? false)
                ? '${item['tool_label']} is not wired on mobile yet.'
                : 'This recommendation does not have a mobile destination yet.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: destination!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final situationRead = result?['situation_read']?.toString().trim();

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('War Room'),
            backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _HeroCard(
                  flags: [
                    if (_safetyConcern) 'Safety concern',
                    if (_waitingOnReply) 'Waiting on someone else',
                    if (_spiraling) 'Spiraling',
                    'Urgency: ${_urgency.label}',
                    'Impact: ${_impact.label}',
                    'Control: ${_control.label}',
                  ],
                ),
                const SizedBox(height: 18),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quick triage signals',
                        style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Optional, but useful. These cues get folded into the generated triage.',
                        style: TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _LevelControl(
                        title: 'Urgency',
                        subtitle: 'How quickly does something truly need attention?',
                        value: _urgency,
                        onChanged: (value) => setState(() => _urgency = value),
                      ),
                      const SizedBox(height: 16),
                      _LevelControl(
                        title: 'Impact',
                        subtitle: 'If ignored, how much does this affect your life?',
                        value: _impact,
                        onChanged: (value) => setState(() => _impact = value),
                      ),
                      const SizedBox(height: 16),
                      _LevelControl(
                        title: 'Control',
                        subtitle: 'How much influence do you realistically have?',
                        value: _control,
                        onChanged: (value) => setState(() => _control = value),
                      ),
                      const SizedBox(height: 16),
                      _ToggleTile(
                        value: _safetyConcern,
                        onChanged: (value) =>
                            setState(() => _safetyConcern = value),
                        icon: CupertinoIcons.exclamationmark_shield_fill,
                        iconColor: JournalColors.danger,
                        title: 'Safety concern',
                        subtitle: 'You feel unsafe, threatened, trapped, or at risk.',
                      ),
                      const SizedBox(height: 10),
                      _ToggleTile(
                        value: _waitingOnReply,
                        onChanged: (value) =>
                            setState(() => _waitingOnReply = value),
                        icon: CupertinoIcons.chat_bubble_2_fill,
                        iconColor: JournalColors.info,
                        title: 'Waiting on someone else',
                        subtitle:
                            'The next move partly depends on another person responding.',
                      ),
                      const SizedBox(height: 10),
                      _ToggleTile(
                        value: _spiraling,
                        onChanged: (value) =>
                            setState(() => _spiraling = value),
                        icon: CupertinoIcons.waveform_path_ecg,
                        iconColor: JournalColors.accent2,
                        title: 'Spiraling',
                        subtitle:
                            'Your body feels activated and it is hard to think clearly.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                GlassCard(
                  accentBorder: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'What\'s swirling in your head right now?',
                        style: TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      CupertinoTextField(
                        controller: _brainDumpController,
                        minLines: 7,
                        maxLines: 10,
                        padding: const EdgeInsets.all(14),
                        placeholder:
                            'I\'m overwhelmed because... I need to figure out... I\'m worried about... I don\'t know what to do about...',
                        placeholderStyle: const TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 13,
                        ),
                        style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 14,
                          height: 1.45,
                        ),
                        decoration: BoxDecoration(
                          color: JournalColors.bgBase,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: JournalColors.border),
                        ),
                        onChanged: (_) {
                          setState(() {
                            if (_error != null) _error = null;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _starterPrompts
                            .map(
                              (prompt) => GestureDetector(
                                onTap: () => _applyPrompt(prompt.template),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: JournalColors.bgSurface,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: JournalColors.border,
                                    ),
                                  ),
                                  child: Text(
                                    prompt.label,
                                    style: const TextStyle(
                                      color: JournalColors.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: JournalColors.danger,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Your journal history is included automatically for context.',
                              style: TextStyle(
                                color: JournalColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            color: JournalColors.accent,
                            borderRadius: BorderRadius.circular(10),
                            onPressed: _loading ||
                                    _brainDumpController.text.trim().isEmpty
                                ? null
                                : _triage,
                            child: _loading
                                ? const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CupertinoActivityIndicator(
                                        color: CupertinoColors.white,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Triaging...',
                                        style: TextStyle(
                                          color: CupertinoColors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  )
                                : const Text(
                                    'Triage It',
                                    style: TextStyle(
                                      color: CupertinoColors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (result != null) ...[
                  const SizedBox(height: 22),
                  if (situationRead != null && situationRead.isNotEmpty)
                    _SituationReadCard(text: situationRead),
                  if (situationRead != null && situationRead.isNotEmpty)
                    const SizedBox(height: 24),
                  _BucketSection(
                    config: _BucketConfig.actNow,
                    items: _itemsFromResult(result['act_now']),
                    onOpenTool: _openTool,
                  ),
                  const SizedBox(height: 24),
                  _BucketSection(
                    config: _BucketConfig.planWeek,
                    items: _itemsFromResult(result['plan_week']),
                    onOpenTool: _openTool,
                  ),
                  const SizedBox(height: 24),
                  _BucketSection(
                    config: _BucketConfig.letGo,
                    items: _itemsFromResult(result['let_go']),
                    onOpenTool: _openTool,
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

enum _WarRoomLevel { low, medium, high }

extension on _WarRoomLevel {
  String get label {
    switch (this) {
      case _WarRoomLevel.low:
        return 'Low';
      case _WarRoomLevel.medium:
        return 'Medium';
      case _WarRoomLevel.high:
        return 'High';
    }
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.flags});

  final List<String> flags;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            JournalColors.accent.withValues(alpha: 0.24),
            JournalColors.accent2.withValues(alpha: 0.14),
            JournalColors.bgCard,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: JournalColors.accent.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: JournalColors.accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Text(
              '⚔',
              style: TextStyle(fontSize: 20),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Decide what deserves your energy.',
            style: TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'You don\'t need to be organized. Dump the full mess and War Room will sort it into what to act on, what to plan, and what to release.',
            style: TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: flags
                .map(
                  (flag) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: JournalColors.bgSurface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: JournalColors.border),
                    ),
                    child: Text(
                      flag,
                      style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _LevelControl extends StatelessWidget {
  const _LevelControl({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final _WarRoomLevel value;
  final ValueChanged<_WarRoomLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: JournalColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: JournalColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        CupertinoSlidingSegmentedControl<_WarRoomLevel>(
          groupValue: value,
          thumbColor: JournalColors.accent.withValues(alpha: 0.9),
          backgroundColor: JournalColors.bgSurface,
          children: const {
            _WarRoomLevel.low: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text('Low', style: TextStyle(fontSize: 13)),
            ),
            _WarRoomLevel.medium: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text('Medium', style: TextStyle(fontSize: 13)),
            ),
            _WarRoomLevel.high: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text('High', style: TextStyle(fontSize: 13)),
            ),
          },
          onValueChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ],
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.value,
    required this.onChanged,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: JournalColors.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value
              ? iconColor.withValues(alpha: 0.45)
              : JournalColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: iconColor,
          ),
        ],
      ),
    );
  }
}

class _SituationReadCard extends StatelessWidget {
  const _SituationReadCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JournalColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: JournalColors.accent.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              '◈',
              style: TextStyle(
                color: JournalColors.accent2,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
                fontStyle: FontStyle.italic,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BucketSection extends StatelessWidget {
  const _BucketSection({
    required this.config,
    required this.items,
    required this.onOpenTool,
  });

  final _BucketConfig config;
  final List<Map<String, dynamic>> items;
  final Future<void> Function(Map<String, dynamic>) onOpenTool;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: config.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: config.color.withValues(alpha: 0.32),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                config.icon,
                style: TextStyle(
                  color: config.color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.label,
                    style: TextStyle(
                      color: config.color,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    config.description,
                    style: const TextStyle(
                      color: JournalColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: config.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: config.color.withValues(alpha: 0.28),
                ),
              ),
              child: Text(
                '${items.length}',
                style: TextStyle(
                  color: config.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _ActionCard(
              config: config,
              item: item,
              onOpenTool: onOpenTool,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.config,
    required this.item,
    required this.onOpenTool,
  });

  final _BucketConfig config;
  final Map<String, dynamic> item;
  final Future<void> Function(Map<String, dynamic>) onOpenTool;

  @override
  Widget build(BuildContext context) {
    final urgencyNote = item['urgency_note']?.toString().trim();
    final reframe = item['reframe']?.toString().trim();
    final tool = item['tool']?.toString();
    final toolLabel = item['tool_label']?.toString().trim();
    final hasToolRoute = item['tool_route']?.toString().trim().isNotEmpty == true;
    final canOpenTool = tool != null && tool != 'none' && hasToolRoute;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: JournalColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: config.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item['title']?.toString() ?? 'Untitled',
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                config.icon,
                style: TextStyle(
                  color: config.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item['why']?.toString() ?? '',
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
          if (urgencyNote != null && urgencyNote.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: config.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: config.borderColor),
              ),
              child: Text(
                urgencyNote,
                style: TextStyle(
                  color: config.color,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ),
          ],
          if (reframe != null && reframe.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: config.borderColor, width: 2),
                ),
              ),
              child: Text(
                reframe,
                style: const TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
              ),
            ),
          ],
          if (canOpenTool) ...[
            const SizedBox(height: 16),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: CupertinoColors.transparent,
              borderRadius: BorderRadius.circular(10),
              onPressed: () => onOpenTool(item),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  'Open in ${toolLabel?.isNotEmpty == true ? toolLabel : 'Tool'}',
                  style: TextStyle(
                    color: config.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BucketConfig {
  final String label;
  final String icon;
  final Color color;
  final Color borderColor;
  final String description;

  const _BucketConfig({
    required this.label,
    required this.icon,
    required this.color,
    required this.borderColor,
    required this.description,
  });

  static const actNow = _BucketConfig(
    label: 'Act Now',
    icon: '◈',
    color: JournalColors.danger,
    borderColor: Color(0x4DEF4444),
    description: 'Do today — reduces chaos immediately',
  );

  static const planWeek = _BucketConfig(
    label: 'Plan This Week',
    icon: '◷',
    color: JournalColors.severity,
    borderColor: Color(0x4DF59E0B),
    description: 'Schedule before Friday — decisions & conversations',
  );

  static const letGo = _BucketConfig(
    label: 'Let Go For Now',
    icon: '〜',
    color: JournalColors.accent,
    borderColor: Color(0x4D6366F1),
    description: 'Outside your control — stop burning energy here',
  );
}

class _StarterPrompt {
  final String label;
  final String template;

  const _StarterPrompt(this.label, this.template);
}

const _starterPrompts = <_StarterPrompt>[
  _StarterPrompt(
    'Fight or flight',
    'I feel activated and like everything is urgent. I need help sorting what actually needs action right now from what just feels intense.',
  ),
  _StarterPrompt(
    'Big conversation',
    'I need to have an important conversation and I do not want to go in reactive. Help me sort what to do now, what to plan, and what to release.',
  ),
  _StarterPrompt(
    'No reply',
    'I am waiting on someone else to reply and my brain is filling the silence with worst-case stories. Help me separate what I can act on from what is not mine to control.',
  ),
  _StarterPrompt(
    'Safety first',
    'Something feels unsafe or volatile and I need to think clearly about what to do immediately versus what can wait.',
  ),
];

List<Map<String, dynamic>> _itemsFromResult(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

String _parseError(Object error) {
  final raw = error.toString();
  const marker = 'Exception:';
  if (raw.contains(marker)) {
    return raw.split(marker).last.trim();
  }
  return raw;
}
