// lib/screens/entry_detail_screen.dart
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';

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
  final _api = ApiService();
  final _ctrl = TextEditingController();

  Map<String, dynamic>? _entry;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  bool _reflecting = false;
  bool _attachmentsLoading = false;
  String? _reflection;
  final String _selectedTone = 'therapist';
  List<Map<String, dynamic>> _attachments = [];

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
    setState(() {
      _loading = true;
    });
    try {
      final data = await _api.getEntry(widget.entryId);
      setState(() {
        _entry = data;
        _ctrl.text = (data['normalized_text'] as String? ??
                data['text'] as String? ??
                '')
            .trim();
        _loading = false;
      });
      _loadAttachments();
    } catch (e) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadAttachments() async {
    setState(() => _attachmentsLoading = true);
    try {
      final attachments = await _api.getEntryAttachments(widget.entryId);
      final images = attachments
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where(
            (item) =>
                item['media_type']?.toString().startsWith('image/') ?? false,
          )
          .toList();
      if (mounted) {
        setState(() {
          _attachments = images;
          _attachmentsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _attachmentsLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });
    try {
      await _api.updateEntry(widget.entryId, _ctrl.text.trim());
      setState(() {
        _editing = false;
        _saving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Saved ✓'), backgroundColor: Color(0xFF22C55E)),
        );
      }
    } catch (_) {
      setState(() {
        _saving = false;
      });
    }
  }

  Future<void> _reflect() async {
    setState(() {
      _reflecting = true;
      _reflection = null;
    });
    try {
      final res = await _api.getReflection(widget.entryId, tone: _selectedTone);
      setState(() {
        _reflection = res['reflection'] as String?;
        _reflecting = false;
      });
    } catch (_) {
      setState(() {
        _reflecting = false;
      });
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

  String _attachmentImagePath(String attachmentId) {
    return '/api/entry-attachments/$attachmentId/file';
  }

  Future<void> _openImageLightbox(String path) {
    return Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => _EntryImageLightbox(path: path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final date = _entry != null
        ? _fmt(_entry!['entry_date'] ?? _entry!['ingested_at'] ?? '')
        : '';

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: JournalColors.bgBase.withValues(alpha: 0.9),
        border: const Border(
          bottom: BorderSide(color: JournalColors.border, width: 0.5),
        ),
        middle: Text(date,
            style: const TextStyle(color: JournalColors.textPrimary)),
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
                    child: const Icon(CupertinoIcons.pencil,
                        color: JournalColors.accent),
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
          ? const Center(
              child: CupertinoActivityIndicator(color: JournalColors.accent))
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
                                  color: JournalColors.textPrimary,
                                  fontSize: 16,
                                  height: 1.7),
                              decoration: null,
                              textCapitalization: TextCapitalization.sentences,
                            )
                          : Text(
                              _ctrl.text,
                              style: const TextStyle(
                                  color: JournalColors.textPrimary,
                                  fontSize: 16,
                                  height: 1.7),
                            ),
                    ),

                    if (_attachmentsLoading) ...[
                      const SizedBox(height: 18),
                      const Center(
                        child: CupertinoActivityIndicator(
                          color: JournalColors.accent,
                        ),
                      ),
                    ] else if (_attachments.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'Photos',
                        style: TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 120,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _attachments.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final attachment = _attachments[index];
                            final path = _attachmentImagePath(
                              attachment['id'].toString(),
                            );
                            return GestureDetector(
                              onTap: () => _openImageLightbox(path),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: SizedBox(
                                  width: 120,
                                  height: 120,
                                  child: _EntryAuthImage(path: path),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],

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
                      label:
                          _reflecting ? 'Reflecting…' : 'Reflect on this entry',
                    ),

                    if (_reflection != null) ...[
                      const SizedBox(height: 16),
                      GlassCard(
                        accentBorder: true,
                        child: Text(
                          _reflection!,
                          style: const TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 15,
                              height: 1.65),
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

class _EntryAuthImage extends StatefulWidget {
  const _EntryAuthImage({required this.path});

  final String path;

  @override
  State<_EntryAuthImage> createState() => _EntryAuthImageState();
}

class _EntryAuthImageState extends State<_EntryAuthImage> {
  final _api = ApiService();
  List<int>? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final bytes = await _api.fetchImageBytes(widget.path);
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CupertinoActivityIndicator(color: JournalColors.accent),
      );
    }
    if (_bytes == null) {
      return Container(
        color: JournalColors.bgSurface,
        alignment: Alignment.center,
        child: const Icon(
          CupertinoIcons.photo,
          color: JournalColors.textMuted,
          size: 24,
        ),
      );
    }
    return Image.memory(
      Uint8List.fromList(_bytes!),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: JournalColors.bgSurface,
        alignment: Alignment.center,
        child: const Icon(
          CupertinoIcons.photo,
          color: JournalColors.textMuted,
          size: 24,
        ),
      ),
    );
  }
}

class _EntryImageLightbox extends StatelessWidget {
  const _EntryImageLightbox({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.92),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: _EntryAuthImage(path: path),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 20,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: const Icon(
                    CupertinoIcons.xmark,
                    color: JournalColors.textPrimary,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
