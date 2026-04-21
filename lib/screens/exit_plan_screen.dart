// lib/screens/exit_plan_screen.dart
//
// Exit Plan — personalized roadmap for major life transitions.
// Modes: loading → no_plan → creating → plan
// Plan tabs: Today | Phases | Notes

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        Colors,
        LinearProgressIndicator,
        AlwaysStoppedAnimation,
        Divider,
        Material;

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

// ── Priority + status helpers ──────────────────────────────────────────────

const _priorityColors = {
  'critical': JournalColors.danger,
  'high': JournalColors.severity,
  'normal': JournalColors.accent,
  'low': JournalColors.textMuted,
};

const _statusLabels = {
  'backlog': 'Backlog',
  'next': 'Next',
  'doing': 'In Progress',
  'done': 'Done',
  'skipped': 'Skipped',
};

const _branchLabels = {
  'children': 'Children involved',
  'financial': 'Financial dependence',
  'housing': 'Housing concerns',
  'pets': 'Pets',
  'safety': 'Safety concern',
};

// ── Screen ─────────────────────────────────────────────────────────────────

class ExitPlanScreen extends StatefulWidget {
  const ExitPlanScreen({super.key});

  @override
  State<ExitPlanScreen> createState() => _ExitPlanScreenState();
}

class _ExitPlanScreenState extends State<ExitPlanScreen> {
  final _api = ApiService();

  // 'loading' | 'no_plan' | 'creating' | 'plan'
  String _mode = 'loading';

  Map<String, dynamic>? _plan;
  Map<String, dynamic>? _detectData;
  List<dynamic> _phases = [];
  int _activeTab = 0; // 0=Today 1=Phases 2=Notes

  bool _generating = false;
  String? _genError;
  final List<String> _confirmedBranches = [];

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadPlan() async {
    setState(() => _mode = 'loading');
    try {
      final r = await _api.exitPlanGet();
      if (!mounted) return;
      if (r['has_plan'] == true) {
        final planData = Map<String, dynamic>.from(r['plan'] ?? {});
        final phases = List<dynamic>.from(planData['phases'] ?? []);
        setState(() {
          _plan = planData;
          _phases = phases;
          _mode = 'plan';
        });
      } else {
        setState(() => _mode = 'no_plan');
        _loadDetect();
      }
    } catch (_) {
      if (mounted) setState(() => _mode = 'no_plan');
    }
  }

  Future<void> _loadDetect() async {
    try {
      final r = await _api.exitPlanDetect();
      if (mounted) setState(() => _detectData = Map<String, dynamic>.from(r));
    } catch (_) {}
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _genError = null;
    });
    try {
      await _api.exitPlanGenerate(confirmedBranches: _confirmedBranches);
      if (!mounted) return;
      await _loadPlan();
    } catch (e) {
      if (mounted) {
        setState(() {
          _genError = _extractDetail(e) ?? 'Generation failed. Try again.';
          _generating = false;
        });
      }
    }
  }

  Future<void> _updateTaskStatus(String taskId, String status) async {
    try {
      await _api.exitPlanPatchTask(taskId, {'status': status});
      if (!mounted) return;
      await _loadPlan();
    } catch (_) {}
  }

  String? _extractDetail(Object e) {
    if (e is Exception) {
      final s = e.toString();
      final start = s.indexOf('"detail"');
      if (start != -1) {
        final colon = s.indexOf(':', start);
        if (colon != -1) {
          return s
              .substring(colon + 1)
              .trim()
              .replaceAll('"', '')
              .replaceAll('}', '')
              .trim();
        }
      }
    }
    return null;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Material(
      color: JournalColors.bgBase,
      child: CupertinoPageScaffold(
        backgroundColor: JournalColors.bgBase,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: JournalColors.bgBase.withValues(alpha: 0.92),
          border: const Border(
            bottom: BorderSide(color: JournalColors.border, width: 0.5),
          ),
          middle: const Text(
            'Exit Plan',
            style: TextStyle(
              color: JournalColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          leading: CupertinoNavigationBarBackButton(
            color: JournalColors.accent,
            onPressed: () => Navigator.of(context).pop(),
          ),
          trailing: _mode == 'plan'
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _loadPlan,
                  child: const Icon(
                    CupertinoIcons.refresh,
                    color: JournalColors.accent,
                    size: 20,
                  ),
                )
              : null,
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: Stack(
            children: [
              const Positioned.fill(child: _ExitPlanBackdrop()),
              SafeArea(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_mode) {
      case 'loading':
        return _buildLoading();
      case 'no_plan':
        return _buildNoPlan();
      case 'creating':
        return _buildCreating();
      case 'plan':
        return _buildPlan();
      default:
        return _buildLoading();
    }
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return const Center(
      child:
          CupertinoActivityIndicator(radius: 14, color: JournalColors.accent),
    );
  }

  // ── No plan ───────────────────────────────────────────────────────────────

  Widget _buildNoPlan() {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const _ExitPlanHero(
                eyebrow: 'PRIVATE ROADMAP',
                title: 'A step-by-step plan for what needs attention next.',
                body:
                    'Build a private working plan from the signals already present in your journal. The focus here is practical structure, not a long setup flow.',
                icon: CupertinoIcons.map_pin_ellipse,
              ),
              const SizedBox(height: 20),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'No plan has been created yet.',
                      style: TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Start with an initial plan and you will get a Today queue, phased task groups, and a private notes area for context you want to keep nearby.',
                      style: TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 14,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Row(
                      children: [
                        Expanded(
                          child: _MetricTile(
                            label: 'SECTIONS',
                            value: '3',
                            detail: 'Today, phases, notes',
                            color: JournalColors.accent,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: _MetricTile(
                            label: 'SETUP',
                            value: 'Light',
                            detail: 'Uses detected signals first',
                            color: JournalColors.info,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton.filled(
                        borderRadius: BorderRadius.circular(16),
                        onPressed: () => setState(() => _mode = 'creating'),
                        child: const Text(
                          'Create Plan',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  // ── Creating ──────────────────────────────────────────────────────────────

  Widget _buildCreating() {
    final signals = List<String>.from(_detectData?['detected_signals'] ?? []);
    final toggles = List<String>.from(_detectData?['confirm_toggles'] ?? []);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const _ExitPlanHero(
                eyebrow: 'PLAN SETUP',
                title: 'Review the context before the roadmap is generated.',
                body:
                    'Detected signals are shown first. Optional details help tune the plan, but you can keep this light and generate it as-is.',
                icon: CupertinoIcons.slider_horizontal_3,
              ),
              const SizedBox(height: 20),
              GlassCard(
                accentBorder: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Detected Signals'),
                    const SizedBox(height: 12),
                    if (signals.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _withAlpha(JournalColors.bgSurface, 0.72),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: JournalColors.border),
                        ),
                        child: const Text(
                          'No strong signals have been detected yet. You can still generate a plan and refine it afterward.',
                          style: TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      )
                    else
                      ...signals.map(
                        (signal) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _withAlpha(JournalColors.bgSurface, 0.68),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: JournalColors.border),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _withAlpha(
                                      JournalColors.success,
                                      0.14,
                                    ),
                                    border: Border.all(
                                      color: _withAlpha(
                                        JournalColors.success,
                                        0.32,
                                      ),
                                    ),
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.check_mark,
                                    color: JournalColors.success,
                                    size: 15,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    signal.replaceAll('_', ' '),
                                    style: const TextStyle(
                                      color: JournalColors.textPrimary,
                                      fontSize: 14,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (toggles.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const SectionHeader(title: 'Optional Context'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: toggles.map((branch) {
                          final selected = _confirmedBranches.contains(branch);
                          return GestureDetector(
                            onTap: () => setState(() {
                              if (selected) {
                                _confirmedBranches.remove(branch);
                              } else {
                                _confirmedBranches.add(branch);
                              }
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? _withAlpha(JournalColors.accent, 0.18)
                                    : _withAlpha(
                                        JournalColors.bgSurface,
                                        0.60,
                                      ),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: selected
                                      ? JournalColors.borderBright
                                      : JournalColors.border,
                                ),
                              ),
                              child: Text(
                                _branchLabels[branch] ?? branch,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? JournalColors.textPrimary
                                      : JournalColors.textSecondary,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _withAlpha(JournalColors.bgSurface, 0.58),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: JournalColors.border),
                      ),
                      child: const Text(
                        'The generated plan keeps the structure practical: a focused Today list, phased tasks, and lightweight note tracking for anything you want to keep close at hand.',
                        style: TextStyle(
                          color: JournalColors.textSecondary,
                          fontSize: 13,
                          height: 1.55,
                        ),
                      ),
                    ),
                    if (_genError != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _withAlpha(JournalColors.danger, 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _withAlpha(JournalColors.danger, 0.30),
                          ),
                        ),
                        child: Text(
                          _genError!,
                          style: const TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = constraints.maxWidth < 420;
                        final buildButton = SizedBox(
                          width: double.infinity,
                          child: CupertinoButton.filled(
                            borderRadius: BorderRadius.circular(16),
                            onPressed: _generating ? null : _generate,
                            child: _generating
                                ? const CupertinoActivityIndicator(
                                    color: Colors.white,
                                    radius: 10,
                                  )
                                : const Text(
                                    'Build Plan',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        );
                        final backButton = SizedBox(
                          width: double.infinity,
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            color: _withAlpha(JournalColors.bgCardAlt, 0.82),
                            borderRadius: BorderRadius.circular(16),
                            onPressed: _generating
                                ? null
                                : () => setState(() => _mode = 'no_plan'),
                            child: const Text(
                              'Back',
                              style: TextStyle(
                                color: JournalColors.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );

                        if (stacked) {
                          return Column(
                            children: [
                              buildButton,
                              const SizedBox(height: 10),
                              backButton,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(flex: 2, child: buildButton),
                            const SizedBox(width: 10),
                            Expanded(child: backButton),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  // ── Plan (tabs) ───────────────────────────────────────────────────────────

  Widget _buildPlan() {
    final plan = _plan ?? {};
    final planType = plan['plan_type'] as String? ?? '';
    final progress = (plan['overall_progress'] as num?)?.toDouble() ?? 0.0;

    // Compute task counts from phases
    final allPhaseTasks = _phases
        .expand((ph) => List<Map<String, dynamic>>.from(ph['tasks'] ?? []))
        .toList();
    final totalTasks = allPhaseTasks.length;
    final doneTasks = allPhaseTasks.where((t) => t['status'] == 'done').length;

    // Today tasks — backend provides explicit list of IDs
    final todayTaskIds = List<dynamic>.from(plan['today_tasks'] ?? [])
        .map((id) => id.toString())
        .toSet();

    final allTasks = _phases.expand((ph) {
      return List<Map<String, dynamic>>.from(ph['tasks'] ?? []).map((t) => {
            ...t,
            '_phase_title': ph['title'] ?? '',
          });
    }).toList();

    final todayTasks = allTasks
        .where((t) => todayTaskIds.contains(t['id']?.toString()))
        .toList();

    final overview = _PlanOverviewCard(
      title: plan['title'] as String? ?? 'Exit Plan',
      planType: planType,
      progress: progress,
      doneTasks: doneTasks,
      totalTasks: totalTasks,
      todayCount: todayTasks.length,
      phaseCount: _phases.length,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: _withAlpha(JournalColors.bgCard, 0.92),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: JournalColors.border),
            ),
            child: CupertinoSlidingSegmentedControl<int>(
              backgroundColor: Colors.transparent,
              thumbColor: JournalColors.accent,
              groupValue: _activeTab,
              onValueChanged: (value) {
                if (value != null) {
                  setState(() => _activeTab = value);
                }
              },
              children: {
                0: _SegmentLabel(
                  label: 'Today',
                  selected: _activeTab == 0,
                ),
                1: _SegmentLabel(
                  label: 'Phases',
                  selected: _activeTab == 1,
                ),
                2: _SegmentLabel(
                  label: 'Notes',
                  selected: _activeTab == 2,
                ),
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: IndexedStack(
            index: _activeTab,
            children: [
              _TodayTab(
                topContent: overview,
                tasks: todayTasks,
                onStatusChange: _updateTaskStatus,
                onTapTask: _openTaskDetail,
              ),
              _PhasesTab(
                topContent: overview,
                phases: _phases,
                onStatusChange: _updateTaskStatus,
                onTapTask: _openTaskDetail,
                onRefresh: _loadPlan,
              ),
              _NotesTab(
                topContent: overview,
                planId: plan['id']?.toString() ?? '',
                api: _api,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openTaskDetail(Map<String, dynamic> task) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: _TaskDetailSheet(
          task: task,
          onStatusChange: (id, status) async {
            Navigator.of(context).pop();
            await _updateTaskStatus(id, status);
          },
          api: _api,
          onRefresh: _loadPlan,
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
}

// ── Today tab ─────────────────────────────────────────────────────────────

class _ExitPlanBackdrop extends StatelessWidget {
  const _ExitPlanBackdrop();

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
                    Color(0xFF080914),
                    JournalColors.bgBase,
                    Color(0xFF05060D),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 74,
            left: -34,
            child: _GlowOrb(
              size: 176,
              color: _withAlpha(JournalColors.accent, 0.18),
            ),
          ),
          Positioned(
            top: 238,
            right: -36,
            child: _GlowOrb(
              size: 148,
              color: _withAlpha(JournalColors.accent2, 0.12),
            ),
          ),
          Positioned(
            bottom: 112,
            left: 18,
            child: _GlowOrb(
              size: 128,
              color: _withAlpha(JournalColors.info, 0.10),
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

class _HeroGlyph extends StatelessWidget {
  const _HeroGlyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _withAlpha(JournalColors.accent, 0.22),
            _withAlpha(JournalColors.info, 0.12),
          ],
        ),
        border: Border.all(color: JournalColors.borderBright),
      ),
      child: Icon(icon, color: JournalColors.textPrimary, size: 22),
    );
  }
}

class _ExitPlanHero extends StatelessWidget {
  const _ExitPlanHero({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.icon,
  });

  final String eyebrow;
  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: JournalColors.borderBright),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _withAlpha(JournalColors.bgCard, 0.97),
            _withAlpha(const Color(0xFF11142A), 0.94),
            _withAlpha(const Color(0xFF191122), 0.92),
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: JournalColors.accentGlow,
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroGlyph(icon: icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: const TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    height: 1.18,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  body,
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
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _withAlpha(color, 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _withAlpha(color, 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
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
          const SizedBox(height: 4),
          Text(
            detail,
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanOverviewCard extends StatelessWidget {
  const _PlanOverviewCard({
    required this.title,
    required this.planType,
    required this.progress,
    required this.doneTasks,
    required this.totalTasks,
    required this.todayCount,
    required this.phaseCount,
  });

  final String title;
  final String planType;
  final double progress;
  final int doneTasks;
  final int totalTasks;
  final int todayCount;
  final int phaseCount;

  @override
  Widget build(BuildContext context) {
    final progressLabel = '${(progress * 100).round()}% complete';

    return GlassCard(
      padding: const EdgeInsets.all(16),
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
                    const Text(
                      'ACTIVE PLAN',
                      style: TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              if (planType.isNotEmpty)
                _Pill(
                  planType.replaceAll('_', ' '),
                  JournalColors.accent,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _withAlpha(Colors.white, 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _withAlpha(Colors.white, 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'PROGRESS',
                      style: TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      progressLabel,
                      style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: _withAlpha(Colors.white, 0.08),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      JournalColors.success,
                    ),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$doneTasks of $totalTasks tasks completed',
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CompactStatPill(
                label: 'Today',
                value: '$todayCount tasks',
                color: JournalColors.accent,
              ),
              _CompactStatPill(
                label: 'Phases',
                value: '$phaseCount groups',
                color: JournalColors.info,
              ),
              _CompactStatPill(
                label: 'Progress',
                value: progressLabel,
                color: JournalColors.success,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : JournalColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CompactStatPill extends StatelessWidget {
  const _CompactStatPill({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _withAlpha(color, 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _withAlpha(color, 0.20)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: const TextStyle(
                color: JournalColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
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

class _TodayTab extends StatelessWidget {
  final Widget? topContent;
  final List<Map<String, dynamic>> tasks;
  final Future<void> Function(String, String) onStatusChange;
  final void Function(Map<String, dynamic>) onTapTask;

  const _TodayTab({
    this.topContent,
    required this.tasks,
    required this.onStatusChange,
    required this.onTapTask,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          if (topContent != null) ...[
            topContent!,
            const SizedBox(height: 12),
          ],
          const GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _HeroGlyph(icon: CupertinoIcons.check_mark_circled),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Today is clear.',
                        style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),
                Text(
                  'There are no tasks in the current queue. Use the Phases tab if you want to pull the next step forward or add a new task.',
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
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        if (topContent != null) ...[
          topContent!,
          const SizedBox(height: 12),
        ],
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: SectionHeader(title: 'Today Queue'),
        ),
        ...tasks.map((t) => _TodayTaskCard(
              task: t,
              onStatusChange: onStatusChange,
              onTapTask: () => onTapTask(t),
            )),
      ],
    );
  }
}

class _TodayTaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final Future<void> Function(String, String) onStatusChange;
  final VoidCallback onTapTask;

  const _TodayTaskCard({
    required this.task,
    required this.onStatusChange,
    required this.onTapTask,
  });

  @override
  Widget build(BuildContext context) {
    final id = task['id']?.toString() ?? '';
    final status = task['status'] as String? ?? 'backlog';
    final priority = task['priority'] as String? ?? 'normal';
    final isDoing = status == 'doing';
    final isDone = status == 'done';
    final priColor = _priorityColors[priority] ?? JournalColors.accent;
    final dueDate = task['due_date'] as String?;

    String? dueDateStr;
    if (dueDate != null && dueDate.isNotEmpty) {
      try {
        dueDateStr =
            DateTime.parse(dueDate).toLocal().toString().substring(0, 10);
      } catch (_) {}
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _withAlpha(JournalColors.bgCard, 0.98),
                _withAlpha(JournalColors.bgCardAlt, 0.92),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: priColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _withAlpha(priColor, 0.28),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task['title'] as String? ?? '',
                            style: const TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _Pill(priority.toUpperCase(), priColor),
                              if (isDoing)
                                const _Pill(
                                    'In Progress', JournalColors.success),
                              if ((task['_phase_title'] as String? ?? '')
                                  .isNotEmpty)
                                _Pill(
                                  task['_phase_title'] as String,
                                  JournalColors.textMuted,
                                ),
                              if (dueDateStr != null)
                                _Pill(
                                    'Due $dueDateStr', JournalColors.severity),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!isDone) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!isDoing)
                        _SmallBtn(
                          label: 'Start',
                          filled: true,
                          onTap: () => onStatusChange(id, 'doing'),
                        ),
                      _SmallBtn(
                        label: 'Mark Done',
                        filled: true,
                        color: JournalColors.success,
                        onTap: () => onStatusChange(id, 'done'),
                      ),
                      _SmallBtn(
                        label: 'Details',
                        filled: false,
                        onTap: onTapTask,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  final Color color;

  const _SmallBtn({
    required this.label,
    required this.filled,
    required this.onTap,
    this.color = JournalColors.accent,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: filled ? color : _withAlpha(JournalColors.bgSurface, 0.72),
            borderRadius: BorderRadius.circular(12),
            border: filled ? null : Border.all(color: JournalColors.border),
          ),
          child: Text(label,
              style: TextStyle(
                color: filled ? Colors.white : JournalColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              )),
        ),
      );
}

// ── Phases tab ────────────────────────────────────────────────────────────

class _PhasesTab extends StatelessWidget {
  final Widget? topContent;
  final List<dynamic> phases;
  final Future<void> Function(String, String) onStatusChange;
  final void Function(Map<String, dynamic>) onTapTask;
  final VoidCallback onRefresh;

  const _PhasesTab({
    this.topContent,
    required this.phases,
    required this.onStatusChange,
    required this.onTapTask,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (phases.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          if (topContent != null) ...[
            topContent!,
            const SizedBox(height: 12),
          ],
          const GlassCard(
            child: Text(
              'No phases are available yet. Once tasks are generated, they will be grouped here into clear stages.',
              style: TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        if (topContent != null) ...[
          topContent!,
          const SizedBox(height: 12),
        ],
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: SectionHeader(title: 'Phases'),
        ),
        ...phases.map((ph) => _PhaseRow(
              phase: Map<String, dynamic>.from(ph),
              onStatusChange: onStatusChange,
              onTapTask: onTapTask,
              onRefresh: onRefresh,
            )),
      ],
    );
  }
}

class _PhaseRow extends StatefulWidget {
  final Map<String, dynamic> phase;
  final Future<void> Function(String, String) onStatusChange;
  final void Function(Map<String, dynamic>) onTapTask;
  final VoidCallback onRefresh;

  const _PhaseRow({
    required this.phase,
    required this.onStatusChange,
    required this.onTapTask,
    required this.onRefresh,
  });

  @override
  State<_PhaseRow> createState() => _PhaseRowState();
}

class _PhaseRowState extends State<_PhaseRow> {
  late bool _expanded;
  bool _addingTask = false;
  bool _savingTask = false;
  bool _aiEnrich = true;
  String _newPriority = 'normal';
  String? _taskError;
  final _titleCtrl = TextEditingController();
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _expanded = widget.phase['status'] == 'active';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitTask() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() {
      _savingTask = true;
      _taskError = null;
    });
    try {
      final res = await _api.exitPlanAddTask({
        'phase_id': widget.phase['id'],
        'title': title,
        'priority': _newPriority,
      });
      final taskId = res['task_id']?.toString() ?? '';
      _titleCtrl.clear();
      setState(() {
        _addingTask = false;
        _savingTask = false;
        _newPriority = 'normal';
        _aiEnrich = true;
      });
      widget.onRefresh();
      // fire AI enrich in background — non-blocking
      if (_aiEnrich && taskId.isNotEmpty) {
        _api.exitPlanEnrichTask(taskId).whenComplete(widget.onRefresh);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _taskError = 'Failed to save task';
          _savingTask = false;
        });
      }
    }
  }

  void _cancelAdd() {
    _titleCtrl.clear();
    setState(() {
      _addingTask = false;
      _taskError = null;
      _newPriority = 'normal';
      _aiEnrich = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tasks = List<Map<String, dynamic>>.from(widget.phase['tasks'] ?? []);
    final done = tasks.where((t) => t['status'] == 'done').length;
    final total = tasks.length;
    final pct = total > 0 ? done / total : 0.0;
    final status = widget.phase['status'] as String? ?? '';
    final locked = status == 'locked';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _withAlpha(JournalColors.bgCard, 0.98),
                _withAlpha(JournalColors.bgCardAlt, 0.92),
              ],
            ),
          ),
          child: Column(
            children: [
              // ── Phase header ──────────────────────────────────────────────
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PHASE',
                            style: TextStyle(
                              color: _withAlpha(JournalColors.textMuted, 0.9),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                              child: Text(
                                widget.phase['title'] as String? ?? '',
                                style: const TextStyle(
                                  color: JournalColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusPill(status),
                          ]),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: pct,
                              backgroundColor: _withAlpha(Colors.white, 0.08),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                JournalColors.success,
                              ),
                              minHeight: 5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('$done / $total tasks',
                              style: const TextStyle(
                                  color: JournalColors.textSecondary,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      _expanded
                          ? CupertinoIcons.chevron_up
                          : CupertinoIcons.chevron_down,
                      color: JournalColors.textMuted,
                      size: 16,
                    ),
                  ]),
                ),
              ),

              // ── Task list ─────────────────────────────────────────────────
              if (_expanded && tasks.isNotEmpty)
                const Divider(
                    color: JournalColors.border,
                    height: 1,
                    indent: 16,
                    endIndent: 16),
              if (_expanded)
                ...tasks.map((t) => _TaskCard(
                      task: {...t, '_phase_title': widget.phase['title'] ?? ''},
                      onStatusChange: widget.onStatusChange,
                      onTap: () => widget.onTapTask(
                          {...t, '_phase_title': widget.phase['title'] ?? ''}),
                      insideCard: true,
                    )),

              // ── Add task section ──────────────────────────────────────────
              if (_expanded && !locked) ...[
                const Divider(
                    color: JournalColors.border,
                    height: 1,
                    indent: 16,
                    endIndent: 16),
                if (!_addingTask)
                  // Dashed "+ Add task" button
                  GestureDetector(
                    onTap: () => setState(() => _addingTask = true),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _withAlpha(JournalColors.bgSurface, 0.60),
                        border:
                            Border.all(color: JournalColors.border, width: 1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text('+ Add task',
                            style: TextStyle(
                                color: JournalColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  )
                else
                  // Inline add form
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _withAlpha(JournalColors.bgSurface, 0.78),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: JournalColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title input
                          CupertinoTextField(
                            controller: _titleCtrl,
                            autofocus: true,
                            placeholder: 'Task title…',
                            placeholderStyle: const TextStyle(
                                color: JournalColors.textMuted, fontSize: 13),
                            style: const TextStyle(
                                color: JournalColors.textPrimary, fontSize: 13),
                            decoration: BoxDecoration(
                              color: JournalColors.bgCardAlt,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: JournalColors.border),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _submitTask(),
                          ),
                          const SizedBox(height: 12),

                          // Priority label
                          const Text('PRIORITY',
                              style: TextStyle(
                                  color: JournalColors.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.8)),
                          const SizedBox(height: 8),

                          // Priority pills
                          Wrap(
                            spacing: 6,
                            children:
                                ['critical', 'high', 'normal', 'low'].map((p) {
                              final selected = _newPriority == p;
                              final color =
                                  _priorityColors[p] ?? JournalColors.accent;
                              return GestureDetector(
                                onTap: () => setState(() => _newPriority = p),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 130),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? color.withValues(alpha: 0.15)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(99),
                                    border: Border.all(
                                        color: selected
                                            ? color
                                            : JournalColors.border),
                                  ),
                                  child: Text(p,
                                      style: TextStyle(
                                        color: selected
                                            ? color
                                            : JournalColors.textMuted,
                                        fontSize: 12,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                      )),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),

                          // AI enrich toggle
                          GestureDetector(
                            onTap: () => setState(() => _aiEnrich = !_aiEnrich),
                            child: Row(children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 34,
                                height: 20,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(99),
                                  color: _aiEnrich
                                      ? JournalColors.accent
                                      : JournalColors.border,
                                ),
                                child: AnimatedAlign(
                                  duration: const Duration(milliseconds: 200),
                                  alignment: _aiEnrich
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.all(2),
                                    width: 16,
                                    height: 16,
                                    decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _aiEnrich
                                      ? '✨ AI will generate: what to do, why it matters, and resources'
                                      : 'Manual task — no AI enrichment',
                                  style: TextStyle(
                                    color: _aiEnrich
                                        ? JournalColors.textSecondary
                                        : JournalColors.textMuted,
                                    fontSize: 11,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 14),

                          if (_taskError != null) ...[
                            Text(_taskError!,
                                style: const TextStyle(
                                    color: JournalColors.danger, fontSize: 11)),
                            const SizedBox(height: 8),
                          ],

                          // Action buttons
                          Row(children: [
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              color: JournalColors.accent,
                              borderRadius: BorderRadius.circular(8),
                              onPressed: (_savingTask ||
                                      _titleCtrl.text.trim().isEmpty)
                                  ? null
                                  : _submitTask,
                              child: _savingTask
                                  ? const CupertinoActivityIndicator(
                                      radius: 8, color: Colors.white)
                                  : Text(
                                      _aiEnrich ? 'Add + AI Fill' : 'Add Task',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                            ),
                            const SizedBox(width: 8),
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              color: JournalColors.bgCardAlt,
                              borderRadius: BorderRadius.circular(8),
                              onPressed: _cancelAdd,
                              child: const Text('Cancel',
                                  style: TextStyle(
                                      color: JournalColors.textSecondary,
                                      fontSize: 12)),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Notes tab ─────────────────────────────────────────────────────────────

class _NotesTab extends StatefulWidget {
  final Widget? topContent;
  final String planId;
  final ApiService api;

  const _NotesTab({this.topContent, required this.planId, required this.api});

  @override
  State<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<_NotesTab> {
  List<dynamic> _notes = [];
  bool _loading = true;
  bool _saving = false;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await widget.api.exitPlanGetNotes();
      if (mounted) {
        setState(() {
          _notes = List<dynamic>.from(r['notes'] ?? []);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addNote() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.api.exitPlanAddNote(text);
      _ctrl.clear();
      await _load();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        if (widget.topContent != null) ...[
          widget.topContent!,
          const SizedBox(height: 12),
        ],
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: SectionHeader(title: 'Notes'),
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Keep practical context nearby.',
                style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use notes for details you want attached to the plan without turning them into tasks.',
                style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              CupertinoTextField(
                controller: _ctrl,
                placeholder: 'Add a note…',
                placeholderStyle: const TextStyle(
                    color: JournalColors.textMuted, fontSize: 13),
                style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 13,
                    height: 1.5),
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.bgSurface, 0.72),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: JournalColors.border),
                ),
                maxLines: 4,
                minLines: 3,
                padding: const EdgeInsets.all(14),
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  color: JournalColors.accent,
                  borderRadius: BorderRadius.circular(16),
                  onPressed:
                      (_saving || _ctrl.text.trim().isEmpty) ? null : _addNote,
                  child: _saving
                      ? const CupertinoActivityIndicator(
                          radius: 8, color: Colors.white)
                      : const Text('Add Note',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(
                child: CupertinoActivityIndicator(color: JournalColors.accent)),
          )
        else if (_notes.isEmpty)
          const GlassCard(
            child: Text(
              'No notes yet. Add reminders, constraints, contact details, or context you want visible while working through the plan.',
              style: TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          )
        else
          ..._notes.map((n) {
            final note = Map<String, dynamic>.from(n);
            final raw = note['created_at'] as String? ?? '';
            String dateStr = '';
            if (raw.isNotEmpty) {
              try {
                dateStr =
                    DateTime.parse(raw).toLocal().toString().substring(0, 16);
              } catch (_) {}
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note['note_text'] as String? ?? '',
                      style: const TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 14,
                          height: 1.6),
                    ),
                    const SizedBox(height: 8),
                    Text(dateStr,
                        style: const TextStyle(
                            color: JournalColors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

// ── Task card ─────────────────────────────────────────────────────────────

class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final Future<void> Function(String, String) onStatusChange;
  final VoidCallback onTap;
  final bool insideCard;

  const _TaskCard({
    required this.task,
    required this.onStatusChange,
    required this.onTap,
    this.insideCard = false,
  });

  @override
  Widget build(BuildContext context) {
    final status = task['status'] as String? ?? 'backlog';
    final priority = task['priority'] as String? ?? 'normal';
    final title = task['title'] as String? ?? '';
    final phaseTitle = task['_phase_title'] as String? ?? '';
    final isDone = status == 'done';
    final id = task['id']?.toString() ?? '';

    final priColor = _priorityColors[priority] ?? JournalColors.accent;

    Widget content = Padding(
      padding:
          EdgeInsets.symmetric(horizontal: insideCard ? 16 : 0, vertical: 14),
      child: Row(children: [
        // Status toggle circle
        GestureDetector(
          onTap: isDone ? null : () => onStatusChange(id, 'done'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone ? JournalColors.success : Colors.transparent,
              border: Border.all(
                color: isDone ? JournalColors.success : JournalColors.border,
                width: 1.5,
              ),
            ),
            child: isDone
                ? const Icon(CupertinoIcons.checkmark,
                    color: Colors.white, size: 12)
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isDone
                      ? JournalColors.textMuted
                      : JournalColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(children: [
                _PriorityDot(priColor),
                const SizedBox(width: 5),
                Text(priority,
                    style: TextStyle(
                        color: priColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
                if (phaseTitle.isNotEmpty) ...[
                  const Text('  ·  ',
                      style: TextStyle(
                          color: JournalColors.textMuted, fontSize: 11)),
                  Flexible(
                      child: Text(phaseTitle,
                          style: const TextStyle(
                              color: JournalColors.textMuted, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                ],
              ]),
            ],
          ),
        ),
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          onPressed: onTap,
          child: const Icon(CupertinoIcons.chevron_right,
              color: JournalColors.textMuted, size: 14),
        ),
      ]),
    );

    if (insideCard) return content;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: content,
      ),
    );
  }
}

// ── Resource library (ported from ExitPlan.jsx) ───────────────────────────

class _Resource {
  final String name, description, catTitle, catIcon;
  final Color catColor;
  final String? url;
  const _Resource(
      {required this.name,
      required this.description,
      required this.catTitle,
      required this.catIcon,
      required this.catColor,
      this.url});
}

const _resLibrary = {
  'crisis': (
    icon: '🆘',
    color: Color(0xFFEF4444),
    title: 'Crisis & Immediate Safety',
    resources: [
      (
        name: 'National DV Hotline',
        desc: '1-800-799-7233 · text START to 88788 · 24/7',
        url: 'https://thehotline.org'
      ),
      (
        name: 'Crisis Text Line',
        desc: 'Text HOME to 741741 — free, 24/7',
        url: null
      ),
      (
        name: '988 Lifeline',
        desc: 'Call or text 988 — 24/7 crisis support',
        url: 'https://988lifeline.org'
      ),
    ]
  ),
  'legal': (
    icon: '⚖️',
    color: Color(0xFF64748B),
    title: 'Legal Aid & Rights',
    resources: [
      (
        name: 'LawHelp.org',
        desc: 'Free legal info by state',
        url: 'https://lawhelp.org'
      ),
      (
        name: 'Legal Services Corp',
        desc: 'Find free civil legal aid near you',
        url: 'https://www.lsc.gov/about-lsc/what-legal-aid/get-legal-help'
      ),
    ]
  ),
  'housing': (
    icon: '🏠',
    color: Color(0xFF0EA5E9),
    title: 'Housing & Practical Needs',
    resources: [
      (
        name: '211 Helpline',
        desc: 'Dial 2-1-1 — local housing, food, financial',
        url: 'https://211.org'
      ),
      (
        name: 'HUD Rental Assistance',
        desc: 'Federal housing assistance programs',
        url: 'https://www.hud.gov/topics/rental_assistance'
      ),
    ]
  ),
  'financial': (
    icon: '💰',
    color: Color(0xFF10B981),
    title: 'Financial Help',
    resources: [
      (
        name: '211 Helpline',
        desc: 'Dial 2-1-1 — connects to local financial aid',
        url: 'https://211.org'
      ),
      (
        name: 'Free Credit Report',
        desc: 'annualcreditreport.com — free from all 3 bureaus',
        url: 'https://annualcreditreport.com'
      ),
    ]
  ),
  'parenting': (
    icon: '🌻',
    color: Color(0xFFF59E0B),
    title: 'Parenting & Co-Parenting',
    resources: [
      (
        name: 'Our Family Wizard',
        desc: 'Co-parenting communication tool',
        url: 'https://ourfamilywizard.com'
      ),
      (
        name: 'Childhelp Hotline',
        desc: '1-800-422-4453 — support for parents',
        url: null
      ),
    ]
  ),
  'emotional_support': (
    icon: '💬',
    color: Color(0xFF8B5CF6),
    title: 'Emotional Support',
    resources: [
      (
        name: 'BetterHelp',
        desc: 'Online therapy — text, video, or phone',
        url: 'https://betterhelp.com'
      ),
      (
        name: '7 Cups',
        desc: 'Free anonymous chat with trained listeners',
        url: 'https://7cups.com'
      ),
    ]
  ),
  'safety_planning': (
    icon: '🛡',
    color: Color(0xFFF97316),
    title: 'Safety Planning',
    resources: [
      (
        name: 'National DV Hotline',
        desc: '1-800-799-7233 — safety planning support',
        url: 'https://thehotline.org'
      ),
      (
        name: 'iSafety Plan',
        desc: 'Free safety planning guide online',
        url: 'https://www.thehotline.org/plan-for-safety'
      ),
    ]
  ),
  'job_search': (
    icon: '🔍',
    color: Color(0xFF3B82F6),
    title: 'Job Search & Employment',
    resources: [
      (
        name: 'Indeed',
        desc: 'Job listings — filter by location and hours',
        url: 'https://indeed.com'
      ),
      (
        name: 'CareerOneStop',
        desc: 'Free career tools and skills assessment',
        url: 'https://careeronestop.org'
      ),
    ]
  ),
  'pets': (
    icon: '🐾',
    color: Color(0xFFD97706),
    title: 'Pet Resources',
    resources: [
      (
        name: 'ASPCA',
        desc: 'Pet care resources and emergency assistance',
        url: 'https://aspca.org'
      ),
      (
        name: 'RedRover Relief',
        desc: 'Financial aid for urgent pet care needs',
        url: 'https://redrover.org/relief'
      ),
    ]
  ),
  'documentation': (
    icon: '📋',
    color: Color(0xFF475569),
    title: 'Documentation & Records',
    resources: [
      (
        name: 'Google Drive',
        desc: 'Free secure cloud storage for your documents',
        url: 'https://drive.google.com'
      ),
      (
        name: 'Signal',
        desc: 'Encrypted messaging — keep evidence private',
        url: 'https://signal.org'
      ),
    ]
  ),
  'self_care': (
    icon: '🌿',
    color: Color(0xFF7C3AED),
    title: 'Self-Care & Wellbeing',
    resources: [
      (
        name: 'Calm',
        desc: 'Meditation and sleep support app',
        url: 'https://calm.com'
      ),
      (
        name: 'Woebot',
        desc: 'Free AI mental health support',
        url: 'https://woebothealth.com'
      ),
    ]
  ),
};

const _keywordMap = [
  (
    k: [
      'safety contact',
      'safe space',
      'escape route',
      'abuse',
      'violence',
      'emergency',
      'go-bag',
      'safe word',
      'safety plan',
      'dv hotline',
      'unsafe'
    ],
    cats: ['crisis', 'safety_planning']
  ),
  (
    k: [
      'incident log',
      'document incident',
      'record abuse',
      'document abuse',
      'evidence of'
    ],
    cats: ['documentation', 'safety_planning']
  ),
  (
    k: [
      'legal',
      'court',
      'protection order',
      'restraining order',
      'attorney',
      'lawyer',
      'divorce',
      'legal aid'
    ],
    cats: ['legal']
  ),
  (
    k: ['tenant rights', 'lease', 'eviction', 'landlord'],
    cats: ['housing', 'legal']
  ),
  (
    k: [
      'housing',
      'shelter',
      'apartment',
      'rent',
      'move out',
      'new place',
      'living situation',
      'find housing',
      'affordable housing'
    ],
    cats: ['housing']
  ),
  (
    k: [
      'bank account',
      'credit report',
      'credit freeze',
      'savings',
      'budget',
      'financial',
      'direct deposit',
      'joint account',
      'marital assets'
    ],
    cats: ['financial']
  ),
  (
    k: [
      'job',
      'employment',
      'work',
      'career',
      'resume',
      'interview',
      'unemployment',
      'job search'
    ],
    cats: ['job_search']
  ),
  (
    k: [
      'children',
      'child',
      'custody',
      'co-parent',
      'coparent',
      'school',
      'daycare',
      'kids',
      'parenting',
      'child support'
    ],
    cats: ['parenting']
  ),
  (
    k: [
      'pet',
      'pets',
      'animal',
      'dog',
      'cat',
      'vet',
      'boarding',
      'foster pet',
      'pet care'
    ],
    cats: ['pets']
  ),
  (
    k: [
      'therapist',
      'counselor',
      'mental health',
      'emotional support',
      'healing',
      'cope',
      'anxiety',
      'grief',
      'overwhelmed',
      'therapy'
    ],
    cats: ['emotional_support']
  ),
  (
    k: [
      'self-care',
      'self care',
      'exercise',
      'meditation',
      'sleep',
      'grounding',
      'stabilize'
    ],
    cats: ['self_care']
  ),
  (
    k: ['private phone', 'encrypted', 'privacy', 'signal', 'safe contact'],
    cats: ['safety_planning']
  ),
];

List<_Resource> _getTaskResources(Map<String, dynamic> task) {
  final text =
      '${task['title'] ?? ''} ${task['description'] ?? ''} ${task['why_it_matters'] ?? ''}'
          .toLowerCase();
  final matched = <String>{};
  for (final entry in _keywordMap) {
    if (entry.k.any((kw) => text.contains(kw))) {
      matched.addAll(entry.cats);
    }
  }
  if (matched.isEmpty) matched.add('emotional_support');

  final result = <_Resource>[];
  final seen = <String>{};
  for (final cat in matched) {
    final lib = _resLibrary[cat];
    if (lib == null) continue;
    for (final r in lib.resources.take(2)) {
      if (!seen.contains(r.name)) {
        seen.add(r.name);
        result.add(_Resource(
          name: r.name,
          description: r.desc,
          url: r.url,
          catTitle: lib.title,
          catIcon: lib.icon,
          catColor: lib.color,
        ));
      }
    }
  }
  return result.take(7).toList();
}

// ── Task detail sheet ─────────────────────────────────────────────────────

class _TaskDetailSheet extends StatefulWidget {
  final Map<String, dynamic> task;
  final Future<void> Function(String, String) onStatusChange;
  final ApiService api;
  final VoidCallback onRefresh;

  const _TaskDetailSheet(
      {required this.task,
      required this.onStatusChange,
      required this.api,
      required this.onRefresh});

  @override
  State<_TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<_TaskDetailSheet> {
  List<dynamic> _notes = [];
  bool _loadingNotes = false;
  bool _savingNote = false;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    final id = widget.task['id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() => _loadingNotes = true);
    try {
      final r = await widget.api.exitPlanGetNotes(taskId: id);
      if (mounted) {
        setState(() {
          _notes = List<dynamic>.from(r['notes'] ?? []);
          _loadingNotes = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingNotes = false);
    }
  }

  Future<void> _addNote() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final id = widget.task['id']?.toString() ?? '';
    setState(() => _savingNote = true);
    try {
      await widget.api.exitPlanAddNote(text, taskId: id);
      _ctrl.clear();
      await _loadNotes();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  Future<void> _confirmDelete(BuildContext ctx, String taskId) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: ctx,
      builder: (_) => DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: CupertinoAlertDialog(
          title: const Text('Delete Task'),
          content: const Text('Delete this task? This cannot be undone.'),
          actions: [
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.exitPlanDeleteTask(taskId);
      if (mounted) {
        Navigator.of(context).pop();
        widget.onRefresh();
      }
    } catch (_) {}
  }

  List<Widget> _buildResources(Map<String, dynamic> task) {
    final resources = _getTaskResources(task);
    if (resources.isEmpty) return [];
    return [
      _sheetLabel('Resources for this step'),
      const SizedBox(height: 8),
      ...resources.map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: r.catColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: r.catColor.withValues(alpha: 0.2)),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.catIcon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    r.url != null
                        ? Text('${r.name} ↗',
                            style: TextStyle(
                                color: r.catColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600))
                        : Text(r.name,
                            style: TextStyle(
                                color: r.catColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(r.description,
                        style: const TextStyle(
                            color: JournalColors.textMuted,
                            fontSize: 11,
                            height: 1.4)),
                  ],
                )),
              ]),
            ),
          )),
      const SizedBox(height: 8),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final status = task['status'] as String? ?? 'backlog';
    final priority = task['priority'] as String? ?? 'normal';
    final isDone = status == 'done' || status == 'skipped';
    final id = task['id']?.toString() ?? '';
    final priColor = _priorityColors[priority] ?? JournalColors.accent;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: JournalColors.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: JournalColors.border,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row
                  Row(children: [
                    Expanded(
                      child: Text(
                        task['title'] as String? ?? '',
                        style: const TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            height: 1.4),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Icon(CupertinoIcons.xmark_circle_fill,
                          color: JournalColors.textMuted, size: 26),
                    ),
                  ]),
                  const SizedBox(height: 8),

                  // Phase + meta pills
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    _Pill(
                        _statusLabels[status] ?? status, JournalColors.accent),
                    _Pill('$priority priority', priColor),
                    if (task['_phase_title'] != null &&
                        (task['_phase_title'] as String).isNotEmpty)
                      _Pill(task['_phase_title'] as String,
                          JournalColors.textMuted),
                  ]),
                  const SizedBox(height: 16),

                  // Description
                  if ((task['description'] as String? ?? '').isNotEmpty) ...[
                    _sheetLabel('What to do'),
                    const SizedBox(height: 6),
                    Text(task['description'] as String,
                        style: const TextStyle(
                            color: JournalColors.textSecondary,
                            fontSize: 13,
                            height: 1.65)),
                    const SizedBox(height: 16),
                  ],

                  // Why it matters
                  if ((task['why_it_matters'] as String? ?? '').isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: JournalColors.accent.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: JournalColors.accent.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sheetLabel('Why this matters',
                                color: JournalColors.accent),
                            const SizedBox(height: 6),
                            Text(task['why_it_matters'] as String,
                                style: const TextStyle(
                                    color: JournalColors.textSecondary,
                                    fontSize: 13,
                                    height: 1.65)),
                          ]),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Resources
                  ..._buildResources(task),

                  // Status actions
                  if (!isDone) ...[
                    Row(children: [
                      if (status != 'doing')
                        Expanded(
                          child: _ActionBtn(
                            label: 'Mark In Progress',
                            onTap: () => widget.onStatusChange(id, 'doing'),
                            color: JournalColors.accent,
                            ghost: true,
                          ),
                        ),
                      if (status != 'doing') const SizedBox(width: 8),
                      Expanded(
                        child: _ActionBtn(
                          label: 'Mark Done',
                          onTap: () => widget.onStatusChange(id, 'done'),
                          color: const Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ActionBtn(
                        label: 'Skip',
                        onTap: () => widget.onStatusChange(id, 'skipped'),
                        color: JournalColors.textMuted,
                        ghost: true,
                      ),
                    ]),
                    const SizedBox(height: 16),
                  ],

                  // Delete task
                  GestureDetector(
                    onTap: () => _confirmDelete(context, id),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x33EF4444)),
                      ),
                      alignment: Alignment.center,
                      child: const Text('🗑  Delete task',
                          style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Notes
                  _sheetLabel('Notes'),
                  const SizedBox(height: 8),
                  if (_loadingNotes)
                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 12),
                      child: CupertinoActivityIndicator(
                          radius: 8, color: JournalColors.accent),
                    )
                  else
                    ..._notes.map((n) {
                      final note = Map<String, dynamic>.from(n);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: JournalColors.bgBase,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: JournalColors.border),
                          ),
                          child: Text(note['note_text'] as String? ?? '',
                              style: const TextStyle(
                                  color: JournalColors.textSecondary,
                                  fontSize: 12,
                                  height: 1.6)),
                        ),
                      );
                    }),

                  // Add note input
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: CupertinoTextField(
                        controller: _ctrl,
                        placeholder: 'Add a note…',
                        placeholderStyle: const TextStyle(
                            color: JournalColors.textMuted, fontSize: 12),
                        style: const TextStyle(
                            color: JournalColors.textPrimary, fontSize: 12),
                        decoration: BoxDecoration(
                          color: JournalColors.bgBase,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: JournalColors.border),
                        ),
                        padding: const EdgeInsets.all(10),
                        maxLines: 3,
                        minLines: 2,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      color: JournalColors.accent,
                      borderRadius: BorderRadius.circular(8),
                      onPressed: (_savingNote || _ctrl.text.trim().isEmpty)
                          ? null
                          : _addNote,
                      child: _savingNote
                          ? const CupertinoActivityIndicator(
                              radius: 8, color: Colors.white)
                          : const Text('Add',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetLabel(String text, {Color? color}) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color ?? JournalColors.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      );
}

// ── Small shared widgets ───────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill(this.status);

  @override
  Widget build(BuildContext context) {
    final color = status == 'active'
        ? JournalColors.accent
        : status == 'complete'
            ? const Color(0xFF10B981)
            : JournalColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status,
        style:
            TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      );
}

class _PriorityDot extends StatelessWidget {
  final Color color;
  const _PriorityDot(this.color);

  @override
  Widget build(BuildContext context) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool ghost;

  const _ActionBtn(
      {required this.label,
      required this.onTap,
      required this.color,
      this.ghost = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: ghost ? Colors.transparent : color,
            borderRadius: BorderRadius.circular(10),
            border: ghost ? Border.all(color: JournalColors.border) : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: ghost ? JournalColors.textSecondary : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}
