import 'dart:io';
import 'dart:convert';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class SiriCaptureScreen extends StatefulWidget {
  const SiriCaptureScreen({
    super.key,
    required this.initialText,
    this.source = 'siri_shortcut',
    this.autoSave = false,
    this.reviewReason,
    this.preferredFolderName,
    this.preferJournalOnly = false,
  });

  final String initialText;
  final String source;
  final bool autoSave;
  final String? reviewReason;
  final String? preferredFolderName;
  final bool preferJournalOnly;

  @override
  State<SiriCaptureScreen> createState() => _SiriCaptureScreenState();
}

class _SiriCaptureScreenState extends State<SiriCaptureScreen> {
  final _api = ApiService();
  final _entryCtrl = TextEditingController();
  final _imagePicker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _saveError;
  List<Map<String, dynamic>> _folders = [];
  _ShortcutClassification? _classification;
  String? _selectedFolderId;
  bool _saveToTimeline = true;
  bool _saveToProofVault = true;
  bool _autoSaveAttempted = false;
  XFile? _attachedPhoto;

  @override
  void initState() {
    super.initState();
    _entryCtrl.text = widget.initialText.trim();
    _load();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _saveError = null;
    });

    try {
      final folders = await _api.vaultGetFolders();
      final normalizedFolders = List<Map<String, dynamic>>.from(folders);
      final classification = await _classify(
        _entryCtrl.text.trim(),
        normalizedFolders,
      );
      if (!mounted) return;
      final preferredFolder = _matchFolderByName(
        widget.preferredFolderName,
        normalizedFolders,
      );
      setState(() {
        _folders = normalizedFolders;
        _classification = classification;
        _selectedFolderId =
            preferredFolder?['id']?.toString() ?? classification.folderId;
        _saveToProofVault = !widget.preferJournalOnly &&
            (preferredFolder != null || classification.folderId != null);
        _loading = false;
      });
      _tryAutoSave();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _parseError(e);
      });
    }
  }

  Future<_ShortcutClassification> _classify(
    String text,
    List<Map<String, dynamic>> folders,
  ) async {
    final fallback = _heuristicClassification(text, folders);
    try {
      final context = await _api.getFloatchatContext();
      final folderNames = folders
          .map((folder) => folder['name']?.toString().trim() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
      final prompt = '''
You are classifying one spoken journal note for Journal Intelligence.

AVAILABLE PROOF VAULT FOLDERS:
${folderNames.isEmpty ? '- none yet' : folderNames.map((name) => '- $name').join('\n')}

RULES:
- Return JSON only. No markdown. No commentary.
- Keep "normalized_text" in first person and close to the user's meaning.
- "folder_name" must be exactly one of the available folder names, or null.
- For normal personal journaling, reflections, venting, memories, life updates, or notes that do not clearly belong in Proof Vault, set "folder_name" to null.
- Prefer "Financial Support" for purchases, money spent, supplies bought, errands where the support being documented is financial or material.
- Prefer "Activities" for outings, walks, playgrounds, parks, play time, shared activities, transportation, or quality-time events.
- Prefer "Daily Care" for routines like meals, diapers, bedtime, baths, medication support that is not clearly medical.
- Prefer "Medical & Health" for appointments, doctors, meds, illness, therapy, treatment, health monitoring.
- Prefer "School & Education" for school, daycare, homework, conferences, dropoff, pickup, learning support.
- Prefer "Communications" for calls, texts, emails, discussions, coordination, or updates with another person.
- If a timeline-only journal save is appropriate, "needs_confirmation" can be false even when "folder_name" is null.
- If confidence is below 0.90, set "needs_confirmation" to true.
- If there are no folders, keep "folder_name" null and only require confirmation when the note still needs manual review.

Return this exact JSON shape:
{
  "normalized_text": "string",
  "title": "short proof vault title",
  "notes": "1-3 sentence proof note",
  "folder_name": "exact folder name or null",
  "overall_confidence": 0.0,
  "needs_confirmation": true,
  "reason": "short reason"
}

USER NOTE:
$text
''';

      final reply = await _api.sendFloatchatMessage(
        contextString: context,
        webSearchEnabled: false,
        maxTokens: 350,
        messages: [
          {
            'role': 'user',
            'content': prompt,
          }
        ],
      );
      final raw = reply['reply']?.toString() ?? '';
      final parsed = _extractJson(raw);
      if (parsed == null) return fallback;

      final normalizedText =
          parsed['normalized_text']?.toString().trim().isNotEmpty == true
              ? parsed['normalized_text'].toString().trim()
              : fallback.normalizedText;
      final title = parsed['title']?.toString().trim().isNotEmpty == true
          ? parsed['title'].toString().trim()
          : fallback.title;
      final notes = parsed['notes']?.toString().trim().isNotEmpty == true
          ? parsed['notes'].toString().trim()
          : fallback.notes;
      final folderName = parsed['folder_name']?.toString().trim();
      final matchedFolder = _matchFolderByName(folderName, folders) ??
          _matchFolderByName(fallback.folderName, folders);
      var confidence = _clampConfidence(
        (parsed['overall_confidence'] as num?)?.toDouble() ??
            fallback.overallConfidence,
      );
      final fallbackFolderName = fallback.folderName?.trim().toLowerCase();
      final matchedFolderName =
          matchedFolder?['name']?.toString().trim().toLowerCase();
      final strongHeuristicMatch = fallbackFolderName != null &&
          fallbackFolderName.isNotEmpty &&
          fallbackFolderName == matchedFolderName &&
          fallback.overallConfidence >= 0.95;
      if (fallbackFolderName != null &&
          fallbackFolderName.isNotEmpty &&
          fallbackFolderName == matchedFolderName &&
          fallback.overallConfidence > confidence) {
        confidence = fallback.overallConfidence;
      }
      final needsConfirmation = (matchedFolder == null && folders.isNotEmpty) ||
          (!strongHeuristicMatch &&
              (parsed['needs_confirmation'] == true || confidence < 0.90));
      final reason = parsed['reason']?.toString().trim().isNotEmpty == true
          ? parsed['reason'].toString().trim()
          : fallback.reason;

      return _ShortcutClassification(
        normalizedText: normalizedText,
        title: title,
        notes: notes,
        folderId: matchedFolder?['id']?.toString(),
        folderName: matchedFolder?['name']?.toString(),
        overallConfidence: confidence,
        needsConfirmation: needsConfirmation,
        reason: reason,
      );
    } catch (_) {
      return fallback;
    }
  }

  Map<String, dynamic>? _extractJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final fenceMatch =
        RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(trimmed);
    final candidate = fenceMatch?.group(1)?.trim() ?? trimmed;
    final start = candidate.indexOf('{');
    final end = candidate.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    final jsonText = candidate.substring(start, end + 1);
    final decoded = jsonDecode(jsonText);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return null;
  }

  _ShortcutClassification _heuristicClassification(
    String text,
    List<Map<String, dynamic>> folders,
  ) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final lower = normalized.toLowerCase();

    String? preferredFolder;
    String reason;
    double confidence = 0.82;

    final hasPurchaseSignal = RegExp(
      r'\b(bought|buy|paid|purchase|purchased|spent|money|store)\b',
    ).hasMatch(lower);
    final hasSuppliesSignal = RegExp(
      r'\b(pull[- ]?ups|diaper|diapers|wipes|formula|groceries|clothes)\b',
    ).hasMatch(lower);
    final hasActivitySignal = RegExp(
      r'\b(walk|park|playground|zoo|outing|play|soccer|baseball|activity|activities)\b',
    ).hasMatch(lower);
    final hasMedicalSignal = RegExp(
      r'\b(doctor|appointment|medication|medicine|therapy|sick|health)\b',
    ).hasMatch(lower);
    final hasSchoolSignal = RegExp(
      r'\b(school|daycare|homework|teacher|pickup|dropoff)\b',
    ).hasMatch(lower);
    final hasCommunicationSignal = RegExp(
      r'\b(call|text|email|talked|conversation|messaged)\b',
    ).hasMatch(lower);

    final hasGeneralJournalSignal = RegExp(
      r"\b(i felt|i feel|today|tonight|this morning|this afternoon|i want to remember|i need to remember|i was thinking|i realized|i'm feeling|i am feeling)\b",
    ).hasMatch(lower);

    if (hasPurchaseSignal || hasSuppliesSignal) {
      preferredFolder = 'Financial Support';
      confidence = hasPurchaseSignal && hasSuppliesSignal ? 0.97 : 0.93;
      reason = hasPurchaseSignal && hasSuppliesSignal
          ? 'Strong purchase-and-supplies signal for Financial Support.'
          : 'This sounds like material or financial support.';
    } else if (hasActivitySignal) {
      preferredFolder = 'Activities';
      confidence =
          RegExp(r'\b(walk|park|playground)\b').hasMatch(lower) ? 0.96 : 0.91;
      reason = 'This sounds like an outing or shared activity.';
    } else if (hasMedicalSignal) {
      preferredFolder = 'Medical & Health';
      confidence = 0.94;
      reason = 'This sounds like medical or health support.';
    } else if (hasSchoolSignal) {
      preferredFolder = 'School & Education';
      confidence = 0.93;
      reason = 'This sounds school or education related.';
    } else if (hasCommunicationSignal) {
      preferredFolder = 'Communications';
      confidence = 0.9;
      reason = 'This sounds like a communication record.';
    } else if (hasGeneralJournalSignal || widget.preferJournalOnly) {
      preferredFolder = null;
      confidence = widget.preferJournalOnly ? 0.98 : 0.94;
      reason =
          'This reads like a normal journal entry and can stay in the timeline.';
    } else {
      preferredFolder = null;
      confidence = 0.84;
      reason =
          'This can be saved as a journal entry unless you want to route it into Proof Vault.';
    }

    final matchedFolder = _matchFolderByName(preferredFolder, folders);
    final title = _deriveTitle(normalized);
    final notes = 'Captured from Siri: $normalized';
    final resolvedConfidence = preferredFolder == null
        ? confidence
        : matchedFolder == null
            ? (confidence - 0.1).clamp(0.0, 1.0)
            : confidence;

    return _ShortcutClassification(
      normalizedText: normalized,
      title: title,
      notes: notes,
      folderId: matchedFolder?['id']?.toString(),
      folderName: matchedFolder?['name']?.toString(),
      overallConfidence: resolvedConfidence,
      needsConfirmation: preferredFolder == null
          ? resolvedConfidence < 0.88
          : resolvedConfidence < 0.90,
      reason: reason,
    );
  }

  Map<String, dynamic>? _matchFolderByName(
    String? desiredName,
    List<Map<String, dynamic>> folders,
  ) {
    if (desiredName == null || desiredName.trim().isEmpty) return null;
    final target = _normalizeLabel(desiredName);
    for (final folder in folders) {
      final name = folder['name']?.toString() ?? '';
      if (_normalizeLabel(name) == target) return folder;
    }
    for (final folder in folders) {
      final name = _normalizeLabel(folder['name']?.toString() ?? '');
      if (name.contains(target) || target.contains(name)) return folder;
    }
    return null;
  }

  String _normalizeLabel(String value) {
    return value
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _deriveTitle(String text) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return 'Captured care note';
    if (cleaned.length <= 64) return cleaned;
    return '${cleaned.substring(0, 61).trimRight()}...';
  }

  double _clampConfidence(double value) {
    if (value.isNaN) return 0.0;
    return value.clamp(0.0, 1.0);
  }

  Future<void> _tryAutoSave() async {
    if (!widget.autoSave || _autoSaveAttempted || _saving) return;
    if (widget.reviewReason != null) return;
    _autoSaveAttempted = true;
    final classification = _classification;
    if (classification == null) return;
    if (classification.needsConfirmation) return;
    if (_saveToProofVault && _selectedFolderId == null) return;
    await _save(showSuccessDialog: false);
  }

  Future<void> _save({bool showSuccessDialog = true}) async {
    if (_saving) return;
    final text = _entryCtrl.text.trim();
    if (text.isEmpty) return;
    if (!_saveToTimeline && !_saveToProofVault) {
      setState(() => _saveError = 'Choose at least one destination.');
      return;
    }
    if (_saveToProofVault && _selectedFolderId == null) {
      setState(() => _saveError = 'Choose a Proof Vault folder first.');
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final classification =
          _classification ?? _heuristicClassification(text, _folders);
      final normalizedText = text;
      final attachedPhoto = _attachedPhoto;
      String? attachedFilename;
      if (attachedPhoto != null) {
        attachedFilename = attachedPhoto.name.trim().isNotEmpty
            ? attachedPhoto.name
            : attachedPhoto.path.split('/').last;
        if (_saveToTimeline) {
          await _api.validateEntryAttachmentForUpload(
            filePath: attachedPhoto.path,
            filename: attachedFilename,
          );
        }
      }

      int? entryId;
      String? vaultItemId;
      if (_saveToTimeline) {
        final entryRes = await _api.createEntry(
          text: normalizedText,
          entryDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        );
        entryId = (entryRes['entry_id'] as num?)?.toInt();
      }
      if (_saveToProofVault && _selectedFolderId != null) {
        final itemRes = await _api.vaultCreateItem(_selectedFolderId!, {
          'title': classification.title,
          'notes': classification.notes,
          'item_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        });
        vaultItemId = itemRes['id']?.toString();
      }
      if (attachedPhoto != null) {
        final filename = attachedFilename!;
        if (entryId != null) {
          await _api.uploadEntryAttachment(
            entryId: entryId,
            filePath: attachedPhoto.path,
            filename: filename,
          );
        }
        if (vaultItemId != null) {
          final bytes = await attachedPhoto.readAsBytes();
          await _api.vaultUploadItemPhoto(
            vaultItemId,
            bytes,
            filename,
          );
        }
      }
      if (!mounted) return;
      setState(() => _saving = false);
      if (showSuccessDialog) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Saved'),
            content: Text(
              _saveToTimeline && _saveToProofVault
                  ? 'Your note was saved to the timeline and Proof Vault.'
                  : _saveToTimeline
                      ? 'Your note was saved to the timeline.'
                      : 'Your note was saved to Proof Vault.',
            ),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = _parseError(e);
      });
    }
  }

  String _parseError(dynamic e) {
    if (e is EntryAttachmentUploadException) {
      return e.message;
    }
    final str = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    if (str.contains('413')) {
      return 'A photo is too large. Journal photos must be under 8 MB each.';
    }
    return match?.group(1) ?? 'Something went wrong.';
  }

  Future<void> _pickFolder() async {
    if (_folders.isEmpty) return;
    final chosen = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Save to folder'),
        actions: [
          for (final folder in _folders)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop(
                folder['id']?.toString(),
              ),
              child: Text(folder['name']?.toString() ?? 'Folder'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (!mounted || chosen == null) return;
    setState(() => _selectedFolderId = chosen);
  }

  Future<void> _pickAttachment() async {
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Add photo'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('camera'),
            child: const Text('Take Photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('library'),
            child: const Text('Choose From Library'),
          ),
          if (_attachedPhoto != null)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(context).pop('remove'),
              child: const Text('Remove Photo'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'remove') {
      setState(() => _attachedPhoto = null);
      return;
    }
    final source =
        choice == 'camera' ? ImageSource.camera : ImageSource.gallery;
    final image = await _imagePicker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 2000,
      maxHeight: 2000,
    );
    if (!mounted || image == null) return;
    setState(() => _attachedPhoto = image);
  }

  Map<String, dynamic>? get _selectedFolder {
    final selectedId = _selectedFolderId;
    if (selectedId == null) return null;
    for (final folder in _folders) {
      if (folder['id']?.toString() == selectedId) return folder;
    }
    return null;
  }

  bool get _showManualRoutingControls =>
      widget.reviewReason != null ||
      _classification?.needsConfirmation == true ||
      _attachedPhoto != null;

  String get _reviewTitle {
    return switch (widget.reviewReason) {
      'auth_required' => 'Finish Siri save',
      'missing_folder' => 'Review folder',
      'save_failed' => 'Review and save',
      _ => 'Review Siri note',
    };
  }

  String get _reviewSubtitle {
    return switch (widget.reviewReason) {
      'auth_required' =>
        'Your secure session needs attention before Siri can save in the background.',
      'missing_folder' =>
        'Siri found the note but needs you to confirm the Proof Vault destination.',
      'save_failed' =>
        'The background save did not finish cleanly, so this fallback review is keeping the final save in your hands.',
      _ when widget.preferJournalOnly =>
        'Siri captured a journal entry. Review it, attach a photo if you want, and save when ready.',
      _ when _attachedPhoto != null =>
        'You opened the fallback review so you can attach a photo before saving.',
      _ =>
        'Siri captured the note. Review the routing and save when you are ready.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Siri Capture'),
            previousPageTitle: 'Write',
            backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CupertinoActivityIndicator(),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: _SiriCaptureErrorView(
                error: _error!,
                onRetry: _load,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    GlassCard(
                      accentBorder: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      JournalColors.accent,
                                      JournalColors.accent2,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  CupertinoIcons.mic_fill,
                                  color: JournalColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _reviewTitle,
                                      style: const TextStyle(
                                        color: JournalColors.textPrimary,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _reviewSubtitle,
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
                          const SizedBox(height: 16),
                          _ConfidencePill(
                            confidence:
                                _classification?.overallConfidence ?? 0.0,
                            needsConfirmation:
                                _classification?.needsConfirmation ?? true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Captured note',
                                  style: TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(32, 32),
                                onPressed: _pickAttachment,
                                child: const Icon(
                                  CupertinoIcons.paperclip,
                                  color: JournalColors.accent,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                          if (_attachedPhoto != null) ...[
                            const SizedBox(height: 10),
                            _SiriAttachmentTile(
                              photo: _attachedPhoto!,
                              onTap: () => _showAttachedPhotoLightbox(
                                context,
                                _attachedPhoto!,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          CupertinoTextField(
                            controller: _entryCtrl,
                            minLines: 4,
                            maxLines: null,
                            style: const TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 15,
                              height: 1.55,
                            ),
                            placeholder: 'What happened?',
                            placeholderStyle: const TextStyle(
                              color: JournalColors.textMuted,
                            ),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: JournalColors.bgSurface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: JournalColors.border),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _showManualRoutingControls
                                ? 'Review destinations'
                                : 'Saving to',
                            style: const TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_showManualRoutingControls) ...[
                            _DestinationToggleRow(
                              label: 'Timeline',
                              subtitle: 'Save this as a normal journal entry.',
                              value: _saveToTimeline,
                              onChanged: (value) {
                                setState(() => _saveToTimeline = value);
                              },
                            ),
                            const SizedBox(height: 12),
                            _DestinationToggleRow(
                              label: 'Proof Vault',
                              subtitle: _selectedFolder == null
                                  ? 'Choose a folder for the supporting record.'
                                  : 'Selected folder: ${_selectedFolder?['name'] ?? 'Folder'}',
                              value: _saveToProofVault,
                              onChanged: (value) {
                                setState(() => _saveToProofVault = value);
                              },
                            ),
                            const SizedBox(height: 14),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: _folders.isEmpty ? null : _pickFolder,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: JournalColors.bgSurface,
                                  borderRadius: BorderRadius.circular(14),
                                  border:
                                      Border.all(color: JournalColors.border),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      CupertinoIcons.folder_fill,
                                      color: JournalColors.accent,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _selectedFolder?['name']?.toString() ??
                                            (_folders.isEmpty
                                                ? 'Create a Proof Vault folder first'
                                                : 'Choose folder'),
                                        style: const TextStyle(
                                          color: JournalColors.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      CupertinoIcons.chevron_right,
                                      color: JournalColors.textMuted,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ] else ...[
                            _DraftRow(
                              label: 'Timeline',
                              value: _saveToTimeline
                                  ? 'Journal entry will be saved.'
                                  : 'Timeline skipped.',
                            ),
                            const SizedBox(height: 10),
                            _DraftRow(
                              label: 'Proof Vault',
                              value: _saveToProofVault
                                  ? (_selectedFolder?['name']?.toString() ??
                                      'No folder selected.')
                                  : 'Not included for this save.',
                            ),
                          ],
                          if ((_classification?.reason ?? '').isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              _classification!.reason,
                              style: const TextStyle(
                                color: JournalColors.textSecondary,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Review draft',
                            style: TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_saveToProofVault ||
                              _classification?.folderName != null) ...[
                            _DraftRow(
                              label: 'Title',
                              value: _classification?.title ??
                                  'Captured support note',
                            ),
                            const SizedBox(height: 10),
                            _DraftRow(
                              label: 'Notes',
                              value: _classification?.notes ??
                                  'Captured from Siri.',
                              multiline: true,
                            ),
                          ] else
                            const _DraftRow(
                              label: 'Timeline save',
                              value:
                                  'This Siri note will save as a normal journal entry.',
                              multiline: true,
                            ),
                        ],
                      ),
                    ),
                    if (_saveError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _saveError!,
                        style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    AdaptiveButton(
                      label: _saving
                          ? 'Saving…'
                          : _classification?.needsConfirmation == true
                              ? 'Confirm and Save'
                              : 'Save Now',
                      style: AdaptiveButtonStyle.prominentGlass,
                      onPressed: _saving ? null : () => _save(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _showAttachedPhotoLightbox(BuildContext context, XFile photo) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.file(
            File(photo.path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              height: 180,
              color: JournalColors.bgSurface,
              alignment: Alignment.center,
              child: const Icon(
                CupertinoIcons.photo_fill,
                color: JournalColors.textMuted,
                size: 36,
              ),
            ),
          ),
        ),
      ),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

class _SiriAttachmentTile extends StatelessWidget {
  const _SiriAttachmentTile({
    required this.photo,
    required this.onTap,
  });

  final XFile photo;
  final VoidCallback onTap;

  String get _displayName {
    final name = photo.name.trim();
    if (name.isNotEmpty) return name;
    return photo.path.split('/').last;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 148,
        height: 122,
        decoration: BoxDecoration(
          color: JournalColors.bgSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: JournalColors.borderBright),
          boxShadow: [
            BoxShadow(
              color: JournalColors.accentGlow.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(photo.path),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: JournalColors.bgCardAlt,
                  alignment: Alignment.center,
                  child: const Icon(
                    CupertinoIcons.photo_fill,
                    color: JournalColors.textMuted,
                    size: 30,
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        JournalColors.bgBase.withValues(alpha: 0),
                        JournalColors.bgBase.withValues(alpha: 0.76),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Text(
                  _displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: JournalColors.bgBase.withValues(alpha: 0.72),
                    shape: BoxShape.circle,
                    border: Border.all(color: JournalColors.borderBright),
                  ),
                  child: const Icon(
                    CupertinoIcons.arrow_up_left_arrow_down_right,
                    color: JournalColors.textPrimary,
                    size: 13,
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

class _ShortcutClassification {
  const _ShortcutClassification({
    required this.normalizedText,
    required this.title,
    required this.notes,
    required this.folderId,
    required this.folderName,
    required this.overallConfidence,
    required this.needsConfirmation,
    required this.reason,
  });

  final String normalizedText;
  final String title;
  final String notes;
  final String? folderId;
  final String? folderName;
  final double overallConfidence;
  final bool needsConfirmation;
  final String reason;
}

class _ConfidencePill extends StatelessWidget {
  const _ConfidencePill({
    required this.confidence,
    required this.needsConfirmation,
  });

  final double confidence;
  final bool needsConfirmation;

  @override
  Widget build(BuildContext context) {
    final color =
        needsConfirmation ? JournalColors.severity : const Color(0xFF22C55E);
    final label = needsConfirmation ? 'Review needed' : 'Ready to save';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label • ${(confidence * 100).round()}%',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DestinationToggleRow extends StatelessWidget {
  const _DestinationToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        CupertinoSwitch(
          value: value,
          activeTrackColor: JournalColors.accent,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  final String label;
  final String value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: JournalColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: JournalColors.textPrimary,
            fontSize: 14,
            height: multiline ? 1.45 : 1.2,
          ),
        ),
      ],
    );
  }
}

class _SiriCaptureErrorView extends StatelessWidget {
  const _SiriCaptureErrorView({
    required this.error,
    required this.onRetry,
  });

  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.wifi_slash,
              color: JournalColors.textMuted,
              size: 28,
            ),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            CupertinoButton(
              color: JournalColors.accent,
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
