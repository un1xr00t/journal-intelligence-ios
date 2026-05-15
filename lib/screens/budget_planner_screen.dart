import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

const List<Color> _segmentColors = [
  JournalColors.accent,
  JournalColors.accent2,
  JournalColors.severity,
  JournalColors.success,
  Color(0xFFEC4899),
  Color(0xFF06B6D4),
  JournalColors.orange,
  Color(0xFFA3E635),
];

const List<String> _tipPrompts = [
  'Give me one surprising, specific tip about reducing a common household expense that most people overlook. Under 2 sentences. Be concrete, not generic.',
  'What is one counterintuitive money insight that most personal finance advice gets completely wrong? Under 2 sentences. Be specific and bold.',
  'What is one small financial habit that compounds dramatically over 5 years? Name the exact habit and a rough dollar figure. Under 2 sentences.',
  'What is one specific action someone can take this week to meaningfully reduce their monthly spending without feeling deprived? Under 2 sentences.',
];

const List<_TemplateGroup> _quickAddTemplates = [
  _TemplateGroup('Streaming', [
    _TemplateItem('Netflix', 17),
    _TemplateItem('Spotify', 11),
    _TemplateItem('Hulu', 18),
    _TemplateItem('Disney+', 14),
    _TemplateItem('HBO Max', 16),
    _TemplateItem('Apple TV+', 10),
    _TemplateItem('YouTube Premium', 14),
    _TemplateItem('Amazon Prime', 15),
  ]),
  _TemplateGroup('Food', [
    _TemplateItem('Groceries', 400),
    _TemplateItem('Dining Out', 200),
    _TemplateItem('Coffee', 60),
    _TemplateItem('Takeout / Delivery', 100),
  ]),
  _TemplateGroup('Transport', [
    _TemplateItem('Gas', 150),
    _TemplateItem('Car Insurance', 120),
    _TemplateItem('Car Payment', 400),
    _TemplateItem('Public Transit', 80),
    _TemplateItem('Uber / Lyft', 60),
    _TemplateItem('Parking', 50),
  ]),
  _TemplateGroup('Health', [
    _TemplateItem('Gym Membership', 40),
    _TemplateItem('Health Insurance', 200),
    _TemplateItem('Prescriptions', 50),
    _TemplateItem('Therapy', 150),
  ]),
  _TemplateGroup('Tech', [
    _TemplateItem('Phone Bill', 70),
    _TemplateItem('Internet', 60),
    _TemplateItem('iCloud / Google One', 3),
    _TemplateItem('Adobe CC', 55),
  ]),
  _TemplateGroup('Personal', [
    _TemplateItem('Haircut', 30),
    _TemplateItem('Clothing', 100),
    _TemplateItem('Personal Care', 50),
  ]),
  _TemplateGroup('Savings & Debt', [
    _TemplateItem('Credit Card Payment', 200),
    _TemplateItem('Student Loans', 300),
    _TemplateItem('Emergency Fund', 100),
    _TemplateItem('Retirement (401k)', 200),
  ]),
];

class BudgetPlannerScreen extends StatefulWidget {
  const BudgetPlannerScreen({super.key});

  @override
  State<BudgetPlannerScreen> createState() => _BudgetPlannerScreenState();
}

class _BudgetPlannerScreenState extends State<BudgetPlannerScreen> {
  final _api = ApiService();

  bool _loading = true;
  bool _saving = false;
  bool _tipLoading = false;
  bool _analysisLoading = false;
  bool _showTemplates = false;
  bool _editing = false;
  String? _error;
  String? _tip;
  String? _analysis;
  String? _analysisError;
  int _tipIndex = 0;
  String _selectedTemplateCategory = _quickAddTemplates.first.category;

  Map<String, dynamic>? _savedPlan;

  String _income = '';
  String _rent = '';
  String _utilities = '';
  List<_ExpenseDraft> _expenses = [const _ExpenseDraft(name: '', amount: '')];
  double? _simulatedRent;
  List<double> _simulatedValues = [];

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
      final data = await _api.getBudgetPlan();
      final exists = data['exists'] as bool? ?? false;
      if (!mounted) return;
      setState(() {
        if (exists) {
          final plan = _coercePlan(data['plan']);
          _savedPlan = plan;
          _hydrateDraft(plan);
          _editing = false;
        } else {
          _savedPlan = null;
          _editing = true;
          _resetDraft();
        }
        _loading = false;
      });
      if (exists) {
        await _loadTip();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _parseError(e);
        _loading = false;
        _editing = true;
      });
    }
  }

  Future<void> _loadTip() async {
    if (_savedPlan == null) return;
    if (mounted) {
      setState(() {
        _tipLoading = true;
      });
    }
    try {
      final res = await _api.budgetAi(
        prompt: _tipPrompts[_tipIndex % _tipPrompts.length],
        maxTokens: 120,
      );
      if (!mounted) return;
      setState(() {
        _tip = (res['text'] as String?)?.trim();
        _tipLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tip = 'Could not load a tip right now.';
        _tipLoading = false;
      });
    }
  }

  Future<void> _nextTip() async {
    setState(() {
      _tipIndex = (_tipIndex + 1) % _tipPrompts.length;
    });
    await _loadTip();
  }

  Future<void> _generateAnalysis() async {
    final plan = _savedPlan;
    if (plan == null) return;
    setState(() {
      _analysisLoading = true;
      _analysis = null;
      _analysisError = null;
    });
    try {
      final res = await _api.budgetAi(
        prompt: _buildAnalysisPrompt(plan),
      );
      if (!mounted) return;
      setState(() {
        _analysis = (res['text'] as String?)?.trim();
        _analysisLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analysisError = _parseError(e);
        _analysisLoading = false;
      });
    }
  }

  Future<void> _importCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null) return;

    String? content;
    if (file.bytes != null) {
      content = String.fromCharCodes(file.bytes!);
    } else if (file.path != null) {
      content = await File(file.path!).readAsString();
    }
    if (content == null) return;

    final rows = content
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) {
          final parts = line.split(',');
          final name = parts.isNotEmpty ? parts.first.trim() : '';
          final amount = parts.length > 1
              ? parts[1].replaceAll(RegExp(r'[^0-9.]'), '').trim()
              : '';
          return _ExpenseDraft(name: name, amount: amount);
        })
        .where((row) => row.name.isNotEmpty)
        .toList();

    if (rows.isEmpty) return;

    setState(() {
      _expenses = [
        ..._expenses.where((row) => row.name.trim().isNotEmpty),
        ...rows,
      ];
      if (_expenses.isEmpty) {
        _expenses = [const _ExpenseDraft(name: '', amount: '')];
      }
    });
  }

  Future<void> _savePlan() async {
    final payload = _buildPlanPayload();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.saveBudgetPlan(payload);
      if (!mounted) return;
      setState(() {
        _savedPlan = _coercePlan(payload);
        _editing = false;
        _hydrateDraft(_savedPlan!);
        _saving = false;
        _analysis = null;
        _analysisError = null;
      });
      await _loadTip();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _parseError(e);
        _saving = false;
      });
    }
  }

  Future<void> _resetPlan() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Reset Budget Plan'),
        content: const Text(
          'This clears the saved plan and starts over.',
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.deleteBudgetPlan();
      if (!mounted) return;
      setState(() {
        _savedPlan = null;
        _editing = true;
        _saving = false;
        _tip = null;
        _analysis = null;
        _analysisError = null;
      });
      _resetDraft();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _parseError(e);
        _saving = false;
      });
    }
  }

  Map<String, dynamic> _coercePlan(dynamic raw) {
    final map = raw is Map<String, dynamic>
        ? raw
        : Map<String, dynamic>.from(raw as Map);
    final expenses = (map['expenses'] as List? ?? const [])
        .map((item) => item is Map<String, dynamic>
            ? item
            : Map<String, dynamic>.from(item as Map))
        .toList();
    return {
      'income': _readDouble(map['income']),
      'rent': _readDouble(map['rent']),
      'utilities': _readDouble(map['utilities']),
      'expenses': expenses
          .map((expense) => {
                'name': (expense['name'] ?? '').toString(),
                'amount': _readDouble(expense['amount']),
              })
          .toList(),
    };
  }

  void _hydrateDraft(Map<String, dynamic> plan) {
    _income = _numberText(_readDouble(plan['income']));
    _rent = _numberText(_readDouble(plan['rent']));
    _utilities = _numberText(_readDouble(plan['utilities']));
    _expenses = (plan['expenses'] as List<dynamic>? ?? const [])
        .map((item) => item is Map<String, dynamic>
            ? item
            : Map<String, dynamic>.from(item as Map))
        .map(
          (expense) => _ExpenseDraft(
            name: (expense['name'] ?? '').toString(),
            amount: _numberText(_readDouble(expense['amount'])),
          ),
        )
        .toList();
    if (_expenses.isEmpty) {
      _expenses = [const _ExpenseDraft(name: '', amount: '')];
    }
    _resetSimulator();
  }

  void _resetDraft() {
    _income = '';
    _rent = '';
    _utilities = '';
    _expenses = [const _ExpenseDraft(name: '', amount: '')];
    _resetSimulator();
  }

  void _resetSimulator() {
    _simulatedRent = _activePlan.rent;
    _simulatedValues = _activePlan.expenses.map((expense) => expense.amount).toList();
  }

  Map<String, dynamic> _buildPlanPayload() {
    return {
      'income': _readDouble(_income),
      'rent': _readDouble(_rent),
      'utilities': _readDouble(_utilities),
      'expenses': _expenses
          .where((expense) => expense.name.trim().isNotEmpty)
          .map((expense) => {
                'name': expense.name.trim(),
                'amount': _readDouble(expense.amount),
              })
          .toList(),
    };
  }

  String _buildAnalysisPrompt(Map<String, dynamic> plan) {
    final active = _BudgetSnapshot.fromPlan(plan);
    final expenseLines = active.expenses
        .map((expense) => '  - ${expense.name}: \$${expense.amount.toStringAsFixed(0)}/mo')
        .join('\n');
    return '''
You are a compassionate financial advisor. Here is someone's monthly budget:

Monthly take-home income: \$${active.income.toStringAsFixed(0)}
Housing (rent + utilities): \$${active.housing.toStringAsFixed(0)}
Other expenses:
${expenseLines.isEmpty ? '  (none listed)' : expenseLines}

Total spending: \$${active.totalSpend.toStringAsFixed(0)}
Money left over: \$${active.leftover.toStringAsFixed(0)}

Give a structured 4-part response with these exact section headers:

1. ONE THING TO CUT
Identify the single most impactful expense to reduce, name it specifically, and state the exact monthly savings if reduced by a realistic amount.

2. ONE SACRIFICE WORTH MAKING
Name one meaningful short-term sacrifice (something they might resist) that pays off significantly within 6 months.

3. ONE THING THEY'RE DOING RIGHT
Name something genuinely positive in this budget, even if small.

4. ONE 6-MONTH GOAL
Based on these exact numbers, give one concrete, achievable financial goal for the next 6 months with a target dollar amount.

Be specific and direct. Use the actual numbers from their budget. Do not give generic advice.
''';
  }

  String _parseError(dynamic e) {
    final str = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    return match?.group(1) ?? 'Something went wrong.';
  }

  double _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  String _numberText(double value) {
    if (value == 0) return '';
    return value % 1 == 0 ? value.toInt().toString() : value.toString();
  }

  void _updateExpense(int index, {String? name, String? amount}) {
    setState(() {
      _expenses = [
        for (var i = 0; i < _expenses.length; i++)
          if (i == index)
            _ExpenseDraft(
              name: name ?? _expenses[i].name,
              amount: amount ?? _expenses[i].amount,
            )
          else
            _expenses[i],
      ];
    });
  }

  void _addExpense() {
    setState(() {
      _expenses = [..._expenses, const _ExpenseDraft(name: '', amount: '')];
    });
  }

  void _removeExpense(int index) {
    setState(() {
      if (_expenses.length == 1) {
        _expenses = [const _ExpenseDraft(name: '', amount: '')];
      } else {
        _expenses = [
          for (var i = 0; i < _expenses.length; i++)
            if (i != index) _expenses[i],
        ];
      }
    });
  }

  void _addTemplate(_TemplateItem item) {
    final exists = _expenses.any(
      (expense) =>
          expense.name.trim().toLowerCase() == item.name.trim().toLowerCase(),
    );
    if (exists) return;

    setState(() {
      final blankIndex =
          _expenses.indexWhere((expense) => expense.name.trim().isEmpty);
      if (blankIndex != -1) {
        _expenses[blankIndex] = _ExpenseDraft(
          name: item.name,
          amount: item.amount.toStringAsFixed(0),
        );
      } else {
        _expenses = [
          ..._expenses,
          _ExpenseDraft(
            name: item.name,
            amount: item.amount.toStringAsFixed(0),
          ),
        ];
      }
    });
  }

  _BudgetSnapshot get _activePlan {
    final source = _editing || _savedPlan == null ? _buildPlanPayload() : _savedPlan!;
    return _BudgetSnapshot.fromPlan(source);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: Stack(
        children: [
          const Positioned.fill(child: _BudgetBackdrop()),
          CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('Budget Planner'),
                backgroundColor: _withAlpha(JournalColors.bgBase, 0.88),
                border: const Border(
                  bottom: BorderSide(color: JournalColors.border, width: 0.5),
                ),
                trailing: GestureDetector(
                  onTap: _loading ? null : _load,
                  child: const Icon(
                    CupertinoIcons.refresh,
                    color: JournalColors.accent,
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  child: Center(
                    child: CupertinoActivityIndicator(
                      color: JournalColors.accent,
                    ),
                  ),
                )
              else if (_error != null && _savedPlan == null)
                SliverFillRemaining(
                  child: _BudgetErrorView(error: _error!, onRetry: _load),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _BudgetHero(
                        snapshot: _activePlan,
                        hasSavedPlan: _savedPlan != null,
                        isEditing: _editing,
                      ),
                      const SizedBox(height: 18),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _InlineMessage(
                            message: _error!,
                            color: JournalColors.danger,
                            icon: CupertinoIcons.exclamationmark_circle_fill,
                          ),
                        ),
                      if (_editing) ...[
                        _buildEditor(),
                        const SizedBox(height: 18),
                      ] else ...[
                        if (_savedPlan != null) ...[
                          _buildDashboardActions(),
                          const SizedBox(height: 18),
                        ],
                        _buildTipCard(),
                        const SizedBox(height: 18),
                        _buildMetricSection(),
                        const SizedBox(height: 18),
                        _buildBreakdownSection(),
                        const SizedBox(height: 18),
                        if (_activePlan.rent > 0 || _activePlan.expenses.isNotEmpty) ...[
                          _buildSimulatorSection(),
                          const SizedBox(height: 18),
                        ],
                        _buildAnalysisSection(),
                        if (_activePlan.rent > 0 || _activePlan.expenses.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          _buildSimulatorComparisonSection(),
                        ],
                      ],
                      const SizedBox(height: 32),
                    ]),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    final runningTotal = _expenses.fold<double>(
      0,
      (sum, expense) => sum + _readDouble(expense.amount),
    );
    final hasSavedPlan = _savedPlan != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          accentBorder: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BudgetGlyph(
                    icon: CupertinoIcons.creditcard_fill,
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasSavedPlan ? 'Edit budget' : 'Set up budget',
                          style: const TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Keep the inputs simple. The dashboard updates from the same monthly numbers.',
                          style: TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 14,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _BudgetInputField(
                label: 'Monthly Take-Home Income',
                value: _income,
                onChanged: (value) => setState(() => _income = value),
                prominent: true,
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 620;
                  if (stacked) {
                    return Column(
                      children: [
                        _BudgetInputField(
                          label: 'Rent / Mortgage',
                          value: _rent,
                          onChanged: (value) => setState(() => _rent = value),
                        ),
                        const SizedBox(height: 12),
                        _BudgetInputField(
                          label: 'Utilities',
                          value: _utilities,
                          onChanged: (value) =>
                              setState(() => _utilities = value),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: _BudgetInputField(
                          label: 'Rent / Mortgage',
                          value: _rent,
                          onChanged: (value) => setState(() => _rent = value),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _BudgetInputField(
                          label: 'Utilities',
                          value: _utilities,
                          onChanged: (value) =>
                              setState(() => _utilities = value),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: SectionHeader(title: 'Monthly Expenses'),
                  ),
                  CupertinoButton(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    onPressed: _importCsv,
                    child: const Text(
                      'Import CSV',
                      style: TextStyle(
                        color: JournalColors.accent,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _TemplateChooser(
                selectedCategory: _selectedTemplateCategory,
                showTemplates: _showTemplates,
                onToggle: () =>
                    setState(() => _showTemplates = !_showTemplates),
                onCategorySelected: (value) =>
                    setState(() => _selectedTemplateCategory = value),
                onAddTemplate: _addTemplate,
                existingNames: _expenses.map((expense) => expense.name).toList(),
              ),
              const SizedBox(height: 14),
              for (var index = 0; index < _expenses.length; index++) ...[
                _ExpenseRow(
                  index: index,
                  expense: _expenses[index],
                  onNameChanged: (value) =>
                      _updateExpense(index, name: value),
                  onAmountChanged: (value) =>
                      _updateExpense(index, amount: value),
                  onRemove: () => _removeExpense(index),
                ),
                if (index != _expenses.length - 1) const SizedBox(height: 8),
              ],
              const SizedBox(height: 12),
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: _withAlpha(JournalColors.bgSurface, 0.92),
                borderRadius: BorderRadius.circular(14),
                onPressed: _addExpense,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.add,
                      size: 16,
                      color: JournalColors.textSecondary,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Add expense',
                      style: TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.bgSurface, 0.92),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: JournalColors.border),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Running total',
                        style: TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    Text(
                      _currency(runningTotal),
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 560;
                  final cancelButton = CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    color: _withAlpha(JournalColors.bgSurface, 0.96),
                    borderRadius: BorderRadius.circular(16),
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                              _editing = false;
                              if (_savedPlan != null) {
                                _hydrateDraft(_savedPlan!);
                              }
                            }),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                  final saveButton = CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    color: JournalColors.accent,
                    borderRadius: BorderRadius.circular(16),
                    onPressed: _saving ? null : _savePlan,
                    child: Text(
                      _saving
                          ? 'Saving...'
                          : hasSavedPlan
                              ? 'Save changes'
                              : 'Build dashboard',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );

                  if (stacked) {
                    return Column(
                      children: [
                        if (hasSavedPlan)
                          SizedBox(
                            width: double.infinity,
                            child: cancelButton,
                          ),
                        if (hasSavedPlan) const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: saveButton,
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      if (hasSavedPlan) Expanded(child: cancelButton),
                      if (hasSavedPlan) const SizedBox(width: 12),
                      Expanded(child: saveButton),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardActions() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 520;
        final editButton = CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 13),
          color: _withAlpha(JournalColors.bgSurface, 0.94),
          borderRadius: BorderRadius.circular(16),
          onPressed: () => setState(() => _editing = true),
          child: const Text(
            'Edit budget',
            style: TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
        final resetButton = CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 13),
          color: _withAlpha(JournalColors.danger, 0.08),
          borderRadius: BorderRadius.circular(16),
          onPressed: _saving ? null : _resetPlan,
          child: const Text(
            'Reset plan',
            style: TextStyle(
              color: JournalColors.danger,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

        if (stacked) {
          return Column(
            children: [
              SizedBox(width: double.infinity, child: editButton),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: resetButton),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: editButton),
            const SizedBox(width: 12),
            Expanded(child: resetButton),
          ],
        );
      },
    );
  }

  Widget _buildTipCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI tip',
                      style: TextStyle(
                        color: JournalColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'A small, concrete idea based on common monthly spending patterns.',
                      style: TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 14,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                onPressed: _tipLoading ? null : _nextTip,
                child: const Text(
                  'Refresh',
                  style: TextStyle(
                    color: JournalColors.accent,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_tipLoading)
            const Center(
              child: CupertinoActivityIndicator(color: JournalColors.accent),
            )
          else
            Text(
              _tip ?? 'No tip loaded yet.',
              style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 15,
                height: 1.6,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetricSection() {
    final snapshot = _activePlan;
    final rating = _BudgetRating.fromLeftover(snapshot.leftover);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Overview'),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width < 720 ? 2 : 4,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.25,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _MetricCard(label: 'Take-Home', value: snapshot.income),
            _MetricCard(label: 'Base Expenses', value: snapshot.baseExpenses),
            _MetricCard(label: 'Housing', value: snapshot.housing),
            _MetricCard(
              label: 'Left Over',
              value: snapshot.leftover,
              rating: rating,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBreakdownSection() {
    final snapshot = _activePlan;
    final segments = <_BudgetSegment>[
      if (snapshot.housing > 0)
        _BudgetSegment(
          label: 'Housing',
          value: snapshot.housing,
          color: _segmentColors.first,
        ),
      for (var i = 0; i < snapshot.expenses.length; i++)
        if (snapshot.expenses[i].amount > 0)
          _BudgetSegment(
            label: snapshot.expenses[i].name,
            value: snapshot.expenses[i].amount,
            color: _segmentColors[(i + 1) % _segmentColors.length],
          ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Spending Breakdown'),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 760;
            final chart = GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Allocation',
                    style: TextStyle(
                      color: JournalColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: _DonutChart(
                      segments: segments,
                      total: snapshot.totalSpend,
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (var i = 0; i < segments.length; i++) ...[
                    _LegendRow(segment: segments[i]),
                    if (i != segments.length - 1) const SizedBox(height: 8),
                  ],
                ],
              ),
            );

            final itemized = GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Itemized',
                    style: TextStyle(
                      color: JournalColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (snapshot.rent > 0)
                    _LineItem(
                      label: 'Rent / Mortgage',
                      value: snapshot.rent,
                    ),
                  if (snapshot.utilities > 0)
                    _LineItem(
                      label: 'Utilities',
                      value: snapshot.utilities,
                    ),
                  for (final expense in snapshot.expenses)
                    _LineItem(label: expense.name, value: expense.amount),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.only(top: 10),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: JournalColors.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Total',
                            style: TextStyle(
                              color: JournalColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        Text(
                          _currency(snapshot.totalSpend),
                          style: const TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );

            if (stacked) {
              return Column(
                children: [
                  SizedBox(width: double.infinity, child: chart),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: itemized),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: chart),
                const SizedBox(width: 12),
                Expanded(child: itemized),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSimulatorSection() {
    final snapshot = _activePlan;
    final simulatedRent = _simulatedRent ?? snapshot.rent;
    final simValues = _simulatedValues.length == snapshot.expenses.length
        ? _simulatedValues
        : snapshot.expenses.map((expense) => expense.amount).toList();

    final simulatedTotal = simValues.fold<double>(0, (sum, value) => sum + value);
    final simulatedLeftover =
        snapshot.income - simulatedRent - snapshot.utilities - simulatedTotal;
    final delta = simulatedLeftover - snapshot.leftover;
    final rating = _BudgetRating.fromLeftover(simulatedLeftover);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'What-If Simulator'),
        const SizedBox(height: 10),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Adjust each expense to test the impact on monthly leftover cash.',
                style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 18),
              if (snapshot.rent > 0) ...[
                _SimulationRow(
                  expense: _BudgetExpense(
                    name: 'Rent / Mortgage',
                    amount: snapshot.rent,
                  ),
                  value: simulatedRent,
                  onChanged: (value) => setState(() {
                    _simulatedRent = value;
                  }),
                ),
                if (snapshot.expenses.isNotEmpty) const SizedBox(height: 18),
              ],
              for (var i = 0; i < snapshot.expenses.length; i++) ...[
                _SimulationRow(
                  expense: snapshot.expenses[i],
                  value: simValues[i],
                  onChanged: (value) => setState(() {
                    final next = List<double>.from(simValues);
                    next[i] = value;
                    _simulatedValues = next;
                  }),
                ),
                if (i != snapshot.expenses.length - 1) const SizedBox(height: 18),
              ],
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.bgSurface, 0.96),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: JournalColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Simulated Leftover',
                            style: TextStyle(
                              color: JournalColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _currency(simulatedLeftover),
                            style: const TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${delta >= 0 ? '+' : ''}${_currency(delta)} vs current',
                          style: TextStyle(
                            color: delta >= 0
                                ? JournalColors.success
                                : JournalColors.danger,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _RatingPill(rating: rating),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSimulatorComparisonSection() {
    final snapshot = _activePlan;
    final simulatedRent = _simulatedRent ?? snapshot.rent;
    final simValues = _simulatedValues.length == snapshot.expenses.length
        ? _simulatedValues
        : snapshot.expenses.map((expense) => expense.amount).toList();

    final currentExpenses = snapshot.baseExpenses;
    final whatIfExpenses =
        simValues.fold<double>(0, (sum, value) => sum + value);
    final currentTotalSpend = snapshot.totalSpend;
    final currentHousing = snapshot.housing;
    final whatIfHousing = simulatedRent + snapshot.utilities;
    final whatIfTotalSpend = whatIfHousing + whatIfExpenses;
    final whatIfLeftover = snapshot.income - whatIfTotalSpend;

    final rows = <_ComparisonRowData>[
      _ComparisonRowData(
        label: 'Income',
        current: snapshot.income,
        whatIf: snapshot.income,
        deltaMode: _ComparisonDeltaMode.neutral,
      ),
      _ComparisonRowData(
        label: 'Housing',
        current: currentHousing,
        whatIf: whatIfHousing,
        deltaMode: _ComparisonDeltaMode.lowerIsBetter,
      ),
      if (snapshot.rent > 0)
        _ComparisonRowData(
          label: 'Rent / Mortgage',
          current: snapshot.rent,
          whatIf: simulatedRent,
          deltaMode: _ComparisonDeltaMode.lowerIsBetter,
        ),
      _ComparisonRowData(
        label: 'Flexible Expenses',
        current: currentExpenses,
        whatIf: whatIfExpenses,
        deltaMode: _ComparisonDeltaMode.lowerIsBetter,
      ),
      _ComparisonRowData(
        label: 'Total Spend',
        current: currentTotalSpend,
        whatIf: whatIfTotalSpend,
        deltaMode: _ComparisonDeltaMode.lowerIsBetter,
      ),
      _ComparisonRowData(
        label: 'Left Over',
        current: snapshot.leftover,
        whatIf: whatIfLeftover,
        deltaMode: _ComparisonDeltaMode.higherIsBetter,
      ),
      for (var i = 0; i < snapshot.expenses.length; i++)
        _ComparisonRowData(
          label: snapshot.expenses[i].name,
          current: snapshot.expenses[i].amount,
          whatIf: simValues[i],
          deltaMode: _ComparisonDeltaMode.lowerIsBetter,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Current vs What-If'),
        const SizedBox(height: 10),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Side-by-side monthly amounts from the current plan against the simulator values.',
                style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 16),
              const _ComparisonHeaderRow(),
              const SizedBox(height: 8),
              for (var i = 0; i < rows.length; i++) ...[
                _ComparisonAmountRow(data: rows[i]),
                if (i != rows.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnalysisSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'AI Analysis'),
        const SizedBox(height: 10),
        GlassCard(
          accentBorder: _analysis != null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Text(
                      'Generate a focused read on the current plan. The response stays concrete and number-driven.',
                      style: TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 14,
                        height: 1.55,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    onPressed: _analysisLoading ? null : _generateAnalysis,
                    child: Text(
                      _analysis == null ? 'Generate' : 'Refresh',
                      style: const TextStyle(
                        color: JournalColors.accent,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_analysisLoading)
                const Center(
                  child: CupertinoActivityIndicator(
                    color: JournalColors.accent,
                  ),
                )
              else if (_analysisError != null)
                _InlineMessage(
                  message: _analysisError!,
                  color: JournalColors.danger,
                  icon: CupertinoIcons.exclamationmark_circle_fill,
                )
              else if (_analysis == null)
                const Text(
                  'No analysis generated yet.',
                  style: TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 14,
                  ),
                )
              else
                _MiniMarkdown(text: _analysis!),
            ],
          ),
        ),
      ],
    );
  }

  String _currency(double value) {
    final formatter = NumberFormat.currency(
      symbol: '\$',
      decimalDigits: value % 1 == 0 ? 0 : 2,
    );
    return formatter.format(value);
  }
}

class _BudgetBackdrop extends StatelessWidget {
  const _BudgetBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF081014),
                    JournalColors.bgBase,
                    Color(0xFF05060D),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 80,
            left: -36,
            child: _GlowOrb(
              size: 180,
              color: _withAlpha(JournalColors.success, 0.16),
            ),
          ),
          Positioned(
            top: 220,
            right: -34,
            child: _GlowOrb(
              size: 150,
              color: _withAlpha(JournalColors.accent, 0.16),
            ),
          ),
          Positioned(
            bottom: 120,
            left: 24,
            child: _GlowOrb(
              size: 130,
              color: _withAlpha(JournalColors.info, 0.12),
            ),
          ),
        ],
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

class _BudgetHero extends StatelessWidget {
  const _BudgetHero({
    required this.snapshot,
    required this.hasSavedPlan,
    required this.isEditing,
  });

  final _BudgetSnapshot snapshot;
  final bool hasSavedPlan;
  final bool isEditing;

  @override
  Widget build(BuildContext context) {
    final rating = _BudgetRating.fromLeftover(snapshot.leftover);
    return GlassCard(
      accentBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _BudgetGlyph(
                icon: CupertinoIcons.chart_pie_fill,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEditing
                          ? 'Monthly planning'
                          : hasSavedPlan
                              ? 'Current monthly plan'
                              : 'Budget planner',
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hasSavedPlan
                          ? 'Review take-home pay, fixed costs, and flexible expenses in one place.'
                          : 'Start with a few recurring numbers, then use the dashboard to test tradeoffs.',
                      style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 14,
                        height: 1.55,
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
              _HeroPill(
                label: 'Take-home',
                value: _currency(snapshot.income),
                color: JournalColors.accent,
              ),
              _HeroPill(
                label: 'Spend',
                value: _currency(snapshot.totalSpend),
                color: JournalColors.info,
              ),
              _HeroPill(
                label: 'Left over',
                value: _currency(snapshot.leftover),
                color: rating.color,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _currency(double value) {
    final formatter = NumberFormat.currency(
      symbol: '\$',
      decimalDigits: value % 1 == 0 ? 0 : 2,
    );
    return formatter.format(value);
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _withAlpha(color, 0.32)),
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
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetGlyph extends StatelessWidget {
  const _BudgetGlyph({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            _withAlpha(JournalColors.success, 0.22),
            _withAlpha(JournalColors.accent, 0.16),
          ],
        ),
        border: Border.all(color: JournalColors.borderBright),
      ),
      child: Icon(icon, color: JournalColors.textPrimary, size: size),
    );
  }
}

class _BudgetInputField extends StatelessWidget {
  const _BudgetInputField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.prominent = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool prominent;

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
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        CupertinoTextField(
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true, signed: false),
          padding: EdgeInsets.fromLTRB(16, prominent ? 18 : 14, 16, prominent ? 18 : 14),
          decoration: BoxDecoration(
            color: JournalColors.bgSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: JournalColors.border),
          ),
          prefix: const Padding(
            padding: EdgeInsets.only(left: 14),
            child: Text(
              '\$',
              style: TextStyle(
                color: JournalColors.textMuted,
                fontSize: 14,
              ),
            ),
          ),
          placeholder: '0',
          placeholderStyle: const TextStyle(color: JournalColors.textMuted),
          style: TextStyle(
            color: JournalColors.textPrimary,
            fontSize: prominent ? 24 : 16,
            fontWeight: prominent ? FontWeight.w700 : FontWeight.w500,
          ),
          controller: TextEditingController(text: value)
            ..selection = TextSelection.collapsed(offset: value.length),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _TemplateChooser extends StatelessWidget {
  const _TemplateChooser({
    required this.selectedCategory,
    required this.showTemplates,
    required this.onToggle,
    required this.onCategorySelected,
    required this.onAddTemplate,
    required this.existingNames,
  });

  final String selectedCategory;
  final bool showTemplates;
  final VoidCallback onToggle;
  final ValueChanged<String> onCategorySelected;
  final ValueChanged<_TemplateItem> onAddTemplate;
  final List<String> existingNames;

  @override
  Widget build(BuildContext context) {
    final group = _quickAddTemplates.firstWhere(
      (template) => template.category == selectedCategory,
      orElse: () => _quickAddTemplates.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: _withAlpha(JournalColors.bgSurface, 0.94),
          borderRadius: BorderRadius.circular(14),
          onPressed: onToggle,
          child: Text(
            showTemplates ? 'Hide quick add' : 'Quick add common expenses',
            style: const TextStyle(
              color: JournalColors.accent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (showTemplates) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final template in _quickAddTemplates)
                GestureDetector(
                  onTap: () => onCategorySelected(template.category),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: template.category == selectedCategory
                          ? JournalColors.accent
                          : JournalColors.bgSurface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: template.category == selectedCategory
                            ? JournalColors.accent
                            : JournalColors.border,
                      ),
                    ),
                    child: Text(
                      template.category,
                      style: TextStyle(
                        color: template.category == selectedCategory
                            ? Colors.white
                            : JournalColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in group.items)
                _TemplateChip(
                  item: item,
                  added: existingNames
                      .map((name) => name.trim().toLowerCase())
                      .contains(item.name.toLowerCase()),
                  onTap: () => onAddTemplate(item),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TemplateChip extends StatelessWidget {
  const _TemplateChip({
    required this.item,
    required this.added,
    required this.onTap,
  });

  final _TemplateItem item;
  final bool added;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: added ? null : onTap,
      child: Opacity(
        opacity: added ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: JournalColors.bgSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: JournalColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.name,
                style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '\$${item.amount.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({
    required this.index,
    required this.expense,
    required this.onNameChanged,
    required this.onAmountChanged,
    required this.onRemove,
  });

  final int index;
  final _ExpenseDraft expense;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: JournalColors.textMuted,
                fontSize: 11,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: CupertinoTextField(
            controller: TextEditingController(text: expense.name)
              ..selection =
                  TextSelection.collapsed(offset: expense.name.length),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: JournalColors.border),
            ),
            placeholder: 'Expense name',
            placeholderStyle: const TextStyle(color: JournalColors.textMuted),
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 14,
            ),
            onChanged: onNameChanged,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 118,
          child: CupertinoTextField(
            controller: TextEditingController(text: expense.amount)
              ..selection =
                  TextSelection.collapsed(offset: expense.amount.length),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            prefix: const Padding(
              padding: EdgeInsets.only(left: 10),
              child: Text(
                '\$',
                style: TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 13,
                ),
              ),
            ),
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: JournalColors.border),
            ),
            placeholder: '0',
            placeholderStyle: const TextStyle(color: JournalColors.textMuted),
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 14,
            ),
            onChanged: onAmountChanged,
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: CupertinoButton(
            padding: const EdgeInsets.all(8),
            minimumSize: Size.zero,
            onPressed: onRemove,
            child: const Icon(
              CupertinoIcons.xmark,
              size: 16,
              color: JournalColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.rating,
  });

  final String label;
  final double value;
  final _BudgetRating? rating;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
          const SizedBox(height: 10),
          Text(
            _currency(value),
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (rating != null) ...[
            const SizedBox(height: 8),
            _RatingPill(rating: rating!),
          ],
        ],
      ),
    );
  }

  String _currency(double value) {
    final formatter =
        NumberFormat.currency(symbol: '\$', decimalDigits: value % 1 == 0 ? 0 : 2);
    return formatter.format(value);
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.rating});

  final _BudgetRating rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _withAlpha(rating.color, 0.42)),
        color: _withAlpha(rating.color, 0.08),
      ),
      child: Text(
        rating.label,
        style: TextStyle(
          color: rating.color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DonutChart extends StatelessWidget {
  const _DonutChart({
    required this.segments,
    required this.total,
  });

  final List<_BudgetSegment> segments;
  final double total;

  @override
  Widget build(BuildContext context) {
    const size = 220.0;
    const strokeWidth = 28.0;
    const radius = (size - strokeWidth) / 2;
    const circumference = 2 * math.pi * radius;
    var offset = 0.0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: strokeWidth,
              backgroundColor: _withAlpha(JournalColors.accent, 0.06),
              valueColor:
                  AlwaysStoppedAnimation<Color>(_withAlpha(JournalColors.accent, 0.06)),
            ),
          ),
          ...segments.map((segment) {
            final sweep = total <= 0 ? 0.0 : segment.value / total;
            final painter = _DonutPainter(
              color: segment.color,
              strokeWidth: strokeWidth,
              startFraction: offset,
              sweepFraction: sweep,
            );
            offset += sweep;
            return CustomPaint(
              size: const Size(size, size),
              painter: painter,
            );
          }),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _currency(total),
                style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'TOTAL / MO',
                style: TextStyle(
                  color: JournalColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(
            width: circumference,
            height: circumference,
          ),
        ],
      ),
    );
  }

  String _currency(double value) {
    final formatter =
        NumberFormat.currency(symbol: '\$', decimalDigits: value % 1 == 0 ? 0 : 2);
    return formatter.format(value);
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.color,
    required this.strokeWidth,
    required this.startFraction,
    required this.sweepFraction,
  });

  final Color color;
  final double strokeWidth;
  final double startFraction;
  final double sweepFraction;

  @override
  void paint(Canvas canvas, Size size) {
    if (sweepFraction <= 0) return;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      -math.pi / 2 + (startFraction * math.pi * 2),
      sweepFraction * math.pi * 2,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth ||
        startFraction != oldDelegate.startFraction ||
        sweepFraction != oldDelegate.sweepFraction;
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.segment});

  final _BudgetSegment segment;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: segment.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            segment.label,
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Text(
          NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(segment.value),
          style: const TextStyle(
            color: JournalColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LineItem extends StatelessWidget {
  const _LineItem({
    required this.label,
    required this.value,
  });

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 10),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: JournalColors.border),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(value),
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum _ComparisonDeltaMode {
  lowerIsBetter,
  higherIsBetter,
  neutral,
}

class _ComparisonRowData {
  const _ComparisonRowData({
    required this.label,
    required this.current,
    required this.whatIf,
    required this.deltaMode,
  });

  final String label;
  final double current;
  final double whatIf;
  final _ComparisonDeltaMode deltaMode;
}

class _ComparisonHeaderRow extends StatelessWidget {
  const _ComparisonHeaderRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            'ITEM',
            style: TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'CURRENT',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'WHAT-IF',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'CHANGE',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _ComparisonAmountRow extends StatelessWidget {
  const _ComparisonAmountRow({required this.data});

  final _ComparisonRowData data;

  @override
  Widget build(BuildContext context) {
    final delta = data.whatIf - data.current;
    final hasChange = delta.abs() >= 0.5;
    final positiveImpact = switch (data.deltaMode) {
      _ComparisonDeltaMode.lowerIsBetter => delta < 0,
      _ComparisonDeltaMode.higherIsBetter => delta > 0,
      _ComparisonDeltaMode.neutral => false,
    };
    final negativeImpact = switch (data.deltaMode) {
      _ComparisonDeltaMode.lowerIsBetter => delta > 0,
      _ComparisonDeltaMode.higherIsBetter => delta < 0,
      _ComparisonDeltaMode.neutral => false,
    };
    final deltaColor = !hasChange
        ? JournalColors.textMuted
        : positiveImpact
            ? JournalColors.success
            : negativeImpact
                ? JournalColors.danger
                : JournalColors.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JournalColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                data.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          _ComparisonAmountCell(value: data.current),
          _ComparisonAmountCell(value: data.whatIf),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                hasChange
                    ? '${delta >= 0 ? '+' : ''}${NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(delta)}'
                    : '\$0',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: deltaColor,
                  fontSize: 13,
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

class _ComparisonAmountCell extends StatelessWidget {
  const _ComparisonAmountCell({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 2,
      child: Text(
        NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(value),
        textAlign: TextAlign.right,
        style: const TextStyle(
          color: JournalColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SimulationRow extends StatelessWidget {
  const _SimulationRow({
    required this.expense,
    required this.value,
    required this.onChanged,
  });

  final _BudgetExpense expense;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final savings = expense.amount - value;
    final sliderMax = math.max(expense.amount * 3, 500);
    final controller = TextEditingController(
      text: value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(2),
    )..selection = TextSelection.collapsed(
        offset: value % 1 == 0
            ? value.toInt().toString().length
            : value.toStringAsFixed(2).length,
      );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                expense.name,
                style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),
            if (savings > 0.5)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.success, 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _withAlpha(JournalColors.success, 0.26),
                  ),
                ),
                child: Text(
                  'saves ${NumberFormat.compactCurrency(symbol: '\$').format(savings)} / mo',
                  style: const TextStyle(
                    color: JournalColors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            SizedBox(
              width: 88,
              child: CupertinoTextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                prefix: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text(
                    '\$',
                    style: TextStyle(
                      color: JournalColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
                decoration: BoxDecoration(
                  color: JournalColors.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: JournalColors.border),
                ),
                style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 13,
                ),
                onChanged: (text) => onChanged(double.tryParse(text) ?? 0),
              ),
            ),
          ],
        ),
        Material(
          type: MaterialType.transparency,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: JournalColors.accent,
              inactiveTrackColor: _withAlpha(JournalColors.accent, 0.14),
              thumbColor: JournalColors.accent,
              overlayColor: _withAlpha(JournalColors.accent, 0.12),
            ),
            child: Slider(
              value: value.clamp(0.0, sliderMax.toDouble()).toDouble(),
              max: sliderMax.toDouble(),
              min: 0,
              divisions: math.max((sliderMax / 5).round(), 1),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniMarkdown extends StatelessWidget {
  const _MiniMarkdown({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++)
          Builder(
            builder: (context) {
              final line = lines[i];
              if (line.trim().isEmpty) {
                return const SizedBox(height: 6);
              }
              if (line.startsWith('## ')) {
                return Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 14, bottom: 6),
                  child: Text(
                    line.substring(3),
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 14,
                      height: 1.65,
                    ),
                    children: _renderInline(line),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  List<TextSpan> _renderInline(String text) {
    final parts = text.split(RegExp(r'(\*\*[^*]+\*\*)'));
    return parts
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.startsWith('**') && part.endsWith('**')
              ? TextSpan(
                  text: part.substring(2, part.length - 2),
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : TextSpan(text: part),
        )
        .toList();
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.message,
    required this.color,
    required this.icon,
  });

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _withAlpha(color, 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _withAlpha(color, 0.24)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetErrorView extends StatelessWidget {
  const _BudgetErrorView({
    required this.error,
    required this.onRetry,
  });

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: JournalColors.bgCard,
                border: Border.all(color: JournalColors.borderBright),
              ),
              child: const Icon(
                CupertinoIcons.creditcard,
                color: JournalColors.textMuted,
                size: 34,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Budget planner unavailable',
              style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton(
              color: JournalColors.accent,
              borderRadius: BorderRadius.circular(14),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateGroup {
  const _TemplateGroup(this.category, this.items);

  final String category;
  final List<_TemplateItem> items;
}

class _TemplateItem {
  const _TemplateItem(this.name, this.amount);

  final String name;
  final double amount;
}

class _ExpenseDraft {
  const _ExpenseDraft({
    required this.name,
    required this.amount,
  });

  final String name;
  final String amount;
}

class _BudgetExpense {
  const _BudgetExpense({
    required this.name,
    required this.amount,
  });

  final String name;
  final double amount;
}

class _BudgetSnapshot {
  const _BudgetSnapshot({
    required this.income,
    required this.rent,
    required this.utilities,
    required this.expenses,
  });

  final double income;
  final double rent;
  final double utilities;
  final List<_BudgetExpense> expenses;

  double get housing => rent + utilities;
  double get baseExpenses =>
      expenses.fold<double>(0, (sum, expense) => sum + expense.amount);
  double get totalSpend => housing + baseExpenses;
  double get leftover => income - totalSpend;

  factory _BudgetSnapshot.fromPlan(Map<String, dynamic> plan) {
    final expenses = (plan['expenses'] as List<dynamic>? ?? const [])
        .map((item) => item is Map<String, dynamic>
            ? item
            : Map<String, dynamic>.from(item as Map))
        .map(
          (expense) => _BudgetExpense(
            name: (expense['name'] ?? '').toString(),
            amount: (expense['amount'] is num)
                ? (expense['amount'] as num).toDouble()
                : double.tryParse(expense['amount'].toString()) ?? 0,
          ),
        )
        .where((expense) => expense.name.trim().isNotEmpty)
        .toList();

    return _BudgetSnapshot(
      income: (plan['income'] is num)
          ? (plan['income'] as num).toDouble()
          : double.tryParse(plan['income'].toString()) ?? 0,
      rent: (plan['rent'] is num)
          ? (plan['rent'] as num).toDouble()
          : double.tryParse(plan['rent'].toString()) ?? 0,
      utilities: (plan['utilities'] is num)
          ? (plan['utilities'] as num).toDouble()
          : double.tryParse(plan['utilities'].toString()) ?? 0,
      expenses: expenses,
    );
  }
}

class _BudgetRating {
  const _BudgetRating({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  factory _BudgetRating.fromLeftover(double leftover) {
    if (leftover <= 100) {
      return const _BudgetRating(
        label: 'Survival',
        color: JournalColors.danger,
      );
    }
    if (leftover <= 200) {
      return const _BudgetRating(
        label: 'Very Tight',
        color: JournalColors.severity,
      );
    }
    if (leftover <= 300) {
      return const _BudgetRating(
        label: 'Tight',
        color: JournalColors.severity,
      );
    }
    if (leftover <= 500) {
      return const _BudgetRating(
        label: 'Good',
        color: JournalColors.accent,
      );
    }
    return const _BudgetRating(
      label: 'Very Good',
      color: JournalColors.success,
    );
  }
}

class _BudgetSegment {
  const _BudgetSegment({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}
