import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

const _kSuggestedFolders = <({String name, String icon, Color color})>[
  (name: 'Medical & Health', icon: '🏥', color: Color(0xFFEF4444)),
  (name: 'School & Education', icon: '🏫', color: JournalColors.accent),
  (name: 'Daily Care', icon: '🧸', color: Color(0xFF10B981)),
  (name: 'Neglect', icon: '🧹', color: JournalColors.orange),
  (name: 'Financial Support', icon: '💰', color: Color(0xFFF59E0B)),
  (name: 'Activities', icon: '⚽', color: Color(0xFF8B5CF6)),
  (name: 'Communications', icon: '📞', color: Color(0xFF06B6D4)),
];

const _kQuickEntries =
    <({String label, String icon, String title, String folderHint})>[
  (
    label: 'Morning meds',
    icon: '💊',
    title: 'Gave morning medication',
    folderHint: 'Daily Care',
  ),
  (
    label: 'School dropoff',
    icon: '🎒',
    title: 'Got ready and handled school dropoff',
    folderHint: 'School & Education',
  ),
  (
    label: 'Meal prep',
    icon: '🍽',
    title: 'Prepared and served a meal',
    folderHint: 'Daily Care',
  ),
  (
    label: 'Appointment',
    icon: '🩺',
    title: 'Handled a medical appointment',
    folderHint: 'Medical & Health',
  ),
  (
    label: 'Bath time',
    icon: '🛁',
    title: 'Handled bath and bedtime routine',
    folderHint: 'Daily Care',
  ),
  (
    label: 'Errands',
    icon: '🛒',
    title: 'Handled errands and transportation',
    folderHint: 'Activities',
  ),
];

String _proofVaultExtensionLabel(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot <= 0 || dot == filename.length - 1) return 'IMG';
  return filename.substring(dot + 1).toUpperCase();
}

class ProofVaultScreen extends StatefulWidget {
  const ProofVaultScreen({super.key});

  @override
  State<ProofVaultScreen> createState() => _ProofVaultScreenState();
}

class _ProofVaultScreenState extends State<ProofVaultScreen> {
  final _api = ApiService();

  bool _loading = true;
  bool _summarizing = false;
  bool _exportingPdf = false;
  bool _exportingZip = false;
  String? _error;
  String? _summaryError;
  List<Map<String, dynamic>> _folders = [];
  Map<String, dynamic>? _selectedFolder;
  Map<String, dynamic>? _cachedSummary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final folders = await _api.vaultGetFolders();
      final cached = await _api.vaultGetCachedSummary();
      if (!mounted) return;
      setState(() {
        _folders = List<Map<String, dynamic>>.from(folders);
        _cachedSummary = cached['cached'] == true ? cached : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _createFolder() async {
    final form = await showCupertinoModalPopup<_FolderFormData>(
      context: context,
      builder: (context) => const _FolderSheet(),
    );
    if (form == null) return;

    try {
      final created = await _api.vaultCreateFolder(
        name: form.name.trim(),
        icon: form.icon,
        color: _colorToHex(form.color),
        description:
            form.description.trim().isEmpty ? null : form.description.trim(),
      );
      if (!mounted) return;
      setState(() {
        _folders = [..._folders, created];
      });
    } catch (e) {
      _showError('Could not create folder', e);
    }
  }

  Future<void> _deleteFolder(Map<String, dynamic> folder) async {
    final confirmed = await _confirm(
      'Delete "${folder['name']}"?',
      'This removes the folder and all of its entries.',
    );
    if (confirmed != true) return;

    try {
      await _api.vaultDeleteFolder(folder['id'].toString());
      if (!mounted) return;
      setState(() {
        _folders = _folders
            .where((f) => f['id'].toString() != folder['id'].toString())
            .toList();
        if (_selectedFolder?['id'].toString() == folder['id'].toString()) {
          _selectedFolder = null;
        }
      });
    } catch (e) {
      _showError('Could not delete folder', e);
    }
  }

  Future<void> _openQuickEntry(
      ({
        String label,
        String icon,
        String title,
        String folderHint
      }) preset) async {
    if (_folders.isEmpty) return;
    final payload = await showCupertinoModalPopup<_QuickLogData>(
      context: context,
      builder: (context) => _QuickLogSheet(
        folders: _folders,
        preset: preset,
      ),
    );
    if (payload == null) return;

    try {
      await _api.vaultCreateItem(payload.folderId, {
        'title': payload.title.trim(),
        'notes': payload.notes.trim().isEmpty ? null : payload.notes.trim(),
        'item_date': payload.itemDate,
      });
      if (!mounted) return;
      setState(() {
        _folders = _folders.map((folder) {
          if (folder['id'].toString() != payload.folderId) return folder;
          return {
            ...folder,
            'item_count': ((folder['item_count'] as num?) ?? 0) + 1,
          };
        }).toList();
        _cachedSummary = null;
      });
    } catch (e) {
      _showError('Could not add quick log', e);
    }
  }

  Future<void> _generateFullSummary({bool force = false}) async {
    setState(() {
      _summarizing = true;
      _summaryError = null;
    });
    try {
      final result = await _api.vaultGenerateSummary(force: force);
      if (!mounted) return;
      setState(() {
        _cachedSummary = result;
        _summarizing = false;
      });
      _openSummary(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _summarizing = false;
        _summaryError = e.toString();
      });
    }
  }

  void _openSummary(Map<String, dynamic> summary) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => _SummarySheet(
        title: 'Vault Summary',
        summary: summary['summary']?.toString() ?? '',
        meta: summary,
      ),
    );
  }

  Future<void> _exportProofVaultPdf() async {
    if (_exportingPdf || _folders.isEmpty) return;
    setState(() => _exportingPdf = true);
    try {
      final backup = await _loadBackupData();
      final bytes = _buildProofVaultPdf(backup);
      final dir = await getTemporaryDirectory();
      final filename = _backupFilename('pdf');
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Proof Vault Backup',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Could not back up Proof Vault', e);
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _exportProofVaultZip() async {
    if (_exportingZip || _folders.isEmpty) return;
    setState(() => _exportingZip = true);
    try {
      final backup = await _loadBackupData();
      final bytes = _buildProofVaultWebsiteZip(backup);
      final dir = await getTemporaryDirectory();
      final filename = _backupFilename('zip');
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/zip')],
        subject: 'Proof Vault Backup',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Could not back up Proof Vault', e);
    } finally {
      if (mounted) setState(() => _exportingZip = false);
    }
  }

  Future<_VaultBackup> _loadBackupData() async {
    final folders = <_VaultBackupFolder>[];
    for (var folderIndex = 0; folderIndex < _folders.length; folderIndex += 1) {
      final folder = _folders[folderIndex];
      final itemsRaw = await _api.vaultGetFolderItems(folder['id'].toString());
      final items = <_VaultBackupItem>[];
      for (final itemRaw in itemsRaw) {
        final item = Map<String, dynamic>.from(itemRaw as Map);
        final photos = <_VaultBackupPhoto>[];
        for (final photoRaw in List<dynamic>.from(item['photos'] ?? [])) {
          final photo = Map<String, dynamic>.from(photoRaw as Map);
          final photoId = photo['id'].toString();
          final itemId = item['id'].toString();
          final filename = photo['original_filename']?.toString();
          final bytes = await _api.fetchImageBytes(
            '/api/vault/items/$itemId/photos/$photoId/image',
          );
          photos.add(
            _VaultBackupPhoto(
              id: photoId,
              filename: _safePhotoFilename(filename, photoId),
              bytes: Uint8List.fromList(bytes),
            ),
          );
        }
        items.add(
          _VaultBackupItem(
            id: item['id'].toString(),
            title: item['title']?.toString() ?? 'Untitled',
            notes: item['notes']?.toString() ?? '',
            itemDate: item['item_date']?.toString(),
            photos: photos,
          ),
        );
      }
      folders.add(
        _VaultBackupFolder(
          id: folder['id'].toString(),
          name: folder['name']?.toString() ?? 'Folder ${folderIndex + 1}',
          description: folder['description']?.toString() ?? '',
          icon: folder['icon']?.toString() ?? '',
          items: items,
        ),
      );
    }
    return _VaultBackup(
      generatedAt: DateTime.now(),
      folders: folders,
    );
  }

  List<int> _buildProofVaultWebsiteZip(_VaultBackup backup) {
    final archive = Archive();
    final manifest = backup.toJson();
    final manifestBytes =
        utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest));
    final indexBytes = utf8.encode(_buildProofVaultHtml(backup));
    archive.addFile(
      ArchiveFile(
        'manifest.json',
        manifestBytes.length,
        manifestBytes,
      ),
    );
    archive.addFile(
      ArchiveFile(
        'index.html',
        indexBytes.length,
        indexBytes,
      ),
    );

    for (var folderIndex = 0;
        folderIndex < backup.folders.length;
        folderIndex += 1) {
      final folder = backup.folders[folderIndex];
      final folderPath =
          '${(folderIndex + 1).toString().padLeft(2, '0')}-${_slug(folder.name)}';
      archive.addFile(
        ArchiveFile(
          '$folderPath/folder.txt',
          utf8.encode(folder.textSummary).length,
          utf8.encode(folder.textSummary),
        ),
      );
      for (var itemIndex = 0; itemIndex < folder.items.length; itemIndex += 1) {
        final item = folder.items[itemIndex];
        final itemPath =
            '$folderPath/${(itemIndex + 1).toString().padLeft(2, '0')}-${_slug(item.title)}';
        archive.addFile(
          ArchiveFile(
            '$itemPath/entry.txt',
            utf8.encode(item.textSummary).length,
            utf8.encode(item.textSummary),
          ),
        );
        for (var photoIndex = 0;
            photoIndex < item.photos.length;
            photoIndex += 1) {
          final photo = item.photos[photoIndex];
          final photoPath =
              '$itemPath/photos/${(photoIndex + 1).toString().padLeft(2, '0')}-${photo.filename}';
          archive
              .addFile(ArchiveFile(photoPath, photo.bytes.length, photo.bytes));
        }
      }
    }

    return ZipEncoder().encode(archive)!;
  }

  String _buildProofVaultHtml(_VaultBackup backup) {
    final buffer = StringBuffer()
      ..writeln('<!doctype html>')
      ..writeln('<html lang="en">')
      ..writeln('<head>')
      ..writeln('<meta charset="utf-8">')
      ..writeln(
          '<meta name="viewport" content="width=device-width, initial-scale=1">')
      ..writeln('<title>Proof Vault Backup</title>')
      ..writeln('<style>')
      ..writeln(
          'body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#0c0c18;color:#e8e8f0;margin:0;padding:32px;line-height:1.55}')
      ..writeln('main{max-width:920px;margin:0 auto}')
      ..writeln(
          'section{border:1px solid rgba(99,102,241,.22);border-radius:18px;padding:20px;margin:20px 0;background:#10101e}')
      ..writeln(
          'article{border-top:1px solid rgba(99,102,241,.18);padding-top:16px;margin-top:16px}')
      ..writeln(
          'h1,h2,h3{line-height:1.2} .muted{color:#9898b0} img{max-width:100%;border-radius:12px;border:1px solid rgba(99,102,241,.18);margin:8px 0 14px}')
      ..writeln('</style>')
      ..writeln('</head><body><main>')
      ..writeln('<h1>Proof Vault Backup</h1>')
      ..writeln(
          '<p class="muted">Generated ${_htmlEscape(DateFormat('MMMM d, yyyy h:mm a').format(backup.generatedAt))}</p>');

    for (var folderIndex = 0;
        folderIndex < backup.folders.length;
        folderIndex += 1) {
      final folder = backup.folders[folderIndex];
      final folderPath =
          '${(folderIndex + 1).toString().padLeft(2, '0')}-${_slug(folder.name)}';
      buffer
        ..writeln('<section>')
        ..writeln(
            '<h2>${_htmlEscape('${folder.icon} ${folder.name}'.trim())}</h2>');
      if (folder.description.trim().isNotEmpty) {
        buffer
            .writeln('<p class="muted">${_htmlEscape(folder.description)}</p>');
      }
      for (var itemIndex = 0; itemIndex < folder.items.length; itemIndex += 1) {
        final item = folder.items[itemIndex];
        final itemPath =
            '$folderPath/${(itemIndex + 1).toString().padLeft(2, '0')}-${_slug(item.title)}';
        buffer
          ..writeln('<article>')
          ..writeln('<h3>${_htmlEscape(item.title)}</h3>')
          ..writeln(
              '<p class="muted">${_htmlEscape(_formatDate(item.itemDate))}</p>');
        if (item.notes.trim().isNotEmpty) {
          buffer.writeln(
              '<p>${_htmlEscape(item.notes).replaceAll('\n', '<br>')}</p>');
        }
        for (var photoIndex = 0;
            photoIndex < item.photos.length;
            photoIndex += 1) {
          final photo = item.photos[photoIndex];
          final src =
              '$itemPath/photos/${(photoIndex + 1).toString().padLeft(2, '0')}-${photo.filename}';
          buffer.writeln(
              '<img src="${_htmlEscape(src)}" alt="${_htmlEscape(photo.filename)}">');
        }
        buffer.writeln('</article>');
      }
      buffer.writeln('</section>');
    }

    buffer.writeln('</main></body></html>');
    return buffer.toString();
  }

  List<int> _buildProofVaultPdf(_VaultBackup backup) {
    final document = PdfDocument();
    document.pageSettings.margins.all = 36;
    var page = document.pages.add();
    var y = 0.0;
    final titleFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      22,
      style: PdfFontStyle.bold,
    );
    final folderFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      17,
      style: PdfFontStyle.bold,
    );
    final itemFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      13,
      style: PdfFontStyle.bold,
    );
    final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 11);
    final metaFont = PdfStandardFont(PdfFontFamily.helvetica, 9);

    PdfPage ensureSpace(double needed) {
      final height = page.getClientSize().height;
      if (y + needed <= height) return page;
      page = document.pages.add();
      y = 0;
      return page;
    }

    void drawText(
      String text,
      PdfFont font, {
      PdfColor? color,
      double gap = 10,
      double lineSpacing = 3,
    }) {
      ensureSpace(48);
      final bounds = Rect.fromLTWH(
        0,
        y,
        page.getClientSize().width,
        page.getClientSize().height - y,
      );
      final result = PdfTextElement(
        text: _pdfSafeText(text),
        font: font,
        brush: PdfSolidBrush(color ?? PdfColor(35, 35, 45)),
        format: PdfStringFormat(lineSpacing: lineSpacing),
      ).draw(
        page: page,
        bounds: bounds,
        format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
      );
      page = result?.page ?? page;
      y = (result?.bounds.bottom ?? y) + gap;
    }

    drawText(
      'Proof Vault Backup',
      titleFont,
      color: PdfColor(20, 20, 30),
      gap: 6,
    );
    drawText(
      'Generated ${DateFormat('MMMM d, yyyy h:mm a').format(backup.generatedAt)}',
      metaFont,
      color: PdfColor(120, 120, 135),
      gap: 18,
    );

    for (final folder in backup.folders) {
      drawText(
        '${folder.icon} ${folder.name}'.trim(),
        folderFont,
        color: PdfColor(20, 20, 30),
        gap: 6,
      );
      if (folder.description.trim().isNotEmpty) {
        drawText(folder.description, bodyFont, color: PdfColor(70, 70, 85));
      }
      for (final item in folder.items) {
        drawText(item.title, itemFont, color: PdfColor(35, 35, 45), gap: 4);
        drawText(_formatDate(item.itemDate), metaFont,
            color: PdfColor(120, 120, 135), gap: 8);
        if (item.notes.trim().isNotEmpty) {
          drawText(item.notes, bodyFont, color: PdfColor(45, 45, 58), gap: 12);
        }
        for (final photo in item.photos) {
          try {
            final bitmap = PdfBitmap(photo.bytes);
            final maxWidth = page.getClientSize().width;
            final drawWidth = maxWidth;
            final drawHeight =
                (drawWidth * bitmap.height / bitmap.width).clamp(90.0, 360.0);
            ensureSpace(drawHeight + 28);
            page.graphics.drawString(
              _pdfSafeText(photo.filename),
              metaFont,
              brush: PdfSolidBrush(PdfColor(120, 120, 135)),
              bounds: Rect.fromLTWH(0, y, maxWidth, 12),
            );
            y += 16;
            page.graphics.drawImage(
              bitmap,
              Rect.fromLTWH(0, y, drawWidth, drawHeight),
            );
            y += drawHeight + 14;
          } catch (_) {
            drawText(
              'Photo skipped: ${photo.filename}',
              metaFont,
              color: PdfColor(160, 80, 80),
            );
          }
        }
        y += 8;
      }
      y += 10;
    }

    final pages = document.pages;
    for (var i = 0; i < pages.count; i += 1) {
      final current = pages[i];
      current.graphics.drawString(
        'Journal Intelligence Proof Vault',
        metaFont,
        brush: PdfSolidBrush(PdfColor(120, 120, 135)),
        bounds: Rect.fromLTWH(
          0,
          current.getClientSize().height - 16,
          current.getClientSize().width,
          14,
        ),
        format: PdfStringFormat(alignment: PdfTextAlignment.right),
      );
    }

    final bytes = document.saveSync();
    document.dispose();
    return bytes;
  }

  String _backupFilename(String extension) {
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    return 'proof_vault_backup_$stamp.$extension';
  }

  int get _totalItems => _folders.fold<int>(
        0,
        (sum, folder) => sum + ((folder['item_count'] as num?)?.toInt() ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle:
                Text(_selectedFolder == null ? 'Proof Vault' : 'Folder'),
            previousPageTitle: _selectedFolder == null ? 'More' : 'Vault',
            backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
          ),
          if (_selectedFolder != null)
            SliverToBoxAdapter(
              child: _ProofVaultFolderDetail(
                folder: _selectedFolder!,
                onBack: () {
                  setState(() => _selectedFolder = null);
                  _load();
                },
                onFolderUpdated: (updatedFolder) {
                  setState(() {
                    _selectedFolder = updatedFolder;
                    _folders = _folders.map((folder) {
                      return folder['id'].toString() ==
                              updatedFolder['id'].toString()
                          ? updatedFolder
                          : folder;
                    }).toList();
                  });
                },
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: GlassCard(
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
                                  Color(0xFF10B981),
                                  Color(0xFF06B6D4),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Center(
                              child: Text('🗂', style: TextStyle(fontSize: 22)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Build a record that holds up',
                                  style: TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Organize proof by folder, log dated entries, attach photos, and generate AI summaries when you need the whole story.',
                                  style: TextStyle(
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
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _StatPill(
                              label: 'Folders', value: '${_folders.length}'),
                          _StatPill(label: 'Entries', value: '$_totalItems'),
                          _StatPill(
                            label: 'Summary',
                            value: _cachedSummary == null ? 'Waiting' : 'Ready',
                            color: _cachedSummary == null
                                ? JournalColors.textMuted
                                : const Color(0xFF10B981),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_folders.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Quick Log',
                          style: TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Fast proof capture for the things you do all the time.',
                          style: TextStyle(
                            color: JournalColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _kQuickEntries.map((preset) {
                            return GestureDetector(
                              onTap: () => _openQuickEntry(preset),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: JournalColors.bgSurface,
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: JournalColors.border),
                                ),
                                child: Text(
                                  '${preset.icon} ${preset.label}',
                                  style: const TextStyle(
                                    color: JournalColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_folders.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _ProofVaultBackupCard(
                    exportingPdf: _exportingPdf,
                    exportingZip: _exportingZip,
                    onExportPdf: _exportProofVaultPdf,
                    onExportZip: _exportProofVaultZip,
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _folders.isEmpty
                            ? 'Create your first proof folder'
                            : '${_folders.length} folders • $_totalItems entries',
                        style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_folders.isNotEmpty)
                      _MiniActionButton(
                        label: _cachedSummary == null
                            ? (_summarizing ? 'Generating…' : 'Full Summary')
                            : 'View Summary',
                        color: const Color(0xFF10B981),
                        onTap: _summarizing
                            ? null
                            : () {
                                if (_cachedSummary != null) {
                                  _openSummary(_cachedSummary!);
                                } else {
                                  _generateFullSummary();
                                }
                              },
                      ),
                    const SizedBox(width: 8),
                    _MiniActionButton(
                      label: 'New Folder',
                      color: JournalColors.accent,
                      onTap: _createFolder,
                    ),
                  ],
                ),
              ),
            ),
            if (_summaryError != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    _summaryError!,
                    style: const TextStyle(
                      color: Color(0xFFF87171),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: JournalColors.textMuted),
                    ),
                  ),
                ),
              )
            else if (_folders.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  child: GlassCard(
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        const Text('🗂', style: TextStyle(fontSize: 42)),
                        const SizedBox(height: 16),
                        const Text(
                          'Start building your record',
                          style: TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Create folders for medical care, school, daily support, finances, or anything else you need to document over time.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: _kSuggestedFolders.map((suggestion) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: suggestion.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      suggestion.color.withValues(alpha: 0.24),
                                ),
                              ),
                              child: Text(
                                '${suggestion.icon} ${suggestion.name}',
                                style: TextStyle(
                                  color: suggestion.color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 18),
                        _PrimaryButton(
                          label: 'Create Your First Folder',
                          onTap: _createFolder,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                sliver: SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _folders.map((folder) {
                      final color = _colorFromHex(folder['color']?.toString());
                      return SizedBox(
                        width: MediaQuery.of(context).size.width > 700
                            ? (MediaQuery.of(context).size.width - 44) / 2
                            : double.infinity,
                        child: _FolderCard(
                          folder: folder,
                          color: color,
                          onTap: () => setState(() => _selectedFolder = folder),
                          onDelete: () => _deleteFolder(folder),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<bool?> _confirm(String title, String message) {
    return showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showError(String prefix, Object error) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(prefix),
        content: Text('$error'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _ProofVaultFolderDetail extends StatefulWidget {
  const _ProofVaultFolderDetail({
    required this.folder,
    required this.onBack,
    required this.onFolderUpdated,
  });

  final Map<String, dynamic> folder;
  final VoidCallback onBack;
  final ValueChanged<Map<String, dynamic>> onFolderUpdated;

  @override
  State<_ProofVaultFolderDetail> createState() =>
      _ProofVaultFolderDetailState();
}

class _ProofVaultFolderDetailState extends State<_ProofVaultFolderDetail> {
  final _api = ApiService();

  bool _loading = true;
  bool _summarizing = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _cachedSummary;

  String get _folderId => widget.folder['id'].toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.vaultGetFolderItems(_folderId);
      final cached = await _api.vaultGetCachedFolderSummary(_folderId);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(items);
        _cachedSummary = cached['cached'] == true ? cached : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _addEntry() async {
    final result = await showCupertinoModalPopup<_EntryFormData>(
      context: context,
      builder: (context) => const _EntrySheet(),
    );
    if (result == null) return;

    try {
      final created = await _api.vaultCreateItem(_folderId, {
        'title': result.title.trim(),
        'notes': result.notes.trim().isEmpty ? null : result.notes.trim(),
        'item_date': result.itemDate,
      });

      var newItem = {...created, 'photos': <dynamic>[]};
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) continue;
        final photo = await _api.vaultUploadItemPhoto(
          created['id'].toString(),
          bytes,
          file.name,
        );
        (newItem['photos'] as List).add(photo);
      }

      if (!mounted) return;
      setState(() {
        _items = [Map<String, dynamic>.from(newItem), ..._items];
        _cachedSummary = null;
      });
      widget.onFolderUpdated({
        ...widget.folder,
        'item_count': _items.length,
      });
    } catch (e) {
      _showError('Could not add entry', e);
    }
  }

  Future<void> _editEntry(Map<String, dynamic> item) async {
    final result = await showCupertinoModalPopup<_EntryFormData>(
      context: context,
      builder: (context) => _EntrySheet(
        initialTitle: item['title']?.toString() ?? '',
        initialNotes: item['notes']?.toString(),
        initialDate: item['item_date']?.toString(),
        submitLabel: 'Save Changes',
      ),
    );
    if (result == null) return;

    try {
      final updated = await _api.vaultUpdateItem(item['id'].toString(), {
        'title': result.title.trim(),
        'notes': result.notes.trim().isEmpty ? null : result.notes.trim(),
        'item_date': result.itemDate,
      });
      if (!mounted) return;
      setState(() {
        _items = _items.map((entry) {
          if (entry['id'].toString() != item['id'].toString()) return entry;
          return {
            ...updated,
            'photos': entry['photos'] ?? [],
          };
        }).toList();
      });
    } catch (e) {
      _showError('Could not save entry', e);
    }
  }

  Future<void> _deleteEntry(Map<String, dynamic> item) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('This removes the entry and any attached photos.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _api.vaultDeleteItem(item['id'].toString());
      if (!mounted) return;
      setState(() {
        _items = _items
            .where((entry) => entry['id'].toString() != item['id'].toString())
            .toList();
        _cachedSummary = null;
      });
      widget.onFolderUpdated({
        ...widget.folder,
        'item_count': _items.length,
      });
    } catch (e) {
      _showError('Could not delete entry', e);
    }
  }

  Future<void> _addPhotos(Map<String, dynamic> item) async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    try {
      final photos = <Map<String, dynamic>>[];
      for (final file in picked.files) {
        final bytes = file.bytes;
        if (bytes == null) continue;
        final uploaded = await _api.vaultUploadItemPhoto(
          item['id'].toString(),
          bytes,
          file.name,
        );
        photos.add(uploaded);
      }
      if (!mounted || photos.isEmpty) return;
      setState(() {
        _items = _items.map((entry) {
          if (entry['id'].toString() != item['id'].toString()) return entry;
          final existing = List<dynamic>.from(entry['photos'] ?? []);
          return {
            ...entry,
            'photos': [...existing, ...photos],
          };
        }).toList();
        _cachedSummary = null;
      });
    } catch (e) {
      _showError('Could not upload photos', e);
    }
  }

  Future<void> _deletePhoto(String itemId, String photoId) async {
    try {
      await _api.vaultDeleteItemPhoto(itemId, photoId);
      if (!mounted) return;
      setState(() {
        _items = _items.map((entry) {
          if (entry['id'].toString() != itemId) return entry;
          final photos = List<dynamic>.from(entry['photos'] ?? [])
            ..removeWhere((photo) => photo['id'].toString() == photoId);
          return {
            ...entry,
            'photos': photos,
          };
        }).toList();
      });
    } catch (e) {
      _showError('Could not delete photo', e);
    }
  }

  Future<void> _showSummary({bool force = false}) async {
    setState(() => _summarizing = true);
    try {
      final result =
          await _api.vaultGenerateFolderSummary(_folderId, force: force);
      if (!mounted) return;
      setState(() {
        _cachedSummary = result;
        _summarizing = false;
      });
      showCupertinoModalPopup<void>(
        context: context,
        builder: (context) => _SummarySheet(
          title: widget.folder['name']?.toString() ?? 'Folder Summary',
          summary: result['summary']?.toString() ?? '',
          meta: result,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _summarizing = false);
      _showError('Could not generate summary', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFromHex(widget.folder['color']?.toString());
    final photoCount = _items.fold<int>(
      0,
      (sum, item) => sum + ((item['photos'] as List?)?.length ?? 0),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        children: [
          GlassCard(
            accentBorder: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: widget.onBack,
                      child: const Text('← Back'),
                    ),
                    const Spacer(),
                    _MiniActionButton(
                      label: _summarizing
                          ? 'Generating…'
                          : (_cachedSummary == null
                              ? 'AI Summary'
                              : 'View Summary'),
                      color: const Color(0xFF10B981),
                      onTap: _summarizing
                          ? null
                          : () {
                              if (_cachedSummary == null) {
                                _showSummary();
                              } else {
                                showCupertinoModalPopup<void>(
                                  context: context,
                                  builder: (context) => _SummarySheet(
                                    title: widget.folder['name']?.toString() ??
                                        'Folder Summary',
                                    summary: _cachedSummary!['summary']
                                            ?.toString() ??
                                        '',
                                    meta: _cachedSummary!,
                                  ),
                                );
                              }
                            },
                    ),
                    const SizedBox(width: 8),
                    _MiniActionButton(
                      label: 'Add Entry',
                      color: JournalColors.accent,
                      onTap: _addEntry,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: color.withValues(alpha: 0.28)),
                      ),
                      child: Center(
                        child: Text(
                          widget.folder['icon']?.toString() ?? '📁',
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.folder['name']?.toString() ?? 'Folder',
                            style: const TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if ((widget.folder['description']?.toString() ?? '')
                              .isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.folder['description'].toString(),
                              style: const TextStyle(
                                color: JournalColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _StatPill(
                        label: 'Entries',
                        value: '${_items.length}',
                        color: color),
                    _StatPill(
                        label: 'Photos', value: '$photoCount', color: color),
                    _StatPill(
                      label: 'Updated',
                      value: _cachedSummary == null ? 'Manual' : 'AI Ready',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: CupertinoActivityIndicator(),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Text(
                _error!,
                style: const TextStyle(color: JournalColors.textMuted),
              ),
            )
          else if (_items.isEmpty)
            GlassCard(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Text(
                    widget.folder['icon']?.toString() ?? '📁',
                    style: const TextStyle(fontSize: 40),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'No entries yet',
                    style: TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add dated entries with notes and photos so this folder becomes a useful record over time.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _PrimaryButton(label: 'Add First Entry', onTap: _addEntry),
                ],
              ),
            )
          else
            Column(
              children: _items.map((item) {
                return Padding(
                  key: ValueKey('vault-entry-${item['id']}'),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _VaultEntryCard(
                    item: item,
                    onEdit: () => _editEntry(item),
                    onDelete: () => _deleteEntry(item),
                    onAddPhotos: () => _addPhotos(item),
                    onDeletePhoto: (photoId) =>
                        _deletePhoto(item['id'].toString(), photoId),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  void _showError(String prefix, Object error) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(prefix),
        content: Text('$error'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    required this.folder,
    required this.color,
    required this.onTap,
    required this.onDelete,
  });

  final Map<String, dynamic> folder;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Center(
                  child: Text(
                    folder['icon']?.toString() ?? '📁',
                    style: const TextStyle(fontSize: 21),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder['name']?.toString() ?? 'Folder',
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      folder['description']?.toString().isNotEmpty == true
                          ? folder['description'].toString()
                          : 'Open folder',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(28, 28),
                onPressed: onDelete,
                child: const Icon(
                  CupertinoIcons.trash,
                  color: JournalColors.textMuted,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '${(folder['item_count'] as num?)?.toInt() ?? 0}',
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'entries',
                style: TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              const Text(
                'Open →',
                style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProofVaultBackupCard extends StatelessWidget {
  const _ProofVaultBackupCard({
    required this.exportingPdf,
    required this.exportingZip,
    required this.onExportPdf,
    required this.onExportZip,
  });

  final bool exportingPdf;
  final bool exportingZip;
  final VoidCallback onExportPdf;
  final VoidCallback onExportZip;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                CupertinoIcons.archivebox,
                color: JournalColors.accent,
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Backup Proof Vault',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Export folders, entries, descriptions, and attached photos in the same structure.',
            style: TextStyle(
              color: JournalColors.textMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SecondaryButton(
                  label: exportingZip ? 'Building ZIP…' : 'Website ZIP',
                  onTap: exportingPdf || exportingZip ? null : onExportZip,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PrimaryButton(
                  label: exportingPdf ? 'Building PDF…' : 'PDF Backup',
                  onTap: exportingPdf || exportingZip ? null : onExportPdf,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VaultEntryCard extends StatelessWidget {
  const _VaultEntryCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onAddPhotos,
    required this.onDeletePhoto,
  });

  final Map<String, dynamic> item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddPhotos;
  final ValueChanged<String> onDeletePhoto;

  @override
  Widget build(BuildContext context) {
    final photos = List<dynamic>.from(item['photos'] ?? []);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['title']?.toString() ?? 'Untitled',
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(item['item_date']?.toString()),
                      style: const TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    if ((item['notes']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        item['notes'].toString(),
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
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _IconAction(icon: CupertinoIcons.photo, onTap: onAddPhotos),
                  const SizedBox(width: 6),
                  _IconAction(icon: CupertinoIcons.pencil, onTap: onEdit),
                  const SizedBox(width: 6),
                  _IconAction(
                    icon: CupertinoIcons.trash,
                    onTap: onDelete,
                    color: const Color(0xFFEF4444),
                  ),
                ],
              ),
            ],
          ),
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '${photos.length} photo${photos.length == 1 ? '' : 's'}',
              style: const TextStyle(
                color: JournalColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: photos.map((photo) {
                return _VaultPhotoThumb(
                  key: ValueKey(
                    'vault-photo-${item['id']}-${photo['id']}',
                  ),
                  itemId: item['id'].toString(),
                  photoId: photo['id'].toString(),
                  filename: photo['original_filename']?.toString(),
                  onDelete: () => onDeletePhoto(photo['id'].toString()),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _VaultPhotoThumb extends StatefulWidget {
  const _VaultPhotoThumb({
    super.key,
    required this.itemId,
    required this.photoId,
    this.filename,
    required this.onDelete,
  });

  final String itemId;
  final String photoId;
  final String? filename;
  final VoidCallback onDelete;

  @override
  State<_VaultPhotoThumb> createState() => _VaultPhotoThumbState();
}

class _VaultPhotoThumbState extends State<_VaultPhotoThumb> {
  final _api = ApiService();
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _VaultPhotoThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemId != widget.itemId ||
        oldWidget.photoId != widget.photoId) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await _api.fetchImageBytes(
        '/api/vault/items/${widget.itemId}/photos/${widget.photoId}/image',
      );
      if (!mounted) return;
      setState(() => _bytes = Uint8List.fromList(bytes));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _bytes == null
          ? null
          : () {
              showCupertinoModalPopup<void>(
                context: context,
                barrierColor: CupertinoColors.black.withValues(alpha: 0.9),
                builder: (context) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    color: JournalColors.bgBase.withValues(alpha: 0.96),
                    width: double.infinity,
                    height: double.infinity,
                    child: SafeArea(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 56, 20, 20),
                              child: GestureDetector(
                                onTap: () {},
                                child: InteractiveViewer(
                                  child: Image.memory(
                                    _bytes!,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 12,
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(36, 36),
                              onPressed: () => Navigator.pop(context),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: JournalColors.bgBase
                                      .withValues(alpha: 0.82),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: JournalColors.borderBright,
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
                  ),
                ),
              );
            },
      child: Stack(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: JournalColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: _bytes == null
                ? const Center(
                    child: Icon(
                      CupertinoIcons.photo,
                      color: JournalColors.textMuted,
                    ),
                  )
                : Image.memory(_bytes!, fit: BoxFit.cover),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: widget.onDelete,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xAA000000),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  CupertinoIcons.xmark,
                  color: CupertinoColors.white,
                  size: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderSheet extends StatefulWidget {
  const _FolderSheet();

  @override
  State<_FolderSheet> createState() => _FolderSheetState();
}

class _FolderSheetState extends State<_FolderSheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  String _icon = _kSuggestedFolders.first.icon;
  Color _color = _kSuggestedFolders.first.color;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _VaultSheet(
      title: 'New Folder',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Quick start'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kSuggestedFolders.map((suggestion) {
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _name.text = suggestion.name;
                    _icon = suggestion.icon;
                    _color = suggestion.color;
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: suggestion.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: suggestion.color.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Text(
                    '${suggestion.icon} ${suggestion.name}',
                    style: TextStyle(
                      color: suggestion.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Folder name'),
          _VaultTextField(controller: _name, placeholder: 'Medical & Health'),
          const SizedBox(height: 14),
          const _FieldLabel('Description'),
          _VaultTextField(
            controller: _description,
            placeholder: 'What belongs in this folder?',
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Color'),
          Wrap(
            spacing: 10,
            children: _kSuggestedFolders.map((suggestion) {
              final selected = suggestion.color.toARGB32() == _color.toARGB32();
              return GestureDetector(
                onTap: () => setState(() {
                  _color = suggestion.color;
                  _icon = suggestion.icon;
                }),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: suggestion.color,
                    border: Border.all(
                      color: selected
                          ? CupertinoColors.white
                          : CupertinoColors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _SecondaryButton(
                  label: 'Cancel',
                  onTap: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PrimaryButton(
                  label: 'Create Folder',
                  onTap: () {
                    if (_name.text.trim().isEmpty) return;
                    Navigator.pop(
                      context,
                      _FolderFormData(
                        name: _name.text,
                        description: _description.text,
                        icon: _icon,
                        color: _color,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntrySheet extends StatefulWidget {
  const _EntrySheet({
    this.initialTitle = '',
    this.initialNotes,
    this.initialDate,
    this.submitLabel = 'Add Entry',
  });

  final String initialTitle;
  final String? initialNotes;
  final String? initialDate;
  final String submitLabel;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late DateTime _date;
  List<PlatformFile> _files = [];

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initialTitle);
    _notes = TextEditingController(text: widget.initialNotes ?? '');
    _date = _parseDate(widget.initialDate) ?? DateTime.now();
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _VaultSheet(
      title: widget.submitLabel == 'Add Entry' ? 'Add Entry' : 'Edit Entry',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('What did you do?'),
          _VaultTextField(controller: _title, placeholder: 'Document the task'),
          const SizedBox(height: 14),
          const _FieldLabel('Date'),
          GestureDetector(
            onTap: () async {
              final picked = await _pickDate(context, _date);
              if (picked != null) setState(() => _date = picked);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: JournalColors.bgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: JournalColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('MMMM d, yyyy').format(_date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    CupertinoIcons.calendar,
                    color: JournalColors.textMuted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Notes'),
          CupertinoTextField(
            controller: _notes,
            autocorrect: false,
            enableSuggestions: false,
            minLines: 3,
            maxLines: 5,
            padding: const EdgeInsets.all(14),
            style: const TextStyle(
              color: JournalColors.textPrimary,
              decoration: TextDecoration.none,
            ),
            placeholder: 'Add extra context if it matters',
            placeholderStyle: const TextStyle(
              color: JournalColors.textMuted,
              decoration: TextDecoration.none,
            ),
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: JournalColors.border),
            ),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Photos'),
          _SecondaryButton(
            label: _files.isEmpty ? 'Add Photos' : '${_files.length} selected',
            onTap: () async {
              final picked = await FilePicker.platform.pickFiles(
                allowMultiple: true,
                type: FileType.image,
                withData: true,
              );
              if (picked == null || picked.files.isEmpty) return;
              setState(() => _files = picked.files);
            },
          ),
          if (_files.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _files
                  .map((file) => _PendingPickedPhotoTile(file: file))
                  .toList(),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _SecondaryButton(
                  label: 'Cancel',
                  onTap: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PrimaryButton(
                  label: widget.submitLabel,
                  onTap: () {
                    if (_title.text.trim().isEmpty) return;
                    Navigator.pop(
                      context,
                      _EntryFormData(
                        title: _title.text,
                        notes: _notes.text,
                        itemDate: DateFormat('yyyy-MM-dd').format(_date),
                        files: _files,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickLogSheet extends StatefulWidget {
  const _QuickLogSheet({
    required this.folders,
    required this.preset,
  });

  final List<Map<String, dynamic>> folders;
  final ({String label, String icon, String title, String folderHint}) preset;

  @override
  State<_QuickLogSheet> createState() => _QuickLogSheetState();
}

class _QuickLogSheetState extends State<_QuickLogSheet> {
  late final TextEditingController _title;
  final _notes = TextEditingController();
  late String _folderId;
  DateTime _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.preset.title);
    final guess = widget.folders.firstWhere(
      (folder) => folder['name']?.toString() == widget.preset.folderHint,
      orElse: () => widget.folders.first,
    );
    _folderId = guess['id'].toString();
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _VaultSheet(
      title: '${widget.preset.icon} Quick Log',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Folder'),
          Container(
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: JournalColors.border),
            ),
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue: _folderId,
              thumbColor: JournalColors.accent.withValues(alpha: 0.9),
              children: {
                for (final folder in widget.folders.take(3))
                  folder['id'].toString(): Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    child: Text(
                      folder['name']?.toString() ?? 'Folder',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              },
              onValueChanged: (value) {
                if (value != null) setState(() => _folderId = value);
              },
            ),
          ),
          if (widget.folders.length > 3) ...[
            const SizedBox(height: 8),
            const Text(
              'Using the first three folders here for speed. Open a folder if you need a different target.',
              style: TextStyle(
                color: JournalColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 14),
          const _FieldLabel('Entry'),
          _VaultTextField(controller: _title, placeholder: 'Quick proof note'),
          const SizedBox(height: 14),
          const _FieldLabel('Date'),
          GestureDetector(
            onTap: () async {
              final picked = await _pickDate(context, _date);
              if (picked != null) setState(() => _date = picked);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: JournalColors.bgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: JournalColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('MMMM d, yyyy').format(_date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    CupertinoIcons.calendar,
                    color: JournalColors.textMuted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Notes'),
          CupertinoTextField(
            controller: _notes,
            autocorrect: false,
            enableSuggestions: false,
            minLines: 2,
            maxLines: 4,
            padding: const EdgeInsets.all(14),
            style: const TextStyle(
              color: JournalColors.textPrimary,
              decoration: TextDecoration.none,
            ),
            placeholder: 'Optional context',
            placeholderStyle: const TextStyle(
              color: JournalColors.textMuted,
              decoration: TextDecoration.none,
            ),
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: JournalColors.border),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _SecondaryButton(
                  label: 'Cancel',
                  onTap: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PrimaryButton(
                  label: 'Log It',
                  onTap: () {
                    if (_title.text.trim().isEmpty) return;
                    Navigator.pop(
                      context,
                      _QuickLogData(
                        folderId: _folderId,
                        title: _title.text,
                        notes: _notes.text,
                        itemDate: DateFormat('yyyy-MM-dd').format(_date),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummarySheet extends StatelessWidget {
  const _SummarySheet({
    required this.title,
    required this.summary,
    required this.meta,
  });

  final String title;
  final String summary;
  final Map<String, dynamic> meta;

  @override
  Widget build(BuildContext context) {
    return _VaultSheet(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (meta['folder_count'] != null)
                _StatPill(label: 'Folders', value: '${meta['folder_count']}'),
              if (meta['item_count'] != null)
                _StatPill(label: 'Entries', value: '${meta['item_count']}'),
              if (meta['photo_count'] != null)
                _StatPill(label: 'Photos', value: '${meta['photo_count']}'),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: JournalColors.border),
            ),
            child: MarkdownBody(
              data: summary,
              shrinkWrap: true,
              selectable: false,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 13,
                  height: 1.55,
                  decoration: TextDecoration.none,
                ),
                strong: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
                em: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontStyle: FontStyle.italic,
                  decoration: TextDecoration.none,
                ),
                listBullet: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 13,
                  decoration: TextDecoration.none,
                ),
                blockquote: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 13,
                  height: 1.55,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _PrimaryButton(
            label: 'Done',
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

class _VaultSheet extends StatelessWidget {
  const _VaultSheet({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final topInset = mediaQuery.padding.top;
    final bottomInset = mediaQuery.padding.bottom;
    final maxHeight = mediaQuery.size.height - topInset - 12;

    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: CupertinoPopupSurface(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(0, topInset + 8, 0, keyboardInset),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Container(
                color: JournalColors.bgBase,
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(16, 14, 16, bottomInset + 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const Spacer(),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(28, 28),
                            onPressed: () => Navigator.pop(context),
                            child: const Icon(
                              CupertinoIcons.xmark_circle_fill,
                              color: JournalColors.textMuted,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      child,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingPhotoPreview extends StatelessWidget {
  const _PendingPhotoPreview({
    required this.file,
  });

  final PlatformFile file;

  @override
  Widget build(BuildContext context) {
    final bytes = file.bytes;
    final extension = _proofVaultExtensionLabel(file.name);

    return Container(
      width: 108,
      height: 112,
      decoration: BoxDecoration(
        color: JournalColors.bgSurface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JournalColors.borderBright),
        boxShadow: [
          BoxShadow(
            color: JournalColors.bgBase.withValues(alpha: 0.36),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null && bytes.isNotEmpty)
              Image.memory(
                bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _PendingPhotoFallback(),
              )
            else
              const _PendingPhotoFallback(),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      JournalColors.bgBase.withValues(alpha: 0),
                      JournalColors.bgBase.withValues(alpha: 0.74),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              bottom: 8,
              child: _PendingPhotoBadge(label: extension),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: JournalColors.bgBase.withValues(alpha: 0.72),
                  shape: BoxShape.circle,
                  border: Border.all(color: JournalColors.borderBright),
                ),
                child: const Icon(
                  CupertinoIcons.photo,
                  color: JournalColors.textPrimary,
                  size: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingPhotoFallback extends StatelessWidget {
  const _PendingPhotoFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: JournalColors.bgCardAlt,
      alignment: Alignment.center,
      child: const Icon(
        CupertinoIcons.photo,
        color: JournalColors.textMuted,
        size: 28,
      ),
    );
  }
}

class _PendingPhotoBadge extends StatelessWidget {
  const _PendingPhotoBadge({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: JournalColors.bgBase.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: JournalColors.borderBright),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: JournalColors.textPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

class _PendingPickedPhotoTile extends StatelessWidget {
  const _PendingPickedPhotoTile({
    required this.file,
  });

  final PlatformFile file;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PendingPhotoPreview(file: file),
        const SizedBox(height: 8),
        SizedBox(
          width: 108,
          child: Text(
            file.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: JournalColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

class _VaultTextField extends StatelessWidget {
  const _VaultTextField({
    required this.controller,
    required this.placeholder,
  });

  final TextEditingController controller;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      autocorrect: false,
      enableSuggestions: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      style: const TextStyle(
        color: JournalColors.textPrimary,
        decoration: TextDecoration.none,
      ),
      placeholder: placeholder,
      placeholderStyle: const TextStyle(
        color: JournalColors.textMuted,
        decoration: TextDecoration.none,
      ),
      decoration: BoxDecoration(
        color: JournalColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JournalColors.border),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: (color ?? JournalColors.accent).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (color ?? JournalColors.accent).withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color ?? JournalColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      color: JournalColors.accent,
      borderRadius: BorderRadius.circular(14),
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: CupertinoColors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      color: JournalColors.bgSurface,
      borderRadius: BorderRadius.circular(14),
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: JournalColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.26)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: onTap == null ? JournalColors.textMuted : color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.onTap,
    this.color = JournalColors.textSecondary,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}

class _FolderFormData {
  const _FolderFormData({
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String name;
  final String description;
  final String icon;
  final Color color;
}

class _EntryFormData {
  const _EntryFormData({
    required this.title,
    required this.notes,
    required this.itemDate,
    required this.files,
  });

  final String title;
  final String notes;
  final String itemDate;
  final List<PlatformFile> files;
}

class _QuickLogData {
  const _QuickLogData({
    required this.folderId,
    required this.title,
    required this.notes,
    required this.itemDate,
  });

  final String folderId;
  final String title;
  final String notes;
  final String itemDate;
}

class _VaultBackup {
  const _VaultBackup({
    required this.generatedAt,
    required this.folders,
  });

  final DateTime generatedAt;
  final List<_VaultBackupFolder> folders;

  Map<String, dynamic> toJson() {
    return {
      'generated_at': generatedAt.toIso8601String(),
      'folder_count': folders.length,
      'item_count': folders.fold<int>(
        0,
        (sum, folder) => sum + folder.items.length,
      ),
      'photo_count': folders.fold<int>(
        0,
        (sum, folder) =>
            sum +
            folder.items.fold<int>(
              0,
              (inner, item) => inner + item.photos.length,
            ),
      ),
      'folders': folders.map((folder) => folder.toJson()).toList(),
    };
  }
}

class _VaultBackupFolder {
  const _VaultBackupFolder({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.items,
  });

  final String id;
  final String name;
  final String description;
  final String icon;
  final List<_VaultBackupItem> items;

  String get textSummary {
    return [
      'Folder: $name',
      if (description.trim().isNotEmpty) 'Description: $description',
      'Entries: ${items.length}',
    ].join('\n');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'item_count': items.length,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

class _VaultBackupItem {
  const _VaultBackupItem({
    required this.id,
    required this.title,
    required this.notes,
    required this.itemDate,
    required this.photos,
  });

  final String id;
  final String title;
  final String notes;
  final String? itemDate;
  final List<_VaultBackupPhoto> photos;

  String get textSummary {
    return [
      'Title: $title',
      'Date: ${_formatDate(itemDate)}',
      if (notes.trim().isNotEmpty) 'Description:\n$notes',
      'Photos: ${photos.length}',
    ].join('\n\n');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': notes,
      'item_date': itemDate,
      'photo_count': photos.length,
      'photos': photos
          .map((photo) => {
                'id': photo.id,
                'filename': photo.filename,
              })
          .toList(),
    };
  }
}

class _VaultBackupPhoto {
  const _VaultBackupPhoto({
    required this.id,
    required this.filename,
    required this.bytes,
  });

  final String id;
  final String filename;
  final Uint8List bytes;
}

DateTime? _parseDate(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    return DateTime.parse(value);
  } catch (_) {
    return null;
  }
}

String _formatDate(String? value) {
  final parsed = _parseDate(value);
  if (parsed == null) return 'No date';
  return DateFormat('MMMM d, yyyy').format(parsed);
}

Future<DateTime?> _pickDate(BuildContext context, DateTime initial) async {
  DateTime temp = initial;
  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (context) => CupertinoPopupSurface(
      child: Container(
        height: 320,
        color: JournalColors.bgBase,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.pop(context, temp),
                  child: const Text('Done'),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: initial,
                maximumDate: DateTime.now().add(const Duration(days: 365)),
                onDateTimeChanged: (date) => temp = date,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Color _colorFromHex(String? hex) {
  if (hex == null || hex.isEmpty) return JournalColors.accent;
  final sanitized = hex.replaceAll('#', '');
  final value = sanitized.length == 6 ? 'FF$sanitized' : sanitized;
  return Color(
      int.tryParse(value, radix: 16) ?? JournalColors.accent.toARGB32());
}

String _colorToHex(Color color) {
  return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
}

String _safePhotoFilename(String? filename, String fallbackId) {
  final raw = (filename == null || filename.trim().isEmpty)
      ? 'photo_$fallbackId.jpg'
      : filename.trim();
  final sanitized = raw
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  return sanitized.isEmpty ? 'photo_$fallbackId.jpg' : sanitized;
}

String _slug(String value) {
  final slug = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return slug.isEmpty ? 'untitled' : slug;
}

String _htmlEscape(String value) {
  return const HtmlEscape(HtmlEscapeMode.element).convert(value);
}

String _pdfSafeText(String value) {
  final normalized = value
      .replaceAll('\u2018', "'")
      .replaceAll('\u2019', "'")
      .replaceAll('\u201C', '"')
      .replaceAll('\u201D', '"')
      .replaceAll('\u2013', '-')
      .replaceAll('\u2014', '-')
      .replaceAll('\u2026', '...');
  final buffer = StringBuffer();
  for (final rune in normalized.runes) {
    if (rune == 10 || rune == 13 || rune == 9 || (rune >= 32 && rune <= 126)) {
      buffer.writeCharCode(rune);
    }
  }
  final sanitized = buffer.toString().replaceAll(RegExp(r'[ \t]+\n'), '\n');
  return sanitized.trim().isEmpty ? 'Untitled' : sanitized;
}
