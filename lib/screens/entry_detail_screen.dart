// lib/screens/entry_detail_screen.dart
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class EntryDetailScreen extends StatefulWidget {
  const EntryDetailScreen({super.key, required this.entryId});
  final int entryId;

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  final _api  = ApiService();
  final _ctrl = TextEditingController();

  Map<String, dynamic>? _entry;
  bool _loading    = true;
  bool _editing    = false;
  bool _saving     = false;
  bool _reflecting = false;
  String? _reflection;
  String _selectedTone = 'therapist';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; });
    try {
      final data = await _api.getEntry(widget.entryId);
      setState(() {
        _entry = data;
        _ctrl.text = data['text'] as String? ?? '';
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; });
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; });
    try {
      await _api.updateEntry(widget.entryId, _ctrl.text.trim());
      setState(() { _editing = false; _saving = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved ✓'), backgroundColor: Color(0xFF22C55E)),
        );
      }
    } catch (_) {
      setState(() { _saving = false; });
    }
  }

  Future<void> _reflect() async {
    setState(() { _reflecting = true; _reflection = null; });
    try {
      final res = await _api.getReflection(widget.entryId, tone: _selectedTone);
      setState(() {
        _reflection  = res['reflection'] as String?;
        _reflecting  = false;
      });
    } catch (_) {
      setState(() { _reflecting = false; });
    }
  }

  Future<void> _delete() async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('This cannot be undone.'),
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
    if (confirm == true) {
      await _api.deleteEntry(widget.entryId);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = _entry != null
        ? _fmt(_entry!['entry_date'] ?? _entry!['ingested_at'] ?? '')
        : '';

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: JournalColors.bgBase.withOpacity(0.9),
        border: const Border(
          bottom: BorderSide(color: JournalColors.border, width: 0.5),
        ),
        middle: Text(date, style: const TextStyle(color: JournalColors.textPrimary)),
        trailing: _editing
            ? GestureDetector(
                onTap: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Done',
                    style: const TextStyle(color: JournalColors.accent)),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _editing = true),
                    child: const Icon(CupertinoIcons.pencil, color: JournalColors.accent),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: _delete,
                    child: const Icon(CupertinoIcons.trash, color: Colors.red),
                  ),
                ],
              ),
      ),
      child: _loading
          ? const Center(child: CupertinoActivityIndicator(color: JournalColors.accent))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Entry text ───────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: JournalColors.bgCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _editing
                              ? JournalColors.borderBright
                              : JournalColors.border,
                        ),
                      ),
                      child: _editing
                          ? CupertinoTextField(
                              controller: _ctrl,
                              maxLines: null,
                              style: const TextStyle(
                                  color: JournalColors.textPrimary, fontSize: 16, height: 1.7),
                              decoration: null,
                              textCapitalization: TextCapitalization.sentences,
                            )
                          : Text(
                              _ctrl.text,
                              style: const TextStyle(
                                  color: JournalColors.textPrimary, fontSize: 16, height: 1.7),
                            ),
                    ),

                    const SizedBox(height: 28),

                    // ── Reflection ───────────────────────────────────
                    const Text(
                      'AI Reflection',
                      style: TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),

                    AdaptiveButton(
                      style: AdaptiveButtonStyle.prominentGlass,
                      onPressed: _reflecting ? null : _reflect,
                      label: _reflecting ? 'Reflecting…' : 'Reflect on this entry',
                    ),

                    if (_reflection != null) ...[
                      const SizedBox(height: 16),
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
                  ],
                ),
              ),
            ),
    );
  }

  String _fmt(String raw) {
    try {
      return DateFormat('EEE, MMMM d, y').format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }
}
