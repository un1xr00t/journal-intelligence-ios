// lib/screens/detective_case_screen.dart
//
// Case workspace — scrollable tab bar.
// Log tab: fully built with photo attachments + thumbnails.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Divider;

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

class _AuthImage extends StatelessWidget {
  final String path;   // relative path e.g. /api/detective/cases/1/entries/2/photos/3/image
  final BoxFit fit;

  const _AuthImage({required this.path, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final token = ApiService().accessToken ?? '';
    return Image.network(
      '${ApiService.baseUrl}$path',
      fit: fit,
      headers: {'Authorization': 'Bearer $token'},
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : const Center(child: CupertinoActivityIndicator()),
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(CupertinoIcons.photo, color: JournalColors.textMuted, size: 20),
      ),
    );
  }
}

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
                    onTap: () => setState(() => _tabIndex = i),
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
        );
      case 1:
        return _CasePartnerTab(
          caseId: _caseId,
          caseName: widget.caseData['title'] as String? ?? 'Case',
        );
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