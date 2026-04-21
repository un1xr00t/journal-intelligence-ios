// lib/screens/my_story_screen.dart
//
// My Story — AI-generated narrative drafts of your journey.
// Two tabs: Build (configure + generate) and Drafts (saved narratives).

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _purposes = [
  ('general',  'General'),
  ('therapy',  'For Therapist'),
  ('legal',    'For Legal'),
  ('custody',  'For Custody'),
  ('hr',       'For HR / Work'),
  ('support',  'Support Network'),
  ('personal', 'Personal Record'),
];

const _styles = [
  ('advocate', 'Advocate'),
  ('neutral',  'Neutral'),
  ('emotional','Emotional'),
  ('clinical', 'Clinical'),
];

const _purposeColors = {
  'legal':    Color(0xFF8B5CF6),
  'custody':  Color(0xFFEC4899),
  'therapy':  Color(0xFF10B981),
  'hr':       Color(0xFFF59E0B),
  'support':  Color(0xFF3B82F6),
  'personal': Color(0xFF9898B0),
  'general':  JournalColors.accent,
};

String _purposeLabel(String key) =>
    _purposes.firstWhere((p) => p.$1 == key, orElse: () => (key, key)).$2;

Color _purposeColor(String key) => _purposeColors[key] ?? JournalColors.accent;

String _parseError(dynamic e) {
  // Try DioException response data first
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail != null) return detail.toString();
    }
    if (data is String && data.isNotEmpty) return data;
    final status = e.response?.statusCode;
    if (status != null) return 'Server error ($status). Check your settings and try again.';
  }
  final str = e.toString();
  final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
  return match?.group(1) ?? 'Something went wrong.';
}

// ── Screen ────────────────────────────────────────────────────────────────────

class MyStoryScreen extends StatefulWidget {
  const MyStoryScreen({super.key});

  @override
  State<MyStoryScreen> createState() => _MyStoryScreenState();
}

class _MyStoryScreenState extends State<MyStoryScreen> {
  final _api = ApiService();

  // init data
  List<dynamic> _cases = [];
  bool _hasDetective  = false;
  bool _initLoading   = true;

  // build config
  final Set<dynamic> _selectedCases = {};
  bool   _includeJournal  = true;
  int    _journalCount    = 20;
  bool   _includeFairness = false;
  String _purpose         = 'general';
  String _style           = 'advocate';
  final _manualCtrl = TextEditingController();

  // generate state
  bool    _generating = false;
  String? _narrative;
  String? _genError;
  bool    _autoSaved  = false;

  // drafts
  int _tab = 0; // 0 = build, 1 = drafts
  List<dynamic> _drafts        = [];
  bool          _draftsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInit();
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInit() async {
    try {
      final r = await _api.myStoryGetCases();
      if (mounted) {
        setState(() {
          _cases       = r['cases'] as List? ?? [];
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
      if (mounted) setState(() { _drafts = d; _draftsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _draftsLoading = false);
    }
  }

  bool get _canGenerate =>
      _includeJournal || _selectedCases.isNotEmpty || _manualCtrl.text.trim().isNotEmpty;

  Future<void> _generate() async {
    if (!_canGenerate || _generating) return;
    setState(() { _generating = true; _genError = null; _narrative = null; _autoSaved = false; });

    try {
      final body = {
        'case_ids':            _selectedCases.toList(),
        'include_journal':     _includeJournal,
        'journal_entry_count': _journalCount,
        'manual_context':      _manualCtrl.text.trim(),
        'include_fairness':    _includeFairness,
        'output_purpose':      _purpose,
        'output_style':        _style,
      };
      final r = await _api.myStoryGenerate(body);
      final text = r['narrative'] as String? ?? '';

      if (!mounted) return;
      setState(() { _narrative = text; });

      // Auto-save
      try {
        final parts = <String>[];
        if (_includeJournal)       parts.add('$_journalCount journal entries');
        if (_selectedCases.isNotEmpty) parts.add('${_selectedCases.length} case(s)');
        if (_manualCtrl.text.trim().isNotEmpty) parts.add('manual context');

        await _api.myStorySaveDraft({
          'title':          'My Story — ${_purposeLabel(_purpose)}',
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
      // ignore: avoid_print
      print('[MyStory] generate error: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _loadDraft(Map<String, dynamic> draft) async {
    try {
      final full = await _api.myStoryGetDraft(draft['id'] as int);
      if (!mounted) return;
      setState(() {
        _narrative     = full['generated_text'] as String? ?? '';
        _purpose       = full['output_purpose']  as String? ?? 'general';
        _manualCtrl.text = full['manual_context'] as String? ?? '';
        _autoSaved     = true;
        _tab           = 0;
      });
    } catch (e) {
      if (mounted) _showError(_parseError(e));
    }
  }

  Future<void> _deleteDraft(int id) async {
    try {
      await _api.myStoryDeleteDraft(id);
      if (mounted) setState(() => _drafts.removeWhere((d) => d['id'] == id));
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
          CupertinoDialogAction(child: const Text('OK'), onPressed: () => Navigator.pop(context)),
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
          CupertinoDialogAction(isDefaultAction: true, child: const Text('OK'), onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('My Story'),
            backgroundColor: JournalColors.bgBase.withOpacity(0.92),
            border: const Border(bottom: BorderSide(color: JournalColors.border, width: 0.5)),
          ),

          // ── Tab switcher ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: _tab,
                onValueChanged: (v) { if (v != null) setState(() => _tab = v); },
                children: const {
                  0: Text('Build'),
                  1: Text('Drafts'),
                },
              ),
            ),
          ),

          if (_tab == 0) ..._buildTab(),
          if (_tab == 1) ..._draftsTab(),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  // ── Build tab ─────────────────────────────────────────────────────────────

  List<Widget> _buildTab() {
    if (_initLoading) {
      return [
        const SliverFillRemaining(
          child: Center(child: CupertinoActivityIndicator()),
        ),
      ];
    }

    return [
      // Subtitle
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(
            "Let AI help you explain what you've been going through \u2014 pulling from your journal, your cases, and anything you add here. Written in your corner.",
            style: const TextStyle(color: JournalColors.textMuted, fontSize: 13, height: 1.55),
          ),
        ),
      ),

      // Sources card
      SliverToBoxAdapter(child: _sectionLabel('Sources')),
      SliverToBoxAdapter(
        child: _Card(
          child: Column(
            children: [
              // Include journal toggle
              _ToggleRow(
                label: 'Include Journal',
                subtitle: '$_journalCount recent entries',
                value: _includeJournal,
                onChanged: (v) => setState(() => _includeJournal = v),
              ),

              // Journal count stepper (visible only when journal included)
              if (_includeJournal) ...[
                Container(height: 0.5, color: JournalColors.border, margin: const EdgeInsets.only(left: 16)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Text('Entry count', style: TextStyle(color: JournalColors.textPrimary, fontSize: 15)),
                      const Spacer(),
                      _Stepper(
                        value: _journalCount,
                        min: 5,
                        max: 50,
                        step: 5,
                        onChanged: (v) => setState(() => _journalCount = v),
                      ),
                    ],
                  ),
                ),
              ],

              // Cases (only if detective access and cases exist)
              if (_hasDetective && _cases.isNotEmpty) ...[
                Container(height: 0.5, color: JournalColors.border, margin: const EdgeInsets.only(left: 16)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Row(
                    children: [
                      const Text('Detective Cases', style: TextStyle(color: JournalColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                for (final c in _cases) _CaseRow(
                  label: c['title'] as String? ?? 'Case',
                  checked: _selectedCases.contains(c['id']),
                  onChanged: (v) => setState(() {
                    v ? _selectedCases.add(c['id']) : _selectedCases.remove(c['id']);
                  }),
                ),
              ],

              // Include fairness toggle
              Container(height: 0.5, color: JournalColors.border, margin: const EdgeInsets.only(left: 16)),
              _ToggleRow(
                label: 'Include Fairness Ledger',
                value: _includeFairness,
                onChanged: (v) => setState(() => _includeFairness = v),
                isLast: true,
              ),
            ],
          ),
        ),
      ),

      // Manual context
      SliverToBoxAdapter(child: _sectionLabel('Add Context')),
      SliverToBoxAdapter(
        child: _Card(
          child: CupertinoTextField(
            controller: _manualCtrl,
            placeholder: 'Add anything you want included — background, key dates, what you want the reader to understand…',
            placeholderStyle: const TextStyle(color: JournalColors.textMuted, fontSize: 14),
            style: const TextStyle(color: JournalColors.textPrimary, fontSize: 14, height: 1.55),
            padding: const EdgeInsets.all(14),
            maxLines: null,
            minLines: 4,
            decoration: null,
            onChanged: (_) => setState(() {}),
          ),
        ),
      ),

      // Purpose
      SliverToBoxAdapter(child: _sectionLabel('Purpose')),
      SliverToBoxAdapter(
        child: _Card(
          child: Column(
            children: List.generate(_purposes.length, (i) {
              final (key, label) = _purposes[i];
              final isLast = i == _purposes.length - 1;
              return _RadioRow(
                label: label,
                selected: _purpose == key,
                accentColor: _purposeColor(key),
                isLast: isLast,
                onTap: () => setState(() => _purpose = key),
              );
            }),
          ),
        ),
      ),

      // Style
      SliverToBoxAdapter(child: _sectionLabel('Writing Style')),
      SliverToBoxAdapter(
        child: _Card(
          child: Column(
            children: List.generate(_styles.length, (i) {
              final (key, label) = _styles[i];
              final isLast = i == _styles.length - 1;
              return _RadioRow(
                label: label,
                selected: _style == key,
                isLast: isLast,
                onTap: () => setState(() => _style = key),
              );
            }),
          ),
        ),
      ),

      // Error
      if (_genError != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4)),
              ),
              child: Text(_genError!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
            ),
          ),
        ),

      // Generate button
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: CupertinoButton(
            onPressed: (_canGenerate && !_generating) ? _generate : null,
            padding: EdgeInsets.zero,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: (_canGenerate && !_generating)
                    ? JournalColors.accent
                    : JournalColors.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (_canGenerate && !_generating)
                      ? Colors.transparent
                      : JournalColors.border,
                ),
              ),
              child: Center(
                child: _generating
                    ? const CupertinoActivityIndicator()
                    : Text(
                        '✦  Write My Story',
                        style: TextStyle(
                          color: (_canGenerate && !_generating)
                              ? CupertinoColors.black
                              : JournalColors.textMuted,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),

      // Narrative result
      if (_narrative != null) ...[
        SliverToBoxAdapter(child: _sectionLabel('Your Story')),
        SliverToBoxAdapter(
          child: _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Action bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: Row(
                    children: [
                      if (_autoSaved) ...[
                        const Icon(CupertinoIcons.checkmark_circle_fill, color: Color(0xFF22C55E), size: 13),
                        const SizedBox(width: 4),
                        const Text('Auto-saved', style: TextStyle(color: Color(0xFF22C55E), fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                      const Spacer(),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minSize: 0,
                        onPressed: _copyNarrative,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: JournalColors.bgBase,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: JournalColors.border),
                          ),
                          child: const Text('Copy', style: TextStyle(color: JournalColors.textSecondary, fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(height: 0.5, color: JournalColors.border),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _narrative!,
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 15,
                      height: 1.85,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ];
  }

  // ── Drafts tab ────────────────────────────────────────────────────────────

  List<Widget> _draftsTab() {
    if (_draftsLoading) {
      return [
        const SliverFillRemaining(
          child: Center(child: CupertinoActivityIndicator()),
        ),
      ];
    }

    if (_drafts.isEmpty) {
      return [
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('✦', style: TextStyle(fontSize: 32, color: JournalColors.accent)),
                const SizedBox(height: 14),
                const Text('No saved drafts yet', style: TextStyle(color: JournalColors.textSecondary, fontSize: 16)),
                const SizedBox(height: 6),
                const Text("Generate your story and it'll be saved here.", style: TextStyle(color: JournalColors.textMuted, fontSize: 13)),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _DraftCard(
              draft: _drafts[i] as Map<String, dynamic>,
              onLoad: _loadDraft,
              onDelete: (id) => _deleteDraft(id),
            ),
            childCount: _drafts.length,
          ),
        ),
      ),
    ];
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: JournalColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
          ),
        ),
      );
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: JournalColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: JournalColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: child,
        ),
      );
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isLast;

  const _ToggleRow({
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: JournalColors.textPrimary, fontSize: 15)),
                  if (subtitle != null)
                    Text(subtitle!, style: const TextStyle(color: JournalColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            CupertinoSwitch(
              value: value,
              activeColor: JournalColors.accent,
              onChanged: onChanged,
            ),
          ],
        ),
      );
}

class _CaseRow extends StatelessWidget {
  final String label;
  final bool checked;
  final ValueChanged<bool> onChanged;

  const _CaseRow({required this.label, required this.checked, required this.onChanged});

  @override
  Widget build(BuildContext context) => CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 0,
        onPressed: () => onChanged(!checked),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                checked ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                color: checked ? JournalColors.accent : JournalColors.textMuted,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: const TextStyle(color: JournalColors.textPrimary, fontSize: 15)),
              ),
            ],
          ),
        ),
      );
}

class _RadioRow extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accentColor;
  final bool isLast;
  final VoidCallback onTap;

  const _RadioRow({
    required this.label,
    required this.selected,
    this.accentColor = JournalColors.accent,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 0,
            onPressed: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    selected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                    color: selected ? accentColor : JournalColors.textMuted,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? JournalColors.textPrimary : JournalColors.textSecondary,
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isLast)
            Container(height: 0.5, color: JournalColors.border, margin: const EdgeInsets.only(left: 46)),
        ],
      );
}

class _Stepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepBtn(
            icon: CupertinoIcons.minus,
            enabled: value > min,
            onTap: () => onChanged(value - step),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(color: JournalColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          _StepBtn(
            icon: CupertinoIcons.plus,
            enabled: value < max,
            onTap: () => onChanged(value + step),
          ),
        ],
      );
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _StepBtn({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) => CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 0,
        onPressed: enabled ? onTap : null,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: JournalColors.bgBase,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: JournalColors.border),
          ),
          child: Icon(icon, size: 14, color: enabled ? JournalColors.textPrimary : JournalColors.textMuted),
        ),
      );
}

// ── Draft Card ────────────────────────────────────────────────────────────────

class _DraftCard extends StatefulWidget {
  final Map<String, dynamic> draft;
  final Future<void> Function(Map<String, dynamic>) onLoad;
  final void Function(int) onDelete;

  const _DraftCard({required this.draft, required this.onLoad, required this.onDelete});

  @override
  State<_DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<_DraftCard> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final purpose = d['output_purpose'] as String? ?? 'general';
    final color   = _purposeColor(purpose);
    final label   = _purposeLabel(purpose);
    final date    = (d['created_at'] as String? ?? '').replaceAll('T', ' ').substring(0, 10 < (d['created_at'] as String? ?? '').length ? 10 : (d['created_at'] as String? ?? '').length);
    final sources = d['sources_summary'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JournalColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Expanded(
                child: Text(
                  d['title'] as String? ?? 'Draft',
                  style: const TextStyle(color: JournalColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Action buttons
              if (_confirming) ...[
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  onPressed: () => widget.onDelete(d['id'] as int),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.5)),
                    ),
                    child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 6),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  onPressed: () => setState(() => _confirming = false),
                  child: const Text('Cancel', style: TextStyle(color: JournalColors.textMuted, fontSize: 12)),
                ),
              ] else ...[
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  onPressed: () => widget.onLoad(d),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: JournalColors.bgBase,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: JournalColors.border),
                    ),
                    child: const Text('Load', style: TextStyle(color: JournalColors.textSecondary, fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 6),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  onPressed: () => setState(() => _confirming = true),
                  child: const Icon(CupertinoIcons.xmark_circle, color: JournalColors.textMuted, size: 18),
                ),
              ],
            ],
          ),

          const SizedBox(height: 6),

          // Meta row
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                ),
              ),
              if (date.isNotEmpty)
                Text(date, style: const TextStyle(color: JournalColors.textMuted, fontSize: 11)),
              if (sources.isNotEmpty)
                Text(sources, style: const TextStyle(color: JournalColors.textMuted, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

// Needed for Color usage without direct Material import
class Colors {
  static const transparent = Color(0x00000000);
}