// lib/screens/write_screen.dart
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

class WriteScreen extends StatefulWidget {
  const WriteScreen({super.key});

  @override
  State<WriteScreen> createState() => _WriteScreenState();
}

class _WriteScreenState extends State<WriteScreen> {
  final _api  = ApiService();
  final _ctrl = TextEditingController();

  String _selectedTone = 'therapist';
  bool _saving     = false;
  bool _reflecting = false;
  String? _savedEntryId;
  String? _reflection;
  String? _error;

  static final _tones = [
    ('therapist',   'Therapist',   CupertinoIcons.heart),
    ('detective',   'Detective',   CupertinoIcons.search),
    ('coach',       'Coach',       CupertinoIcons.flame),
    ('friend',      'Friend',      CupertinoIcons.person_2),
    ('philosopher', 'Philosopher', CupertinoIcons.book),
    ('chaos_agent', 'Chaos Agent', CupertinoIcons.burst),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() { _saving = true; _error = null; });
    try {
      final res = await _api.createEntry(text: _ctrl.text.trim());
      setState(() {
        _savedEntryId = res['entry_id']?.toString() ?? res['id']?.toString();
        _saving = false;
      });
      _showSavedBanner();
    } catch (e) {
      setState(() { _error = 'Save failed. Check your connection.'; _saving = false; });
    }
  }

  Future<void> _reflect() async {
    if (_savedEntryId == null && _ctrl.text.trim().isEmpty) return;
    // Auto-save first if not saved
    if (_savedEntryId == null) await _save();
    if (_savedEntryId == null) return;

    setState(() { _reflecting = true; _reflection = null; });
    try {
      final res = await _api.getReflection(
        int.parse(_savedEntryId!),
        tone: _selectedTone,
      );
      setState(() {
        _reflection = res['reflection'] as String?;
        _reflecting = false;
      });
    } catch (e) {
      setState(() { _reflection = null; _reflecting = false;
        _error = 'Reflection failed.'; });
    }
  }

  void _clear() {
    _ctrl.clear();
    setState(() {
      _savedEntryId = null;
      _reflection   = null;
      _error        = null;
    });
  }

  void _showSavedBanner() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Entry saved ✓'),
        backgroundColor: Color(0xFF22C55E),
        behavior: SnackBarBehavior.floating,
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
            largeTitle: const Text('Write'),
            backgroundColor: JournalColors.bgBase.withOpacity(0.9),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
            trailing: _ctrl.text.isNotEmpty
                ? GestureDetector(
                    onTap: _clear,
                    child: const Text('Clear',
                        style: TextStyle(color: JournalColors.accent)),
                  )
                : null,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Text editor ───────────────────────────────────────
                Container(
                  constraints: const BoxConstraints(minHeight: 220),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: JournalColors.bgCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: JournalColors.border),
                  ),
                  child: CupertinoTextField(
                    controller: _ctrl,
                    placeholder: 'What\'s on your mind today?',
                    placeholderStyle: const TextStyle(
                        color: JournalColors.textMuted, fontSize: 16),
                    style: const TextStyle(
                        color: JournalColors.textPrimary, fontSize: 16, height: 1.7),
                    maxLines: null,
                    minLines: 8,
                    decoration: null,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                  ),
                ),

                const SizedBox(height: 8),

                // ── Word count ────────────────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${_ctrl.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length} words',
                    style: const TextStyle(
                        color: JournalColors.textMuted, fontSize: 12),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Save button ───────────────────────────────────────
                AdaptiveButton(
                  style: AdaptiveButtonStyle.prominentGlass,
                  onPressed: (_saving || _ctrl.text.trim().isEmpty) ? null : _save,
                  label: _saving ? 'Saving…' : (_savedEntryId != null ? 'Saved ✓' : 'Save Entry'),
                ),

                const SizedBox(height: 28),

                // ── AI Reflection ─────────────────────────────────────
                const SectionHeader(title: 'AI Reflection'),
                const SizedBox(height: 12),

                // Tone picker
                AdaptiveSegmentedControl(
                  labels: _tones.map((t) => t.$2).toList(),
                  selectedIndex: _tones.indexWhere((t) => t.$1 == _selectedTone),
                  onValueChanged: (i) =>
                      setState(() => _selectedTone = _tones[i].$1),
                ),

                const SizedBox(height: 16),

                AdaptiveButton(
                  style: AdaptiveButtonStyle.prominentGlass,
                  onPressed: _reflecting ? null : _reflect,
                  label: _reflecting ? 'Reflecting…' : 'Get Reflection',
                ),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],

                if (_reflection != null) ...[
                  const SizedBox(height: 20),
                  GlassCard(
                    accentBorder: true,
                    child: Text(
                      _reflection!,
                      style: const TextStyle(
                          color: JournalColors.textPrimary, fontSize: 15, height: 1.65),
                    ),
                  ),
                ],

                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
