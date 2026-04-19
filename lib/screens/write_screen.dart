// lib/screens/write_screen.dart
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';


class WriteScreen extends StatefulWidget {
  const WriteScreen({super.key});

  @override
  State<WriteScreen> createState() => _WriteScreenState();
}

class _WriteScreenState extends State<WriteScreen> {
  final _api  = ApiService();
  final _ctrl = TextEditingController();

  bool _saving = false;
  bool _saved  = false;
  String? _error;



  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() { _saving = true; _error = null; _saved = false; });
    try {
      await _api.createEntry(text: _ctrl.text.trim());
      _ctrl.clear();
      if (mounted) {
        setState(() { _saving = false; _saved = true; });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _saved = false);
        });
      }
    } catch (e) {
      final msg = _parseError(e);
      if (mounted) setState(() { _error = msg; _saving = false; });
    }
  }

  String _parseError(dynamic e) {
    try {
      // DioException with a response body
      final str = e.toString();
      final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
      if (match != null) return match.group(1)!;
      if (str.contains('SocketException') || str.contains('Failed host lookup')) {
        return 'Cannot reach server. Check your network.';
      }
      if (str.contains('401')) return 'Session expired. Please log out and back in.';
      if (str.contains('422')) return 'Invalid entry format (422).';
      if (str.contains('500')) return 'Server error (500). Try again.';
      return 'Save failed: $str';
    } catch (_) {
      return 'Save failed. Unknown error.';
    }
  }



  void _clear() {
    _ctrl.clear();
    setState(() { _error = null; });
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
                GestureDetector(
                  onTap: (_saving || _ctrl.text.trim().isEmpty) ? null : _save,
                  child: Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _saved
                          ? const Color(0xFF22C55E)
                          : (_saving || _ctrl.text.trim().isEmpty)
                              ? JournalColors.bgCard
                              : JournalColors.accent,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _saved
                            ? const Color(0xFF22C55E)
                            : (_saving || _ctrl.text.trim().isEmpty)
                                ? JournalColors.border
                                : JournalColors.accent,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _saved ? '✓ Entry Saved' : (_saving ? 'Saving…' : 'Save Entry'),
                        style: TextStyle(
                          color: (_saving || _ctrl.text.trim().isEmpty) && !_saved
                              ? JournalColors.textMuted
                              : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13)),
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
