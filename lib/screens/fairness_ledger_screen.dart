import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

const _fairnessCategories = <_FairnessCategory>[
  _FairnessCategory('childcare', 'Childcare', '◎'),
  _FairnessCategory('chores', 'Chores', '⬡'),
  _FairnessCategory('emotional_labor', 'Emotional Labor', '〜'),
  _FairnessCategory('finances', 'Finances', '◈'),
  _FairnessCategory('logistics', 'Logistics', '▷'),
];

const _relationshipOptions = <String>[
  'Partner',
  'Co-parent',
  'Spouse',
  'Child',
  'Roommate',
  'Sibling',
  'Other',
];

class FairnessLedgerScreen extends StatefulWidget {
  const FairnessLedgerScreen({super.key});

  @override
  State<FairnessLedgerScreen> createState() => _FairnessLedgerScreenState();
}

class _FairnessLedgerScreenState extends State<FairnessLedgerScreen> {
  final _api = ApiService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _config;
  List<dynamic> _tasks = const [];
  List<dynamic> _logs = const [];
  List<dynamic> _contributions = const [];
  Map<String, dynamic>? _summary;
  bool _generating = false;
  int _tabIndex = 0;

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
      final config = await _api.getFairnessConfig();
      if ((config['configured'] as bool?) != true) {
        if (mounted) {
          setState(() {
            _config = config;
            _loading = false;
          });
        }
        return;
      }

      final results = await Future.wait([
        _api.getFairnessTasks().catchError((_) => <dynamic>[]),
        _api.getFairnessLogs(limit: 60).catchError((_) => <dynamic>[]),
        _api.getFairnessContributions(limit: 60).catchError((_) => <dynamic>[]),
        _api
            .getFairnessSummary()
            .catchError((_) => <String, dynamic>{'exists': false}),
      ]);

      if (mounted) {
        setState(() {
          _config = config;
          _tasks = List<dynamic>.from(results[0] as List<dynamic>);
          _logs = List<dynamic>.from(results[1] as List<dynamic>);
          _contributions = List<dynamic>.from(results[2] as List<dynamic>);
          _summary = Map<String, dynamic>.from(results[3] as Map);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _parseError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveSetup(Map<String, dynamic> payload) async {
    await _api.saveFairnessConfig(payload);
    await _load();
  }

  Future<void> _openLogTask() async {
    if (_tasks.whereType<Map>().every((task) => task['is_active'] != true)) {
      await _showInfoDialog(
        title: 'No active tasks',
        message:
            'This ledger has no active tasks to log yet. You can still add a freeform contribution.',
      );
      return;
    }

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _unstyledOverlay(
        _SheetHost(
          child: _LogTaskSheet(
            tasks: _tasks,
            myName: _personName('me'),
            partnerName: _personName('partner'),
            member3Name: _member3Name,
            onSubmit: (taskId, who, note) async {
              await _api.logFairnessTask(
                taskId: taskId,
                performedBy: who,
                note: note,
              );
              if (mounted) Navigator.of(context).pop();
              await _load();
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openContribution() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _unstyledOverlay(
        _SheetHost(
          child: _ContributionSheet(
            myName: _personName('me'),
            partnerName: _personName('partner'),
            member3Name: _member3Name,
            onSubmit: (payload) async {
              await _api.createFairnessContribution(payload);
              if (mounted) Navigator.of(context).pop();
              await _load();
            },
          ),
        ),
      ),
    );
  }

  Future<void> _generateSummary() async {
    setState(() => _generating = true);
    try {
      final summary = await _api.generateFairnessSummary();
      if (mounted) {
        setState(() {
          _summary = <String, dynamic>{'exists': true, ...summary};
          _generating = false;
          _tabIndex = 2;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _generating = false);
        await _showInfoDialog(
          title: 'Generation failed',
          message: _parseError(e),
        );
      }
    }
  }

  Future<void> _deleteLog(int id) async {
    await _api.deleteFairnessLog(id);
    await _load();
  }

  Future<void> _deleteContribution(int id) async {
    await _api.deleteFairnessContribution(id);
    await _load();
  }

  Future<void> _showInfoDialog({
    required String title,
    required String message,
  }) async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => _unstyledOverlay(
        _FairnessMessageDialog(
          title: title,
          message: message,
        ),
      ),
    );
  }

  String _personName(String who) {
    final config = _config ?? const <String, dynamic>{};
    if (who == 'me') {
      return (config['my_name'] as String?)?.trim().isNotEmpty == true
          ? config['my_name'] as String
          : 'Me';
    }
    if (who == 'partner') {
      return (config['partner_name'] as String?)?.trim().isNotEmpty == true
          ? config['partner_name'] as String
          : 'Partner';
    }
    if (who == 'member3') {
      return _member3Name ?? 'Member 3';
    }
    return who;
  }

  String? get _member3Name {
    final value = (_config?['member3_name'] as String?)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Fairness Ledger'),
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
              child: _ErrorState(
                message: _error!,
                onRetry: _load,
              ),
            )
          else if ((_config?['configured'] as bool?) != true)
            SliverToBoxAdapter(
              child: _FairnessSetupView(onSave: _saveSetup),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeaderCard(
                      myName: _personName('me'),
                      partnerName: _personName('partner'),
                      member3Name: _member3Name,
                      onLogTask: _openLogTask,
                      onAddContribution: _openContribution,
                    ),
                    const SizedBox(height: 16),
                    _TabBar(
                      index: _tabIndex,
                      onChanged: (index) => setState(() => _tabIndex = index),
                    ),
                    const SizedBox(height: 16),
                    if (_tabIndex == 0)
                      _OverviewTab(
                        summary: _summary,
                        myName: _personName('me'),
                        partnerName: _personName('partner'),
                        member3Name: _member3Name,
                      )
                    else if (_tabIndex == 1)
                      _HistoryTab(
                        logs: _logs,
                        contributions: _contributions,
                        myName: _personName('me'),
                        partnerName: _personName('partner'),
                        member3Name: _member3Name,
                        onDeleteLog: _deleteLog,
                        onDeleteContribution: _deleteContribution,
                      )
                    else
                      _AssessmentTab(
                        summary: _summary,
                        generating: _generating,
                        onGenerate: _generateSummary,
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

class _FairnessCategory {
  final String key;
  final String label;
  final String icon;

  const _FairnessCategory(this.key, this.label, this.icon);
}

class _HeaderCard extends StatelessWidget {
  final String myName;
  final String partnerName;
  final String? member3Name;
  final VoidCallback onLogTask;
  final VoidCallback onAddContribution;

  const _HeaderCard({
    required this.myName,
    required this.partnerName,
    required this.member3Name,
    required this.onLogTask,
    required this.onAddContribution,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accentBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(CupertinoIcons.equal_circle,
                  color: JournalColors.severity, size: 22),
              SizedBox(width: 10),
              Text(
                'Track who does what',
                style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            [myName, partnerName, if (member3Name != null) member3Name!]
                .join(' · '),
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          AdaptiveButton(
            style: AdaptiveButtonStyle.prominentGlass,
            onPressed: onLogTask,
            label: 'Log Task',
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              color: JournalColors.bgCardAlt,
              borderRadius: BorderRadius.circular(14),
              onPressed: onAddContribution,
              child: const Text(
                'Add Contribution',
                style: TextStyle(
                  color: JournalColors.accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _TabBar({
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: JournalColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JournalColors.border),
      ),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final selected = i == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? JournalColors.accent : JournalColors.bgCard,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _tabs[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected
                        ? JournalColors.textPrimary
                        : JournalColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

const _tabs = ['OVERVIEW', 'HISTORY', 'ASSESSMENT'];

class _OverviewTab extends StatelessWidget {
  final Map<String, dynamic>? summary;
  final String myName;
  final String partnerName;
  final String? member3Name;

  const _OverviewTab({
    required this.summary,
    required this.myName,
    required this.partnerName,
    required this.member3Name,
  });

  @override
  Widget build(BuildContext context) {
    final score = summary?['score'] as Map<String, dynamic>?;
    return Column(
      children: [
        _ScoreBar(
          myName: myName,
          partnerName: partnerName,
          member3Name: member3Name,
          score: score,
        ),
        const SizedBox(height: 16),
        _PersonTotals(
          myName: myName,
          partnerName: partnerName,
          member3Name: member3Name,
          score: score,
        ),
      ],
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final String myName;
  final String partnerName;
  final String? member3Name;
  final Map<String, dynamic>? score;

  const _ScoreBar({
    required this.myName,
    required this.partnerName,
    required this.member3Name,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final meTotal = _totalFor(score, 'me');
    final partnerTotal = _totalFor(score, 'partner');
    final member3Total = _totalFor(score, 'member3');
    final grandTotal = meTotal + partnerTotal + member3Total;

    final meFraction = grandTotal == 0 ? 0.0 : meTotal / grandTotal;
    final partnerFraction = grandTotal == 0 ? 0.0 : partnerTotal / grandTotal;
    final member3Fraction = grandTotal == 0 ? 0.0 : member3Total / grandTotal;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OVERALL LOAD SPLIT',
            style: TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  if (meFraction > 0)
                    Expanded(
                      flex: (meFraction * 1000).round(),
                      child: Container(color: JournalColors.accent),
                    ),
                  if (partnerFraction > 0)
                    Expanded(
                      flex: (partnerFraction * 1000).round(),
                      child: Container(color: JournalColors.textMuted),
                    ),
                  if (member3Name != null && member3Fraction > 0)
                    Expanded(
                      flex: (member3Fraction * 1000).round(),
                      child: Container(color: JournalColors.accent2),
                    ),
                  if (grandTotal == 0)
                    const Expanded(
                        child: ColoredBox(color: JournalColors.border)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _LegendChip(
                name: myName,
                total: meTotal,
                percent: _percent(meFraction),
                color: JournalColors.accent,
              ),
              _LegendChip(
                name: partnerName,
                total: partnerTotal,
                percent: _percent(partnerFraction),
                color: JournalColors.textMuted,
              ),
              if (member3Name != null)
                _LegendChip(
                  name: member3Name!,
                  total: member3Total,
                  percent: _percent(member3Fraction),
                  color: JournalColors.accent2,
                ),
            ],
          ),
          const SizedBox(height: 20),
          for (final category in _fairnessCategories)
            _CategorySplitRow(
              category: category,
              myName: myName,
              partnerName: partnerName,
              member3Name: member3Name,
              meValue: _categoryTotal(score, 'me', category.key),
              partnerValue: _categoryTotal(score, 'partner', category.key),
              member3Value: _categoryTotal(score, 'member3', category.key),
            ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String name;
  final int total;
  final int percent;
  final Color color;

  const _LegendChip({
    required this.name,
    required this.total,
    required this.percent,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$name $percent% · $total',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CategorySplitRow extends StatelessWidget {
  final _FairnessCategory category;
  final String myName;
  final String partnerName;
  final String? member3Name;
  final int meValue;
  final int partnerValue;
  final int member3Value;

  const _CategorySplitRow({
    required this.category,
    required this.myName,
    required this.partnerName,
    required this.member3Name,
    required this.meValue,
    required this.partnerValue,
    required this.member3Value,
  });

  @override
  Widget build(BuildContext context) {
    final total = meValue + partnerValue + member3Value;
    if (total == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${category.icon} ${category.label}',
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '$myName: $meValue · $partnerName: $partnerValue${member3Name != null ? ' · $member3Name: $member3Value' : ''}',
                style: const TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  Expanded(
                    flex: meValue == 0 ? 1 : meValue,
                    child: Container(
                      color: meValue == 0
                          ? JournalColors.bgBase
                          : JournalColors.accent,
                    ),
                  ),
                  Expanded(
                    flex: partnerValue == 0 ? 1 : partnerValue,
                    child: Container(
                      color: partnerValue == 0
                          ? JournalColors.bgBase
                          : JournalColors.textMuted,
                    ),
                  ),
                  if (member3Name != null)
                    Expanded(
                      flex: member3Value == 0 ? 1 : member3Value,
                      child: Container(
                        color: member3Value == 0
                            ? JournalColors.bgBase
                            : JournalColors.accent2,
                      ),
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

class _PersonTotals extends StatelessWidget {
  final String myName;
  final String partnerName;
  final String? member3Name;
  final Map<String, dynamic>? score;

  const _PersonTotals({
    required this.myName,
    required this.partnerName,
    required this.member3Name,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final cards = <Map<String, dynamic>>[
      {
        'name': myName,
        'total': _totalFor(score, 'me'),
        'color': JournalColors.accent,
      },
      {
        'name': partnerName,
        'total': _totalFor(score, 'partner'),
        'color': JournalColors.textMuted,
      },
      if (member3Name != null)
        {
          'name': member3Name,
          'total': _totalFor(score, 'member3'),
          'color': JournalColors.accent2,
        },
    ];

    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          Expanded(
            child: GlassCard(
              child: Column(
                children: [
                  Text(
                    '${cards[i]['total']}',
                    style: TextStyle(
                      color: cards[i]['color'] as Color,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cards[i]['name'] as String,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: JournalColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (i < cards.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final List<dynamic> logs;
  final List<dynamic> contributions;
  final String myName;
  final String partnerName;
  final String? member3Name;
  final Future<void> Function(int id) onDeleteLog;
  final Future<void> Function(int id) onDeleteContribution;

  const _HistoryTab({
    required this.logs,
    required this.contributions,
    required this.myName,
    required this.partnerName,
    required this.member3Name,
    required this.onDeleteLog,
    required this.onDeleteContribution,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Map<String, dynamic>>[
      ...logs.map((item) => <String, dynamic>{
            ...Map<String, dynamic>.from(item as Map),
            '_kind': 'log',
            '_sortDate': item['logged_at'] ?? '',
          }),
      ...contributions.map((item) => <String, dynamic>{
            ...Map<String, dynamic>.from(item as Map),
            '_kind': 'contribution',
            '_sortDate': '${item['contribution_date'] ?? ''}T23:59:59',
          }),
    ]..sort((a, b) => '${b['_sortDate']}'.compareTo('${a['_sortDate']}'));

    if (items.isEmpty) {
      return const GlassCard(
        child: Text(
          'No entries yet.',
          style: TextStyle(
            color: JournalColors.textMuted,
            fontSize: 14,
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final item in items.take(50)) ...[
          _HistoryRow(
            item: item,
            myName: myName,
            partnerName: partnerName,
            member3Name: member3Name,
            onDelete: () async {
              final id = (item['id'] as num?)?.toInt();
              if (id == null) return;
              if (item['_kind'] == 'log') {
                await onDeleteLog(id);
              } else {
                await onDeleteContribution(id);
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final String myName;
  final String partnerName;
  final String? member3Name;
  final Future<void> Function() onDelete;

  const _HistoryRow({
    required this.item,
    required this.myName,
    required this.partnerName,
    required this.member3Name,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final category = _categoryByKey(item['category'] as String?);
    final who = _whoLabel(
      item['performed_by'] as String?,
      myName,
      partnerName,
      member3Name,
    );
    final whoColor = _whoColor(item['performed_by'] as String?);
    final isContribution = item['_kind'] == 'contribution';

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            category?.icon ?? '◌',
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      who,
                      style: TextStyle(
                        color: whoColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _Badge(
                        text: isContribution
                            ? category?.label ?? 'Contribution'
                            : '${item['task_name'] ?? 'Task'}'),
                    if (isContribution)
                      const _Badge(
                        text: 'freeform',
                        color: JournalColors.accent2,
                      ),
                  ],
                ),
                if (isContribution &&
                    (item['description'] as String?)?.trim().isNotEmpty ==
                        true) ...[
                  const SizedBox(height: 4),
                  Text(
                    item['description'] as String,
                    style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
                if ((item['note'] as String?)?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    item['note'] as String,
                    style: const TextStyle(
                      color: JournalColors.textMuted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  _formatHistoryDate(
                    isContribution
                        ? item['contribution_date'] as String?
                        : item['logged_at'] as String?,
                  ),
                  style: const TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDelete,
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(
                CupertinoIcons.xmark,
                color: JournalColors.textMuted,
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({
    required this.text,
    this.color = JournalColors.textMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: JournalColors.bgCardAlt,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _AssessmentTab extends StatelessWidget {
  final Map<String, dynamic>? summary;
  final bool generating;
  final Future<void> Function() onGenerate;

  const _AssessmentTab({
    required this.summary,
    required this.generating,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final exists = (summary?['exists'] as bool?) == true;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'AI ASSESSMENT',
                  style: TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                borderRadius: BorderRadius.circular(8),
                color: JournalColors.bgCardAlt,
                onPressed: generating ? null : onGenerate,
                child: Text(
                  generating
                      ? 'Generating…'
                      : exists
                          ? 'Regenerate'
                          : 'Generate',
                  style: const TextStyle(
                    color: JournalColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (generating)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CupertinoActivityIndicator(color: JournalColors.accent),
              ),
            )
          else if (!exists)
            const Text(
              'Log some tasks first, then generate your first assessment.',
              style: TextStyle(
                color: JournalColors.textMuted,
                fontSize: 14,
                height: 1.6,
              ),
            )
          else ...[
            Text(
              summary?['summary_text'] as String? ??
                  summary?['summary'] as String? ??
                  'No assessment text available.',
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
                height: 1.75,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Based on ${summary?['log_count'] ?? 0} entries · Last updated ${_formatHistoryDate(summary?['generated_at'] as String?)}',
              style: const TextStyle(
                color: JournalColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FairnessSetupView extends StatefulWidget {
  final Future<void> Function(Map<String, dynamic> payload) onSave;

  const _FairnessSetupView({
    required this.onSave,
  });

  @override
  State<_FairnessSetupView> createState() => _FairnessSetupViewState();
}

class _FairnessSetupViewState extends State<_FairnessSetupView> {
  final _myNameController = TextEditingController(text: 'Me');

  final List<_PersonDraft> _others = [];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _myNameController.dispose();
    for (final draft in _others) {
      draft.dispose();
    }
    super.dispose();
  }

  void _addPerson() {
    if (_others.length >= 2) return;
    setState(() {
      _others.add(_PersonDraft());
      _error = null;
    });
  }

  void _removePerson(int index) {
    setState(() {
      _others.removeAt(index).dispose();
    });
  }

  Future<void> _save() async {
    if (_others.isEmpty || _others.first.nameController.text.trim().isEmpty) {
      setState(() => _error = 'Add at least one other person.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.onSave({
        'my_name': _myNameController.text.trim().isEmpty
            ? 'Me'
            : _myNameController.text.trim(),
        'partner_name': _others.first.nameController.text.trim(),
        'partner_relationship': _others.first.relationship,
        'member3_name': _others.length > 1 &&
                _others[1].nameController.text.trim().isNotEmpty
            ? _others[1].nameController.text.trim()
            : null,
        'member3_relationship':
            _others.length > 1 ? _others[1].relationship : null,
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _parseError(e);
          _saving = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        children: [
          GlassCard(
            accentBorder: true,
            child: Column(
              children: [
                const Icon(
                  CupertinoIcons.equal_circle,
                  color: JournalColors.severity,
                  size: 34,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Fairness Ledger',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Track who does what. Let the data speak.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                const _FieldLabel('Your name'),
                _TextInput(
                  controller: _myNameController,
                  placeholder: 'Me',
                ),
                for (var i = 0; i < _others.length; i++) ...[
                  const SizedBox(height: 16),
                  _SetupPersonCard(
                    index: i,
                    draft: _others[i],
                    onRemove: () => _removePerson(i),
                    onChanged: () => setState(() => _error = null),
                  ),
                ],
                if (_others.length < 2) ...[
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _addPerson,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: JournalColors.border),
                        color: JournalColors.bgBase,
                      ),
                      child: Text(
                        _others.isEmpty
                            ? '+ Add someone to track'
                            : '+ Add another person',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: JournalColors.danger,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                AdaptiveButton(
                  style: AdaptiveButtonStyle.prominentGlass,
                  onPressed: _saving || _others.isEmpty ? null : _save,
                  label: _saving ? 'Setting up…' : 'Set Up Ledger',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonDraft {
  final TextEditingController nameController = TextEditingController();
  String? relationship;

  void dispose() {
    nameController.dispose();
  }
}

class _SetupPersonCard extends StatelessWidget {
  final int index;
  final _PersonDraft draft;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _SetupPersonCard({
    required this.index,
    required this.draft,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JournalColors.bgBase,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Person ${index + 2}',
                style: const TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(
                  CupertinoIcons.xmark,
                  color: JournalColors.textMuted,
                  size: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _TextInput(
            controller: draft.nameController,
            placeholder: 'Their name',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 12),
          const _FieldLabel('Their relationship to you'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final relationship in _relationshipOptions)
                _ChoiceChip(
                  label: relationship,
                  selected: draft.relationship == relationship,
                  onTap: () {
                    draft.relationship = relationship;
                    onChanged();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: JournalColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? JournalColors.accent : JournalColors.bgBase,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? JournalColors.accent : JournalColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? JournalColors.textPrimary : JournalColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final int minLines;
  final int? maxLines;

  const _TextInput({
    required this.controller,
    required this.placeholder,
    this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      onChanged: onChanged,
      minLines: minLines,
      maxLines: maxLines,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      placeholder: placeholder,
      style: const TextStyle(
        color: JournalColors.textPrimary,
        fontSize: 14,
      ),
      placeholderStyle: const TextStyle(
        color: JournalColors.textMuted,
      ),
      decoration: BoxDecoration(
        color: JournalColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JournalColors.border),
      ),
    );
  }
}

class _SheetHost extends StatelessWidget {
  final Widget child;

  const _SheetHost({required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        color: JournalColors.glassBg,
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {},
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _FairnessMessageDialog extends StatelessWidget {
  final String title;
  final String message;

  const _FairnessMessageDialog({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: GlassCard(
          accentBorder: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 14,
                  height: 1.6,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: AdaptiveButton(
                  style: AdaptiveButtonStyle.prominentGlass,
                  onPressed: () => Navigator.of(context).pop(),
                  label: 'OK',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogTaskSheet extends StatefulWidget {
  final List<dynamic> tasks;
  final String myName;
  final String partnerName;
  final String? member3Name;
  final Future<void> Function(int taskId, String who, String? note) onSubmit;

  const _LogTaskSheet({
    required this.tasks,
    required this.myName,
    required this.partnerName,
    required this.member3Name,
    required this.onSubmit,
  });

  @override
  State<_LogTaskSheet> createState() => _LogTaskSheetState();
}

class _LogTaskSheetState extends State<_LogTaskSheet> {
  String _who = 'me';
  String _filter = 'all';
  int? _taskId;
  final _noteController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.tasks
        .whereType<Map>()
        .where((task) {
          if (task['is_active'] != true) return false;
          if (_filter == 'all') return true;
          return task['category'] == _filter;
        })
        .map((task) => Map<String, dynamic>.from(task))
        .toList();

    return Container(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
      decoration: BoxDecoration(
        color: JournalColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHeader(title: 'Log a Task'),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _WhoPicker(
                    value: _who,
                    myName: widget.myName,
                    partnerName: widget.partnerName,
                    member3Name: widget.member3Name,
                    onChanged: (value) => setState(() => _who = value),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _ChoiceChip(
                        label: 'All',
                        selected: _filter == 'all',
                        onTap: () => setState(() => _filter = 'all'),
                      ),
                      for (final category in _fairnessCategories)
                        _ChoiceChip(
                          label: '${category.icon} ${category.label}',
                          selected: _filter == category.key,
                          onTap: () => setState(() => _filter = category.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  for (final task in tasks) ...[
                    GestureDetector(
                      onTap: () => setState(() {
                        _taskId = (task['id'] as num?)?.toInt();
                        _error = null;
                      }),
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: _taskId == task['id']
                              ? JournalColors.bgCardAlt
                              : JournalColors.bgBase,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _taskId == task['id']
                                ? JournalColors.accent
                                : JournalColors.border,
                          ),
                        ),
                        child: Text(
                          '${_categoryByKey(task['category'] as String?)?.icon ?? '◌'} ${task['name'] ?? 'Task'}',
                          style: TextStyle(
                            color: _taskId == task['id']
                                ? JournalColors.accent
                                : JournalColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (tasks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No active tasks match this filter.',
                        style: TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  _TextInput(
                    controller: _noteController,
                    placeholder: 'Optional note',
                    minLines: 1,
                    maxLines: 3,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: JournalColors.danger,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  AdaptiveButton(
                    style: AdaptiveButtonStyle.prominentGlass,
                    onPressed: _saving
                        ? null
                        : () async {
                            if (_taskId == null) {
                              setState(() => _error = 'Select a task first.');
                              return;
                            }
                            setState(() {
                              _saving = true;
                              _error = null;
                            });
                            try {
                              await widget.onSubmit(
                                _taskId!,
                                _who,
                                _noteController.text.trim().isEmpty
                                    ? null
                                    : _noteController.text.trim(),
                              );
                            } catch (e) {
                              if (mounted) {
                                setState(() {
                                  _saving = false;
                                  _error = _parseError(e);
                                });
                              }
                            }
                          },
                    label: _saving
                        ? 'Logging…'
                        : _taskId == null
                            ? 'Select a task first'
                            : 'Log Task',
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

class _ContributionSheet extends StatefulWidget {
  final String myName;
  final String partnerName;
  final String? member3Name;
  final Future<void> Function(Map<String, dynamic> payload) onSubmit;

  const _ContributionSheet({
    required this.myName,
    required this.partnerName,
    required this.member3Name,
    required this.onSubmit,
  });

  @override
  State<_ContributionSheet> createState() => _ContributionSheetState();
}

class _ContributionSheetState extends State<_ContributionSheet> {
  String _who = 'me';
  String _category = _fairnessCategories.first.key;
  final _descriptionController = TextEditingController();
  final _dateController = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _descriptionController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
      decoration: BoxDecoration(
        color: JournalColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHeader(title: 'Add Contribution'),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _WhoPicker(
                    value: _who,
                    myName: widget.myName,
                    partnerName: widget.partnerName,
                    member3Name: widget.member3Name,
                    onChanged: (value) => setState(() => _who = value),
                  ),
                  const SizedBox(height: 14),
                  const _FieldLabel('Category'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final category in _fairnessCategories)
                        _ChoiceChip(
                          label: '${category.icon} ${category.label}',
                          selected: _category == category.key,
                          onTap: () => setState(() => _category = category.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _FieldLabel('What happened?'),
                  _TextInput(
                    controller: _descriptionController,
                    placeholder: 'Describe what was done…',
                    minLines: 3,
                    maxLines: null,
                  ),
                  const SizedBox(height: 14),
                  const _FieldLabel('Date'),
                  _TextInput(
                    controller: _dateController,
                    placeholder: 'YYYY-MM-DD',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: JournalColors.danger,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  AdaptiveButton(
                    style: AdaptiveButtonStyle.prominentGlass,
                    onPressed: _saving
                        ? null
                        : () async {
                            if (_descriptionController.text.trim().isEmpty) {
                              setState(() => _error = 'Add a description.');
                              return;
                            }
                            setState(() {
                              _saving = true;
                              _error = null;
                            });
                            try {
                              await widget.onSubmit({
                                'performed_by': _who,
                                'category': _category,
                                'description':
                                    _descriptionController.text.trim(),
                                'contribution_date':
                                    _dateController.text.trim(),
                              });
                            } catch (e) {
                              if (mounted) {
                                setState(() {
                                  _saving = false;
                                  _error = _parseError(e);
                                });
                              }
                            }
                          },
                    label: _saving ? 'Saving…' : 'Save Contribution',
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

class _SheetHeader extends StatelessWidget {
  final String title;

  const _SheetHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(
              CupertinoIcons.xmark,
              color: JournalColors.textMuted,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _WhoPicker extends StatelessWidget {
  final String value;
  final String myName;
  final String partnerName;
  final String? member3Name;
  final ValueChanged<String> onChanged;

  const _WhoPicker({
    required this.value,
    required this.myName,
    required this.partnerName,
    required this.member3Name,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = <Map<String, String>>[
      {'value': 'me', 'label': myName},
      {'value': 'partner', 'label': partnerName},
      if (member3Name != null) {'value': 'member3', 'label': member3Name!},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Who?'),
        Row(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(options[i]['value']!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: value == options[i]['value']
                          ? _whoColor(options[i]['value'])
                          : JournalColors.bgBase,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: value == options[i]['value']
                            ? _whoColor(options[i]['value'])
                            : JournalColors.border,
                      ),
                    ),
                    child: Text(
                      options[i]['label']!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: value == options[i]['value']
                            ? JournalColors.textPrimary
                            : JournalColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              if (i < options.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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

String _parseError(dynamic e) {
  final str = e.toString();
  final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
  return match?.group(1) ?? 'Something went wrong.';
}

Widget _unstyledOverlay(Widget child) {
  return DefaultTextStyle.merge(
    style: const TextStyle(decoration: TextDecoration.none),
    child: child,
  );
}

_FairnessCategory? _categoryByKey(String? key) {
  for (final category in _fairnessCategories) {
    if (category.key == key) return category;
  }
  return null;
}

String _whoLabel(
    String? who, String myName, String partnerName, String? member3Name) {
  if (who == 'me') return myName;
  if (who == 'partner') return partnerName;
  if (who == 'member3') return member3Name ?? 'Member 3';
  return who ?? 'Unknown';
}

Color _whoColor(String? who) {
  if (who == 'me') return JournalColors.accent;
  if (who == 'partner') return JournalColors.textMuted;
  if (who == 'member3') return JournalColors.accent2;
  return JournalColors.textMuted;
}

int _totalFor(Map<String, dynamic>? score, String who) {
  return ((score?[who] as Map?)?['total'] as num?)?.toInt() ?? 0;
}

int _categoryTotal(Map<String, dynamic>? score, String who, String category) {
  final byCategory =
      ((score?[who] as Map?)?['by_category'] as Map?) ?? const {};
  return (byCategory[category] as num?)?.toInt() ?? 0;
}

int _percent(double value) => (value * 100).round();

String _formatHistoryDate(String? raw) {
  if (raw == null || raw.isEmpty) return 'Unknown date';
  try {
    final normalized = raw.contains('T') ? raw : '${raw}T00:00:00';
    final date = DateTime.parse(normalized).toLocal();
    return DateFormat('M/d/yyyy').format(date);
  } catch (_) {
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }
}
