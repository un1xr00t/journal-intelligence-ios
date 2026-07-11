import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

const _purposes = [
  ('general', 'General'),
  ('therapy', 'For Therapist'),
  ('legal', 'For Legal'),
  ('custody', 'For Custody'),
  ('hr', 'For HR / Work'),
  ('support', 'Support Network'),
  ('personal', 'Personal Record'),
];

const _styles = [
  ('advocate', 'Advocate'),
  ('neutral', 'Neutral'),
  ('emotional', 'Emotional'),
  ('clinical', 'Clinical'),
];

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

const _purposeColors = {
  'general': JournalColors.accent,
  'therapy': JournalColors.success,
  'legal': JournalColors.accent2,
  'custody': JournalColors.danger,
  'hr': JournalColors.severity,
  'support': JournalColors.info,
  'personal': JournalColors.textSecondary,
};

String _purposeLabel(String key) =>
    _purposes.firstWhere((p) => p.$1 == key, orElse: () => (key, key)).$2;

Color _purposeColor(String key) => _purposeColors[key] ?? JournalColors.accent;

String _parseError(dynamic e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail != null) return detail.toString();
    }
    if (data is String && data.isNotEmpty) return data;
    final status = e.response?.statusCode;
    if (status != null) {
      return 'Server error ($status). Check your settings and try again.';
    }
  }

  final str = e.toString();
  final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
  return match?.group(1) ?? 'Something went wrong.';
}

class MyStoryScreen extends StatefulWidget {
  const MyStoryScreen({super.key});

  @override
  State<MyStoryScreen> createState() => _MyStoryScreenState();
}

class _MyStoryScreenState extends State<MyStoryScreen> {
  final _api = ApiService();

  List<dynamic> _cases = [];
  bool _hasDetective = false;
  bool _initLoading = true;

  final Set<dynamic> _selectedCases = {};
  bool _includeJournal = true;
  int _journalCount = 20;
  bool _includeFairness = false;
  bool _includeProofVault = true;
  bool _includeArgumentTracker = true;
  String _purpose = 'general';
  String _style = 'advocate';
  final _manualCtrl = TextEditingController();
  final _manualFocus = FocusNode();

  bool _generating = false;
  String? _narrative;
  String? _genError;
  bool _autoSaved = false;

  int _tab = 0;
  List<dynamic> _drafts = [];
  bool _draftsLoading = true;

  @override
  void initState() {
    super.initState();
    _manualFocus.addListener(() => setState(() {}));
    _loadInit();
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    _manualFocus.dispose();
    super.dispose();
  }

  Future<void> _loadInit() async {
    try {
      final r = await _api.myStoryGetCases();
      if (mounted) {
        setState(() {
          _cases = r['cases'] as List? ?? [];
          _hasDetective = r['has_detective_access'] as bool? ?? false;
          _initLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _initLoading = false);
    }

    _loadDrafts();
  }

  Future<void> _loadDrafts() async {
    try {
      final d = await _api.myStoryGetDrafts();
      if (mounted) {
        setState(() {
          _drafts = d;
          _draftsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _draftsLoading = false);
    }
  }

  bool get _canGenerate =>
      _includeJournal ||
      _includeProofVault ||
      _includeArgumentTracker ||
      _selectedCases.isNotEmpty ||
      _manualCtrl.text.trim().isNotEmpty;

  int get _sourceCount {
    var count = 0;
    if (_includeJournal) count++;
    if (_includeProofVault) count++;
    if (_includeArgumentTracker) count++;
    if (_selectedCases.isNotEmpty) count++;
    if (_includeFairness) count++;
    if (_manualCtrl.text.trim().isNotEmpty) count++;
    return count;
  }

  String get _sourceSummary {
    final parts = <String>[];
    if (_includeJournal) parts.add('$_journalCount journal entries');
    if (_includeProofVault) parts.add('Proof Vault');
    if (_includeArgumentTracker) parts.add('Argument Tracker');
    if (_selectedCases.isNotEmpty) {
      parts.add(
        _selectedCases.length == 1
            ? '1 case file'
            : '${_selectedCases.length} case files',
      );
    }
    if (_includeFairness) parts.add('fairness ledger');
    if (_manualCtrl.text.trim().isNotEmpty) parts.add('manual context');
    return parts.isEmpty ? 'No sources selected yet' : parts.join(' • ');
  }

  Future<void> _generate() async {
    if (!_canGenerate || _generating) return;

    setState(() {
      _generating = true;
      _genError = null;
      _narrative = null;
      _autoSaved = false;
    });

    try {
      final body = {
        'case_ids': _selectedCases.toList(),
        'include_journal': _includeJournal,
        'journal_entry_count': _journalCount,
        'manual_context': _manualCtrl.text.trim(),
        'include_fairness': _includeFairness,
        'include_proof_vault': _includeProofVault,
        'include_argument_tracker': _includeArgumentTracker,
        'output_purpose': _purpose,
        'output_style': _style,
      };

      final r = await _api.myStoryGenerate(body);
      final text = r['narrative'] as String? ?? '';

      if (!mounted) return;
      setState(() => _narrative = text);

      try {
        final parts = <String>[];
        if (_includeJournal) parts.add('$_journalCount journal entries');
        if (_includeProofVault) parts.add('Proof Vault');
        if (_includeArgumentTracker) parts.add('Argument Tracker');
        if (_selectedCases.isNotEmpty) {
          parts.add('${_selectedCases.length} case(s)');
        }
        if (_manualCtrl.text.trim().isNotEmpty) parts.add('manual context');

        await _api.myStorySaveDraft({
          'title': 'My Story - ${_purposeLabel(_purpose)}',
          'generated_text': text,
          'manual_context': _manualCtrl.text.trim(),
          'output_purpose': _purpose,
          'sources_summary': parts.join(', '),
        });
        if (mounted) setState(() => _autoSaved = true);
        _loadDrafts();
      } catch (_) {}
    } catch (e) {
      if (mounted) setState(() => _genError = _parseError(e));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _loadDraft(Map<String, dynamic> draft) async {
    try {
      final full = await _api.myStoryGetDraft(draft['id'] as int);
      if (!mounted) return;

      setState(() {
        _narrative = full['generated_text'] as String? ?? '';
        _purpose = full['output_purpose'] as String? ?? 'general';
        _manualCtrl.text = full['manual_context'] as String? ?? '';
        _autoSaved = true;
        _tab = 0;
      });
    } catch (e) {
      if (mounted) _showError(_parseError(e));
    }
  }

  Future<void> _deleteDraft(int id) async {
    try {
      await _api.myStoryDeleteDraft(id);
      if (mounted) {
        setState(() => _drafts.removeWhere((d) => d['id'] == id));
      }
    } catch (e) {
      if (mounted) _showError(_parseError(e));
    }
  }

  void _copyNarrative() {
    if (_narrative == null) return;
    Clipboard.setData(ClipboardData(text: _narrative!));
    _showToast('Copied to clipboard');
  }

  void _showError(String msg) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(msg),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showToast(String msg) {
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => CupertinoAlertDialog(
        content: Text(msg),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildContent() {
    if (_tab == 1) {
      return _buildDraftsContent();
    }

    if (_initLoading) {
      return const [
        SizedBox(height: 120),
        Center(
          child: CupertinoActivityIndicator(color: JournalColors.accent),
        ),
      ];
    }

    return [
      _MyStoryHero(
        sourceCount: _sourceCount,
        sourceSummary: _sourceSummary,
        selectedPurpose: _purposeLabel(_purpose),
        selectedStyle: _styles
            .firstWhere((style) => style.$1 == _style, orElse: () => _styles[0])
            .$2,
        hasNarrative: _narrative != null,
      ),
      const SizedBox(height: 20),
      _tabSwitcher(),
      const SizedBox(height: 20),
      _buildSection(
        title: 'Sources',
        child: GlassCard(
          child: Column(
            children: [
              _ToggleTile(
                title: 'Journal entries',
                subtitle: 'Use recent entries as primary context.',
                valueLabel: _includeJournal ? '$_journalCount selected' : null,
                value: _includeJournal,
                onChanged: (v) => setState(() => _includeJournal = v),
              ),
              if (_includeJournal) ...[
                const SizedBox(height: 14),
                _CompactInfoRow(
                  label: 'Entry count',
                  child: _Stepper(
                    value: _journalCount,
                    min: 5,
                    max: 50,
                    step: 5,
                    onChanged: (v) => setState(() => _journalCount = v),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _ToggleTile(
                title: 'Proof Vault',
                subtitle:
                    'Use stored evidence, dated proof items, and cached vault summaries.',
                value: _includeProofVault,
                onChanged: (v) => setState(() => _includeProofVault = v),
              ),
              const SizedBox(height: 18),
              _ToggleTile(
                title: 'Argument Tracker',
                subtitle:
                    'Use brief summaries of saved argument reports without pulling the full long reports.',
                value: _includeArgumentTracker,
                onChanged: (v) => setState(() => _includeArgumentTracker = v),
              ),
              if (_hasDetective && _cases.isNotEmpty) ...[
                const SizedBox(height: 18),
                const _InlineSectionLabel(
                  title: 'Case Files',
                  subtitle: 'Optional supporting records to include.',
                ),
                const SizedBox(height: 10),
                ...List.generate(_cases.length, (index) {
                  final c = _cases[index] as Map<String, dynamic>;
                  final isLast = index == _cases.length - 1;
                  return Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
                    child: _SelectableTile(
                      title: c['title'] as String? ?? 'Case',
                      selected: _selectedCases.contains(c['id']),
                      onTap: () => setState(() {
                        if (_selectedCases.contains(c['id'])) {
                          _selectedCases.remove(c['id']);
                        } else {
                          _selectedCases.add(c['id']);
                        }
                      }),
                    ),
                  );
                }),
              ],
              const SizedBox(height: 18),
              _ToggleTile(
                title: 'Fairness ledger',
                subtitle: 'Include fairness and pattern context if available.',
                value: _includeFairness,
                onChanged: (v) => setState(() => _includeFairness = v),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      _buildSection(
        title: 'Add Context',
        child: GlassCard(
          accentBorder:
              _manualFocus.hasFocus || _manualCtrl.text.trim().isNotEmpty,
          padding: const EdgeInsets.all(0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _withAlpha(JournalColors.bgCard, 0.96),
                  _withAlpha(JournalColors.bgCardAlt, 0.92),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
                  child: _InlineSectionLabel(
                    title: 'Notes For This Draft',
                    subtitle:
                        'Add dates, background, or anything the draft should make clear.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: CupertinoTextField(
                    controller: _manualCtrl,
                    focusNode: _manualFocus,
                    placeholder: 'Add anything that should shape the draft.',
                    placeholderStyle: const TextStyle(
                      color: JournalColors.textMuted,
                      fontSize: 14,
                    ),
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 15,
                      height: 1.55,
                    ),
                    padding: const EdgeInsets.all(16),
                    maxLines: null,
                    minLines: 4,
                    onChanged: (_) => setState(() {}),
                    decoration: BoxDecoration(
                      color: _withAlpha(JournalColors.bgSurface, 0.72),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _manualFocus.hasFocus
                            ? JournalColors.borderBright
                            : JournalColors.border,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 18),
      _buildSection(
        title: 'Output',
        child: Column(
          children: [
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _InlineSectionLabel(
                    title: 'Purpose',
                    subtitle: 'Choose the intended use for this draft.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _purposes
                        .map(
                          (purpose) => _ChoiceChip(
                            label: purpose.$2,
                            selected: _purpose == purpose.$1,
                            color: _purposeColor(purpose.$1),
                            onTap: () => setState(() => _purpose = purpose.$1),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _InlineSectionLabel(
                    title: 'Writing Style',
                    subtitle: 'Keep the tone aligned with the audience.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _styles
                        .map(
                          (style) => _ChoiceChip(
                            label: style.$2,
                            selected: _style == style.$1,
                            onTap: () => setState(() => _style = style.$1),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (_genError != null) ...[
        const SizedBox(height: 18),
        _ErrorCard(message: _genError!),
      ],
      const SizedBox(height: 18),
      _GenerateCard(
        canGenerate: _canGenerate,
        generating: _generating,
        purpose: _purposeLabel(_purpose),
        sourceSummary: _sourceSummary,
        onGenerate: _generate,
      ),
      if (_narrative != null) ...[
        const SizedBox(height: 22),
        _buildSection(
          title: 'Draft',
          child: _NarrativeCard(
            narrative: _narrative!,
            autoSaved: _autoSaved,
            purpose: _purposeLabel(_purpose),
            style: _styles
                .firstWhere(
                  (style) => style.$1 == _style,
                  orElse: () => _styles[0],
                )
                .$2,
            onCopy: _copyNarrative,
          ),
        ),
      ],
      const SizedBox(height: 40),
    ];
  }

  List<Widget> _buildDraftsContent() {
    if (_draftsLoading) {
      return const [
        SizedBox(height: 120),
        Center(
          child: CupertinoActivityIndicator(color: JournalColors.accent),
        ),
      ];
    }

    return [
      _MyStoryHero(
        sourceCount: _drafts.length,
        sourceSummary: _drafts.isEmpty
            ? 'Saved drafts will appear here after generation.'
            : _drafts.length == 1
                ? '1 saved draft available.'
                : '${_drafts.length} saved drafts available.',
        selectedPurpose: 'Saved drafts',
        selectedStyle: 'History',
        hasNarrative: _drafts.isNotEmpty,
      ),
      const SizedBox(height: 20),
      _tabSwitcher(),
      const SizedBox(height: 20),
      if (_drafts.isEmpty)
        GlassCard(
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _withAlpha(JournalColors.accent, 0.12),
                  border: Border.all(color: JournalColors.borderBright),
                ),
                child: const Icon(
                  CupertinoIcons.doc_text,
                  color: JournalColors.accent,
                  size: 22,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No saved drafts yet',
                style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Generate a draft and it will be stored here for quick reload later.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
            ],
          ),
        )
      else
        ..._drafts.map(
          (draft) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _DraftCard(
              draft: draft as Map<String, dynamic>,
              onLoad: _loadDraft,
              onDelete: _deleteDraft,
            ),
          ),
        ),
      const SizedBox(height: 40),
    ];
  }

  Widget _tabSwitcher() {
    return GlassCard(
      padding: const EdgeInsets.all(8),
      child: CupertinoSlidingSegmentedControl<int>(
        groupValue: _tab,
        thumbColor: _withAlpha(JournalColors.bgCardAlt, 0.96),
        backgroundColor: _withAlpha(JournalColors.bgSurface, 0.82),
        onValueChanged: (value) {
          if (value != null) setState(() => _tab = value);
        },
        children: const {
          0: Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Build',
              style: TextStyle(
                color: JournalColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          1: Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Drafts',
              style: TextStyle(
                color: JournalColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        },
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        const SizedBox(height: 10),
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: Stack(
        children: [
          const Positioned.fill(child: _MyStoryBackdrop()),
          CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('My Story'),
                backgroundColor: _withAlpha(JournalColors.bgBase, 0.85),
                border: const Border(
                  bottom: BorderSide(color: JournalColors.border, width: 0.5),
                ),
                trailing: _manualFocus.hasFocus
                    ? GestureDetector(
                        onTap: () => _manualFocus.unfocus(),
                        child: const Text(
                          'Done',
                          style: TextStyle(color: JournalColors.accent),
                        ),
                      )
                    : null,
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(_buildContent()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MyStoryBackdrop extends StatelessWidget {
  const _MyStoryBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF080914),
                    JournalColors.bgBase,
                    Color(0xFF05060D),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 92,
            left: -34,
            child: _GlowOrb(
              size: 190,
              color: _withAlpha(JournalColors.accent, 0.18),
            ),
          ),
          Positioned(
            top: 228,
            right: -42,
            child: _GlowOrb(
              size: 148,
              color: _withAlpha(JournalColors.accent2, 0.14),
            ),
          ),
          Positioned(
            bottom: 132,
            left: 18,
            child: _GlowOrb(
              size: 124,
              color: _withAlpha(JournalColors.info, 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, _withAlpha(color, 0)],
        ),
      ),
    );
  }
}

class _MyStoryHero extends StatelessWidget {
  const _MyStoryHero({
    required this.sourceCount,
    required this.sourceSummary,
    required this.selectedPurpose,
    required this.selectedStyle,
    required this.hasNarrative,
  });

  final int sourceCount;
  final String sourceSummary;
  final String selectedPurpose;
  final String selectedStyle;
  final bool hasNarrative;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accentBorder: hasNarrative,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _withAlpha(JournalColors.accent, 0.24),
                      _withAlpha(JournalColors.info, 0.14),
                    ],
                  ),
                  border: Border.all(color: JournalColors.borderBright),
                ),
                child: const Icon(
                  CupertinoIcons.doc_text_search,
                  color: JournalColors.textPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MY STORY',
                      style: TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Build a clean summary from journal history, case material, and your own context.',
                      style: TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.28,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Use this to assemble a practical draft you can refine, reuse, or share as needed.',
            style: TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricPill(
                label: 'Sources',
                value: '$sourceCount',
                color: JournalColors.accent,
              ),
              _MetricPill(
                label: 'Purpose',
                value: selectedPurpose,
                color: JournalColors.info,
              ),
              _MetricPill(
                label: 'Style',
                value: selectedStyle,
                color: JournalColors.accent2,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _withAlpha(JournalColors.bgSurface, 0.75),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: JournalColors.border),
            ),
            child: Text(
              sourceSummary,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _withAlpha(color, 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _withAlpha(color, 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color == JournalColors.textSecondary
                  ? JournalColors.textPrimary
                  : color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineSectionLabel extends StatelessWidget {
  const _InlineSectionLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: JournalColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: JournalColors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.valueLabel,
  });

  final String title;
  final String subtitle;
  final String? valueLabel;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value ? JournalColors.borderBright : JournalColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (valueLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _withAlpha(JournalColors.accent, 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          valueLabel!,
                          style: const TextStyle(
                            color: JournalColors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          CupertinoSwitch(
            value: value,
            activeTrackColor: JournalColors.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _CompactInfoRow extends StatelessWidget {
  const _CompactInfoRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.60),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JournalColors.border),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          child,
        ],
      ),
    );
  }
}

class _SelectableTile extends StatelessWidget {
  const _SelectableTile({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _withAlpha(JournalColors.bgSurface, 0.68),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? JournalColors.borderBright : JournalColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              color: selected ? JournalColors.accent : JournalColors.textMuted,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: selected
                      ? JournalColors.textPrimary
                      : JournalColors.textSecondary,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = JournalColors.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? _withAlpha(color, 0.14)
              : _withAlpha(JournalColors.bgSurface, 0.70),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _withAlpha(color, 0.34) : JournalColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? JournalColors.textPrimary
                : JournalColors.textSecondary,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _GenerateCard extends StatelessWidget {
  const _GenerateCard({
    required this.canGenerate,
    required this.generating,
    required this.purpose,
    required this.sourceSummary,
    required this.onGenerate,
  });

  final bool canGenerate;
  final bool generating;
  final String purpose;
  final String sourceSummary;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accentBorder: canGenerate,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ready To Generate',
            style: TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Purpose: $purpose',
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sourceSummary,
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          CupertinoButton(
            onPressed: canGenerate && !generating ? onGenerate : null,
            padding: EdgeInsets.zero,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: canGenerate && !generating
                    ? LinearGradient(
                        colors: [
                          _withAlpha(JournalColors.accent, 0.96),
                          _withAlpha(JournalColors.accent2, 0.92),
                        ],
                      )
                    : null,
                color: canGenerate && !generating
                    ? null
                    : _withAlpha(JournalColors.bgSurface, 0.88),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: canGenerate && !generating
                      ? const Color(0x00000000)
                      : JournalColors.border,
                ),
              ),
              child: Center(
                child: generating
                    ? const CupertinoActivityIndicator(
                        color: JournalColors.textPrimary,
                      )
                    : Text(
                        'Generate Draft',
                        style: TextStyle(
                          color: canGenerate
                              ? JournalColors.textPrimary
                              : JournalColors.textMuted,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NarrativeCard extends StatelessWidget {
  const _NarrativeCard({
    required this.narrative,
    required this.autoSaved,
    required this.purpose,
    required this.style,
    required this.onCopy,
  });

  final String narrative;
  final bool autoSaved;
  final String purpose;
  final String style;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accentBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MiniPill(label: purpose, color: JournalColors.accent),
                    _MiniPill(label: style, color: JournalColors.info),
                    if (autoSaved)
                      const _MiniPill(
                        label: 'Saved',
                        color: JournalColors.success,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: onCopy,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _withAlpha(JournalColors.bgSurface, 0.82),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: JournalColors.border),
                  ),
                  child: const Text(
                    'Copy',
                    style: TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 220),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _withAlpha(JournalColors.bgSurface, 0.70),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: JournalColors.border),
            ),
            child: Text(
              narrative,
              style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 15,
                height: 1.72,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _withAlpha(color, 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _withAlpha(color, 0.30)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _withAlpha(JournalColors.danger, 0.14),
            ),
            child: const Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              color: JournalColors.danger,
              size: 17,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: CupertinoIcons.minus,
          enabled: value > min,
          onTap: () => onChanged(value - step),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _StepButton(
          icon: CupertinoIcons.plus,
          enabled: value < max,
          onTap: () => onChanged(value + step),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: _withAlpha(JournalColors.bgBase, enabled ? 0.86 : 0.54),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: JournalColors.border),
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled ? JournalColors.textPrimary : JournalColors.textMuted,
        ),
      ),
    );
  }
}

class _DraftCard extends StatefulWidget {
  const _DraftCard({
    required this.draft,
    required this.onLoad,
    required this.onDelete,
  });

  final Map<String, dynamic> draft;
  final Future<void> Function(Map<String, dynamic>) onLoad;
  final void Function(int) onDelete;

  @override
  State<_DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<_DraftCard> {
  bool _confirming = false;

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final purpose = d['output_purpose'] as String? ?? 'general';
    final color = _purposeColor(purpose);
    final label = _purposeLabel(purpose);
    final date = _formatDate(d['created_at'] as String?);
    final sources = d['sources_summary'] as String? ?? '';

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d['title'] as String? ?? 'Draft',
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MiniPill(label: label, color: color),
                        if (date.isNotEmpty)
                          _MiniPill(
                            label: date,
                            color: JournalColors.textSecondary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (_confirming)
                Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      onPressed: () => widget.onDelete(d['id'] as int),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _withAlpha(JournalColors.danger, 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _withAlpha(JournalColors.danger, 0.30),
                          ),
                        ),
                        child: const Text(
                          'Delete',
                          style: TextStyle(
                            color: JournalColors.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      onPressed: () => setState(() => _confirming = false),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      onPressed: () => widget.onLoad(d),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _withAlpha(JournalColors.bgSurface, 0.76),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: JournalColors.border),
                        ),
                        child: const Text(
                          'Load',
                          style: TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      onPressed: () => setState(() => _confirming = true),
                      child: const Icon(
                        CupertinoIcons.trash,
                        color: JournalColors.textMuted,
                        size: 18,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (sources.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _withAlpha(JournalColors.bgSurface, 0.64),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: JournalColors.border),
              ),
              child: Text(
                sources,
                style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
