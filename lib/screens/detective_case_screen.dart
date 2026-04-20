// lib/screens/detective_case_screen.dart
//
// Case workspace — scrollable tab bar.
// Log tab: fully built with photo attachments + thumbnails.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';

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
      navigationBar: CupertinoNavigationBar(
        middle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 7, height: 7,
              decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Flexible(
              child: Text(widget.caseData['title'] ?? 'Case',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: JournalColors.textPrimary, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        backgroundColor: JournalColors.bgBase.withOpacity(0.92),
        border: const Border(bottom: BorderSide(color: JournalColors.border, width: 0.5)),
      ),
      child: Column(
        children: [
          // Tab bar
          Container(
            height: 44,
            decoration: const BoxDecoration(
              color: JournalColors.bgSurface,
              border: Border(bottom: BorderSide(color: JournalColors.border, width: 0.5)),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _kTabs.length,
              itemBuilder: (_, i) {
                final selected = _tabIndex == i;
                return GestureDetector(
                  onTap: () => setState(() => _tabIndex = i),
                  child: Container(
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
              },
            ),
          ),
          Expanded(child: _buildTab()),
        ],
      ),
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
                          child: Text(entry['content'] ?? '',
                            maxLines: expanded ? null : 3,
                            overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: JournalColors.textPrimary, fontSize: 13, height: 1.55)),
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