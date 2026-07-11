// lib/screens/write_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../providers/launch_intent_provider.dart';
import '../services/api_service.dart';
import '../services/follow_up_tasks_service.dart';
import '../services/notification_nudge_service.dart';
import '../services/sage_inbox_service.dart';
import '../services/voice_entry_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

const double _kPickedImageMaxDimension = 2000;
const String _kEntryDraftTextKeyPrefix = 'write_entry_draft_text';
const String _kEntryDraftUrlKeyPrefix = 'write_entry_draft_url';

class WriteScreen extends StatefulWidget {
  const WriteScreen({super.key, this.initialText});

  final String? initialText;

  @override
  State<WriteScreen> createState() => _WriteScreenState();
}

class _WriteScreenState extends State<WriteScreen> {
  final _api = ApiService();
  final _sageInbox = SageInboxService();
  final _notifications = NotificationNudgeService();
  final _ctrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _picker = ImagePicker();
  LaunchIntentProvider? _launchIntent;
  int _lastLaunchIntentVersion = 0;
  bool _draftLoadStarted = false;
  bool _hasUserEditedDraft = false;
  bool _suppressDraftPersistence = false;

  bool _saving = false;
  bool _saved = false;
  bool _processingPhotos = false;
  bool _photosReady = false;
  int _processingPhotoCount = 0;
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
    _ctrl.addListener(_handleEntryTextChanged);
    _urlCtrl.addListener(_handleUrlChanged);
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

    if (!_draftLoadStarted) {
      _draftLoadStarted = true;
      unawaited(_loadPersistedDraft());
    }
  }

  @override
  void dispose() {
    _launchIntent?.removeListener(_handleLaunchIntentChange);
    _ctrl.removeListener(_handleEntryTextChanged);
    _urlCtrl.removeListener(_handleUrlChanged);
    _ctrl.dispose();
    _urlCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _draftKeySuffix {
    final username =
        context.read<AuthProvider>().user?['username']?.toString().trim();
    return username == null || username.isEmpty ? 'anonymous' : username;
  }

  String get _draftTextKey => '${_kEntryDraftTextKeyPrefix}_$_draftKeySuffix';

  String get _draftUrlKey => '${_kEntryDraftUrlKeyPrefix}_$_draftKeySuffix';

  Future<void> _loadPersistedDraft() async {
    if (widget.initialText?.trim().isNotEmpty == true) {
      await _persistDraft();
      return;
    }

    final textKey = _draftTextKey;
    final urlKey = _draftUrlKey;
    final prefs = await SharedPreferences.getInstance();
    final draftText = prefs.getString(textKey)?.trimRight() ?? '';
    final draftUrl = prefs.getString(urlKey)?.trim() ?? '';
    if (!mounted || _hasUserEditedDraft) return;
    if (draftText.isEmpty && draftUrl.isEmpty) return;

    _suppressDraftPersistence = true;
    try {
      _ctrl.text = draftText;
      _urlCtrl.text = draftUrl;
    } finally {
      _suppressDraftPersistence = false;
    }

    setState(() {
      _saved = false;
      _error = null;
    });
  }

  Future<void> _persistDraft() async {
    if (_suppressDraftPersistence) return;
    final textKey = _draftTextKey;
    final urlKey = _draftUrlKey;
    final prefs = await SharedPreferences.getInstance();
    final text = _ctrl.text.trimRight();
    final url = _urlCtrl.text.trim();

    if (text.isEmpty && url.isEmpty) {
      await _clearPersistedDraft();
      return;
    }

    await prefs.setString(textKey, text);
    if (url.isEmpty) {
      await prefs.remove(urlKey);
    } else {
      await prefs.setString(urlKey, url);
    }
  }

  Future<void> _clearPersistedDraft() async {
    final textKey = _draftTextKey;
    final urlKey = _draftUrlKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(textKey);
    await prefs.remove(urlKey);
  }

  void _handleEntryTextChanged() {
    if (!_suppressDraftPersistence) {
      _hasUserEditedDraft = true;
      unawaited(_persistDraft());
    }
    if (mounted) setState(() {});
  }

  void _handleUrlChanged() {
    if (!_suppressDraftPersistence) {
      _hasUserEditedDraft = true;
      unawaited(_persistDraft());
    }
    if (mounted) setState(() {});
  }

  void _handleLaunchIntentChange() {
    final launchIntent = _launchIntent;
    if (launchIntent == null) return;

    final version = launchIntent.intentVersion;
    final routePath = launchIntent.routePath;
    if (version == _lastLaunchIntentVersion) return;
    if (routePath != '/write' && routePath != '/compose') return;

    _lastLaunchIntentVersion = version;
    // One-shot consume: a recreated WriteScreen state (tab switch, shell
    // rebuild) gets null here once the prefill has been applied, instead of
    // re-reading the stale route and re-injecting the same prompt.
    final prefill = launchIntent.takeWritePrefill();
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
    unawaited(_persistDraft());

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

  Future<void> _showVoiceReflectionSheet() async {
    _focusNode.unfocus();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => const DefaultTextStyle(
        style: TextStyle(decoration: TextDecoration.none),
        child: _VoiceReflectionSheet(),
      ),
    );
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
      _processingPhotos = false;
      _photosReady = false;
      _processingPhotoCount = 0;
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
      unawaited(_createAdaptiveInboxCheckIn(
        entryText: _ctrl.text.trim(),
        entryId: entryId,
      ));
      final photoCount = _pendingImages.length;

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

      await _clearPersistedDraft();
      _suppressDraftPersistence = true;
      try {
        _ctrl.clear();
        _urlCtrl.clear();
      } finally {
        _suppressDraftPersistence = false;
      }
      if (mounted) {
        setState(() {
          _saving = false;
          _saved = photoCount == 0;
          _processingPhotos = entryId != null && photoCount > 0;
          _processingPhotoCount = photoCount;
          _pendingImages.clear();
        });
        if (entryId != null && photoCount > 0) {
          unawaited(_watchEntryAttachmentProcessing(entryId));
        } else {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _saved = false);
          });
        }
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

  Future<void> _createAdaptiveInboxCheckIn({
    required String entryText,
    required int? entryId,
  }) async {
    try {
      final snapshot = await _sageInbox.createAdaptiveJournalCheckIn(
        entryText: entryText,
        entryId: entryId,
      );
      if (snapshot != null) {
        await _notifications.notifyNewSageInboxMessages(snapshot.messages);
      }
    } catch (_) {}
  }

  Future<void> _watchEntryAttachmentProcessing(int entryId) async {
    for (var attempt = 0; attempt < 100; attempt += 1) {
      try {
        final status = await _api.getEntryAttachmentProcessingStatus(entryId);
        final pendingCount = (status['pending_count'] as num?)?.toInt() ?? 0;
        final processing = status['processing'] == true || pendingCount > 0;
        if (!mounted) return;
        if (!processing) {
          setState(() {
            _processingPhotos = false;
            _photosReady = true;
            _saved = true;
            _processingPhotoCount = 0;
          });
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) {
              setState(() {
                _saved = false;
                _photosReady = false;
              });
            }
          });
          return;
        }
        setState(() => _processingPhotoCount = pendingCount);
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 3));
    }
    if (!mounted) return;
    setState(() {
      _processingPhotos = false;
      _saved = true;
      _photosReady = false;
      _processingPhotoCount = 0;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _saved = false);
    });
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
      if (str.contains('Connection reset by peer')) {
        return 'The upload connection was interrupted. Check the timeline before retrying; some photos may have saved already.';
      }
      if (str.toLowerCase().contains('receive timeout') ||
          str.toLowerCase().contains('send timeout')) {
        return 'Uploading photos took too long. Try again on Wi-Fi or with fewer photos at once.';
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

  Future<void> _clear() async {
    await _clearPersistedDraft();
    if (!mounted) return;
    _suppressDraftPersistence = true;
    try {
      _ctrl.clear();
      _urlCtrl.clear();
    } finally {
      _suppressDraftPersistence = false;
    }
    _hasUserEditedDraft = false;
    setState(() {
      _error = null;
      _saved = false;
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
                              final voiceButton = GestureDetector(
                                onTap:
                                    _saving ? null : _showVoiceReflectionSheet,
                                child: Container(
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: _withAlpha(
                                      JournalColors.accent,
                                      0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: JournalColors.borderBright,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        CupertinoIcons.mic_fill,
                                        color: _saving
                                            ? JournalColors.textMuted
                                            : JournalColors.textPrimary,
                                        size: 19,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Voice Session',
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
                                      child: voiceButton,
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
                                  Expanded(child: voiceButton),
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
                    if (_saved || _processingPhotos || _error != null) ...[
                      const SizedBox(height: 16),
                      _StatusBanner(
                        icon: _processingPhotos
                            ? CupertinoIcons.clock_fill
                            : _saved
                                ? CupertinoIcons.check_mark_circled_solid
                                : CupertinoIcons.exclamationmark_triangle_fill,
                        title: _processingPhotos
                            ? 'Finalizing photos'
                            : _saved
                                ? 'Saved to your journal'
                                : 'Couldn\'t save yet',
                        message: _processingPhotos
                            ? _processingPhotoCount > 0
                                ? 'Your entry is saved. $_processingPhotoCount photo ${_processingPhotoCount == 1 ? 'summary is' : 'summaries are'} still processing, so it will appear in Timeline when ready.'
                                : 'Your entry is saved. Photo summaries are still processing, so it will appear in Timeline when ready.'
                            : _saved
                                ? _photosReady
                                    ? 'Photo summaries are done. The entry is ready in Timeline.'
                                    : 'Your words and attachments are safely tucked into the timeline.'
                                : _error!,
                        color: _processingPhotos
                            ? JournalColors.info
                            : _saved
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

class _VoiceReflectionSheet extends StatefulWidget {
  const _VoiceReflectionSheet();

  @override
  State<_VoiceReflectionSheet> createState() => _VoiceReflectionSheetState();
}

class _VoiceReflectionSheetState extends State<_VoiceReflectionSheet> {
  final _api = ApiService();
  final _followUps = FollowUpTaskService();
  final _sageInbox = SageInboxService();
  final _notifications = NotificationNudgeService();
  final _voice = VoiceEntryService();
  final _transcriptCtrl = TextEditingController();
  final _transcriptFocus = FocusNode();

  StreamSubscription<VoiceEntryEvent>? _voiceSub;
  VoiceReflectionAnalysis? _analysis;
  String? _fallbackReflection;
  String? _error;
  String? _savedMessage;
  bool _listening = false;
  bool _analyzing = false;
  bool _saving = false;
  Set<int> _acceptedFollowUps = {};
  Set<int> _acceptedTasks = {};

  bool get _hasTranscript => _transcriptCtrl.text.trim().isNotEmpty;
  bool get _canAnalyze => _hasTranscript && !_listening && !_analyzing;
  bool get _canSave => _hasTranscript && !_saving && !_listening;

  @override
  void initState() {
    super.initState();
    _transcriptCtrl.addListener(() => setState(() {}));
    _transcriptFocus.addListener(() => setState(() {}));
    _voiceSub = _voice.events.listen(_handleVoiceEvent);
  }

  @override
  void dispose() {
    if (_listening) {
      unawaited(_voice.cancelListening());
    }
    _voiceSub?.cancel();
    _transcriptFocus.dispose();
    _transcriptCtrl.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    _transcriptFocus.unfocus();
    FocusScope.of(context).unfocus();
  }

  void _handleVoiceEvent(VoiceEntryEvent event) {
    if (!mounted) return;
    setState(() {
      _listening = event.isListening;
      final error = event.error?.trim();
      if (error != null && error.isNotEmpty) {
        _error = error;
      }
      final transcript = event.transcript?.trim();
      if (transcript != null && transcript.isNotEmpty) {
        _transcriptCtrl.value = TextEditingValue(
          text: transcript,
          selection: TextSelection.collapsed(offset: transcript.length),
        );
      }
    });
  }

  Future<void> _startListening() async {
    _dismissKeyboard();
    setState(() {
      _error = null;
      _savedMessage = null;
      _fallbackReflection = null;
    });
    try {
      await _voice.startListening();
      if (mounted) setState(() => _listening = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _listening = false;
          _error = _parseVoiceError(e);
        });
      }
    }
  }

  Future<void> _stopListening() async {
    try {
      await _voice.stopListening();
      if (mounted) setState(() => _listening = false);
    } catch (e) {
      if (mounted) setState(() => _error = _parseVoiceError(e));
    }
  }

  Future<void> _clear() async {
    await _voice.cancelListening();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _analysis = null;
      _fallbackReflection = null;
      _error = null;
      _savedMessage = null;
      _acceptedFollowUps = {};
      _acceptedTasks = {};
      _transcriptCtrl.clear();
    });
  }

  Future<void> _analyze() async {
    _dismissKeyboard();
    final transcript = _transcriptCtrl.text.trim();
    if (transcript.isEmpty) return;
    setState(() {
      _analyzing = true;
      _error = null;
      _fallbackReflection = null;
      _savedMessage = null;
    });
    try {
      final analysis = await _api.analyzeVoiceReflection(
        transcript: transcript,
      );
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _acceptedFollowUps =
            Set<int>.from(List.generate(analysis.followUps.length, (i) => i));
        _acceptedTasks =
            Set<int>.from(List.generate(analysis.tasks.length, (i) => i));
        _analyzing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analysis = null;
        _analyzing = false;
        _error = _parseError(e);
      });
    }
  }

  Future<void> _saveSession() async {
    _dismissKeyboard();
    final transcript = _transcriptCtrl.text.trim();
    if (transcript.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
      _savedMessage = null;
    });

    var analysis = _analysis;
    try {
      analysis ??= await _api.analyzeVoiceReflection(transcript: transcript);
      final result =
          await _api.createEntry(text: _entryText(transcript, analysis));
      final entryId = (result['entry_id'] as num?)?.toInt();
      await _createAdaptiveInboxCheckIn(
        entryText: transcript,
        entryId: entryId,
      );
      if (entryId != null && _analysis == null) {
        try {
          final reflection =
              await _api.getReflection(entryId, tone: 'therapist');
          _fallbackReflection = reflection['reflection']?.toString();
        } catch (_) {}
      }
      await _saveAcceptedFollowUps(analysis);
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _saving = false;
        _savedMessage = 'Voice reflection saved with accepted follow-ups.';
      });
    } catch (e) {
      try {
        final result = await _api.createEntry(text: transcript);
        final entryId = (result['entry_id'] as num?)?.toInt();
        await _createAdaptiveInboxCheckIn(
          entryText: transcript,
          entryId: entryId,
        );
        if (entryId != null) {
          final reflection =
              await _api.getReflection(entryId, tone: 'therapist');
          _fallbackReflection = reflection['reflection']?.toString();
        }
        if (!mounted) return;
        setState(() {
          _saving = false;
          _savedMessage =
              'Voice entry saved. Structured analysis needs the backend route deployed.';
          _error = null;
        });
      } catch (fallbackError) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = _parseError(fallbackError);
        });
      }
    }
  }

  Future<void> _createAdaptiveInboxCheckIn({
    required String entryText,
    required int? entryId,
  }) async {
    final inboxSnapshot = await _sageInbox.createAdaptiveJournalCheckIn(
      entryText: entryText,
      entryId: entryId,
    );
    if (inboxSnapshot == null) return;
    unawaited(
      _notifications.notifyNewSageInboxMessages(inboxSnapshot.messages),
    );
  }

  Future<void> _saveAcceptedFollowUps(VoiceReflectionAnalysis analysis) async {
    final selectedActions = <VoiceReflectionAction>[
      for (final index in _acceptedFollowUps)
        if (index >= 0 && index < analysis.followUps.length)
          analysis.followUps[index],
      for (final index in _acceptedTasks)
        if (index >= 0 && index < analysis.tasks.length) analysis.tasks[index],
    ];
    if (selectedActions.isEmpty) return;

    final existing = await _followUps.loadTasks();
    final now = DateTime.now();
    final additions = selectedActions.map((action) {
      final followUpAt =
          action.followUpAt ?? DateTime(now.year, now.month, now.day + 3);
      return FollowUpTask(
        id: '${now.microsecondsSinceEpoch}-${action.title.hashCode}',
        title: action.title,
        bucket: 'personal',
        status: 'active',
        priority: _normalizedPriority(action.priority),
        createdAt: now,
        lastTouchedAt: now,
        nextAction: action.nextAction,
        notes: 'Extracted from a voice reflection session.',
        followUpAt: followUpAt,
        followUpTimeSet: action.followUpAt != null,
      );
    }).toList();

    await _followUps.saveTasks([...existing, ...additions]);
  }

  String _normalizedPriority(String? priority) {
    switch (priority?.trim().toLowerCase()) {
      case 'urgent':
      case 'high':
        return 'high';
      case 'low':
        return 'low';
      default:
        return 'normal';
    }
  }

  String _entryText(String transcript, VoiceReflectionAnalysis analysis) {
    final lines = <String>[
      'Voice Reflection Session',
      '',
      'Transcript:',
      transcript,
    ];
    if (analysis.summary.isNotEmpty) {
      lines.addAll(['', 'What I heard:', analysis.summary]);
    }
    _addNamedList(lines, 'Emotions', analysis.emotions);
    _addNamedList(lines, 'Topics', analysis.topics);
    _addNamedList(
      lines,
      'Follow-ups',
      analysis.followUps.map((item) => item.title).toList(),
    );
    _addNamedList(
      lines,
      'Tasks',
      analysis.tasks.map((item) => item.title).toList(),
    );
    _addNamedList(lines, 'Unresolved questions', analysis.unresolvedQuestions);
    return lines.join('\n').trim();
  }

  void _addNamedList(List<String> lines, String label, List<String> items) {
    if (items.isEmpty) return;
    lines.addAll(['', '$label:']);
    lines.addAll(items.map((item) => '- $item'));
  }

  String _parseVoiceError(dynamic e) {
    final raw = e.toString();
    if (raw.contains('not available')) {
      return 'Voice capture is not available on this device.';
    }
    return 'Could not start voice capture. $raw';
  }

  String _parseError(dynamic e) {
    final str = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    if (match != null) return match.group(1)!;
    if (str.contains('404')) {
      return 'Voice analysis route is not deployed yet.';
    }
    if (str.contains('SocketException') || str.contains('Failed host lookup')) {
      return 'Cannot reach server. Check your network.';
    }
    return 'Voice reflection failed. $str';
  }

  void _toggleAccepted(Set<int> source, int index, bool followUp) {
    final next = Set<int>.from(source);
    if (next.contains(index)) {
      next.remove(index);
    } else {
      next.add(index);
    }
    setState(() {
      if (followUp) {
        _acceptedFollowUps = next;
      } else {
        _acceptedTasks = next;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final analysis = _analysis;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: const BoxDecoration(
          color: JournalColors.bgBase,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: JournalColors.borderBright, width: 0.5),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _withAlpha(JournalColors.accent, 0.14),
                        border: Border.all(color: JournalColors.borderBright),
                      ),
                      child: Icon(
                        _listening
                            ? CupertinoIcons.waveform
                            : CupertinoIcons.mic_fill,
                        color: JournalColors.textPrimary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'VOICE REFLECTION',
                            style: TextStyle(
                              color: JournalColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'Speak freely, then review what Sage extracts.',
                            style: TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_transcriptFocus.hasFocus)
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        onPressed: _dismissKeyboard,
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            color: JournalColors.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(context),
                        child: const Icon(
                          CupertinoIcons.xmark_circle_fill,
                          color: JournalColors.textMuted,
                          size: 26,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(20, 6, 20, safeBottom + 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GlassCard(
                        accentBorder: _listening || _hasTranscript,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CupertinoTextField(
                              controller: _transcriptCtrl,
                              focusNode: _transcriptFocus,
                              placeholder:
                                  'Your transcript appears here. You can edit before saving.',
                              placeholderStyle: const TextStyle(
                                color: JournalColors.textMuted,
                                fontSize: 15,
                                height: 1.45,
                              ),
                              style: const TextStyle(
                                color: JournalColors.textPrimary,
                                fontSize: 15,
                                height: 1.65,
                              ),
                              minLines: 7,
                              maxLines: null,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _withAlpha(
                                  JournalColors.bgSurface,
                                  0.74,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _listening
                                      ? JournalColors.borderBright
                                      : JournalColors.border,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _VoiceSheetButton(
                                    label: _listening ? 'Stop' : 'Record',
                                    icon: _listening
                                        ? CupertinoIcons.stop_fill
                                        : CupertinoIcons.mic_fill,
                                    color: _listening
                                        ? JournalColors.danger
                                        : JournalColors.accent,
                                    onTap: _listening
                                        ? _stopListening
                                        : _startListening,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _VoiceSheetButton(
                                    label: _analyzing ? 'Analyzing' : 'Analyze',
                                    icon: CupertinoIcons.sparkles,
                                    color: JournalColors.info,
                                    disabled: !_canAnalyze,
                                    loading: _analyzing,
                                    onTap: _analyze,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _IconActionButton(
                                  icon: CupertinoIcons.trash,
                                  disabled: !_hasTranscript && !_listening,
                                  onTap: _clear,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (analysis != null) ...[
                        const SizedBox(height: 16),
                        _AnalysisCard(
                          analysis: analysis,
                          acceptedFollowUps: _acceptedFollowUps,
                          acceptedTasks: _acceptedTasks,
                          onToggleFollowUp: (index) => _toggleAccepted(
                            _acceptedFollowUps,
                            index,
                            true,
                          ),
                          onToggleTask: (index) => _toggleAccepted(
                            _acceptedTasks,
                            index,
                            false,
                          ),
                        ),
                      ],
                      if (_fallbackReflection?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 16),
                        _FallbackReflectionCard(text: _fallbackReflection!),
                      ],
                      if (_error != null || _savedMessage != null) ...[
                        const SizedBox(height: 16),
                        _StatusBanner(
                          icon: _savedMessage != null
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.exclamationmark_triangle_fill,
                          title: _savedMessage != null
                              ? 'Saved'
                              : 'Voice reflection issue',
                          message: _savedMessage ?? _error!,
                          color: _savedMessage != null
                              ? JournalColors.success
                              : JournalColors.danger,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _SaveEntryButton(
                        enabled: _canSave,
                        saving: _saving,
                        saved: _savedMessage != null,
                        onPressed: _saveSession,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceSheetButton extends StatelessWidget {
  const _VoiceSheetButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.disabled = false,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool disabled;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final inactive = disabled || loading;
    return GestureDetector(
      onTap: inactive ? null : onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: inactive ? JournalColors.bgCardAlt : _withAlpha(color, 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: inactive ? JournalColors.border : _withAlpha(color, 0.34),
          ),
        ),
        child: Center(
          child: loading
              ? const CupertinoActivityIndicator(color: JournalColors.accent)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: inactive ? JournalColors.textMuted : color,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: inactive
                            ? JournalColors.textMuted
                            : JournalColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  const _IconActionButton({
    required this.icon,
    required this.onTap,
    this.disabled = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: JournalColors.bgSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: JournalColors.border),
        ),
        child: Icon(
          icon,
          color: disabled ? JournalColors.textMuted : JournalColors.textPrimary,
          size: 18,
        ),
      ),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({
    required this.analysis,
    required this.acceptedFollowUps,
    required this.acceptedTasks,
    required this.onToggleFollowUp,
    required this.onToggleTask,
  });

  final VoiceReflectionAnalysis analysis;
  final Set<int> acceptedFollowUps;
  final Set<int> acceptedTasks;
  final ValueChanged<int> onToggleFollowUp;
  final ValueChanged<int> onToggleTask;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accentBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WHAT I HEARD',
            style: TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          if (analysis.summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              analysis.summary,
              style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 15,
                height: 1.55,
              ),
            ),
          ],
          _ChipSection(title: 'Emotions', items: analysis.emotions),
          _ChipSection(title: 'Topics', items: analysis.topics),
          _ReviewActionSection(
            title: 'Follow-ups',
            actions: analysis.followUps,
            selected: acceptedFollowUps,
            onToggle: onToggleFollowUp,
          ),
          _ReviewActionSection(
            title: 'Tasks',
            actions: analysis.tasks,
            selected: acceptedTasks,
            onToggle: onToggleTask,
          ),
          _QuestionSection(items: analysis.unresolvedQuestions),
        ],
      ),
    );
  }
}

class _ChipSection extends StatelessWidget {
  const _ChipSection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((item) => _ReviewChip(label: item)).toList(),
          ),
        ],
      ),
    );
  }
}

class _ReviewActionSection extends StatelessWidget {
  const _ReviewActionSection({
    required this.title,
    required this.actions,
    required this.selected,
    required this.onToggle,
  });

  final String title;
  final List<VoiceReflectionAction> actions;
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < actions.length; i++) ...[
            _ReviewActionTile(
              action: actions[i],
              selected: selected.contains(i),
              onTap: () => onToggle(i),
            ),
            if (i != actions.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _ReviewActionTile extends StatelessWidget {
  const _ReviewActionTile({
    required this.action,
    required this.selected,
    required this.onTap,
  });

  final VoiceReflectionAction action;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? _withAlpha(JournalColors.accent, 0.12)
              : _withAlpha(JournalColors.bgSurface, 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? JournalColors.borderBright : JournalColors.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              color: selected ? JournalColors.accent : JournalColors.textMuted,
              size: 19,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.title,
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  if (action.nextAction?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      action.nextAction!,
                      style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewChip extends StatelessWidget {
  const _ReviewChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.info, 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _withAlpha(JournalColors.info, 0.24)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: JournalColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _QuestionSection extends StatelessWidget {
  const _QuestionSection({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'UNRESOLVED QUESTIONS',
            style: TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items) ...[
            Text(
              item,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _FallbackReflectionCard extends StatelessWidget {
  const _FallbackReflectionCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accentBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'REFLECTION',
            style: TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 15,
              height: 1.55,
            ),
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
