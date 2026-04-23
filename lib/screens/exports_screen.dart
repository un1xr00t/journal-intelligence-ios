import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

const _packetTypes = [
  _ExportPacket(
    id: 'weekly_digest',
    title: 'Weekly Digest',
    subtitle: 'Summary of a week of entries.',
    icon: CupertinoIcons.rectangle_stack,
    color: JournalColors.success,
  ),
  _ExportPacket(
    id: 'incident_packet',
    title: 'Incident Packet',
    subtitle: 'Focused report on a specific event or period.',
    icon: CupertinoIcons.exclamationmark_triangle,
    color: JournalColors.danger,
  ),
  _ExportPacket(
    id: 'pattern_report',
    title: 'Pattern Report',
    subtitle: 'Full pattern analysis with evidence.',
    icon: CupertinoIcons.chart_bar_square,
    color: JournalColors.severity,
  ),
  _ExportPacket(
    id: 'therapy_summary',
    title: 'Therapy Summary',
    subtitle: 'Clinician-friendly narrative summary.',
    icon: CupertinoIcons.doc_text,
    color: JournalColors.info,
  ),
  _ExportPacket(
    id: 'chronology',
    title: 'Facts Chronology',
    subtitle: 'Timestamped factual record only.',
    icon: CupertinoIcons.calendar,
    color: JournalColors.accent,
  ),
];

class ExportsScreen extends StatefulWidget {
  const ExportsScreen({super.key});

  @override
  State<ExportsScreen> createState() => _ExportsScreenState();
}

class _ExportsScreenState extends State<ExportsScreen> {
  final _api = ApiService();
  final _dateFormat = DateFormat('yyyy-MM-dd');

  String _packetType = 'weekly_digest';
  bool _redact = false;
  bool _generating = false;
  bool _downloading = false;
  String? _status;
  bool _isError = false;
  Map<String, dynamic>? _result;

  DateTime? _dateStart;
  DateTime? _dateEnd;

  String? get _startValue =>
      _dateStart == null ? null : _dateFormat.format(_dateStart!);
  String? get _endValue =>
      _dateEnd == null ? null : _dateFormat.format(_dateEnd!);

  _ExportPacket get _selectedPacket {
    return _packetTypes.firstWhere((packet) => packet.id == _packetType);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart
        ? _dateStart ?? DateTime.now().subtract(const Duration(days: 7))
        : _dateEnd ?? DateTime.now();
    var selected = current;

    final picked = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (context) {
        return Container(
          height: 340,
          color: JournalColors.bgCard,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Row(
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(context, selected),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: current,
                    maximumDate: DateTime.now(),
                    onDateTimeChanged: (value) => selected = value,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked == null || !mounted) return;
    setState(() {
      final normalized = DateTime(picked.year, picked.month, picked.day);
      if (isStart) {
        _dateStart = normalized;
        if (_dateEnd != null && _dateStart!.isAfter(_dateEnd!)) {
          _dateEnd = _dateStart;
        }
      } else {
        _dateEnd = normalized;
        if (_dateStart != null && _dateEnd!.isBefore(_dateStart!)) {
          _dateStart = _dateEnd;
        }
      }
      _status = null;
      _result = null;
    });
  }

  Future<void> _generate() async {
    if (_startValue == null || _endValue == null) {
      setState(() {
        _status = 'Select a date range.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _generating = true;
      _status = null;
      _isError = false;
      _result = null;
    });

    try {
      final generated = await _api.generateExport(
        packetType: _packetType,
        dateStart: _startValue!,
        dateEnd: _endValue!,
        redact: _redact,
      );
      if (!mounted) return;
      setState(() {
        _result = generated;
        _status = null;
        _isError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _parseError(e);
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _downloadResult() async {
    final result = _result;
    final exportId = _readInt(result?['export_id']);
    if (exportId == null) {
      setState(() {
        _status = 'Export response did not include an export id.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _downloading = true;
      _status = null;
      _isError = false;
    });

    late String filename;
    late List<int> bytes;
    late File file;

    try {
      filename = _cleanFilename(
        result?['filename'] as String? ?? 'export_$exportId.pdf',
      );
      final response = await _api.fetchExportBlob(exportId);
      bytes = List<int>.from(response.data ?? const <int>[]);
      if (bytes.isEmpty) {
        throw Exception('Downloaded file was empty.');
      }
      final contentType = response.headers.value('content-type') ?? '';
      if (contentType.contains('application/json') ||
          contentType.contains('text/html')) {
        throw Exception(
          'Server returned $contentType: ${_decodeBytesPreview(bytes)}',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Download failed — ${_downloadError(e, exportId, result)}';
        _isError = true;
      });
      if (mounted) setState(() => _downloading = false);
      return;
    }

    try {
      final dir = await Directory.systemTemp.createTemp('journal_exports_');
      file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      if (!await file.exists() || await file.length() == 0) {
        throw Exception('Saved file was empty.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'File save failed — ${_parseError(e)}';
        _isError = true;
      });
      if (mounted) setState(() => _downloading = false);
      return;
    }

    try {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Journal export',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Sharing failed — ${_parseError(e)}';
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String _parseError(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
      if (data is String && data.trim().isNotEmpty) {
        final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(data);
        return match?.group(1) ?? data;
      }
      if (data is List<int>) {
        final decoded = utf8.decode(data, allowMalformed: true).trim();
        if (decoded.isNotEmpty) {
          final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(decoded);
          return match?.group(1) ?? decoded;
        }
      }
      if (e.message != null && e.message!.isNotEmpty) return e.message!;
    }
    final str = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    if (match != null) return match.group(1)!;
    if (str.contains('503')) return 'Export service is not available.';
    if (str.contains('404')) return 'Export file was not found.';
    return str.replaceFirst(RegExp(r'^(Exception|Error):\s*'), '');
  }

  String _downloadError(
    dynamic error,
    int exportId,
    Map<String, dynamic>? result,
  ) {
    final details = <String>[
      _parseError(error),
      'id: $exportId',
      if (result?['filename'] != null) 'file: ${result!['filename']}',
    ];

    if (error is DioException) {
      final status = error.response?.statusCode;
      final contentType = error.response?.headers.value('content-type');
      final data = error.response?.data;
      if (status != null) details.add('status: $status');
      if (contentType != null) details.add('type: $contentType');
      if (data is List<int>) {
        final decoded = utf8.decode(data, allowMalformed: true).trim();
        if (decoded.isNotEmpty) details.add('body: $decoded');
      } else if (data != null) {
        details.add('body: $data');
      }
    }

    return details.join(' · ');
  }

  String _decodeBytesPreview(List<int> bytes) {
    final preview = bytes.take(500).toList();
    return utf8.decode(preview, allowMalformed: true).trim();
  }

  String _cleanFilename(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: Stack(
        children: [
          const Positioned.fill(child: _ExportsBackdrop()),
          CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('Exports'),
                backgroundColor: _withAlpha(JournalColors.bgBase, 0.88),
                border: const Border(
                  bottom: BorderSide(color: JournalColors.border, width: 0.5),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _ExportsHero(
                      title: _selectedPacket.title,
                      dateStart: _startValue,
                      dateEnd: _endValue,
                    ),
                    const SizedBox(height: 20),
                    const SectionHeader(title: 'Export Type'),
                    const SizedBox(height: 10),
                    for (final packet in _packetTypes) ...[
                      _ExportOptionCard(
                        packet: packet,
                        selected: _packetType == packet.id,
                        onTap: _generating
                            ? null
                            : () => setState(() {
                                  _packetType = packet.id;
                                  _status = null;
                                  _result = null;
                                }),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 12),
                    const SectionHeader(title: 'Date Range'),
                    const SizedBox(height: 10),
                    GlassCard(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _DateButton(
                                  label: 'Start',
                                  value: _startValue ?? 'Select',
                                  onTap: _generating
                                      ? null
                                      : () => _pickDate(isStart: true),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _DateButton(
                                  label: 'End',
                                  value: _endValue ?? 'Select',
                                  onTap: _generating
                                      ? null
                                      : () => _pickDate(isStart: false),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _RedactRow(
                            value: _redact,
                            onChanged: _generating
                                ? null
                                : (value) => setState(() {
                                      _redact = value;
                                      _status = null;
                                      _result = null;
                                    }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _GenerateButton(
                      generating: _generating,
                      label: _selectedPacket.title,
                      onPressed: _generate,
                    ),
                    if (_status != null) ...[
                      const SizedBox(height: 14),
                      _StatusBanner(message: _status!, isError: _isError),
                    ],
                    if (_result != null) ...[
                      const SizedBox(height: 14),
                      _ResultCard(
                        result: _result!,
                        downloading: _downloading,
                        onDownload: _downloadResult,
                      ),
                    ],
                    const SizedBox(height: 22),
                    const SectionHeader(title: 'Notes'),
                    const SizedBox(height: 10),
                    const _NotesCard(),
                    const SizedBox(height: 20),
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

class _ExportPacket {
  const _ExportPacket({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _ExportsBackdrop extends StatelessWidget {
  const _ExportsBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _withAlpha(JournalColors.bgCardAlt, 0.92),
              JournalColors.bgBase,
              _withAlpha(JournalColors.bgSurface, 0.72),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportsHero extends StatelessWidget {
  const _ExportsHero({
    required this.title,
    required this.dateStart,
    required this.dateEnd,
  });

  final String title;
  final String? dateStart;
  final String? dateEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: JournalColors.borderBright),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _withAlpha(JournalColors.bgCard, 0.97),
            _withAlpha(JournalColors.bgCardAlt, 0.94),
            _withAlpha(JournalColors.bgSurface, 0.90),
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: JournalColors.accentGlow,
            blurRadius: 26,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroGlyph(icon: CupertinoIcons.arrow_up_doc, size: 22),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EXPORTS',
                      style: TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Create a file from your journal records.',
                      style: TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.22,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryPill(label: title),
              _SummaryPill(
                label: dateStart == null || dateEnd == null
                    ? 'Select dates'
                    : '$dateStart to $dateEnd',
              ),
              const _SummaryPill(label: 'PDF'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExportOptionCard extends StatelessWidget {
  const _ExportOptionCard({
    required this.packet,
    required this.selected,
    required this.onTap,
  });

  final _ExportPacket packet;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accentBorder: selected,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _withAlpha(packet.color, selected ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _withAlpha(packet.color, 0.26)),
            ),
            child: Icon(packet.icon, color: packet.color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        packet.title,
                        style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 10),
                      Icon(
                        CupertinoIcons.checkmark_circle_fill,
                        color: packet.color,
                        size: 18,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  packet.subtitle,
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

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _withAlpha(JournalColors.bgSurface, 0.74),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: JournalColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: JournalColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(
                  CupertinoIcons.calendar,
                  color: JournalColors.textMuted,
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RedactRow extends StatelessWidget {
  const _RedactRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.58),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JournalColors.border),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Redact sensitive details',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Use the backend redaction pass before creating the file.',
                  style: TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
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
      ),
    );
  }
}

class _GenerateButton extends StatelessWidget {
  const _GenerateButton({
    required this.generating,
    required this.label,
    required this.onPressed,
  });

  final bool generating;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton(
        color: JournalColors.accent,
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.symmetric(vertical: 15),
        onPressed: generating ? null : onPressed,
        child: generating
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoActivityIndicator(color: CupertinoColors.white),
                  SizedBox(width: 10),
                  Text(
                    'Generating export',
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.square_arrow_up,
                    color: CupertinoColors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Generate $label',
                    style: const TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.downloading,
    required this.onDownload,
  });

  final Map<String, dynamic> result;
  final bool downloading;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final message = result['message']?.toString().trim();
    return GlassCard(
      accentBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.success, 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _withAlpha(JournalColors.success, 0.26),
                  ),
                ),
                child: const Icon(
                  CupertinoIcons.check_mark,
                  color: JournalColors.success,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Export ready',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (message != null && message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 14),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: _withAlpha(JournalColors.accent, 0.18),
            borderRadius: BorderRadius.circular(14),
            onPressed: downloading ? null : onDownload,
            child: downloading
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoActivityIndicator(
                        color: JournalColors.textPrimary,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Opening',
                        style: TextStyle(color: JournalColors.textPrimary),
                      ),
                    ],
                  )
                : const Text(
                    'Download export',
                    style: TextStyle(
                      color: JournalColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? JournalColors.danger : JournalColors.success;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _withAlpha(color, 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _withAlpha(color, 0.24)),
      ),
      child: Row(
        children: [
          Icon(
            isError
                ? CupertinoIcons.exclamationmark_triangle_fill
                : CupertinoIcons.check_mark_circled_solid,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard();

  @override
  Widget build(BuildContext context) {
    return const GlassCard(
      child: Text(
        'Exports are generated on the server, downloaded to a temporary local file, then opened through the share sheet.',
        style: TextStyle(
          color: JournalColors.textSecondary,
          fontSize: 14,
          height: 1.55,
        ),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgBase, 0.32),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: JournalColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: JournalColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HeroGlyph extends StatelessWidget {
  const _HeroGlyph({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            _withAlpha(JournalColors.accent, 0.28),
            _withAlpha(JournalColors.info, 0.16),
          ],
        ),
        border: Border.all(color: JournalColors.borderBright),
      ),
      child: Icon(icon, color: JournalColors.textPrimary, size: size),
    );
  }
}
