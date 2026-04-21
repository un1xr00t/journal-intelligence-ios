// lib/screens/detective_case_screen.dart
//
// Case workspace — scrollable tab bar.
// Log tab: fully built with photo attachments + thumbnails.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Divider;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

// ── Constants ──────────────────────────────────────────────────────────────

const _kEntryTypes = ['note', 'observation', 'statement', 'admission', 'contradiction', 'timeline'];
const _kSeverities = ['critical', 'high', 'medium', 'low', 'info'];
const _kSeverityColors = {
  'critical': Color(0xFFEF4444),
  'high':     Color(0xFFF97316),
  'medium':   Color(0xFFF59E0B),
  'low':      Color(0xFF6366F1),
  'info':     Color(0xFF22C55E),
};

class _TabMeta {
  final String label;
  final IconData icon;
  const _TabMeta(this.label, this.icon);
}

final _kTabs = [
  const _TabMeta('Log',          CupertinoIcons.doc_text),
  const _TabMeta('Partner',      CupertinoIcons.chat_bubble),
  const _TabMeta('Photos',       CupertinoIcons.photo),
  const _TabMeta('Gallery',      CupertinoIcons.photo_on_rectangle),
  const _TabMeta('Intelligence', CupertinoIcons.sparkles),
  const _TabMeta('Wires',        CupertinoIcons.wifi),
  const _TabMeta('Export',       CupertinoIcons.arrow_up_doc),
  const _TabMeta('Research',     CupertinoIcons.search),
  const _TabMeta('Settings',     CupertinoIcons.settings),
];

// ── Authenticated image widget ─────────────────────────────────────────────
// Uses Dio (not Image.network) to fetch bytes so auth headers are always sent
// and Flutter's URL-keyed image cache never caches a failed/missing response.

class _AuthImage extends StatefulWidget {
  final String path;   // relative path e.g. /api/detective/cases/1/entries/2/photos/3/image
  final BoxFit fit;

  const _AuthImage({required this.path, this.fit = BoxFit.cover});

  @override
  State<_AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<_AuthImage> {
  final _api = ApiService();
  _ImgState _state = _ImgState.loading;
  List<int>? _bytes;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(_AuthImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      setState(() { _state = _ImgState.loading; _bytes = null; });
      _fetch();
    }
  }

  Future<void> _fetch() async {
    if (widget.path.isEmpty) {
      if (mounted) setState(() => _state = _ImgState.error);
      return;
    }
    try {
      final bytes = await _api.fetchImageBytes(widget.path);
      if (mounted) setState(() { _bytes = bytes; _state = _ImgState.done; });
    } catch (_) {
      if (mounted) setState(() => _state = _ImgState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _ImgState.loading:
        return const Center(child: CupertinoActivityIndicator(radius: 8));
      case _ImgState.error:
        return const Center(
          child: Icon(CupertinoIcons.photo,
              color: JournalColors.textMuted, size: 20));
      case _ImgState.done:
        return Image.memory(
          Uint8List.fromList(_bytes!),
          fit: widget.fit,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(CupertinoIcons.photo,
                color: JournalColors.textMuted, size: 20)),
        );
    }
  }
}

enum _ImgState { loading, done, error }

// ── Main screen ────────────────────────────────────────────────────────────

class DetectiveCaseScreen extends StatefulWidget {
  final Map<String, dynamic> caseData;
  const DetectiveCaseScreen({super.key, required this.caseData});

  @override
  State<DetectiveCaseScreen> createState() => _DetectiveCaseScreenState();
}

class _DetectiveCaseScreenState extends State<DetectiveCaseScreen> {
  final _api = ApiService();
  int _tabIndex = 0;
  List<Map<String, dynamic>> _entries = [];
  bool _loadingEntries = true;
  List<Map<String, dynamic>> _uploads = [];
  bool _loadingUploads = false;

  String get _caseId => widget.caseData['id'].toString();

  Color get _statusColor {
    switch (widget.caseData['status']) {
      case 'active':   return const Color(0xFF22C55E);
      case 'closed':   return JournalColors.textMuted;
      case 'archived': return const Color(0xFFF59E0B);
      default:         return JournalColors.textMuted;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _loadUploads();
  }

  Future<void> _loadEntries() async {
    setState(() => _loadingEntries = true);
    try {
      final res = await _api.detectiveGetEntries(_caseId);
      if (mounted) setState(() {
        _entries = List<Map<String, dynamic>>.from(res);
        _loadingEntries = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingEntries = false);
    }
  }

  Future<void> _loadUploads() async {
    if (mounted) setState(() => _loadingUploads = true);
    try {
      final res = await _api.detectiveGetUploads(_caseId);
      if (mounted) setState(() {
        _uploads = List<Map<String, dynamic>>.from(res);
        _loadingUploads = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingUploads = false);
    }
  }

  Future<void> _uploadCasePhoto(PlatformFile file) async {
    if (file.bytes == null) return;
    try {
      final upload = await _api.detectiveUploadCasePhoto(
          _caseId, file.bytes!.toList(), file.name);
      if (mounted) setState(() =>
        _uploads = [Map<String, dynamic>.from(upload), ..._uploads]);
    } catch (e) { _showError(e.toString()); }
  }

  Future<void> _deleteUpload(Map<String, dynamic> upload) async {
    final source = upload['source'] as String? ?? 'upload';
    final rawId  = upload['id'].toString();
    try {
      if (source == 'multi_entry') {
        // Entry-attached photos use a separate endpoint; strip the mphoto_ prefix
        final photoId = rawId.replaceFirst('mphoto_', '');
        await _api.detectiveDeleteEntryPhotoById(_caseId, photoId);
      } else {
        await _api.detectiveDeleteUpload(_caseId, rawId);
      }
      if (mounted) setState(() =>
        _uploads = _uploads.where((u) => u['id'].toString() != rawId).toList());
    } catch (e) { _showError(e.toString()); }
  }

  Future<Map<String, dynamic>?> _addEntry(String content, String type, String severity) async {
    try {
      final entry = await _api.detectiveAddEntry(_caseId, {
        'content': content, 'entry_type': type, 'severity': severity,
      });
      if (mounted) setState(() => _entries = [entry, ..._entries]);
      return entry;
    } catch (e) { _showError(e.toString()); return null; }
  }

  Future<void> _updateEntry(String entryId, Map<String, dynamic> data) async {
    try {
      await _api.detectiveUpdateEntry(_caseId, entryId, data);
      if (mounted) setState(() {
        _entries = _entries.map((e) =>
          e['id'].toString() == entryId ? {...e, ...data} : e).toList();
      });
    } catch (e) { _showError(e.toString()); }
  }

  Future<void> _deleteEntry(String entryId) async {
    try {
      await _api.detectiveDeleteEntry(_caseId, entryId);
      if (mounted) setState(() =>
        _entries = _entries.where((e) => e['id'].toString() != entryId).toList());
    } catch (e) { _showError(e.toString()); }
  }

  void _onPhotoAdded(String entryId, Map<String, dynamic> photo) {
    if (!mounted) return;
    setState(() {
      _entries = _entries.map((e) {
        if (e['id'].toString() != entryId) return e;
        final photos = List<dynamic>.from(e['photos'] ?? []);
        photos.add(photo);
        return {...e, 'photos': photos};
      }).toList();
    });
  }

  void _onPhotoDeleted(String entryId, String photoId) {
    if (!mounted) return;
    setState(() {
      _entries = _entries.map((e) {
        if (e['id'].toString() != entryId) return e;
        final photos = List<dynamic>.from(e['photos'] ?? [])
          ..removeWhere((p) => p['id'].toString() == photoId);
        return {...e, 'photos': photos};
      }).toList();
    });
  }

  void _onAnalysisUpdated(String entryId, String analysis) {
    if (!mounted) return;
    setState(() {
      _entries = _entries.map((e) =>
        e['id'].toString() == entryId
          ? {...e, 'multi_photo_analysis': analysis}
          : e).toList();
    });
  }

  void _showError(String msg) {
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(msg),
        actions: [CupertinoDialogAction(
          child: const Text('OK'),
          onPressed: () => Navigator.pop(context))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Row(
              children: [
                Container(width: 7, height: 7,
                  decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(widget.caseData['title'] ?? 'Case',
                    overflow: TextOverflow.ellipsis)),
              ],
            ),
            backgroundColor: JournalColors.bgBase.withOpacity(0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5)),
          ),
          SliverToBoxAdapter(child: _buildTabBar()),
          SliverFillRemaining(
            hasScrollBody: true,
            child: _buildTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: ColoredBox(
            color: JournalColors.bgSurface,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: List.generate(_kTabs.length, (i) {
                  final selected = _tabIndex == i;
                  return GestureDetector(
                    onTap: () {
                setState(() => _tabIndex = i);
                // Refresh uploads when switching to Photos or Gallery tab
                if (i == 2 || i == 3) _loadUploads();
              },
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(
                          color: selected ? JournalColors.accent : const Color(0x00000000),
                          width: 2,
                        )),
                      ),
                      alignment: Alignment.center,
                      child: Text(_kTabs[i].label,
                        style: TextStyle(
                          color: selected ? JournalColors.textPrimary : JournalColors.textSecondary,
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        )),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
        const Divider(height: 0.5, thickness: 0.5, color: JournalColors.border),
      ],
    );
  }

  Widget _buildTab() {
    switch (_tabIndex) {
      case 0:
        return _LogTab(
          caseId: _caseId,
          entries: _entries,
          loading: _loadingEntries,
          onAdd: _addEntry,
          onUpdate: _updateEntry,
          onDelete: _deleteEntry,
          onPhotoAdded: _onPhotoAdded,
          onPhotoDeleted: _onPhotoDeleted,
          onAnalysisUpdated: _onAnalysisUpdated,
          onUploadsRefresh: _loadUploads,
        );
      case 1:
        return _CasePartnerTab(
          caseId: _caseId,
          caseName: widget.caseData['title'] as String? ?? 'Case',
        );
      case 2:
        return _PhotosTab(
          caseId: _caseId,
          uploads: _uploads,
          loading: _loadingUploads,
          onUpload: _uploadCasePhoto,
          onDelete: _deleteUpload,
        );
      case 3:
        return _GalleryTab(
          caseId: _caseId,
          uploads: _uploads,
          onDelete: _deleteUpload,
        );
      case 4:
        return _IntelligenceTab(caseId: _caseId);
      case 5:
        return _WiresTab(caseId: _caseId);
      case 6:
        return _ExportTab(
          caseId: _caseId,
          caseName: widget.caseData['title'] as String? ?? 'Case',
        );
      case 7:
        return _ResearchTab(caseId: _caseId);
      case 8:
        return _SettingsTab();
      default:
        return _TabPlaceholder(tabName: _kTabs[_tabIndex].label);
    }
  }
}

// ── Log Tab ────────────────────────────────────────────────────────────────

class _LogTab extends StatefulWidget {
  final String caseId;
  final List<Map<String, dynamic>> entries;
  final bool loading;
  final Future<Map<String, dynamic>?> Function(String, String, String) onAdd;
  final Future<void> Function(String, Map<String, dynamic>) onUpdate;
  final Future<void> Function(String) onDelete;
  final void Function(String entryId, Map<String, dynamic> photo) onPhotoAdded;
  final void Function(String entryId, String photoId) onPhotoDeleted;
  final void Function(String entryId, String analysis) onAnalysisUpdated;
  final VoidCallback onUploadsRefresh;

  const _LogTab({
    required this.caseId,
    required this.entries,
    required this.loading,
    required this.onAdd,
    required this.onUpdate,
    required this.onDelete,
    required this.onPhotoAdded,
    required this.onPhotoDeleted,
    required this.onAnalysisUpdated,
    required this.onUploadsRefresh,
  });

  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> {
  final _api = ApiService();
  final _ctrl = TextEditingController();
  String _type = 'note';
  String _severity = 'medium';
  bool _adding = false;
  String? _expandedId;
  String? _editingId;
  final _editCtrl = TextEditingController();
  String _editType = 'note';
  String _editSeverity = 'medium';
  bool _saving = false;

  // Pending photos for new entry
  List<PlatformFile> _pendingPhotos = [];
  bool _pickingPhotos = false;

  // Per-entry upload/synthesize state
  final Map<String, bool> _uploadingFor = {};
  final Map<String, bool> _synthesizingFor = {};

  @override
  void dispose() {
    _ctrl.dispose();
    _editCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    setState(() => _pickingPhotos = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (result != null && mounted) {
        setState(() => _pendingPhotos = [..._pendingPhotos, ...result.files]);
      }
    } finally {
      if (mounted) setState(() => _pickingPhotos = false);
    }
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final photos = List<PlatformFile>.from(_pendingPhotos);
    setState(() { _adding = true; _pendingPhotos = []; });

    final entry = await widget.onAdd(text, _type, _severity);
    if (entry != null && photos.isNotEmpty) {
      await _uploadPhotosAndSynthesize(entry['id'].toString(), photos);
    }
    if (mounted) { _ctrl.clear(); setState(() => _adding = false); }
  }

  Future<void> _uploadPhotosAndSynthesize(String entryId, List<PlatformFile> photos) async {
    setState(() => _uploadingFor[entryId] = true);
    try {
      for (final f in photos) {
        if (f.bytes == null) continue;
        try {
          final photo = await _api.detectiveUploadEntryPhoto(
            widget.caseId, entryId, f.bytes!, f.name);
          widget.onPhotoAdded(entryId, Map<String, dynamic>.from(photo));
        } catch (_) {}
      }
      // Auto-synthesize
      await _synthesize(entryId);
    } finally {
      if (mounted) setState(() => _uploadingFor.remove(entryId));
      // Refresh uploads list so Photos + Gallery tabs pick up new entry photos
      widget.onUploadsRefresh();
    }
  }

  Future<void> _synthesize(String entryId) async {
    if (mounted) setState(() => _synthesizingFor[entryId] = true);
    try {
      final res = await _api.detectiveSynthesizeEntryPhotos(widget.caseId, entryId);
      widget.onAnalysisUpdated(entryId, res['synthesis'] ?? '');
    } catch (_) {} finally {
      if (mounted) setState(() => _synthesizingFor.remove(entryId));
    }
  }

  Future<void> _deletePhoto(String entryId, String photoId) async {
    try {
      await _api.detectiveDeleteEntryPhoto(widget.caseId, entryId, photoId);
      widget.onPhotoDeleted(entryId, photoId);
    } catch (_) {}
  }

  void _startEdit(Map<String, dynamic> e) {
    _editCtrl.text = e['content'] ?? '';
    _editType = e['entry_type'] ?? 'note';
    _editSeverity = e['severity'] ?? 'medium';
    setState(() => _editingId = e['id'].toString());
  }

  Future<void> _saveEdit(String id) async {
    setState(() => _saving = true);
    await widget.onUpdate(id, {
      'content': _editCtrl.text.trim(),
      'entry_type': _editType,
      'severity': _editSeverity,
    });
    if (mounted) setState(() { _editingId = null; _saving = false; });
  }

  void _confirmDelete(String id) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('This cannot be undone.'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () { Navigator.pop(context); widget.onDelete(id); },
            child: const Text('Delete')),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ],
      ),
    );
  }

  Widget _chips(List<String> options, String selected,
      Color Function(String) colorFn, void Function(String) onTap) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((o) {
          final sel = selected == o;
          final color = colorFn(o);
          return GestureDetector(
            onTap: () => onTap(o),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: sel ? color.withOpacity(0.18) : const Color(0x0AFFFFFF),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: sel ? color.withOpacity(0.6) : JournalColors.border),
              ),
              child: Text(o.toUpperCase(),
                style: TextStyle(
                  color: sel ? color : JournalColors.textMuted,
                  fontSize: 10,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                  letterSpacing: 0.4,
                )),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // ── Add form ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GlassCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('LOG ENTRY', style: TextStyle(
                    color: JournalColors.textMuted, fontSize: 10,
                    fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                  const SizedBox(height: 10),
                  CupertinoTextField(
                    controller: _ctrl,
                    placeholder: 'What did you observe, hear, or find? Be specific.',
                    placeholderStyle: const TextStyle(color: JournalColors.textMuted, fontSize: 13),
                    style: const TextStyle(
                      color: JournalColors.textPrimary, fontSize: 13, height: 1.5),
                    maxLines: null, minLines: 3,
                    decoration: BoxDecoration(
                      color: const Color(0x0AFFFFFF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: JournalColors.border),
                    ),
                    padding: const EdgeInsets.all(10),
                  ),

                  // Pending photos strip
                  if (_pendingPhotos.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _pendingPhotos.asMap().entries.map((entry) {
                          final i = entry.key;
                          final f = entry.value;
                          return Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: JournalColors.accent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: JournalColors.accent.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('📎', style: TextStyle(fontSize: 11)),
                                const SizedBox(width: 4),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 120),
                                  child: Text(f.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: JournalColors.textSecondary, fontSize: 10)),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => setState(() =>
                                    _pendingPhotos = List.from(_pendingPhotos)..removeAt(i)),
                                  child: const Text('✕',
                                    style: TextStyle(
                                      color: Color(0x80EF4444), fontSize: 11)),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),
                  _chips(_kEntryTypes, _type,
                    (_) => JournalColors.accent,
                    (t) => setState(() => _type = t)),
                  const SizedBox(height: 8),
                  _chips(_kSeverities, _severity,
                    (s) => _kSeverityColors[s]!,
                    (s) => setState(() => _severity = s)),
                  const SizedBox(height: 12),

                  // Bottom row: attach + submit
                  Row(
                    children: [
                      // Attach button
                      GestureDetector(
                        onTap: _pickingPhotos ? null : _pickPhotos,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _pendingPhotos.isNotEmpty
                                ? JournalColors.accent.withOpacity(0.15)
                                : const Color(0x0AFFFFFF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _pendingPhotos.isNotEmpty
                                  ? JournalColors.accent.withOpacity(0.4)
                                  : JournalColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _pickingPhotos
                                  ? const CupertinoActivityIndicator(radius: 8)
                                  : Icon(CupertinoIcons.paperclip,
                                      size: 16,
                                      color: _pendingPhotos.isNotEmpty
                                          ? JournalColors.accent
                                          : JournalColors.textMuted),
                              if (_pendingPhotos.isNotEmpty) ...[
                                const SizedBox(width: 5),
                                Text('${_pendingPhotos.length}',
                                  style: const TextStyle(
                                    color: JournalColors.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: CupertinoButton.filled(
                          borderRadius: BorderRadius.circular(8),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          onPressed: _adding ? null : _submit,
                          child: _adding
                              ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                              : Text(
                                  _pendingPhotos.isNotEmpty
                                    ? 'Log + ${_pendingPhotos.length} photo${_pendingPhotos.length > 1 ? 's' : ''}'
                                    : 'Log It',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Entry list ──
        if (widget.loading)
          const SliverFillRemaining(child: Center(child: CupertinoActivityIndicator()))
        else if (widget.entries.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: const [
                Text('🕵️', style: TextStyle(fontSize: 36)),
                SizedBox(height: 12),
                Text('Nothing logged yet.',
                  style: TextStyle(color: JournalColors.textSecondary, fontSize: 15)),
                SizedBox(height: 4),
                Text('Start building the record.',
                  style: TextStyle(color: JournalColors.textMuted, fontSize: 13)),
              ]),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final e = widget.entries[i];
                  final id = e['id'].toString();
                  return _EntryCard(
                    entry: e,
                    caseId: widget.caseId,
                    expanded: _expandedId == id,
                    editing: _editingId == id,
                    editCtrl: _editCtrl,
                    editType: _editType,
                    editSeverity: _editSeverity,
                    saving: _saving,
                    uploading: _uploadingFor[id] ?? false,
                    synthesizing: _synthesizingFor[id] ?? false,
                    onTap: () => setState(() =>
                      _expandedId = _expandedId == id ? null : id),
                    onEditStart: () => _startEdit(e),
                    onEditCancel: () => setState(() => _editingId = null),
                    onEditSave: () => _saveEdit(id),
                    onEditTypeChange: (t) => setState(() => _editType = t),
                    onEditSeverityChange: (s) => setState(() => _editSeverity = s),
                    onDelete: () => _confirmDelete(id),
                    onAddPhoto: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.image,
                        allowMultiple: true,
                        withData: true,
                      );
                      if (result != null) {
                        await _uploadPhotosAndSynthesize(
                          id, result.files);
                      }
                    },
                    onDeletePhoto: (photoId) => _deletePhoto(id, photoId),
                    onSynthesize: () => _synthesize(id),
                  );
                },
                childCount: widget.entries.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Entry card ─────────────────────────────────────────────────────────────

class _EntryCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final String caseId;
  final bool expanded;
  final bool editing;
  final TextEditingController editCtrl;
  final String editType;
  final String editSeverity;
  final bool saving;
  final bool uploading;
  final bool synthesizing;
  final VoidCallback onTap;
  final VoidCallback onEditStart;
  final VoidCallback onEditCancel;
  final VoidCallback onEditSave;
  final ValueChanged<String> onEditTypeChange;
  final ValueChanged<String> onEditSeverityChange;
  final VoidCallback onDelete;
  final VoidCallback onAddPhoto;
  final ValueChanged<String> onDeletePhoto;
  final VoidCallback onSynthesize;

  const _EntryCard({
    required this.entry, required this.caseId,
    required this.expanded, required this.editing,
    required this.editCtrl, required this.editType, required this.editSeverity,
    required this.saving, required this.uploading, required this.synthesizing,
    required this.onTap, required this.onEditStart, required this.onEditCancel,
    required this.onEditSave, required this.onEditTypeChange,
    required this.onEditSeverityChange, required this.onDelete,
    required this.onAddPhoto, required this.onDeletePhoto, required this.onSynthesize,
  });

  Color get _sevColor => _kSeverityColors[entry['severity']] ?? JournalColors.border;

  String _fmt(String? raw) {
    if (raw == null || raw.length < 16) return raw ?? '';
    return raw.substring(0, 16).replaceAll('T', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final photos = List<dynamic>.from(entry['photos'] ?? []);
    final analysis = entry['multi_photo_analysis'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: JournalColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JournalColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: _sevColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(children: [
                        Flexible(
                          child: Wrap(spacing: 5, runSpacing: 4, children: [
                            _Chip(entry['entry_type'] ?? 'note', JournalColors.textMuted),
                            _Chip((entry['severity'] ?? 'medium').toString().toUpperCase(), _sevColor),
                            if (photos.isNotEmpty)
                              _Chip('📎 ${photos.length}', const Color(0xFF22C55E)),
                          ]),
                        ),
                        const SizedBox(width: 6),
                        Text(_fmt(entry['created_at']),
                          style: const TextStyle(color: JournalColors.textMuted, fontSize: 10)),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onAddPhoto,
                          child: const Icon(CupertinoIcons.paperclip,
                            size: 15, color: JournalColors.textMuted)),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: editing ? onEditCancel : onEditStart,
                          child: Icon(
                            editing ? CupertinoIcons.xmark : CupertinoIcons.pencil,
                            size: 15,
                            color: editing ? JournalColors.accent : JournalColors.textMuted)),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onDelete,
                          child: const Icon(CupertinoIcons.trash,
                            size: 15, color: Color(0x80EF4444))),
                      ]),
                      const SizedBox(height: 8),

                      // Content or edit form
                      if (editing) ...[
                        CupertinoTextField(
                          controller: editCtrl,
                          style: const TextStyle(
                            color: JournalColors.textPrimary, fontSize: 13, height: 1.5),
                          maxLines: null, minLines: 3,
                          decoration: BoxDecoration(
                            color: const Color(0x0AFFFFFF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: JournalColors.accent.withOpacity(0.5)),
                          ),
                          padding: const EdgeInsets.all(10),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: _kEntryTypes.map((t) => GestureDetector(
                            onTap: () => onEditTypeChange(t),
                            child: Container(
                              margin: const EdgeInsets.only(right: 5),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: editType == t
                                  ? JournalColors.accent.withOpacity(0.18)
                                  : const Color(0x0AFFFFFF),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: editType == t
                                  ? JournalColors.accent.withOpacity(0.5)
                                  : JournalColors.border),
                              ),
                              child: Text(t, style: TextStyle(
                                color: editType == t ? JournalColors.accent : JournalColors.textMuted,
                                fontSize: 10)),
                            ),
                          )).toList()),
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: _kSeverities.map((s) {
                            final c = _kSeverityColors[s]!;
                            return GestureDetector(
                              onTap: () => onEditSeverityChange(s),
                              child: Container(
                                margin: const EdgeInsets.only(right: 5),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: editSeverity == s ? c.withOpacity(0.18) : const Color(0x0AFFFFFF),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: editSeverity == s
                                    ? c.withOpacity(0.5) : JournalColors.border),
                                ),
                                child: Text(s.toUpperCase(), style: TextStyle(
                                  color: editSeverity == s ? c : JournalColors.textMuted,
                                  fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                            );
                          }).toList()),
                        ),
                        const SizedBox(height: 10),
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            onPressed: onEditCancel,
                            child: const Text('Cancel',
                              style: TextStyle(color: JournalColors.textMuted, fontSize: 13))),
                          CupertinoButton.filled(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            borderRadius: BorderRadius.circular(8),
                            onPressed: saving ? null : onEditSave,
                            child: saving
                              ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                              : const Text('Save', style: TextStyle(fontSize: 13))),
                        ]),
                      ] else
                        GestureDetector(
                          onTap: onTap,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry['content'] ?? '',
                                maxLines: expanded ? null : 3,
                                overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: JournalColors.textPrimary, fontSize: 13, height: 1.55)),
                              if (photos.isNotEmpty || (analysis != null && analysis.isNotEmpty)) ...[
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!expanded && photos.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 5),
                                        child: Text('${photos.length} photo${photos.length == 1 ? '' : 's'}',
                                          style: const TextStyle(
                                            color: JournalColors.textMuted,
                                            fontSize: 10)),
                                      ),
                                    Icon(
                                      expanded
                                        ? CupertinoIcons.chevron_up
                                        : CupertinoIcons.chevron_down,
                                      size: 11,
                                      color: JournalColors.textMuted),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                      // ── Photo strip (when expanded) ──────────────────
                      if (expanded && (photos.isNotEmpty || uploading)) ...[
                        const SizedBox(height: 10),
                        Container(
                          height: 0.5,
                          color: const Color(0x1AFFFFFF),
                          margin: const EdgeInsets.only(bottom: 10),
                        ),

                        // Upload indicator
                        if (uploading)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(children: const [
                              CupertinoActivityIndicator(radius: 7),
                              SizedBox(width: 8),
                              Text('Uploading photos…',
                                style: TextStyle(
                                  color: JournalColors.textMuted, fontSize: 11)),
                            ]),
                          ),

                        // Thumbnails
                        if (photos.isNotEmpty)
                          Wrap(spacing: 8, runSpacing: 8,
                            children: photos.map<Widget>((p) {
                              final photoId = p['id'].toString();
                              final imageUrl = p['image_url'] as String? ?? '';
                              final status = p['analysis_status'] as String? ?? 'pending';
                              final statusColor = status == 'done'
                                  ? const Color(0xFF22C55E)
                                  : status == 'failed'
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFFF59E0B);

                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: SizedBox(
                                      width: 80, height: 80,
                                      child: _AuthImage(path: imageUrl),
                                    ),
                                  ),
                                  // Status dot
                                  Positioned(
                                    bottom: 4, left: 4,
                                    child: Container(
                                      width: 7, height: 7,
                                      decoration: BoxDecoration(
                                        color: statusColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: JournalColors.bgCard, width: 1),
                                      ),
                                    ),
                                  ),
                                  // Delete button
                                  Positioned(
                                    top: 3, right: 3,
                                    child: GestureDetector(
                                      onTap: () => onDeletePhoto(photoId),
                                      child: Container(
                                        width: 18, height: 18,
                                        decoration: BoxDecoration(
                                          color: const Color(0xCC000000),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          CupertinoIcons.xmark,
                                          size: 10, color: CupertinoColors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),

                        // Synthesize / analysis
                        if (synthesizing) ...[
                          const SizedBox(height: 8),
                          Row(children: const [
                            CupertinoActivityIndicator(radius: 7),
                            SizedBox(width: 8),
                            Text('Analyzing photos together…',
                              style: TextStyle(color: JournalColors.textMuted, fontSize: 11)),
                          ]),
                        ] else if (photos.length > 1 && !uploading) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: onSynthesize,
                            child: Text(
                              analysis != null ? '↺ Re-run analysis' : '🧠 Run combined analysis',
                              style: TextStyle(
                                color: JournalColors.accent.withOpacity(0.8),
                                fontSize: 11,
                                fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],

                        if (analysis != null && analysis.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: JournalColors.accent.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: JournalColors.accent.withOpacity(0.15)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('COMBINED ANALYSIS',
                                  style: TextStyle(
                                    color: JournalColors.accent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8)),
                                const SizedBox(height: 6),
                                Text(analysis,
                                  style: const TextStyle(
                                    color: JournalColors.textSecondary,
                                    fontSize: 12,
                                    height: 1.55)),
                              ],
                            ),
                          ),
                        ],
                      ],
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

// ── Case Partner Tab ───────────────────────────────────────────────────────

class _CasePartnerTab extends StatefulWidget {
  final String caseId;
  final String caseName;
  const _CasePartnerTab({required this.caseId, required this.caseName});

  @override
  State<_CasePartnerTab> createState() => _CasePartnerTabState();
}

class _CasePartnerTabState extends State<_CasePartnerTab> {
  final _api = ApiService();
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool _loading = false;
  bool _loadingChat = true;
  String? _sessionId;
  String? _compressedSummary;
  bool _showCompressed = false;
  bool _wiring = false;
  Map<String, dynamic>? _wireResult;
  bool _showWire = false;

  static const _compressAt = 20;

  String get _greeting =>
    'Hey, I\'m up to speed on the case — "${widget.caseName}". What are you thinking? What do you need from me right now?';

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadSession() async {
    setState(() => _loadingChat = true);
    try {
      final res = await _api.detectiveChatLatestSession(widget.caseId);
      final saved = List<dynamic>.from(res['messages'] ?? []);
      if (mounted) {
        setState(() {
          _sessionId = res['session_id'] as String?;
          if (saved.isNotEmpty) {
            final summary = saved.cast<Map>().firstWhere(
              (m) => m['role'] == 'system-summary', orElse: () => <String, dynamic>{});
            if (summary.isNotEmpty) _compressedSummary = summary['content'] as String?;
            _messages = saved.map<Map<String, dynamic>>((m) => Map<String, dynamic>.from(m)).toList();
          } else {
            _messages = [{'role': 'assistant', 'content': _greeting}];
          }
          _loadingChat = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() {
        _messages = [{'role': 'assistant', 'content': _greeting}];
        _loadingChat = false;
      });
    }
  }

  Future<void> _send() async {
    final msg = _ctrl.text.trim();
    if (msg.isEmpty || _loading) return;
    _ctrl.clear();
    final history = List<Map<String, dynamic>>.from(_messages);
    setState(() {
      _messages = [..._messages, {'role': 'user', 'content': msg}];
      _loading = true;
    });
    _scrollToBottom();
    try {
      final rawHistory = history.length > 8 ? history.sublist(history.length - 8) : history;
      final res = await _api.detectiveChatSend(
        widget.caseId,
        message: msg,
        history: rawHistory,
        compressedContext: _compressedSummary,
      );
      final reply = res['response'] as String? ?? '';
      if (mounted) {
        setState(() => _messages = [..._messages, {'role': 'assistant', 'content': reply}]);
        _scrollToBottom();
      }
      // Persist to DB
      if (_sessionId != null) {
        _api.detectiveChatSaveMessages(widget.caseId, _sessionId!, [
          {'role': 'user', 'content': msg},
          {'role': 'assistant', 'content': reply},
        ]).catchError((_) {});
      }
      // Auto-compress at threshold
      if (_messages.length >= _compressAt && _compressedSummary == null) {
        final toCompress = _messages.length > 6 ? _messages.sublist(1, _messages.length - 5) : <Map<String, dynamic>>[];
        if (toCompress.length >= 4) {
          _api.detectiveChatCompress(widget.caseId, toCompress).then((res) {
            final summary = res['summary'] as String? ?? '';
            final sentinel = {'role': 'system-summary', 'content': summary};
            if (mounted) setState(() {
              _compressedSummary = summary;
              final tail = _messages.length > 6 ? _messages.sublist(_messages.length - 6) : _messages;
              _messages = [_messages.first, sentinel, ...tail];
            });
            if (_sessionId != null) {
              _api.detectiveChatSaveMessages(widget.caseId, _sessionId!, [sentinel]).catchError((_) {});
            }
          }).catchError((_) {});
        }
      }
    } catch (_) {
      if (mounted) setState(() => _messages = [
        ..._messages,
        {'role': 'assistant', 'content': 'Sorry, hit an error. Check your API key in Settings.'},
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newSession() async {
    try {
      final res = await _api.detectiveChatNewSession(widget.caseId);
      final newId = res['session_id'] as String?;
      if (newId != null) {
        await _api.detectiveChatSaveMessages(widget.caseId, newId, [
          {'role': 'assistant', 'content': _greeting}
        ]).catchError((_) {});
      }
      if (mounted) setState(() {
        _sessionId = newId;
        _compressedSummary = null;
        _showCompressed = false;
        _messages = [{'role': 'assistant', 'content': _greeting}];
        _showWire = false;
        _wireResult = null;
      });
    } catch (_) {}
  }

  Future<void> _dropWire() async {
    setState(() { _wiring = true; _showWire = true; _wireResult = null; });
    _scrollToBottom();
    try {
      final res = await _api.detectiveDropWire(widget.caseId);
      if (mounted) setState(() => _wireResult = res);
    } catch (_) {
      if (mounted) setState(() => _wireResult = {'error': true});
    } finally {
      if (mounted) setState(() => _wiring = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final extraCount = (_loading ? 1 : 0) + (_showWire ? 1 : 0);
    return Column(
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: JournalColors.border, width: 0.5)),
          ),
          child: Row(children: [
            Container(width: 8, height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF22C55E), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            const Text('Case Partner',
              style: TextStyle(
                color: JournalColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('AI · reads your case file · best friend mode',
                style: TextStyle(color: JournalColors.textMuted, fontSize: 10),
                overflow: TextOverflow.ellipsis)),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: _newSession,
              child: const Text('+ new chat',
                style: TextStyle(
                  color: JournalColors.accent, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),

        // ── Messages ─────────────────────────────────────────────────────────
        Expanded(
          child: _loadingChat
            ? const Center(child: CupertinoActivityIndicator())
            : ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + extraCount,
                itemBuilder: (ctx, i) {
                  if (i < _messages.length) return _buildMessage(_messages[i]);
                  final extraIdx = i - _messages.length;
                  if (_loading && extraIdx == 0) return _buildTypingIndicator();
                  return _buildWireResult();
                },
              ),
        ),

        // ── Input area ───────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: JournalColors.border, width: 0.5)),
          ),
          child: Column(children: [
            // Drop Wire button
            GestureDetector(
              onTap: _wiring ? null : _dropWire,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0x336366F1), Color(0x33A855F7)]),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x666366F1)),
                ),
                child: Text(
                  _wiring ? '📡 Dropping Wire…' : '📡 Drop a Wire',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _wiring ? JournalColors.textMuted : JournalColors.accent,
                    fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                ),
              ),
            ),
            // Text field + send
            Row(children: [
              Expanded(
                child: CupertinoTextField(
                  controller: _ctrl,
                  placeholder: 'Talk to your Case Partner…',
                  placeholderStyle: const TextStyle(color: JournalColors.textMuted, fontSize: 13),
                  style: const TextStyle(color: JournalColors.textPrimary, fontSize: 13),
                  maxLines: null, minLines: 1,
                  decoration: BoxDecoration(
                    color: const Color(0x0AFFFFFF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: JournalColors.border),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _loading ? null : _send,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _loading
                      ? const Color(0x336366F1)
                      : JournalColors.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(CupertinoIcons.arrow_up,
                    color: CupertinoColors.white, size: 16),
                ),
              ),
            ]),
          ]),
        ),
      ],
    );
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    final role = msg['role'] as String;
    final content = msg['content'] as String? ?? '';

    // Compressed summary sentinel
    if (role == 'system-summary') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: () => setState(() => _showCompressed = !_showCompressed),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: JournalColors.accent.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: JournalColors.accent.withOpacity(0.2)),
                ),
                child: Row(children: [
                  const Text('📋', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Earlier conversation compressed',
                      style: TextStyle(
                        color: JournalColors.accent, fontSize: 10, fontWeight: FontWeight.w500))),
                  Text(_showCompressed ? '▲ hide' : '▼ show',
                    style: const TextStyle(color: JournalColors.textMuted, fontSize: 10)),
                ]),
              ),
            ),
            if (_showCompressed)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: JournalColors.accent.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: JournalColors.accent.withOpacity(0.15)),
                ),
                child: Text(content,
                  style: const TextStyle(
                    color: JournalColors.textSecondary, fontSize: 12,
                    height: 1.6, fontStyle: FontStyle.italic)),
              ),
          ],
        ),
      );
    }

    final isUser = role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              Container(
                width: 28, height: 28,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFFA855F7)]),
                  shape: BoxShape.circle,
                ),
                child: const Center(child: Text('🕵️', style: TextStyle(fontSize: 13))),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser
                    ? JournalColors.accent.withOpacity(0.18)
                    : const Color(0x0DFFFFFF),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(14),
                    topRight: const Radius.circular(14),
                    bottomLeft: Radius.circular(isUser ? 14 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 14),
                  ),
                  border: Border.all(
                    color: isUser
                      ? JournalColors.accent.withOpacity(0.3)
                      : JournalColors.border),
                ),
                child: Text(content,
                  style: const TextStyle(
                    color: JournalColors.textPrimary, fontSize: 13, height: 1.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF6366F1), Color(0xFFA855F7)]),
              shape: BoxShape.circle,
            ),
            child: const Center(child: Text('🕵️', style: TextStyle(fontSize: 13))),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0x0DFFFFFF),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14), topRight: Radius.circular(14),
                bottomRight: Radius.circular(14), bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: JournalColors.border),
            ),
            child: const CupertinoActivityIndicator(radius: 7),
          ),
        ],
      ),
    );
  }

  Widget _buildWireResult() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JournalColors.accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JournalColors.accent.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Text('📡', style: TextStyle(fontSize: 16)),
            SizedBox(width: 8),
            Text('WIRE DROPPED — Case Briefing',
              style: TextStyle(
                color: JournalColors.accent, fontSize: 12,
                fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ]),
          const SizedBox(height: 10),
          if (_wireResult == null)
            const Text('Compiling full case intelligence…',
              style: TextStyle(color: JournalColors.textMuted, fontSize: 11))
          else if (_wireResult!['error'] == true)
            const Text('Wire failed. Check your API key in Settings.',
              style: TextStyle(color: Color(0xFFEF4444), fontSize: 12))
          else
            Text(_wireResult!['briefing'] as String? ?? '',
              style: const TextStyle(
                color: JournalColors.textPrimary, fontSize: 13, height: 1.7)),
        ],
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(label,
      style: TextStyle(
        color: color, fontSize: 10,
        fontWeight: FontWeight.w600, letterSpacing: 0.3)),
  );
}

class _TabPlaceholder extends StatelessWidget {
  final String tabName;
  const _TabPlaceholder({required this.tabName});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(CupertinoIcons.hammer, color: JournalColors.textMuted, size: 36),
      const SizedBox(height: 14),
      Text('$tabName — Coming Soon',
        style: const TextStyle(color: JournalColors.textSecondary, fontSize: 16)),
    ]),
  );
}
// ── Photos Tab ──────────────────────────────────────────────────────────────

class _PhotosTab extends StatefulWidget {
  final String caseId;
  final List<Map<String, dynamic>> uploads;
  final bool loading;
  final Future<void> Function(PlatformFile) onUpload;
  final Future<void> Function(Map<String, dynamic>) onDelete;

  const _PhotosTab({
    required this.caseId,
    required this.uploads,
    required this.loading,
    required this.onUpload,
    required this.onDelete,
  });

  @override
  State<_PhotosTab> createState() => _PhotosTabState();
}

class _PhotosTabState extends State<_PhotosTab> {
  bool _uploading = false;

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    setState(() => _uploading = true);
    await widget.onUpload(res.files.first);
    if (mounted) setState(() => _uploading = false);
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'done':    return '✓ analyzed';
      case 'failed':  return '✕ failed';
      case 'pending': return '⏳ pending';
      default:        return '… analyzing';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'done':   return const Color(0xFF22C55E);
      case 'failed': return const Color(0xFFEF4444);
      default:       return const Color(0xFFF59E0B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(
                onTap: _uploading ? null : _pick,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  decoration: BoxDecoration(
                    color: JournalColors.bgSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: JournalColors.accent.withOpacity(0.3), width: 1.5),
                  ),
                  child: _uploading
                    ? const Column(mainAxisSize: MainAxisSize.min, children: [
                        CupertinoActivityIndicator(radius: 12),
                        SizedBox(height: 10),
                        Text('Analyzing image…',
                          style: TextStyle(color: JournalColors.textMuted, fontSize: 12)),
                      ])
                    : const Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('📷', style: TextStyle(fontSize: 28)),
                        SizedBox(height: 6),
                        Text('Tap to upload photo',
                          style: TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 13, fontWeight: FontWeight.w600)),
                        SizedBox(height: 3),
                        Text('AI analyzes instantly · JPEG, PNG, WEBP',
                          style: TextStyle(color: JournalColors.textMuted, fontSize: 11)),
                      ]),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.loading)
                const Center(child: CupertinoActivityIndicator())
              else if (widget.uploads.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('🖼', style: TextStyle(fontSize: 36)),
                      SizedBox(height: 10),
                      Text('No photos yet',
                        style: TextStyle(
                          color: JournalColors.textSecondary, fontSize: 14)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
        if (!widget.loading && widget.uploads.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final u = widget.uploads[i];
                  final uid = u['id'].toString();
                  final status = u['analysis_status'] as String?;
                  final imgPath = u['image_url'] as String? ?? '';
                  final isEntry = u['source'] == 'entry';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: JournalColors.bgSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: JournalColors.border),
                    ),
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(10)),
                        child: SizedBox(
                          width: 72, height: 72,
                          child: imgPath.isNotEmpty
                            ? _AuthImage(path: imgPath)
                            : const Icon(CupertinoIcons.photo,
                                color: JournalColors.textMuted, size: 24),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(u['original_filename'] as String? ?? 'photo',
                            style: const TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 12, fontWeight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _statusColor(status).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(_statusLabel(status),
                              style: TextStyle(
                                color: _statusColor(status),
                                fontSize: 9, fontFamily: 'monospace')),
                          ),
                          if (u['ai_analysis'] != null) ...[
                            const SizedBox(height: 5),
                            Text(u['ai_analysis'] as String,
                              style: const TextStyle(
                                color: JournalColors.textSecondary,
                                fontSize: 11, height: 1.4),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                        ],
                      )),
                      if (!isEntry)
                        CupertinoButton(
                          padding: const EdgeInsets.all(12),
                          onPressed: () => showCupertinoDialog(
                            context: context,
                            builder: (_) => CupertinoAlertDialog(
                              title: const Text('Delete Photo'),
                              content: const Text('Remove this photo?'),
                              actions: [
                                CupertinoDialogAction(
                                  isDestructiveAction: true,
                                  onPressed: () {
                                    Navigator.pop(context);
                                    widget.onDelete(u);
                                  },
                                  child: const Text('Delete')),
                                CupertinoDialogAction(
                                  child: const Text('Cancel'),
                                  onPressed: () => Navigator.pop(context)),
                              ],
                            ),
                          ),
                          child: const Icon(CupertinoIcons.xmark,
                            color: Color(0xFFEF4444), size: 14),
                        ),
                    ]),
                  );
                },
                childCount: widget.uploads.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Gallery Tab ─────────────────────────────────────────────────────────────

class _GalleryTab extends StatefulWidget {
  final String caseId;
  final List<Map<String, dynamic>> uploads;
  final Future<void> Function(Map<String, dynamic>) onDelete;

  const _GalleryTab({
    required this.caseId,
    required this.uploads,
    required this.onDelete,
  });

  @override
  State<_GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends State<_GalleryTab> {
  Map<String, dynamic>? _lightbox;

  @override
  Widget build(BuildContext context) {
    if (widget.uploads.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('🖼', style: TextStyle(fontSize: 40)),
          SizedBox(height: 12),
          Text('No photos yet',
            style: TextStyle(
              color: JournalColors.textSecondary, fontSize: 14)),
          SizedBox(height: 4),
          Text('Upload some in the Photos tab',
            style: TextStyle(color: JournalColors.textMuted, fontSize: 12)),
        ]),
      );
    }

    return Stack(children: [
      CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final u = widget.uploads[i];
                  final status = u['analysis_status'] as String?;
                  final imgPath = u['image_url'] as String? ?? '';
                  final isEntry = u['source'] == 'entry';

                  Color statusColor() {
                    switch (status) {
                      case 'done':   return const Color(0xFF22C55E);
                      case 'failed': return const Color(0xFFEF4444);
                      default:       return const Color(0xFFF59E0B);
                    }
                  }
                  String statusLabel() {
                    switch (status) {
                      case 'done':    return '✓ analyzed';
                      case 'failed':  return '✕ failed';
                      case 'pending': return '⏳ pending';
                      default:        return '… analyzing';
                    }
                  }

                  return GestureDetector(
                    onTap: () => setState(() => _lightbox = u),
                    child: Container(
                      decoration: BoxDecoration(
                        color: JournalColors.bgSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: JournalColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Stack(children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(10)),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: imgPath.isNotEmpty
                                    ? _AuthImage(path: imgPath, fit: BoxFit.cover)
                                    : const Icon(CupertinoIcons.photo,
                                        color: JournalColors.textMuted, size: 28),
                                ),
                              ),
                              Positioned(
                                top: 6, right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xCC000000),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(statusLabel(),
                                    style: TextStyle(
                                      color: statusColor(),
                                      fontSize: 8, fontFamily: 'monospace')),
                                ),
                              ),
                            ]),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(children: [
                              Expanded(
                                child: Text(
                                  u['original_filename'] as String? ?? 'photo',
                                  style: const TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 11, fontWeight: FontWeight.w600),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                              if (!isEntry)
                                GestureDetector(
                                  onTap: () => showCupertinoDialog(
                                    context: context,
                                    builder: (_) => CupertinoAlertDialog(
                                      title: const Text('Delete Photo'),
                                      content: const Text('Remove this photo?'),
                                      actions: [
                                        CupertinoDialogAction(
                                          isDestructiveAction: true,
                                          onPressed: () {
                                            Navigator.pop(context);
                                            widget.onDelete(u);
                                          },
                                          child: const Text('Delete')),
                                        CupertinoDialogAction(
                                          child: const Text('Cancel'),
                                          onPressed: () => Navigator.pop(context)),
                                      ],
                                    ),
                                  ),
                                  child: const Icon(CupertinoIcons.xmark,
                                    color: Color(0xFFEF4444), size: 12),
                                ),
                            ]),
                          ),
                          if (u['ai_analysis'] != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                              child: Text(u['ai_analysis'] as String,
                                style: const TextStyle(
                                  color: JournalColors.textMuted,
                                  fontSize: 10, height: 1.4),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: widget.uploads.length,
              ),
            ),
          ),
        ],
      ),

      // Lightbox
      if (_lightbox != null)
        GestureDetector(
          onTap: () => setState(() => _lightbox = null),
          child: Container(
            color: const Color(0xEB000000),
            child: SafeArea(
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        _lightbox!['original_filename'] as String? ?? '',
                        style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => setState(() => _lightbox = null),
                      child: const Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: JournalColors.textMuted, size: 24),
                    ),
                  ]),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {},
                    child: _AuthImage(
                      path: _lightbox!['image_url'] as String? ?? '',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                if (_lightbox!['ai_analysis'] != null)
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xDD0C0C18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: JournalColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '— ${_lightbox!['analysis_label'] ?? 'AI Analysis'} —',
                            style: TextStyle(
                              color: JournalColors.accent,
                              fontSize: 9, fontFamily: 'monospace',
                              letterSpacing: 1.2)),
                          const SizedBox(height: 8),
                          Text(_lightbox!['ai_analysis'] as String,
                            style: const TextStyle(
                              color: JournalColors.textSecondary,
                              fontSize: 12, height: 1.6),
                            maxLines: 6, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
    ]);
  }
}

// ── Intelligence Tab ────────────────────────────────────────────────────────

class _IntelligenceTab extends StatefulWidget {
  final String caseId;
  const _IntelligenceTab({required this.caseId});
  @override
  State<_IntelligenceTab> createState() => _IntelligenceTabState();
}

class _IntelligenceTabState extends State<_IntelligenceTab> {
  final _api = ApiService();
  Map<String, dynamic>? _intel;
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _api.detectiveGetIntelligence(widget.caseId);
      if (mounted) setState(() { _intel = r; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final r = await _api.detectiveRefreshIntelligence(widget.caseId);
      if (mounted) setState(() => _intel = r);
    } catch (e) {
      if (mounted) _showErr(e.toString());
    }
    if (mounted) setState(() => _refreshing = false);
  }

  void _showErr(String msg) => showCupertinoDialog(
    context: context,
    builder: (_) => CupertinoAlertDialog(
      title: const Text('Error'),
      content: Text(msg),
      actions: [CupertinoDialogAction(
        child: const Text('OK'),
        onPressed: () => Navigator.pop(context))],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CupertinoActivityIndicator(),
        SizedBox(height: 10),
        Text('Loading intelligence brief…',
          style: TextStyle(color: JournalColors.textMuted, fontSize: 12)),
      ]));
    }

    final summary = _intel?['summary'] as String?;
    if (summary == null || summary.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🧠', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 16),
            const Text('No Intelligence Brief Yet',
              style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Text(
              'Drop a Wire to generate your first case intelligence brief. '
              'This brief persists between sessions — your Case Partner reads '
              'it instead of loading all raw entries every time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: JournalColors.textMuted, fontSize: 13, height: 1.7)),
            const SizedBox(height: 16),
            const Text(
              'After each wire drop, the brief auto-updates and gets '
              'injected into every Case Partner chat — saving 60–70% on AI tokens.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: JournalColors.textMuted, fontSize: 10,
                fontFamily: 'monospace', height: 1.6)),
          ]),
        ),
      );
    }

    final entryCount = _intel?['entry_count'] ?? 0;
    final wireCount  = _intel?['wire_count'] ?? 0;
    final rawDate    = _intel?['last_updated'] as String? ?? '';
    final lastUp     = rawDate.length >= 16
      ? rawDate.substring(0, 16).replaceAll('T', ' ')
      : rawDate;
    final tokensSaved = (summary.length / 4).ceil();

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                child: Text('🧠 Case Intelligence Brief',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _refreshing ? null : _refresh,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _refreshing
                      ? JournalColors.accent.withOpacity(0.1)
                      : JournalColors.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: JournalColors.accent.withOpacity(0.35)),
                  ),
                  child: _refreshing
                    ? const CupertinoActivityIndicator(radius: 7)
                    : const Text('⟳ Refresh',
                        style: TextStyle(
                          color: JournalColors.accent,
                          fontSize: 11, fontFamily: 'monospace')),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              '$entryCount entries · $wireCount wire drop${wireCount != 1 ? 's' : ''}'
              '${lastUp.isNotEmpty ? ' · last updated $lastUp' : ''}',
              style: const TextStyle(
                color: JournalColors.textMuted,
                fontSize: 10, fontFamily: 'monospace')),
            const SizedBox(height: 16),

            // Brief card
            Container(
              decoration: BoxDecoration(
                color: JournalColors.accent.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: JournalColors.accent.withOpacity(0.2)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  height: 4,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Color(0xFF6366F1), Color(0xFFA855F7), Color(0xFFEC4899)]),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(12)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(summary,
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 13, height: 1.8)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0x33000000),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(12)),
                    border: Border(
                      top: BorderSide(color: JournalColors.border)),
                  ),
                  child: Row(children: [
                    const Expanded(
                      child: Text(
                        'PERSISTENT BRIEF — auto-updates on wire drop',
                        style: TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 9, fontFamily: 'monospace')),
                    ),
                    Text('≈ $tokensSaved tokens saved per chat',
                      style: TextStyle(
                        color: JournalColors.accent.withOpacity(0.6),
                        fontSize: 9, fontFamily: 'monospace')),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),

            // Token savings callout
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF22C55E).withOpacity(0.15)),
              ),
              child: Row(children: [
                const Text('⚡', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Intelligence active — Case Partner reads this brief '
                    'instead of loading all $entryCount raw entries.'
                    '${entryCount > 10 ? ' Estimated ${(entryCount * 120 * 0.65).round()} tokens saved per conversation.' : ''}',
                    style: const TextStyle(
                      color: Color(0xCC22C55E),
                      fontSize: 11, fontFamily: 'monospace', height: 1.5)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ── Wires Tab ───────────────────────────────────────────────────────────────

class _WiresTab extends StatefulWidget {
  final String caseId;
  const _WiresTab({required this.caseId});
  @override
  State<_WiresTab> createState() => _WiresTabState();
}

class _WiresTabState extends State<_WiresTab> {
  final _api = ApiService();
  List<Map<String, dynamic>> _wires = [];
  bool _loading = true;
  bool _wiring  = false;
  int? _expanded;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _api.detectiveGetWireHistory(widget.caseId);
      if (mounted) setState(() {
        _wires = List<Map<String, dynamic>>.from(r);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _dropNew() async {
    setState(() => _wiring = true);
    try {
      final r = await _api.detectiveDropWire(widget.caseId);
      if (mounted) {
        final w = <String, dynamic>{
          'id': DateTime.now().millisecondsSinceEpoch,
          'briefing': r['briefing'],
          'created_at': DateTime.now().toIso8601String(),
        };
        setState(() { _wires = [w, ..._wires]; _expanded = 0; });
      }
    } catch (e) {
      if (mounted) showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Wire Failed'),
          content: Text(e.toString()),
          actions: [CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context))],
        ),
      );
    }
    if (mounted) setState(() => _wiring = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CupertinoActivityIndicator());

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('📡 Wire History',
                style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 17, fontWeight: FontWeight.w800)),
              Text(
                '${_wires.length} briefing${_wires.length != 1 ? 's' : ''} on file',
                style: const TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 10, fontFamily: 'monospace')),
            ]),
            const Spacer(),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _wiring ? null : _dropNew,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: _wiring ? null : const LinearGradient(
                    colors: [Color(0x406366F1), Color(0x40A855F7)]),
                  color: _wiring
                    ? JournalColors.accent.withOpacity(0.1)
                    : null,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: JournalColors.accent.withOpacity(0.4)),
                ),
                child: _wiring
                  ? const Row(mainAxisSize: MainAxisSize.min, children: [
                      CupertinoActivityIndicator(radius: 6),
                      SizedBox(width: 6),
                      Text('Dropping Wire…',
                        style: TextStyle(
                          color: JournalColors.accent, fontSize: 11,
                          fontFamily: 'monospace')),
                    ])
                  : const Text('📡 Drop New Wire',
                      style: TextStyle(
                        color: JournalColors.accent, fontSize: 11,
                        fontFamily: 'monospace', fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),

      if (_wires.isEmpty)
        const SliverFillRemaining(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('📡', style: TextStyle(fontSize: 40)),
              SizedBox(height: 14),
              Text('No Wires Dropped Yet',
                style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 15, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Drop a Wire to get a full case briefing — your Case Partner '
                  'reads everything and tells you exactly where things stand.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 13, height: 1.6)),
              ),
            ]),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final w = _wires[i];
                final isOpen = _expanded == i;
                final briefing = w['briefing'] as String? ?? '';
                final raw = w['created_at'] as String? ?? '';
                final dateStr = raw.length >= 16
                  ? raw.substring(0, 16).replaceAll('T', ' ')
                  : raw;

                return GestureDetector(
                  onTap: () => setState(
                    () => _expanded = isOpen ? null : i),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: JournalColors.bgSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isOpen
                          ? JournalColors.accent.withOpacity(0.3)
                          : JournalColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                          child: Row(children: [
                            const Text('📡',
                              style: TextStyle(fontSize: 16)),
                            const SizedBox(width: 10),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Wire Drop #${_wires.length - i}',
                                  style: const TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                                if (dateStr.isNotEmpty)
                                  Text(dateStr,
                                    style: const TextStyle(
                                      color: JournalColors.textMuted,
                                      fontSize: 10,
                                      fontFamily: 'monospace')),
                              ],
                            )),
                            const SizedBox(width: 8),
                            Text(isOpen ? '▲' : '▼',
                              style: const TextStyle(
                                color: JournalColors.textMuted,
                                fontSize: 12)),
                          ]),
                        ),
                        if (isOpen) ...[
                          const Divider(
                            height: 0.5, thickness: 0.5,
                            color: JournalColors.border),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(briefing,
                              style: const TextStyle(
                                color: JournalColors.textPrimary,
                                fontSize: 13, height: 1.8)),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
              childCount: _wires.length,
            ),
          ),
        ),
    ]);
  }
}

// ── Export Tab ──────────────────────────────────────────────────────────────

const _kExportTones = [
  (
    id: 'case_file',
    icon: '🗂',
    label: 'Case File',
    tag: 'INVESTIGATIVE',
    tagColor: Color(0xFFEF4444),
    desc: 'Full forensic report. Every entry, wire drop, photo, and AI analysis.',
    accentColor: Color(0xFF6366F1),
  ),
  (
    id: 'conversation',
    icon: '💬',
    label: 'The Conversation',
    tag: 'PERSONAL',
    tagColor: Color(0xFFA855F7),
    desc: 'Written as a personal statement — the pattern, the evidence, your decision.',
    accentColor: Color(0xFFA855F7),
  ),
  (
    id: 'personal_record',
    icon: '📋',
    label: 'Personal Record',
    tag: 'ARCHIVAL',
    tagColor: Color(0xFF38BDF8),
    desc: 'Clean, readable account for therapy, legal consultation, or long-term archives.',
    accentColor: Color(0xFF38BDF8),
  ),
];

class _ExportTab extends StatefulWidget {
  final String caseId;
  final String caseName;
  const _ExportTab({required this.caseId, required this.caseName});
  @override
  State<_ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends State<_ExportTab> {
  final _api = ApiService();
  String _tone = 'case_file';
  bool _exporting = false;
  String? _statusMsg;
  bool _isError = false;

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _statusMsg = null;
      _isError = false;
    });
    try {
      final bytes = await _api.detectiveExport(widget.caseId, _tone);
      final dir   = await getTemporaryDirectory();
      final file  = File(
        '${dir.path}/case_report_${widget.caseId}_$_tone.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Case Report — ${widget.caseName}',
      );
      if (mounted) setState(() {
        _statusMsg = 'PDF ready — use the share sheet to save or send.';
        _isError = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _statusMsg = e.toString();
        _isError = true;
      });
    }
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Export Case Report',
              style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'Choose a format, then generate a PDF to share or save.',
              style: TextStyle(
                color: JournalColors.textMuted, fontSize: 12)),
            const SizedBox(height: 20),

            ..._kExportTones.map((t) {
              final selected = _tone == t.id;
              return GestureDetector(
                onTap: () => setState(() => _tone = t.id),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: selected
                      ? t.accentColor.withOpacity(0.08)
                      : JournalColors.bgSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                        ? t.accentColor.withOpacity(0.4)
                        : JournalColors.border,
                      width: selected ? 1.5 : 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.icon, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(t.label,
                              style: const TextStyle(
                                color: JournalColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: t.tagColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: t.tagColor.withOpacity(0.3)),
                              ),
                              child: Text(t.tag,
                                style: TextStyle(
                                  color: t.tagColor,
                                  fontSize: 9, fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700)),
                            ),
                          ]),
                          const SizedBox(height: 5),
                          Text(t.desc,
                            style: const TextStyle(
                              color: JournalColors.textMuted,
                              fontSize: 12, height: 1.5)),
                        ],
                      )),
                      if (selected)
                        Icon(CupertinoIcons.checkmark_circle_fill,
                          color: t.accentColor, size: 18),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 16),

            if (_statusMsg != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: (_isError
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF22C55E)).withOpacity(0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (_isError
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF22C55E)).withOpacity(0.2)),
                ),
                child: Row(children: [
                  Text(_isError ? '⚠' : '✓',
                    style: TextStyle(
                      color: _isError
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF22C55E),
                      fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_statusMsg!,
                      style: TextStyle(
                        color: _isError
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF22C55E),
                        fontSize: 12))),
                ]),
              ),

            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: JournalColors.accent,
                borderRadius: BorderRadius.circular(10),
                padding: const EdgeInsets.symmetric(vertical: 14),
                onPressed: _exporting ? null : _export,
                child: _exporting
                  ? const Row(mainAxisSize: MainAxisSize.min, children: [
                      CupertinoActivityIndicator(
                        radius: 8, color: Colors.white),
                      SizedBox(width: 10),
                      Text('Generating PDF…',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                    ])
                  : const Text('Generate PDF & Share',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
            ),

            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: JournalColors.bgSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: JournalColors.border),
              ),
              child: const Text(
                'Requires weasyprint on the server.\n'
                'If export fails: pip install weasyprint --break-system-packages',
                style: TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 10, fontFamily: 'monospace', height: 1.6)),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ── Research Tab ────────────────────────────────────────────────────────────

class _ResearchTab extends StatefulWidget {
  final String caseId;
  const _ResearchTab({required this.caseId});
  @override
  State<_ResearchTab> createState() => _ResearchTabState();
}

class _ResearchTabState extends State<_ResearchTab> {
  final _api = ApiService();
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  int? _expanded;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _api.detectiveGetResearch(widget.caseId);
      if (mounted) setState(() {
        _reports = List<Map<String, dynamic>>.from(r);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openModal() => showCupertinoModalPopup(
    context: context,
    builder: (ctx) => DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: _ResearchModal(
        caseId: widget.caseId,
        onCompleted: (report) {
          if (mounted) setState(() =>
            _reports = [Map<String, dynamic>.from(report), ..._reports]);
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CupertinoActivityIndicator());

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('🔍 Research Reports',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 17, fontWeight: FontWeight.w800)),
                Text('Saved to case log automatically',
                  style: TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 10, fontFamily: 'monospace')),
              ]),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _openModal,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: JournalColors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: JournalColors.accent.withOpacity(0.35)),
                ),
                child: const Text('🔍 Run Agent',
                  style: TextStyle(
                    color: JournalColors.accent, fontSize: 11,
                    fontFamily: 'monospace', fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),

      if (_reports.isEmpty)
        const SliverFillRemaining(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('🔍', style: TextStyle(fontSize: 40)),
              SizedBox(height: 12),
              Text('No Research Reports Yet',
                style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 15, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Tap "Run Agent" to deploy the research agent.\n'
                  'Reports are saved here and added to your case context.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 13, height: 1.6)),
              ),
            ]),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final r = _reports[i];
                final isOpen = _expanded == i;
                final content = r['content'] as String? ?? '';
                final subjectMatch =
                  RegExp(r'Subject:\s*(.+?)\n').firstMatch(content);
                final subject =
                  subjectMatch?.group(1) ?? 'Research Report';
                final raw = r['created_at'] as String? ?? '';
                final dateStr = raw.length >= 10
                  ? raw.substring(0, 10)
                  : raw;

                return GestureDetector(
                  onTap: () => setState(
                    () => _expanded = isOpen ? null : i),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: JournalColors.bgSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: JournalColors.accent.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                          child: Row(children: [
                            const Text('🔍',
                              style: TextStyle(fontSize: 16)),
                            const SizedBox(width: 10),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(subject,
                                  style: const TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                                if (!isOpen)
                                  Text(
                                    content.length > 100
                                      ? '${content.substring(0, 100)}…'
                                      : content,
                                    style: const TextStyle(
                                      color: JournalColors.textMuted,
                                      fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ],
                            )),
                            if (dateStr.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(dateStr,
                                  style: const TextStyle(
                                    color: JournalColors.textMuted,
                                    fontSize: 10,
                                    fontFamily: 'monospace')),
                              ),
                            Text(isOpen ? '▲' : '▼',
                              style: const TextStyle(
                                color: JournalColors.textMuted,
                                fontSize: 12)),
                          ]),
                        ),
                        if (isOpen) ...[
                          const Divider(
                            height: 0.5, thickness: 0.5,
                            color: JournalColors.border),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0x4D000000),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(content,
                                style: const TextStyle(
                                  color: JournalColors.textSecondary,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  height: 1.8)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
              childCount: _reports.length,
            ),
          ),
        ),
    ]);
  }
}

// ── Research Run Modal ──────────────────────────────────────────────────────

class _ResearchModal extends StatefulWidget {
  final String caseId;
  final void Function(Map<String, dynamic>) onCompleted;
  const _ResearchModal({required this.caseId, required this.onCompleted});
  @override
  State<_ResearchModal> createState() => _ResearchModalState();
}

class _ResearchModalState extends State<_ResearchModal> {
  final _api          = ApiService();
  final _subjectCtrl  = TextEditingController();
  final _contextCtrl  = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _employerCtrl = TextEditingController();
  final _relCtrl      = TextEditingController();
  final _ageCtrl      = TextEditingController();

  bool _loading = false;
  String? _error;
  String _step = 'form'; // form | running | result
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _subjectCtrl.dispose(); _contextCtrl.dispose();
    _locationCtrl.dispose(); _employerCtrl.dispose();
    _relCtrl.dispose(); _ageCtrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_subjectCtrl.text.trim().isEmpty) return;
    setState(() { _step = 'running'; _loading = true; _error = null; });
    final idents = <String, dynamic>{};
    if (_locationCtrl.text.trim().isNotEmpty)
      idents['location'] = _locationCtrl.text.trim();
    if (_employerCtrl.text.trim().isNotEmpty)
      idents['employer'] = _employerCtrl.text.trim();
    if (_relCtrl.text.trim().isNotEmpty)
      idents['relationship'] = _relCtrl.text.trim();
    if (_ageCtrl.text.trim().isNotEmpty)
      idents['age_range'] = _ageCtrl.text.trim();
    try {
      final r = await _api.detectiveRunResearch(widget.caseId, {
        'subject': _subjectCtrl.text.trim(),
        if (_contextCtrl.text.trim().isNotEmpty)
          'context': _contextCtrl.text.trim(),
        if (idents.isNotEmpty) 'identifiers': idents,
        'search_options': ['court', 'business', 'social', 'news', 'licenses'],
      });
      if (mounted) setState(() { _result = r; _step = 'result'; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _step = 'form'; });
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _tf(String label, TextEditingController ctrl,
      {String ph = '', int lines = 1}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(),
        style: const TextStyle(
          color: JournalColors.textMuted, fontSize: 10,
          fontFamily: 'monospace', letterSpacing: 0.8)),
      const SizedBox(height: 6),
      CupertinoTextField(
        controller: ctrl,
        placeholder: ph,
        minLines: 1, maxLines: lines == 1 ? 1 : 5,
        style: const TextStyle(
          color: JournalColors.textPrimary, fontSize: 13),
        placeholderStyle: const TextStyle(
          color: JournalColors.textMuted, fontSize: 13),
        decoration: BoxDecoration(
          color: JournalColors.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: JournalColors.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: JournalColors.bgBase,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 16),
          width: 38, height: 4,
          decoration: BoxDecoration(
            color: JournalColors.border,
            borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Text('🔍', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Research Agent',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15, fontWeight: FontWeight.w800)),
                Text('Searches public web sources',
                  style: TextStyle(
                    color: JournalColors.textMuted, fontSize: 11)),
              ]),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                style: TextStyle(
                  color: JournalColors.textMuted, fontSize: 14)),
            ),
          ]),
        ),
        const SizedBox(height: 4),
        const Divider(height: 1, color: JournalColors.border),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _step == 'running'
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CupertinoActivityIndicator(radius: 16),
                      SizedBox(height: 16),
                      Text('Running research agent…',
                        style: TextStyle(
                          color: JournalColors.textMuted, fontSize: 13)),
                      SizedBox(height: 6),
                      Text('This may take 30–60 seconds',
                        style: TextStyle(
                          color: JournalColors.textMuted, fontSize: 11)),
                    ]),
                  ),
                )
              : _step == 'result'
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withOpacity(0.07),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF22C55E).withOpacity(0.2)),
                      ),
                      child: const Text(
                        '✓ Research complete — saved to your investigation log',
                        style: TextStyle(
                          color: Color(0xFF86EFAC), fontSize: 12)),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0x4D000000),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: JournalColors.border),
                      ),
                      child: Text(_result?['report'] as String? ?? '',
                        style: const TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 12, fontFamily: 'monospace', height: 1.8)),
                    ),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withOpacity(0.3)),
                        ),
                        child: Text('⚠️ $_error',
                          style: const TextStyle(
                            color: Color(0xFFFCA5A5), fontSize: 12)),
                      ),
                    ],
                    _tf('Subject Name *', _subjectCtrl,
                      ph: 'e.g. John Smith'),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: JournalColors.accent.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: JournalColors.accent.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🎯 IDENTITY ANCHORS',
                            style: TextStyle(
                              color: JournalColors.accent, fontSize: 10,
                              fontFamily: 'monospace')),
                          const SizedBox(height: 4),
                          const Text(
                            'Helps find the RIGHT person, not just anyone with this name',
                            style: TextStyle(
                              color: JournalColors.textMuted, fontSize: 11)),
                          const SizedBox(height: 14),
                          _tf('City / Location', _locationCtrl,
                            ph: 'e.g. Austin, TX'),
                          const SizedBox(height: 10),
                          _tf('Employer / Organization', _employerCtrl,
                            ph: 'e.g. Acme Corp'),
                          const SizedBox(height: 10),
                          _tf('Relationship to You', _relCtrl,
                            ph: 'e.g. ex-partner, coworker'),
                          const SizedBox(height: 10),
                          _tf('Approx. Age / Age Range', _ageCtrl,
                            ph: 'e.g. mid-30s, born ~1990'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _tf('Additional Context (optional)', _contextCtrl,
                      ph: 'e.g. claims to be a contractor, drives a blue truck',
                      lines: 3),
                  ]),
          ),
        ),

        Container(
          padding: EdgeInsets.fromLTRB(
            20, 12, 20,
            12 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: JournalColors.border))),
          child: _step == 'result'
            ? SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: JournalColors.accent,
                  borderRadius: BorderRadius.circular(10),
                  onPressed: () {
                    if (_result != null) widget.onCompleted(_result!);
                    Navigator.pop(context);
                  },
                  child: const Text('✓ Done',
                    style: TextStyle(
                      color: Colors.white, fontSize: 14,
                      fontWeight: FontWeight.w700)),
                ),
              )
            : SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: _subjectCtrl.text.trim().isNotEmpty
                    ? JournalColors.accent
                    : JournalColors.accent.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                  onPressed: (_subjectCtrl.text.trim().isEmpty || _loading)
                    ? null : _run,
                  child: const Text('🔍 Run Agent',
                    style: TextStyle(
                      color: Colors.white, fontSize: 14,
                      fontWeight: FontWeight.w700)),
                ),
              ),
        ),
      ]),
    );
  }
}

// ── Settings Tab ────────────────────────────────────────────────────────────

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();
  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  final _api          = ApiService();
  final _nameCtrl     = TextEditingController();
  final _pronounsCtrl = TextEditingController();
  final _contextCtrl  = TextEditingController();
  bool _loading = true;
  bool _saving  = false;
  bool _saved   = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pronounsCtrl.dispose();
    _contextCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _api.detectiveGetSettings();
      if (mounted) {
        _nameCtrl.text     = r['investigator_name']     as String? ?? '';
        _pronounsCtrl.text = r['investigator_pronouns'] as String? ?? '';
        _contextCtrl.text  = r['background_context']   as String? ?? '';
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; _saved = false; });
    try {
      await _api.detectiveSaveSettings({
        'investigator_name':     _nameCtrl.text.trim(),
        'investigator_pronouns': _pronounsCtrl.text.trim(),
        'background_context':    _contextCtrl.text.trim(),
      });
      if (mounted) {
        setState(() { _saved = true; _saving = false; });
        await Future.delayed(const Duration(milliseconds: 2500));
        if (mounted) setState(() => _saved = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showCupertinoDialog(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Save Failed'),
            content: Text(e.toString()),
            actions: [CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context))],
          ),
        );
      }
    }
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(t.toUpperCase(),
      style: const TextStyle(
        color: JournalColors.textMuted, fontSize: 10,
        fontFamily: 'monospace', letterSpacing: 0.8)),
  );

  Widget _tf(TextEditingController c,
      {String ph = '', int maxLines = 1}) =>
    CupertinoTextField(
      controller: c,
      placeholder: ph,
      minLines: 1, maxLines: maxLines,
      style: const TextStyle(
        color: JournalColors.textPrimary, fontSize: 13),
      placeholderStyle: const TextStyle(
        color: JournalColors.textMuted, fontSize: 13),
      decoration: BoxDecoration(
        color: JournalColors.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: JournalColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CupertinoActivityIndicator());

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('⚙️ Detective Settings',
              style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
              'Injected into all AI photo analyses and case partner conversations '
              'so the AI knows who\'s who.',
              style: TextStyle(
                color: JournalColors.textMuted, fontSize: 13, height: 1.6)),
            const SizedBox(height: 28),

            _label('Your Real Name'),
            _tf(_nameCtrl, ph: 'e.g. Alex'),
            const SizedBox(height: 4),
            const Text(
              'Used in photo analysis so the AI knows you are never a participant '
              'in screenshots unless explicitly mentioned.',
              style: TextStyle(
                color: JournalColors.textMuted, fontSize: 11, height: 1.6)),

            const SizedBox(height: 20),
            _label('Your Pronouns (optional)'),
            SizedBox(
              width: 200,
              child: _tf(_pronounsCtrl, ph: 'e.g. he/him')),

            const SizedBox(height: 20),
            _label('Background Context (optional)'),
            _tf(_contextCtrl,
              ph: 'e.g. I am documenting an abusive relationship. '
                  'The subject has a history of manipulation.',
              maxLines: 4),
            const SizedBox(height: 4),
            const Text(
              'Injected into photo analysis and AI chat. Keep it concise.',
              style: TextStyle(
                color: JournalColors.textMuted, fontSize: 11, height: 1.6)),

            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: _saved
                  ? const Color(0x4D10B981)
                  : _saving
                    ? JournalColors.accent.withOpacity(0.4)
                    : JournalColors.accent,
                borderRadius: BorderRadius.circular(10),
                padding: const EdgeInsets.symmetric(vertical: 14),
                onPressed: _saving ? null : _save,
                child: _saving
                  ? const CupertinoActivityIndicator(
                      radius: 8, color: Colors.white)
                  : Text(_saved ? '✓ Saved' : 'Save Settings',
                      style: const TextStyle(
                        color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
            ),

            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: JournalColors.accent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: JournalColors.accent.withOpacity(0.15)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How this works',
                    style: TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 12, fontWeight: FontWeight.w700)),
                  SizedBox(height: 8),
                  Text(
                    'When you attach photos to a log entry and run Combined Analysis, '
                    'the AI is told exactly who you are and who the case subject is. '
                    'Instead of "the gray bubble sender," it will say your real name '
                    '— using the names you\'ve configured here.',
                    style: TextStyle(
                      color: JournalColors.textMuted,
                      fontSize: 12, height: 1.7)),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ]),
        ),
      ),
    ]);
  }
}