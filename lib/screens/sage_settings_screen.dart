import 'package:flutter/cupertino.dart';

import 'sage_tracks_screen.dart';
import '../services/sage_profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

const _kSageVoices = <({String id, String label, String desc})>[
  (id: 'shimmer', label: 'Shimmer', desc: 'Soft, calm, reflective'),
  (id: 'nova', label: 'Nova', desc: 'Warm, conversational, close'),
  (id: 'fable', label: 'Fable', desc: 'Steady, grounded, coach-like'),
  (id: 'onyx', label: 'Onyx', desc: 'Sharper, darker, more edge'),
  (id: 'echo', label: 'Echo', desc: 'Clean, neutral, understated'),
  (id: 'alloy', label: 'Alloy', desc: 'Balanced, general-purpose'),
];

const _kWarmthOptions = <({String id, String label})>[
  (id: 'calm', label: 'Calm'),
  (id: 'warm', label: 'Warm'),
  (id: 'close', label: 'Close'),
];

const _kToneModeOptions = <({String id, String label, String desc})>[
  (
    id: 'standard',
    label: 'Standard',
    desc: 'Grounded, direct, emotionally intelligent'
  ),
  (
    id: 'unhinged',
    label: 'Unhinged',
    desc: 'Chaos agent v2. Sharper, meaner, less patient with excuses'
  ),
];

const _kDirectnessOptions = <({String id, String label})>[
  (id: 'gentle', label: 'Gentle'),
  (id: 'direct', label: 'Direct'),
  (id: 'blunt', label: 'Blunt'),
];

class SageSettingsScreen extends StatefulWidget {
  const SageSettingsScreen({super.key});

  @override
  State<SageSettingsScreen> createState() => _SageSettingsScreenState();
}

class _SageSettingsScreenState extends State<SageSettingsScreen> {
  final _profile = SageProfileService();
  final _memoryCtrl = TextEditingController();

  SageSettings _settings = SageSettings.defaults;
  List<SageMemoryItem> _memoryItems = const [];
  bool _loading = true;
  bool _saving = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _memoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await _profile.loadSettings();
      final memory = await _profile.loadMemoryItems();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _memoryItems = memory;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load Sage settings.';
      });
    }
  }

  Future<void> _saveSettings(SageSettings next) async {
    setState(() {
      _settings = next;
      _saving = true;
      _saved = false;
      _error = null;
    });
    try {
      await _profile.saveSettings(next);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saved = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save Sage settings.';
      });
    }
  }

  Future<void> _addMemory() async {
    final text = _memoryCtrl.text.trim();
    if (text.isEmpty) return;
    final memory = await _profile.addMemoryTexts([text]);
    _memoryCtrl.clear();
    if (!mounted) return;
    setState(() => _memoryItems = memory);
  }

  Future<void> _removeMemory(String id) async {
    final memory = await _profile.removeMemoryItem(id);
    if (!mounted) return;
    setState(() => _memoryItems = memory);
  }

  Future<void> _clearMemory() async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Clear Sage Memory'),
        content: const Text(
          'This removes all locally saved Sage memory notes from this device.',
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _profile.clearMemory();
    if (!mounted) return;
    setState(() => _memoryItems = const []);
  }

  Future<void> _push(Widget screen) {
    return Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: screen,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Sage Settings'),
            backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(
                      child: CupertinoActivityIndicator(
                          color: JournalColors.accent),
                    ),
                  )
                else ...[
                  GlassCard(
                    accentBorder: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tune Sage',
                          style: TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Control how Sage sounds, what gets remembered, and what carries forward into future conversations.',
                          style: TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          _StatusChip(
                            label: _error!,
                            color: JournalColors.danger,
                          ),
                        ] else if (_saved || _saving) ...[
                          const SizedBox(height: 12),
                          _StatusChip(
                            label: _saving ? 'Saving…' : 'Saved',
                            color: JournalColors.accent,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _SectionLabel('VOICE'),
                  const SizedBox(height: 8),
                  GlassCard(
                    child: Column(
                      children: _kSageVoices.map((voice) {
                        final active = _settings.voiceId == voice.id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GestureDetector(
                            onTap: () => _saveSettings(
                                _settings.copyWith(voiceId: voice.id)),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: active
                                    ? _withAlpha(JournalColors.accent, 0.14)
                                    : JournalColors.bgSurface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: active
                                      ? JournalColors.borderBright
                                      : JournalColors.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          voice.label,
                                          style: TextStyle(
                                            color: active
                                                ? JournalColors.textPrimary
                                                : JournalColors.textSecondary,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          voice.desc,
                                          style: const TextStyle(
                                            color: JournalColors.textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    active
                                        ? CupertinoIcons
                                            .check_mark_circled_solid
                                        : CupertinoIcons.circle,
                                    color: active
                                        ? JournalColors.accent
                                        : JournalColors.textMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _SectionLabel('TONE'),
                  const SizedBox(height: 8),
                  GlassCard(
                    child: Column(
                      children: _kToneModeOptions.map((mode) {
                        final active = _settings.toneMode == mode.id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GestureDetector(
                            onTap: () => _saveSettings(
                              _settings.copyWith(toneMode: mode.id),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: active
                                    ? _withAlpha(JournalColors.accent, 0.14)
                                    : JournalColors.bgSurface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: active
                                      ? JournalColors.borderBright
                                      : JournalColors.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          mode.label,
                                          style: TextStyle(
                                            color: active
                                                ? JournalColors.textPrimary
                                                : JournalColors.textSecondary,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          mode.desc,
                                          style: const TextStyle(
                                            color: JournalColors.textMuted,
                                            fontSize: 12,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    active
                                        ? CupertinoIcons
                                            .check_mark_circled_solid
                                        : CupertinoIcons.circle,
                                    color: active
                                        ? JournalColors.accent
                                        : JournalColors.textMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _SectionLabel('PERSONALITY'),
                  const SizedBox(height: 8),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Warmth',
                          style: TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: _kWarmthOptions
                              .map(
                                (opt) => Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: opt.id == _kWarmthOptions.last.id
                                          ? 0
                                          : 8,
                                    ),
                                    child: _ChoicePill(
                                      label: opt.label,
                                      active: _settings.warmth == opt.id,
                                      onTap: () => _saveSettings(
                                        _settings.copyWith(warmth: opt.id),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Directness',
                          style: TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: _kDirectnessOptions
                              .map(
                                (opt) => Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right:
                                          opt.id == _kDirectnessOptions.last.id
                                              ? 0
                                              : 8,
                                    ),
                                    child: _ChoicePill(
                                      label: opt.label,
                                      active: _settings.directness == opt.id,
                                      onTap: () => _saveSettings(
                                        _settings.copyWith(directness: opt.id),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _SectionLabel('BEHAVIOR'),
                  const SizedBox(height: 8),
                  GlassCard(
                    child: Column(
                      children: [
                        _ToggleRow(
                          icon: CupertinoIcons.sparkles,
                          title: 'Auto greeting',
                          subtitle:
                              'Start each new session with a context-aware opening.',
                          value: _settings.autoGreeting,
                          onChanged: (value) => _saveSettings(
                              _settings.copyWith(autoGreeting: value)),
                        ),
                        Container(
                          height: 1,
                          margin: const EdgeInsets.symmetric(vertical: 20),
                          color: JournalColors.border,
                        ),
                        _ToggleRow(
                          icon: CupertinoIcons.bookmark,
                          title: 'Auto remember',
                          subtitle:
                              'Let Sage save durable conversation facts for future context.',
                          value: _settings.autoRemember,
                          onChanged: (value) => _saveSettings(
                              _settings.copyWith(autoRemember: value)),
                        ),
                        Container(
                          height: 1,
                          margin: const EdgeInsets.symmetric(vertical: 20),
                          color: JournalColors.border,
                        ),
                        _ToggleRow(
                          icon: CupertinoIcons.chat_bubble_2_fill,
                          title: 'Allow swearing',
                          subtitle:
                              'Keep Sage natural and blunt when the moment calls for it.',
                          value: _settings.allowSwearing,
                          onChanged: (value) => _saveSettings(
                              _settings.copyWith(allowSwearing: value)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _SectionLabel('INTELLIGENCE'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _withAlpha(JournalColors.severity, 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _withAlpha(JournalColors.severity, 0.28),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          CupertinoIcons.globe,
                          color: JournalColors.severity,
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Web search sends your questions to external servers to fetch real-time results. '
                            'No journal content is included in the search — only the specific query Sage generates. '
                            'Off by default.',
                            style: TextStyle(
                              color: JournalColors.severity,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  GlassCard(
                    child: _ToggleRow(
                      icon: CupertinoIcons.search,
                      title: 'Web search',
                      subtitle:
                          'Let Sage fetch real-time results for lawyers, resources, news, and anything that needs live data.',
                      value: _settings.webSearchEnabled,
                      onChanged: (value) => _saveSettings(
                        _settings.copyWith(webSearchEnabled: value),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _withAlpha(JournalColors.info, 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _withAlpha(JournalColors.info, 0.24),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          CupertinoIcons.paperclip,
                          color: JournalColors.info,
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Sage can review supported text-based files right inside chat now. '
                            'Live image vision and true web-search tooling still need additional backend support, so keep this focused on documents and text for now.',
                            style: TextStyle(
                              color: JournalColors.info,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _SectionLabel('ONGOING COACH'),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _push(const SageTracksScreen()),
                    child: GlassCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: _withAlpha(JournalColors.accent, 0.16),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: JournalColors.borderBright,
                              ),
                            ),
                            child: const Icon(
                              CupertinoIcons.arrow_branch,
                              color: JournalColors.textPrimary,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Focus Tracks',
                                  style: TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Create persistent tracks like breakup recovery, custody, sobriety, burnout, or finances so Sage can carry goals and unfinished threads across sessions.',
                                  style: TextStyle(
                                    color: JournalColors.textSecondary,
                                    fontSize: 13,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            CupertinoIcons.chevron_right,
                            color: JournalColors.textMuted,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _SectionLabel('SAGE MEMORY'),
                  const SizedBox(height: 8),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Saved context',
                          style: TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Short durable notes Sage should carry into future conversations on this device.',
                          style: TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 14),
                        CupertinoTextField(
                          controller: _memoryCtrl,
                          placeholder: 'Add something Sage should remember…',
                          minLines: 2,
                          maxLines: 4,
                          padding: const EdgeInsets.all(14),
                          style: const TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 15,
                          ),
                          placeholderStyle: const TextStyle(
                            color: JournalColors.textMuted,
                            fontSize: 15,
                          ),
                          decoration: BoxDecoration(
                            color: JournalColors.bgSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: JournalColors.border),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              color: JournalColors.accent,
                              onPressed: _addMemory,
                              child: const Text(
                                'Save Memory',
                                style: TextStyle(
                                  color: JournalColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (_memoryItems.isNotEmpty)
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: _clearMemory,
                                child: const Text(
                                  'Clear All',
                                  style: TextStyle(
                                    color: JournalColors.danger,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (_memoryItems.isEmpty) ...[
                          const SizedBox(height: 10),
                          const Text(
                            'Nothing saved yet.',
                            style: TextStyle(
                              color: JournalColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                          ..._memoryItems.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      _withAlpha(JournalColors.bgSurface, 0.9),
                                  borderRadius: BorderRadius.circular(14),
                                  border:
                                      Border.all(color: JournalColors.border),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.text,
                                            style: const TextStyle(
                                              color: JournalColors.textPrimary,
                                              fontSize: 14,
                                              height: 1.45,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            item.source == 'learned'
                                                ? 'Learned from conversation'
                                                : 'Saved manually',
                                            style: const TextStyle(
                                              color: JournalColors.textMuted,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    GestureDetector(
                                      onTap: () => _removeMemory(item.id),
                                      child: const Icon(
                                        CupertinoIcons.xmark_circle_fill,
                                        color: JournalColors.textMuted,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: JournalColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.15,
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 44,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? _withAlpha(JournalColors.accent, 0.16)
              : JournalColors.bgSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? JournalColors.borderBright : JournalColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? JournalColors.accent : JournalColors.textSecondary,
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: JournalColors.accent, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
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
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        CupertinoSwitch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: JournalColors.accent,
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _withAlpha(color, 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _withAlpha(color, 0.26)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
