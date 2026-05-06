import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/orbit_ledger_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

const _orbitTypeOptions = <String>[
  'Quick Favor',
  'Household',
  'Errand',
  'Childcare',
  'Admin',
  'Emotional Labor',
  'Other',
];

const _orbitUrgencyOptions = <String>[
  'Low',
  'Normal',
  'High',
];

const _quickOrbitItems =
    <({String label, String request, String type, String urgency})>[
  (
    label: 'Water',
    request: 'Brought a bottle of water',
    type: 'Quick Favor',
    urgency: 'Normal',
  ),
  (
    label: 'Trash',
    request: 'Took something out to the trash',
    type: 'Household',
    urgency: 'Normal',
  ),
  (
    label: 'Dish',
    request: 'Brought a dirty dish to the sink',
    type: 'Household',
    urgency: 'Low',
  ),
  (
    label: 'Charger',
    request: 'Grabbed the phone charger',
    type: 'Quick Favor',
    urgency: 'Normal',
  ),
  (
    label: 'Headphones',
    request: 'Grabbed the headphones',
    type: 'Quick Favor',
    urgency: 'Normal',
  ),
  (
    label: 'From car',
    request: 'Retrieved something from the car',
    type: 'Errand',
    urgency: 'Normal',
  ),
  (
    label: 'Upstairs',
    request: 'Retrieved something from upstairs',
    type: 'Errand',
    urgency: 'Normal',
  ),
];

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

class OrbitLedgerScreen extends StatefulWidget {
  const OrbitLedgerScreen({super.key});

  @override
  State<OrbitLedgerScreen> createState() => _OrbitLedgerScreenState();
}

class _OrbitLedgerScreenState extends State<OrbitLedgerScreen> {
  final _service = OrbitLedgerService();
  final _dateFormat = DateFormat('MMM d, yyyy');
  final _timeFormat = DateFormat('h:mm a');

  bool _loading = true;
  String? _error;
  List<OrbitLedgerEntry> _entries = const [];

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
      final entries = await _service.loadEntries();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load Orbit Ledger right now.';
        _loading = false;
      });
    }
  }

  Future<void> _saveEntries(List<OrbitLedgerEntry> entries) async {
    await _service.saveEntries(entries);
    if (!mounted) return;
    setState(() {
      _entries = List<OrbitLedgerEntry>.from(entries)
        ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    });
  }

  Future<void> _openEntrySheet({OrbitLedgerEntry? existing}) async {
    final result = await Navigator.push<OrbitLedgerEntry>(
      context,
      CupertinoPageRoute(
        builder: (context) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: _OrbitEntryScreen(existing: existing),
        ),
      ),
    );
    if (result == null) return;

    final nextEntries = [..._entries];
    final existingIndex =
        nextEntries.indexWhere((item) => item.id == result.id);
    if (existingIndex >= 0) {
      nextEntries[existingIndex] = result;
    } else {
      nextEntries.add(result);
    }
    await _saveEntries(nextEntries);
  }

  Future<void> _addQuickItem(
    ({
      String label,
      String request,
      String type,
      String urgency,
    }) preset,
  ) async {
    final now = DateTime.now();
    final nextEntries = [
      OrbitLedgerEntry(
        id: now.microsecondsSinceEpoch.toString(),
        request: preset.request,
        type: preset.type,
        urgency: preset.urgency,
        loggedAt: now,
      ),
      ..._entries,
    ];
    await _saveEntries(nextEntries);
  }

  Future<void> _deleteEntry(OrbitLedgerEntry entry) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete request?'),
        content: const Text(
          'This removes the item from Orbit Ledger.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final nextEntries = _entries.where((item) => item.id != entry.id).toList();
    await _saveEntries(nextEntries);
  }

  Future<void> _copyContextSummary() async {
    await Clipboard.setData(ClipboardData(text: _buildContextSummary()));
    if (!mounted) return;

    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Copied'),
        content: const Text(
          'The Orbit Ledger context summary is on your clipboard.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _buildContextSummary() {
    final total = _entries.length;
    final highUrgencyCount =
        _entries.where((item) => item.urgency == 'High').length;
    final now = DateTime.now();
    final todayCount = _entries.where((item) {
      return item.loggedAt.year == now.year &&
          item.loggedAt.month == now.month &&
          item.loggedAt.day == now.day;
    }).length;

    final typeCounts = <String, int>{};
    for (final entry in _entries) {
      typeCounts.update(entry.type, (value) => value + 1, ifAbsent: () => 1);
    }

    final topTypes = typeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final recentLines = _entries.take(5).map((entry) {
      return '- ${entry.request} [${entry.type}, ${entry.urgency}, ${_dateFormat.format(entry.loggedAt)} ${_timeFormat.format(entry.loggedAt)}]';
    }).join('\n');

    return [
      'Orbit Ledger',
      'Use this as context for requests, favors, errands, and interruptions that pull on your time and attention.',
      'Total logged: $total',
      'Logged today: $todayCount',
      'High urgency: $highUrgencyCount',
      if (topTypes.isNotEmpty)
        'Top request types: ${topTypes.take(3).map((item) => '${item.key} (${item.value})').join(', ')}',
      if (recentLines.isNotEmpty) 'Recent requests:\n$recentLines',
    ].join('\n');
  }

  int get _highUrgencyCount =>
      _entries.where((item) => item.urgency == 'High').length;

  int get _todayCount {
    final now = DateTime.now();
    return _entries.where((item) {
      return item.loggedAt.year == now.year &&
          item.loggedAt.month == now.month &&
          item.loggedAt.day == now.day;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Orbit Ledger'),
            previousPageTitle: 'More',
            backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CupertinoActivityIndicator(color: JournalColors.accent),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: _OrbitErrorState(
                message: _error!,
                onRetry: _load,
              ),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OrbitHeroCard(
                      totalCount: _entries.length,
                      todayCount: _todayCount,
                      highUrgencyCount: _highUrgencyCount,
                      onAddPressed: _openEntrySheet,
                    ),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Quick Items'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final item in _quickOrbitItems)
                          _QuickOrbitChip(
                            label: item.label,
                            onTap: () => _addQuickItem(item),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Context Name'),
                    const SizedBox(height: 12),
                    GlassCard(
                      accentBorder: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Orbit Ledger',
                            style: TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Use this named context anywhere you want a running record of requests, favors, errands, and attention pulls.',
                            style: TextStyle(
                              color: JournalColors.textSecondary,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          AdaptiveButton(
                            style: AdaptiveButtonStyle.prominentGlass,
                            onPressed:
                                _entries.isEmpty ? null : _copyContextSummary,
                            label: _entries.isEmpty
                                ? 'Log a request first'
                                : 'Copy context summary',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SectionHeader(
                      title: 'Recent Requests',
                      trailing: Text(
                        '${_entries.length} total',
                        style: const TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_entries.isEmpty)
                      const GlassCard(
                        child: _EmptyOrbitState(),
                      )
                    else
                      Column(
                        children: [
                          for (final entry in _entries)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _OrbitEntryCard(
                                entry: entry,
                                dateLabel: _dateFormat.format(entry.loggedAt),
                                timeLabel: _timeFormat.format(entry.loggedAt),
                                onEdit: () => _openEntrySheet(existing: entry),
                                onDelete: () => _deleteEntry(entry),
                              ),
                            ),
                        ],
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

class _OrbitHeroCard extends StatelessWidget {
  const _OrbitHeroCard({
    required this.totalCount,
    required this.todayCount,
    required this.highUrgencyCount,
    required this.onAddPressed,
  });

  final int totalCount;
  final int todayCount;
  final int highUrgencyCount;
  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            JournalColors.accent.withValues(alpha: 0.15),
            JournalColors.bgCard.withValues(alpha: 0.96),
            JournalColors.bgCardAlt.withValues(alpha: 0.94),
          ],
        ),
        border: Border.all(color: JournalColors.borderBright),
        boxShadow: const [
          BoxShadow(
            color: JournalColors.accentGlow,
            blurRadius: 22,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: JournalColors.accent.withValues(alpha: 0.14),
                    border: Border.all(color: JournalColors.borderBright),
                  ),
                  child: const Icon(
                    CupertinoIcons.arrow_2_circlepath_circle,
                    color: JournalColors.textPrimary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Orbit Ledger',
                        style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Keep a visible record of every ask that pulls your time, energy, or attention.',
                        style: TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 14,
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
                _OrbitMetricPill(
                  label: 'Total',
                  value: '$totalCount',
                  color: JournalColors.accent,
                ),
                _OrbitMetricPill(
                  label: 'Today',
                  value: '$todayCount',
                  color: JournalColors.info,
                ),
                _OrbitMetricPill(
                  label: 'Types',
                  value: '${_orbitTypeOptions.length}',
                  color: JournalColors.success,
                ),
                _OrbitMetricPill(
                  label: 'High urgency',
                  value: '$highUrgencyCount',
                  color: JournalColors.danger,
                ),
              ],
            ),
            const SizedBox(height: 18),
            AdaptiveButton(
              style: AdaptiveButtonStyle.prominentGlass,
              onPressed: onAddPressed,
              label: 'Log custom request',
            ),
          ],
        ),
      ),
    );
  }
}

class _OrbitMetricPill extends StatelessWidget {
  const _OrbitMetricPill({
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
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color.withValues(alpha: 0.9),
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

class _QuickOrbitChip extends StatelessWidget {
  const _QuickOrbitChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: JournalColors.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: JournalColors.border),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: JournalColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _OrbitEntryCard extends StatelessWidget {
  const _OrbitEntryCard({
    required this.entry,
    required this.dateLabel,
    required this.timeLabel,
    required this.onEdit,
    required this.onDelete,
  });

  final OrbitLedgerEntry entry;
  final String dateLabel;
  final String timeLabel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Color get _urgencyColor {
    return switch (entry.urgency) {
      'High' => JournalColors.danger,
      'Low' => JournalColors.success,
      _ => JournalColors.severity,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('orbit-ledger-${entry.id}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onDelete();
        } else {
          onEdit();
        }
        return false;
      },
      background: _orbitEntrySwipeBackground(
        alignment: Alignment.centerLeft,
        color: JournalColors.danger,
        icon: CupertinoIcons.trash,
        label: 'Delete',
      ),
      secondaryBackground: _orbitEntrySwipeBackground(
        alignment: Alignment.centerRight,
        color: JournalColors.accent,
        icon: CupertinoIcons.pencil,
        label: 'Edit',
      ),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'REQUEST',
              style: TextStyle(
                color: JournalColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              entry.request,
              style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OrbitMetaChip(
                  label: 'Type',
                  value: entry.type,
                  color: JournalColors.accent,
                ),
                _OrbitMetaChip(
                  label: 'Urgency',
                  value: entry.urgency,
                  color: _urgencyColor,
                ),
                _OrbitMetaChip(
                  label: 'Date',
                  value: dateLabel,
                  color: JournalColors.info,
                ),
                _OrbitMetaChip(
                  label: 'Time',
                  value: timeLabel,
                  color: JournalColors.orange,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  CupertinoIcons.clock,
                  size: 14,
                  color: JournalColors.success,
                ),
                const SizedBox(width: 6),
                Text(
                  'Logged $dateLabel at $timeLabel',
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (entry.note != null && entry.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'NOTE',
                style: TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                entry.note!.trim(),
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
    );
  }

  Widget _orbitEntrySwipeBackground({
    required Alignment alignment,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    final isRight = alignment == Alignment.centerRight;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: color.withValues(alpha: 0.14),
      ),
      padding: EdgeInsets.only(left: isRight ? 0 : 20, right: isRight ? 20 : 0),
      alignment: alignment,
      child: Row(
        mainAxisAlignment:
            isRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isRight) Icon(icon, color: color, size: 18),
          if (!isRight) const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (isRight) const SizedBox(width: 8),
          if (isRight) Icon(icon, color: color, size: 18),
        ],
      ),
    );
  }
}

class _OrbitMetaChip extends StatelessWidget {
  const _OrbitMetaChip({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color.withValues(alpha: 0.9),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyOrbitState extends StatelessWidget {
  const _EmptyOrbitState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nothing logged yet.',
          style: TextStyle(
            color: JournalColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Start with a quick item or a custom request so this ledger becomes a reliable running record.',
          style: TextStyle(
            color: JournalColors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _OrbitErrorState extends StatelessWidget {
  const _OrbitErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle,
              color: JournalColors.textMuted,
              size: 34,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            AdaptiveButton(
              style: AdaptiveButtonStyle.prominentGlass,
              onPressed: onRetry,
              label: 'Retry',
            ),
          ],
        ),
      ),
    );
  }
}

class _OrbitEntryScreen extends StatefulWidget {
  const _OrbitEntryScreen({
    this.existing,
  });

  final OrbitLedgerEntry? existing;

  @override
  State<_OrbitEntryScreen> createState() => _OrbitEntryScreenState();
}

class _OrbitEntryScreenState extends State<_OrbitEntryScreen> {
  late final TextEditingController _requestController;
  late final TextEditingController _noteController;
  late String _type;
  late String _urgency;
  late DateTime _loggedAt;

  void _dismissKeyboard() {
    final focus = FocusScope.of(context);
    if (!focus.hasPrimaryFocus) {
      focus.unfocus();
    }
  }

  @override
  void initState() {
    super.initState();
    _requestController = TextEditingController(
      text: widget.existing?.request ?? '',
    );
    _noteController = TextEditingController(
      text: widget.existing?.note ?? '',
    );
    _type = widget.existing?.type ?? _orbitTypeOptions.first;
    _urgency = widget.existing?.urgency ?? _orbitUrgencyOptions[1];
    _loggedAt = widget.existing?.loggedAt ?? DateTime.now();
  }

  @override
  void dispose() {
    _requestController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    final request = _requestController.text.trim();
    if (request.isEmpty) return;

    final now = DateTime.now();
    final existing = widget.existing;
    Navigator.of(context).pop(
      OrbitLedgerEntry(
        id: existing?.id ?? now.microsecondsSinceEpoch.toString(),
        request: request,
        type: _type,
        urgency: _urgency,
        loggedAt: _loggedAt,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await _showOrbitDatePicker(
      context,
      initial: _loggedAt,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _loggedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _loggedAt.hour,
        _loggedAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await _showOrbitTimePicker(
      context,
      initial: _loggedAt,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _loggedAt = DateTime(
        _loggedAt.year,
        _loggedAt.month,
        _loggedAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final loggedStamp = DateFormat('MMM d, yyyy h:mm a').format(_loggedAt);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final canSave = _requestController.text.trim().isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismissKeyboard,
      child: CupertinoPageScaffold(
        backgroundColor: JournalColors.bgBase,
        navigationBar: CupertinoNavigationBar(
          middle:
              Text(widget.existing == null ? 'Log Request' : 'Edit Request'),
          previousPageTitle: 'Orbit',
          backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
          border: const Border(
            bottom: BorderSide(color: JournalColors.border, width: 0.5),
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(20, 20, 20, keyboardInset + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.existing == null ? 'Log Request' : 'Edit Request',
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Track the request, how urgent it felt, and any context you want later.',
                  style: TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                _OrbitInputField(
                  controller: _requestController,
                  placeholder: 'What was the request?',
                  minLines: 2,
                  maxLines: 4,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                _OrbitPickerRow(
                  title: 'Type',
                  value: _type,
                  options: _orbitTypeOptions,
                  onChanged: (value) => setState(() => _type = value),
                ),
                const SizedBox(height: 14),
                _OrbitPickerRow(
                  title: 'Urgency',
                  value: _urgency,
                  options: _orbitUrgencyOptions,
                  onChanged: (value) => setState(() => _urgency = value),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TIME / DATE',
                        style: TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        loggedStamp,
                        style: const TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AdaptiveButton(
                              onPressed: _pickDate,
                              label: 'Pick date',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AdaptiveButton(
                              onPressed: _pickTime,
                              label: 'Pick time',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'NOTES',
                  style: TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: _noteController,
                  minLines: 3,
                  maxLines: 5,
                  padding: const EdgeInsets.all(14),
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    decoration: TextDecoration.none,
                  ),
                  placeholder:
                      'Optional note: what it interrupted, how it landed, or any context you want later.',
                  placeholderStyle: const TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 14,
                    decoration: TextDecoration.none,
                  ),
                  decoration: BoxDecoration(
                    color: JournalColors.bgSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: JournalColors.border,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        color: JournalColors.bgSurface,
                        borderRadius: BorderRadius.circular(14),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: JournalColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        borderRadius: BorderRadius.circular(14),
                        onPressed: canSave ? _submit : null,
                        child: Text(
                          widget.existing == null
                              ? 'Save Request'
                              : 'Update Request',
                          style: const TextStyle(
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
      ),
    );
  }
}

Future<DateTime?> _showOrbitDatePicker(
  BuildContext context, {
  required DateTime initial,
}) {
  var selected = initial;
  return showCupertinoModalPopup<DateTime>(
    context: context,
    barrierColor: JournalColors.bgBase.withValues(alpha: 0.78),
    builder: (context) => DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: CupertinoPopupSurface(
        isSurfacePainted: false,
        child: Container(
          height: 320,
          decoration: BoxDecoration(
            color: JournalColors.bgCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: JournalColors.border),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: JournalColors.textSecondary),
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'Pick Date',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).pop(selected),
                      child: const Text(
                        'Done',
                        style: TextStyle(color: JournalColors.accent),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: initial,
                  maximumDate: DateTime.now(),
                  onDateTimeChanged: (value) => selected = value,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<DateTime?> _showOrbitTimePicker(
  BuildContext context, {
  required DateTime initial,
}) {
  var selected = DateTime(
    2024,
    1,
    1,
    initial.hour,
    initial.minute,
  );

  return showCupertinoModalPopup<DateTime>(
    context: context,
    barrierColor: JournalColors.bgBase.withValues(alpha: 0.78),
    builder: (context) => DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: CupertinoPopupSurface(
        isSurfacePainted: false,
        child: Container(
          height: 320,
          decoration: BoxDecoration(
            color: JournalColors.bgCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: JournalColors.border),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: JournalColors.textSecondary),
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'Pick Time',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).pop(selected),
                      child: const Text(
                        'Done',
                        style: TextStyle(color: JournalColors.accent),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: selected,
                  use24hFormat: false,
                  onDateTimeChanged: (value) => selected = value,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _OrbitInputField extends StatelessWidget {
  const _OrbitInputField({
    required this.controller,
    required this.placeholder,
    this.minLines = 1,
    this.maxLines = 1,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String placeholder;
  final int minLines;
  final int? maxLines;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      autofocus: autofocus,
      onChanged: onChanged,
      minLines: minLines,
      maxLines: maxLines,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      style: const TextStyle(
        color: JournalColors.textPrimary,
        fontSize: 15,
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
    );
  }
}

class _OrbitPickerRow extends StatelessWidget {
  const _OrbitPickerRow({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JournalColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                GestureDetector(
                  onTap: () => onChanged(option),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: option == value
                          ? _withAlpha(JournalColors.accent, 0.16)
                          : JournalColors.bgCardAlt,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: option == value
                            ? JournalColors.borderBright
                            : JournalColors.border,
                      ),
                    ),
                    child: Text(
                      option,
                      style: TextStyle(
                        color: option == value
                            ? JournalColors.textPrimary
                            : JournalColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
