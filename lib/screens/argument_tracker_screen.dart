import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class ArgumentTrackerScreen extends StatefulWidget {
  const ArgumentTrackerScreen({super.key});

  @override
  State<ArgumentTrackerScreen> createState() => _ArgumentTrackerScreenState();
}

class _ArgumentTrackerScreenState extends State<ArgumentTrackerScreen> {
  final _api = ApiService();
  final _titleController = TextEditingController();
  final _optionalDetailsController = TextEditingController();
  final _reportEditorController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _dateFormat = DateFormat('MMM d, yyyy • h:mm a');

  List<_PickedArgumentFile> _files = const [];
  List<ArgumentTrackerReport> _reports = const [];
  ArgumentTrackerReport? _activeReport;
  bool _loadingReports = true;
  bool _generating = false;
  bool _exportingPdf = false;
  bool _editingReport = false;
  bool _savingReport = false;
  String? _error;
  String? _openingId;
  String? _deletingId;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _optionalDetailsController.dispose();
    _reportEditorController.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    setState(() {
      _loadingReports = true;
      _error = null;
    });
    try {
      final reports = await _api.listArgumentTrackerReports();
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loadingReports = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingReports = false;
        _error = _parseError(e, fallback: 'Could not load saved arguments.');
      });
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: false,
    );
    if (result == null) return;
    final next = [
      ..._files,
      ...result.files
          .where((file) => file.path != null || file.bytes != null)
          .map(_PickedArgumentFile.fromPlatformFile),
    ];
    setState(() => _files = next);
  }

  Future<void> _pickPhotos() async {
    try {
      final picked = await _imagePicker.pickMultiImage(imageQuality: 88);
      if (picked.isEmpty) return;
      final next = [
        ..._files,
        ...picked.map(_PickedArgumentFile.fromXFile),
      ];
      if (mounted) setState(() => _files = next);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _parseError(e, fallback: 'Could not open photo library.');
      });
    }
  }

  void _removeFile(_PickedArgumentFile file) {
    setState(() {
      _files = _files.where((item) => item.id != file.id).toList();
    });
  }

  Future<void> _generate() async {
    final title = _titleController.text.trim();
    final optionalDetails = _optionalDetailsController.text.trim();

    if (title.isEmpty) {
      setState(() {
        _error = 'Add a title first.';
      });
      return;
    }

    if (_files.isEmpty && optionalDetails.isEmpty) {
      setState(() {
        _error = 'Attach photos, files, or add optional details first.';
      });
      return;
    }

    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      final contextString = await _api.getFloatchatContext();
      final report = await _api.generateArgumentTrackerReport(
        title: title,
        eventSummary: title,
        inputText: optionalDetails,
        contextString: contextString,
        attachments: _files
            .map((file) => ArgumentTrackerAttachment(
                  filename: file.name,
                  filePath: file.path,
                  bytes: file.bytes,
                ))
            .toList(),
      );
      if (!mounted) return;
      setState(() {
        _activeReport = report;
        _reportEditorController.text = report.result;
        _editingReport = false;
        _reports = [report, ..._reports.where((item) => item.id != report.id)];
        _generating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error =
            _parseError(e, fallback: 'Could not generate argument report.');
      });
    }
  }

  Future<void> _openReport(ArgumentTrackerReport report) async {
    if (_openingId != null || _deletingId != null) return;
    setState(() => _openingId = report.id);
    try {
      final detail = await _api.getArgumentTrackerReport(report.id);
      if (!mounted) return;
      setState(() {
        _activeReport = detail;
        _reportEditorController.text = detail.result;
        _editingReport = false;
        _openingId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _openingId = null;
        _error = _parseError(e, fallback: 'Could not open saved report.');
      });
    }
  }

  void _startEditingReport() {
    final report = _activeReport;
    if (report == null) return;
    _reportEditorController.text = report.result;
    setState(() => _editingReport = true);
  }

  void _cancelEditingReport() {
    final report = _activeReport;
    if (report != null) _reportEditorController.text = report.result;
    setState(() => _editingReport = false);
  }

  Future<void> _saveReportCorrections() async {
    final report = _activeReport;
    final result = _reportEditorController.text.trim();
    if (report == null || _savingReport) return;
    if (result.isEmpty) {
      setState(() => _error = 'Report text cannot be empty.');
      return;
    }

    setState(() {
      _savingReport = true;
      _error = null;
    });
    try {
      final updated = await _api.updateArgumentTrackerReport(
        reportId: report.id,
        result: result,
      );
      if (!mounted) return;
      setState(() {
        _activeReport = updated;
        _reports = [
          updated,
          ..._reports.where((item) => item.id != updated.id),
        ];
        _reportEditorController.text = updated.result;
        _editingReport = false;
        _savingReport = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingReport = false;
        _error = _parseError(e, fallback: 'Could not save report corrections.');
      });
    }
  }

  Future<void> _deleteReport(ArgumentTrackerReport report) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete argument report'),
        content: Text('Remove "${report.title}" from saved arguments?'),
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
    if (confirmed != true) return;

    setState(() => _deletingId = report.id);
    try {
      await _api.deleteArgumentTrackerReport(report.id);
      if (!mounted) return;
      setState(() {
        _reports = _reports.where((item) => item.id != report.id).toList();
        if (_activeReport?.id == report.id) _activeReport = null;
        _deletingId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deletingId = null;
        _error = _parseError(e, fallback: 'Could not delete saved report.');
      });
    }
  }

  Future<void> _exportActiveReportPdf() async {
    final report = _activeReport;
    if (report == null || _exportingPdf) return;

    setState(() {
      _exportingPdf = true;
      _error = null;
    });

    try {
      final bytes = _buildArgumentReportPdf(report);
      final dir = await getTemporaryDirectory();
      final filename = _pdfFilename(report.title);
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: report.title,
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _parseError(e, fallback: 'Could not export PDF.');
      });
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  List<int> _buildArgumentReportPdf(ArgumentTrackerReport report) {
    final document = PdfDocument();
    document.pageSettings.margins.all = 42;
    final page = document.pages.add();
    final bounds = Rect.fromLTWH(
      0,
      0,
      page.getClientSize().width,
      page.getClientSize().height,
    );
    final titleFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      18,
      style: PdfFontStyle.bold,
    );
    final metaFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
    final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 11);

    final title = report.title.trim().isEmpty
        ? 'Argument Tracker Report'
        : report.title.trim();
    final savedAt = _formatDate(report.updatedAt);
    final text = [
      'Saved: $savedAt',
      if (report.attachmentCount > 0)
        'Evidence: ${report.attachmentCount} attachment${report.attachmentCount == 1 ? '' : 's'}',
      '',
      report.result.trim().isEmpty
          ? 'No report text available.'
          : report.result,
    ].join('\n');

    PdfTextElement(
      text: title,
      font: titleFont,
      brush: PdfSolidBrush(PdfColor(20, 20, 30)),
    ).draw(page: page, bounds: bounds);

    PdfTextElement(
      text: text,
      font: bodyFont,
      brush: PdfSolidBrush(PdfColor(35, 35, 45)),
      format: PdfStringFormat(lineSpacing: 4),
    ).draw(
      page: page,
      bounds: Rect.fromLTWH(0, 34, bounds.width, bounds.height - 34),
      format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
    );

    final pages = document.pages;
    for (var i = 0; i < pages.count; i += 1) {
      final current = pages[i];
      current.graphics.drawString(
        'Journal Intelligence Argument Tracker',
        metaFont,
        brush: PdfSolidBrush(PdfColor(120, 120, 135)),
        bounds: Rect.fromLTWH(
          0,
          current.getClientSize().height - 18,
          current.getClientSize().width,
          16,
        ),
        format: PdfStringFormat(alignment: PdfTextAlignment.right),
      );
    }

    final bytes = document.saveSync();
    document.dispose();
    return bytes;
  }

  String _pdfFilename(String title) {
    final base = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    return '${base.isEmpty ? 'argument_report' : base}_$stamp.pdf';
  }

  String _parseError(dynamic e, {required String fallback}) {
    if (e is DioException && e.response?.statusCode == 413) {
      return 'Upload is too large for one request. Remove a few files or try smaller screenshots.';
    }
    final str = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    return match?.group(1) ?? fallback;
  }

  String _formatDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return 'Saved argument';
    return _dateFormat.format(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final activeReport = _activeReport;

    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: CupertinoPageScaffold(
        backgroundColor: JournalColors.bgBase,
        child: CustomScrollView(
          slivers: [
            CupertinoSliverNavigationBar(
              largeTitle: const Text('Argument Tracker'),
              backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
              border: const Border(
                bottom: BorderSide(color: JournalColors.border, width: 0.5),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _IntroCard(fileCount: _files.length),
                  const SizedBox(height: 16),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Build a case report',
                          style: TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _LabeledField(
                          label: 'Title',
                          controller: _titleController,
                          placeholder: 'Confrontation over search history',
                          minLines: 1,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 12),
                        _LabeledField(
                          label: 'Optional details',
                          controller: _optionalDetailsController,
                          placeholder:
                              'Add contradictions, timeline notes, names, or context the attachments do not show.',
                          minLines: 5,
                          maxLines: null,
                        ),
                        const SizedBox(height: 14),
                        _AttachmentBar(
                          files: _files,
                          onPick: _pickFiles,
                          onPickPhotos: _pickPhotos,
                          onRemove: _removeFile,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          _InlineNotice(
                            icon: CupertinoIcons.exclamationmark_triangle,
                            text: _error!,
                            color: JournalColors.severity,
                          ),
                        ],
                        const SizedBox(height: 16),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: _generating ? null : _generate,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: _generating
                                  ? JournalColors.bgCardAlt
                                  : JournalColors.accent,
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: JournalColors.borderBright),
                            ),
                            alignment: Alignment.center,
                            child: _generating
                                ? const CupertinoActivityIndicator(
                                    color: JournalColors.accent,
                                  )
                                : const Text(
                                    'Generate Case Documentation',
                                    style: TextStyle(
                                      color: JournalColors.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (activeReport != null) ...[
                    const SizedBox(height: 18),
                    _ReportCard(
                      report: activeReport,
                      exportingPdf: _exportingPdf,
                      editing: _editingReport,
                      saving: _savingReport,
                      editorController: _reportEditorController,
                      onExportPdf: _exportActiveReportPdf,
                      onEdit: _startEditingReport,
                      onCancelEdit: _cancelEditingReport,
                      onSaveEdit: _saveReportCorrections,
                    ),
                  ],
                  const SizedBox(height: 22),
                  _SavedReportsSection(
                    reports: _reports,
                    loading: _loadingReports,
                    openingId: _openingId,
                    deletingId: _deletingId,
                    formatDate: _formatDate,
                    onRefresh: _loadReports,
                    onOpen: _openReport,
                    onDelete: _deleteReport,
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedArgumentFile {
  const _PickedArgumentFile({
    required this.id,
    required this.name,
    required this.size,
    this.path,
    this.bytes,
  });

  final String id;
  final String name;
  final int size;
  final String? path;
  final List<int>? bytes;

  factory _PickedArgumentFile.fromPlatformFile(PlatformFile file) {
    return _PickedArgumentFile(
      id: '${file.name}_${file.size}_${DateTime.now().microsecondsSinceEpoch}',
      name: file.name,
      size: file.size,
      path: file.path,
      bytes: file.bytes,
    );
  }

  factory _PickedArgumentFile.fromXFile(XFile file) {
    return _PickedArgumentFile(
      id: '${file.name}_${DateTime.now().microsecondsSinceEpoch}',
      name: file.name.isEmpty ? 'photo.jpg' : file.name,
      size: 0,
      path: file.path,
    );
  }

  String get sizeLabel {
    if (size <= 0) return 'Photo';
    if (size >= 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (size >= 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '$size B';
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.fileCount});

  final int fileCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: JournalColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: JournalColors.borderBright),
        boxShadow: const [
          BoxShadow(
            color: JournalColors.accentGlow,
            blurRadius: 24,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: JournalColors.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              CupertinoIcons.doc_text_search,
              color: JournalColors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Forensic argument analysis',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  fileCount == 0
                      ? 'Attach screenshots, PDFs, TXT, or paste the conversation.'
                      : '$fileCount attachment${fileCount == 1 ? '' : 's'} ready for analysis.',
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
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

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.placeholder,
    required this.minLines,
    required this.maxLines,
  });

  final String label;
  final TextEditingController controller;
  final String placeholder;
  final int minLines;
  final int? maxLines;

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
            letterSpacing: 1.15,
          ),
        ),
        const SizedBox(height: 7),
        CupertinoTextField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          padding: const EdgeInsets.all(14),
          cursorColor: JournalColors.accent,
          style: const TextStyle(
            color: JournalColors.textPrimary,
            fontSize: 15,
            height: 1.45,
          ),
          placeholder: placeholder,
          placeholderStyle: const TextStyle(
            color: JournalColors.textMuted,
            fontSize: 14,
          ),
          decoration: BoxDecoration(
            color: JournalColors.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: JournalColors.border),
          ),
        ),
      ],
    );
  }
}

class _AttachmentBar extends StatelessWidget {
  const _AttachmentBar({
    required this.files,
    required this.onPick,
    required this.onPickPhotos,
    required this.onRemove,
  });

  final List<_PickedArgumentFile> files;
  final VoidCallback onPick;
  final VoidCallback onPickPhotos;
  final void Function(_PickedArgumentFile file) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'ATTACHMENTS',
                style: TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.15,
                ),
              ),
            ),
            _AttachmentButton(
              icon: CupertinoIcons.photo,
              label: 'Photos',
              onPressed: onPickPhotos,
            ),
            const SizedBox(width: 8),
            _AttachmentButton(
              icon: CupertinoIcons.paperclip,
              label: 'Files',
              onPressed: onPick,
            ),
          ],
        ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: files
                .map((file) => _AttachmentChip(
                      file: file,
                      onRemove: () => onRemove(file),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _AttachmentButton extends StatelessWidget {
  const _AttachmentButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 30),
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: JournalColors.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: JournalColors.borderBright),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: JournalColors.textPrimary,
              size: 13,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.file,
    required this.onRemove,
  });

  final _PickedArgumentFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: JournalColors.bgCardAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JournalColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            CupertinoIcons.doc,
            color: JournalColors.accent,
            size: 14,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              '${file.name} • ${file.sizeLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.only(left: 6),
            minimumSize: const Size(24, 24),
            onPressed: onRemove,
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              color: JournalColors.textMuted,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.exportingPdf,
    required this.editing,
    required this.saving,
    required this.editorController,
    required this.onExportPdf,
    required this.onEdit,
    required this.onCancelEdit,
    required this.onSaveEdit,
  });

  final ArgumentTrackerReport report;
  final bool exportingPdf;
  final bool editing;
  final bool saving;
  final TextEditingController editorController;
  final VoidCallback onExportPdf;
  final VoidCallback onEdit;
  final VoidCallback onCancelEdit;
  final VoidCallback onSaveEdit;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accentBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  'Generated Case Documentation',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _CountPill(count: report.attachmentCount),
            ],
          ),
          const SizedBox(height: 12),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: saving ? null : (editing ? onCancelEdit : onEdit),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: JournalColors.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: JournalColors.borderBright),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    editing ? CupertinoIcons.xmark : CupertinoIcons.pencil,
                    color: JournalColors.accent,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    editing ? 'Cancel Editing' : 'Correct Report Details',
                    style: const TextStyle(
                      color: JournalColors.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: exportingPdf ? null : onExportPdf,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: JournalColors.info.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: JournalColors.info.withValues(alpha: 0.3),
                ),
              ),
              alignment: Alignment.center,
              child: exportingPdf
                  ? const CupertinoActivityIndicator(color: JournalColors.info)
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.doc_richtext,
                          color: JournalColors.info,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Generate PDF',
                          style: TextStyle(
                            color: JournalColors.info,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 14),
          if (editing) ...[
            CupertinoTextField(
              controller: editorController,
              minLines: 14,
              maxLines: null,
              padding: const EdgeInsets.all(14),
              cursorColor: JournalColors.accent,
              style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 14,
                height: 1.5,
              ),
              decoration: BoxDecoration(
                color: JournalColors.bgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: JournalColors.borderBright),
              ),
            ),
            const SizedBox(height: 12),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: saving ? null : onSaveEdit,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color:
                      saving ? JournalColors.bgCardAlt : JournalColors.accent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: JournalColors.borderBright),
                ),
                alignment: Alignment.center,
                child: saving
                    ? const CupertinoActivityIndicator(
                        color: JournalColors.accent,
                      )
                    : const Text(
                        'Save Corrections',
                        style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ] else
            MarkdownBody(
              data: report.result.trim().isEmpty
                  ? 'No generated report text returned.'
                  : report.result,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 15,
                  height: 1.62,
                ),
                h1: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
                h2: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
                h3: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                strong: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
                blockquote: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 15,
                  height: 1.62,
                  fontStyle: FontStyle.italic,
                ),
                blockquotePadding: const EdgeInsets.all(14),
                blockquoteDecoration: BoxDecoration(
                  color: JournalColors.bgSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: JournalColors.borderBright),
                ),
                listBullet: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 15,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SavedReportsSection extends StatelessWidget {
  const _SavedReportsSection({
    required this.reports,
    required this.loading,
    required this.openingId,
    required this.deletingId,
    required this.formatDate,
    required this.onRefresh,
    required this.onOpen,
    required this.onDelete,
  });

  final List<ArgumentTrackerReport> reports;
  final bool loading;
  final String? openingId;
  final String? deletingId;
  final String Function(String value) formatDate;
  final VoidCallback onRefresh;
  final void Function(ArgumentTrackerReport report) onOpen;
  final void Function(ArgumentTrackerReport report) onDelete;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Saved arguments',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28),
                onPressed: onRefresh,
                child: const Icon(
                  CupertinoIcons.refresh,
                  color: JournalColors.accent,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CupertinoActivityIndicator(color: JournalColors.accent),
              ),
            )
          else if (reports.isEmpty)
            const _InlineNotice(
              icon: CupertinoIcons.tray,
              text: 'No saved argument reports yet.',
              color: JournalColors.textMuted,
            )
          else
            Column(
              children: reports
                  .map((report) => _SavedReportRow(
                        report: report,
                        isOpening: openingId == report.id,
                        isDeleting: deletingId == report.id,
                        savedAt: formatDate(report.updatedAt),
                        onOpen: () => onOpen(report),
                        onDelete: () => onDelete(report),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _SavedReportRow extends StatelessWidget {
  const _SavedReportRow({
    required this.report,
    required this.isOpening,
    required this.isDeleting,
    required this.savedAt,
    required this.onOpen,
    required this.onDelete,
  });

  final ArgumentTrackerReport report;
  final bool isOpening;
  final bool isDeleting;
  final String savedAt;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JournalColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JournalColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    report.preview.isEmpty ? savedAt : report.preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    savedAt,
                    style: const TextStyle(
                      color: JournalColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (isOpening || isDeleting)
            const CupertinoActivityIndicator(color: JournalColors.accent)
          else
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(30, 30),
              onPressed: onDelete,
              child: const Icon(
                CupertinoIcons.delete,
                color: JournalColors.danger,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: JournalColors.success.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: JournalColors.success.withValues(alpha: 0.32)),
      ),
      child: Text(
        '$count file${count == 1 ? '' : 's'}',
        style: const TextStyle(
          color: JournalColors.success,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
