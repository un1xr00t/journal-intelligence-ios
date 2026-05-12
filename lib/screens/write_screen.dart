// lib/screens/write_screen.dart
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/launch_intent_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

const double _kPickedImageMaxDimension = 2000;

class WriteScreen extends StatefulWidget {
  const WriteScreen({super.key, this.initialText});

  final String? initialText;

  @override
  State<WriteScreen> createState() => _WriteScreenState();
}

class _WriteScreenState extends State<WriteScreen> {
  final _api = ApiService();
  final _ctrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _picker = ImagePicker();
  LaunchIntentProvider? _launchIntent;
  int _lastLaunchIntentVersion = 0;

  bool _saving = false;
  bool _saved = false;
  String? _error;

  // Pending images to attach after save
  final List<XFile> _pendingImages = [];

  int get _wordCount {
    return _ctrl.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .length;
  }

  bool get _hasReferenceUrl => _urlCtrl.text.trim().isNotEmpty;

  bool get _canSave => !_saving && _ctrl.text.trim().isNotEmpty;

  String get _memoryContextLabel {
    final parts = <String>[];
    if (_pendingImages.isNotEmpty) {
      parts.add(
          '${_pendingImages.length} photo${_pendingImages.length == 1 ? '' : 's'}');
    }
    if (_hasReferenceUrl) parts.add('1 link');
    return parts.isEmpty ? 'No context yet' : parts.join(' + ');
  }

  String get _urlDisplay {
    final raw = _urlCtrl.text.trim();
    if (raw.isEmpty) return '';
    final candidate = raw.contains('://') ? raw : 'https://$raw';
    final uri = Uri.tryParse(candidate);
    return uri?.host.isNotEmpty == true ? uri!.host : raw;
  }

  @override
  void initState() {
    super.initState();
    final initialText = widget.initialText?.trim();
    if (initialText != null && initialText.isNotEmpty) {
      _ctrl.text = initialText;
    }
    _focusNode.addListener(() => setState(() {}));
    _urlCtrl.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final launchIntent = context.read<LaunchIntentProvider>();
    if (_launchIntent == launchIntent) return;

    _launchIntent?.removeListener(_handleLaunchIntentChange);
    _launchIntent = launchIntent;
    _launchIntent?.addListener(_handleLaunchIntentChange);
    _handleLaunchIntentChange();
  }

  @override
  void dispose() {
    _launchIntent?.removeListener(_handleLaunchIntentChange);
    _ctrl.dispose();
    _urlCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleLaunchIntentChange() {
    final launchIntent = _launchIntent;
    if (launchIntent == null) return;

    final version = launchIntent.intentVersion;
    final routePath = launchIntent.routePath;
    if (version == _lastLaunchIntentVersion) return;
    if (routePath != '/write' && routePath != '/compose') return;

    _lastLaunchIntentVersion = version;
    final prefill = launchIntent.writePrefillText?.trim();
    if (prefill == null || prefill.isEmpty) return;

    final existing = _ctrl.text.trim();
    final nextText = existing.isEmpty
        ? prefill
        : existing.contains(prefill)
            ? _ctrl.text
            : '${_ctrl.text.trimRight()}\n\n$prefill';

    _ctrl.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );

    if (mounted) {
      setState(() {
        _saved = false;
        _error = null;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _pickImage() async {
    final source = await _showImageSourceSheet();
    if (source == null) return;
    try {
      if (source == ImageSource.gallery) {
        final picked = await _picker.pickMultiImage(
          imageQuality: 85,
          maxWidth: _kPickedImageMaxDimension,
          maxHeight: _kPickedImageMaxDimension,
        );
        if (picked.isNotEmpty && mounted) {
          setState(() => _pendingImages.addAll(picked));
        }
      } else {
        final picked = await _picker.pickImage(
          source: source,
          imageQuality: 85,
          maxWidth: _kPickedImageMaxDimension,
          maxHeight: _kPickedImageMaxDimension,
        );
        if (picked != null && mounted) {
          setState(() => _pendingImages.add(picked));
        }
      }
    } catch (_) {}
  }

  Future<ImageSource?> _showImageSourceSheet() async {
    return showCupertinoModalPopup<ImageSource>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Add Photo'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: const Text('Take Photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Text('Choose from Library'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _showUrlSheet() async {
    final result = await showCupertinoModalPopup<String>(
      context: context,
      builder: (_) => DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: _UrlContextSheet(initialUrl: _urlCtrl.text.trim()),
      ),
    );
    if (result == null || !mounted) return;
    _urlCtrl.text = result.trim();
  }

  void _removeImage(int index) {
    setState(() => _pendingImages.removeAt(index));
  }

  void _removeUrl() {
    _urlCtrl.clear();
  }

  Future<void> _save() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
      _saved = false;
    });
    try {
      for (final img in _pendingImages) {
        await _api.validateEntryAttachmentForUpload(
          filePath: img.path,
          filename: img.name,
        );
      }

      final result = await _api.createEntry(
        text: _ctrl.text.trim(),
        contextUrls: _hasReferenceUrl ? [_urlCtrl.text.trim()] : const [],
      );
      final entryId = result['entry_id'] as int?;

      // Upload any pending images
      if (entryId != null && _pendingImages.isNotEmpty) {
        for (final img in _pendingImages) {
          await _api.uploadEntryAttachment(
            entryId: entryId,
            filePath: img.path,
            filename: img.name,
          );
        }
      }

      _ctrl.clear();
      _urlCtrl.clear();
      if (mounted) {
        setState(() {
          _saving = false;
          _saved = true;
          _pendingImages.clear();
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _saved = false);
        });
      }
    } catch (e) {
      final msg = _parseError(e);
      if (mounted) {
        setState(() {
          _error = msg;
          _saving = false;
        });
      }
    }
  }

  String _parseError(dynamic e) {
    if (e is JournalUrlContextException) {
      return e.message;
    }
    if (e is EntryAttachmentUploadException) {
      return e.message;
    }
    try {
      // DioException with a response body
      final str = e.toString();
      final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
      if (match != null) return match.group(1)!;
      if (str.contains('SocketException') ||
          str.contains('Failed host lookup')) {
        return 'Cannot reach server. Check your network.';
      }
      if (str.contains('401')) {
        return 'Session expired. Please log out and back in.';
      }
      if (str.contains('413')) {
        return 'A photo is too large. Journal photos must be under 8 MB each.';
      }
      if (str.contains('422')) return 'Invalid entry format (422).';
      if (str.contains('500')) return 'Server error (500). Try again.';
      return 'Save failed: $str';
    } catch (_) {
      return 'Save failed. Unknown error.';
    }
  }

  void _clear() {
    _ctrl.clear();
    _urlCtrl.clear();
    setState(() {
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: Stack(
        children: [
          const Positioned.fill(child: _WriteBackdrop()),
          CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('Write'),
                backgroundColor: _withAlpha(JournalColors.bgBase, 0.9),
                border: const Border(
                  bottom: BorderSide(color: JournalColors.border, width: 0.5),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_focusNode.hasFocus)
                      GestureDetector(
                        onTap: () => _focusNode.unfocus(),
                        child: const Text(
                          'Done',
                          style: TextStyle(color: JournalColors.accent),
                        ),
                      )
                    else if (_ctrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: _clear,
                        child: const Text(
                          'Clear',
                          style: TextStyle(color: JournalColors.accent),
                        ),
                      ),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _WriteHero(
                      wordCount: _wordCount,
                      photoCount: _pendingImages.length,
                      isFocused: _focusNode.hasFocus,
                    ),
                    const SizedBox(height: 18),
                    GlassCard(
                      accentBorder:
                          _focusNode.hasFocus || _ctrl.text.isNotEmpty,
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
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 18, 20, 14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          _withAlpha(
                                              JournalColors.accent, 0.26),
                                          _withAlpha(JournalColors.info, 0.16),
                                        ],
                                      ),
                                      border: Border.all(
                                        color: JournalColors.borderBright,
                                      ),
                                    ),
                                    child: const Icon(
                                      CupertinoIcons.pencil_ellipsis_rectangle,
                                      color: JournalColors.textPrimary,
                                      size: 19,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'COMPOSING',
                                          style: TextStyle(
                                            color: JournalColors.textMuted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Write today\'s entry.',
                                          style: TextStyle(
                                            color: JournalColors.textPrimary,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            height: 1.25,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              decoration: BoxDecoration(
                                color: _withAlpha(
                                  JournalColors.bgSurface,
                                  0.72,
                                ),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: _focusNode.hasFocus
                                      ? JournalColors.borderBright
                                      : JournalColors.border,
                                ),
                              ),
                              child: CupertinoTextField(
                                controller: _ctrl,
                                focusNode: _focusNode,
                                placeholder:
                                    'What shifted today? What stuck with you? What deserves a sentence before it disappears?',
                                placeholderStyle: const TextStyle(
                                  color: JournalColors.textMuted,
                                  fontSize: 16,
                                  height: 1.5,
                                ),
                                style: const TextStyle(
                                  color: JournalColors.textPrimary,
                                  fontSize: 16,
                                  height: 1.75,
                                ),
                                maxLines: null,
                                minLines: 10,
                                decoration: null,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 14, 20, 18),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _focusNode.hasFocus
                                          ? 'Keep going. You can clean it up later if you want to.'
                                          : 'A short note is enough if that is all you have today.',
                                      style: const TextStyle(
                                        color: JournalColors.textSecondary,
                                        fontSize: 13,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  _InfoChip(
                                    icon: CupertinoIcons.text_alignleft,
                                    label: '$_wordCount words',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'MEMORY CONTEXT',
                                      style: TextStyle(
                                        color: JournalColors.textMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'Attach photos or a link without changing your words.',
                                      style: TextStyle(
                                        color: JournalColors.textPrimary,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _withAlpha(
                                    JournalColors.info,
                                    0.10,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: _withAlpha(
                                      JournalColors.info,
                                      0.24,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _memoryContextLabel,
                                  style: const TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (_pendingImages.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: _withAlpha(
                                  JournalColors.bgSurface,
                                  0.65,
                                ),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: JournalColors.border),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.photo_on_rectangle,
                                    color: JournalColors.textMuted,
                                    size: 20,
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Add context that should travel with this entry.',
                                      style: TextStyle(
                                        color: JournalColors.textSecondary,
                                        fontSize: 14,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            SizedBox(
                              height: 94,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _pendingImages.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (_, i) {
                                  return Stack(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          border: Border.all(
                                            color: JournalColors.borderBright,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: JournalColors.accentGlow,
                                              blurRadius: 14,
                                              offset: Offset(0, 8),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          child: Image.file(
                                            File(_pendingImages[i].path),
                                            width: 94,
                                            height: 94,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: GestureDetector(
                                          onTap: () => _removeImage(i),
                                          child: Container(
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              color: _withAlpha(
                                                JournalColors.bgBase,
                                                0.82,
                                              ),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color:
                                                    JournalColors.borderBright,
                                              ),
                                            ),
                                            child: const Icon(
                                              CupertinoIcons.xmark,
                                              size: 13,
                                              color: JournalColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          if (_hasReferenceUrl) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: _withAlpha(
                                  JournalColors.info,
                                  0.08,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _withAlpha(
                                    JournalColors.info,
                                    0.22,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    CupertinoIcons.link,
                                    color: JournalColors.textSecondary,
                                    size: 17,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _urlDisplay,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: JournalColors.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _saving ? null : _removeUrl,
                                    child: const Icon(
                                      CupertinoIcons.xmark_circle_fill,
                                      color: JournalColors.textMuted,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final compactActions = constraints.maxWidth < 380;
                              final photoButton = GestureDetector(
                                onTap: _saving ? null : _pickImage,
                                child: Container(
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: JournalColors.bgSurface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: JournalColors.border,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        CupertinoIcons.camera_fill,
                                        color: _saving
                                            ? JournalColors.textMuted
                                            : JournalColors.textPrimary,
                                        size: 19,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Add Photos',
                                        style: TextStyle(
                                          color: _saving
                                              ? JournalColors.textMuted
                                              : JournalColors.textPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                              final linkButton = GestureDetector(
                                onTap: _saving ? null : _showUrlSheet,
                                child: Container(
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: _hasReferenceUrl
                                        ? _withAlpha(JournalColors.info, 0.12)
                                        : JournalColors.bgSurface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: _hasReferenceUrl
                                          ? JournalColors.borderBright
                                          : JournalColors.border,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        CupertinoIcons.link,
                                        color: _saving
                                            ? JournalColors.textMuted
                                            : JournalColors.textPrimary,
                                        size: 19,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        _hasReferenceUrl
                                            ? 'Edit Link'
                                            : 'Add Link',
                                        style: TextStyle(
                                          color: _saving
                                              ? JournalColors.textMuted
                                              : JournalColors.textPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );

                              final saveButton = _SaveEntryButton(
                                enabled: _canSave,
                                saving: _saving,
                                saved: _saved,
                                onPressed: _save,
                              );

                              if (compactActions) {
                                return Column(
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: photoButton,
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: linkButton,
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: saveButton,
                                    ),
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: photoButton),
                                  const SizedBox(width: 12),
                                  Expanded(child: linkButton),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: saveButton,
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    if (_saved || _error != null) ...[
                      const SizedBox(height: 16),
                      _StatusBanner(
                        icon: _saved
                            ? CupertinoIcons.check_mark_circled_solid
                            : CupertinoIcons.exclamationmark_triangle_fill,
                        title: _saved
                            ? 'Saved to your journal'
                            : 'Couldn\'t save yet',
                        message: _saved
                            ? 'Your words and attachments are safely tucked into the timeline.'
                            : _error!,
                        color: _saved
                            ? JournalColors.success
                            : JournalColors.danger,
                      ),
                    ],
                    const SizedBox(height: 40),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WriteBackdrop extends StatelessWidget {
  const _WriteBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    JournalColors.bgBase,
                    _withAlpha(JournalColors.bgCardAlt, 0.65),
                    JournalColors.bgBase,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 110,
            left: -50,
            child: _GlowOrb(
              size: 200,
              color: _withAlpha(JournalColors.accent, 0.18),
            ),
          ),
          Positioned(
            top: 250,
            right: -36,
            child: _GlowOrb(
              size: 150,
              color: _withAlpha(JournalColors.info, 0.14),
            ),
          ),
          Positioned(
            bottom: 140,
            left: 24,
            child: _GlowOrb(
              size: 120,
              color: _withAlpha(JournalColors.accent2, 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _UrlContextSheet extends StatefulWidget {
  const _UrlContextSheet({required this.initialUrl});

  final String initialUrl;

  @override
  State<_UrlContextSheet> createState() => _UrlContextSheetState();
}

class _UrlContextSheetState extends State<_UrlContextSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl);
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final canSave = _controller.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: JournalColors.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: JournalColors.borderBright, width: 0.5),
          ),
        ),
        padding: EdgeInsets.fromLTRB(20, 18, 20, safeBottom + 18),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _withAlpha(JournalColors.info, 0.12),
                      border: Border.all(
                        color: _withAlpha(JournalColors.info, 0.26),
                      ),
                    ),
                    child: const Icon(
                      CupertinoIcons.link,
                      color: JournalColors.textPrimary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ADD LINK',
                          style: TextStyle(
                            color: JournalColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Include a URL as entry context.',
                          style: TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CupertinoTextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                placeholder: 'https://example.com',
                placeholderStyle: const TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 15,
                ),
                style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 15,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.bgSurface, 0.78),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: JournalColors.border),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      color: JournalColors.bgSurface,
                      borderRadius: BorderRadius.circular(16),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: JournalColors.textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      color: canSave
                          ? JournalColors.accent
                          : JournalColors.bgCardAlt,
                      borderRadius: BorderRadius.circular(16),
                      onPressed: canSave
                          ? () => Navigator.pop(
                                context,
                                _controller.text.trim(),
                              )
                          : null,
                      child: Text(
                        widget.initialUrl.trim().isEmpty ? 'Add' : 'Update',
                        style: TextStyle(
                          color: canSave
                              ? JournalColors.textPrimary
                              : JournalColors.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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

class _WriteHero extends StatelessWidget {
  const _WriteHero({
    required this.wordCount,
    required this.photoCount,
    required this.isFocused,
  });

  final int wordCount;
  final int photoCount;
  final bool isFocused;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: JournalColors.borderBright),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _withAlpha(JournalColors.bgCard, 0.96),
            _withAlpha(JournalColors.bgCardAlt, 0.92),
            _withAlpha(JournalColors.bgSurface, 0.88),
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: JournalColors.accentGlow,
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      _withAlpha(JournalColors.accent, 0.28),
                      _withAlpha(JournalColors.accent2, 0.18),
                    ],
                  ),
                  border: Border.all(color: JournalColors.borderBright),
                ),
                child: const Icon(
                  CupertinoIcons.square_pencil,
                  color: JournalColors.textPrimary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'WRITER\'S ROOM',
                      style: TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isFocused
                          ? 'Add what happened while it is still fresh.'
                          : 'Start a new entry when you are ready.',
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Use this space for notes, context, or anything you want to keep.',
            style: TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: 'Word Count',
                  value: '$wordCount',
                  color: JournalColors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroStat(
                  label: 'Photos',
                  value: '$photoCount',
                  color: JournalColors.info,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _withAlpha(color, 0.08),
        border: Border.all(color: _withAlpha(color, 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: _withAlpha(color, 0.9),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.75),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: JournalColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: JournalColors.textSecondary, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveEntryButton extends StatelessWidget {
  const _SaveEntryButton({
    required this.enabled,
    required this.saving,
    required this.saved,
    required this.onPressed,
  });

  final bool enabled;
  final bool saving;
  final bool saved;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = saved
        ? JournalColors.success
        : enabled
            ? JournalColors.accent
            : JournalColors.bgCardAlt;
    final borderColor = saved
        ? JournalColors.success
        : enabled
            ? JournalColors.borderBright
            : JournalColors.border;
    final labelColor =
        enabled || saved ? JournalColors.textPrimary : JournalColors.textMuted;
    final label = saving
        ? 'Saving...'
        : saved
            ? 'Entry Saved'
            : 'Save Entry';

    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 54,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: enabled
              ? const [
                  BoxShadow(
                    color: JournalColors.accentGlow,
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: saving
              ? const CupertinoActivityIndicator(
                  color: JournalColors.textPrimary,
                )
              : Text(
                  label,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _withAlpha(color, 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _withAlpha(color, 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
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
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
