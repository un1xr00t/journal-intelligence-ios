// lib/screens/detective_screen.dart
//
// Detective Mode entry point — access check + cases list.
// Pushes into DetectiveCaseScreen when a case is selected.

import 'package:flutter/cupertino.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'detective_case_screen.dart';

class DetectiveScreen extends StatefulWidget {
  const DetectiveScreen({super.key});

  @override
  State<DetectiveScreen> createState() => _DetectiveScreenState();
}

class _DetectiveScreenState extends State<DetectiveScreen> {
  final _api = ApiService();

  bool? _hasAccess;         // null = loading
  List<Map<String, dynamic>> _cases = [];
  bool _loadingCases = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    try {
      final res = await _api.detectiveCheckAccess();
      if (!mounted) return;
      setState(() => _hasAccess = res['has_access'] as bool? ?? false);
      if (_hasAccess == true) _loadCases();
    } catch (_) {
      if (mounted) setState(() => _hasAccess = false);
    }
  }

  Future<void> _loadCases() async {
    setState(() { _loadingCases = true; _error = null; });
    try {
      final res = await _api.detectiveGetCases();
      if (mounted) setState(() { _cases = List<Map<String, dynamic>>.from(res); _loadingCases = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loadingCases = false; });
    }
  }

  Future<void> _createCase(String title) async {
    setState(() => _creating = true);
    try {
      final newCase = await _api.detectiveCreateCase(title);
      if (!mounted) return;
      setState(() => _cases = [newCase, ..._cases]);
      _openCase(newCase);
    } catch (_) {} finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _openCase(Map<String, dynamic> c) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: DetectiveCaseScreen(caseData: c),
        ),
      ),
    ).then((_) => _loadCases()); // refresh list on return
  }

  void _showCreateSheet() {
    final controller = TextEditingController();
    showCupertinoModalPopup(
      context: context,
      builder: (_) => _CreateCaseSheet(
        controller: controller,
        creating: _creating,
        onSubmit: (title) {
          Navigator.pop(context);
          _createCase(title);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Detective Mode'),
            backgroundColor: JournalColors.bgBase.withOpacity(0.92),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
            trailing: _hasAccess == true
                ? GestureDetector(
                    onTap: _showCreateSheet,
                    child: const Icon(CupertinoIcons.add_circled,
                        color: JournalColors.accent, size: 24),
                  )
                : null,
          ),

          // ── Loading access ──
          if (_hasAccess == null)
            const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            ),

          // ── Access denied ──
          if (_hasAccess == false)
            SliverFillRemaining(
              child: _AccessDenied(),
            ),

          // ── Has access ──
          if (_hasAccess == true) ...[
            if (_loadingCases)
              const SliverFillRemaining(
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: _ErrorView(error: _error!, onRetry: _loadCases),
              )
            else if (_cases.isEmpty)
              SliverFillRemaining(
                child: _EmptyState(onCreateTap: _showCreateSheet),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    '${_cases.length} CASE${_cases.length == 1 ? '' : 'S'}',
                    style: const TextStyle(
                      color: JournalColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _CaseTile(
                      caseData: _cases[i],
                      onTap: () => _openCase(_cases[i]),
                    ),
                    childCount: _cases.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ],
        ],
      ),
    );
  }
}

// ── Case tile ──────────────────────────────────────────────────────────────

class _CaseTile extends StatelessWidget {
  final Map<String, dynamic> caseData;
  final VoidCallback onTap;
  const _CaseTile({required this.caseData, required this.onTap});

  Color get _statusColor {
    switch (caseData['status']) {
      case 'active':   return const Color(0xFF22C55E);
      case 'closed':   return JournalColors.textMuted;
      case 'archived': return const Color(0xFFF59E0B);
      default:         return JournalColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          // Status dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  caseData['title'] ?? 'Untitled',
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if ((caseData['description'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    caseData['description'],
                    style: const TextStyle(
                      color: JournalColors.textMuted,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  (caseData['status'] ?? 'active').toString().toUpperCase(),
                  style: TextStyle(
                    color: _statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(CupertinoIcons.chevron_right,
              color: JournalColors.textMuted, size: 14),
        ],
      ),
    );
  }
}

// ── Create case sheet ──────────────────────────────────────────────────────

class _CreateCaseSheet extends StatefulWidget {
  final TextEditingController controller;
  final bool creating;
  final ValueChanged<String> onSubmit;
  const _CreateCaseSheet({
    required this.controller,
    required this.creating,
    required this.onSubmit,
  });

  @override
  State<_CreateCaseSheet> createState() => _CreateCaseSheetState();
}

class _CreateCaseSheetState extends State<_CreateCaseSheet> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 24,
        left: 20,
        right: 20,
      ),
      decoration: const BoxDecoration(
        color: JournalColors.bgSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: JournalColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'New Case',
            style: TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          CupertinoTextField(
            controller: widget.controller,
            autofocus: true,
            placeholder: 'Case name…',
            placeholderStyle: const TextStyle(color: JournalColors.textMuted),
            style: const TextStyle(color: JournalColors.textPrimary, fontSize: 15),
            decoration: BoxDecoration(
              color: JournalColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: JournalColors.borderBright),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onSubmitted: (v) { if (v.trim().isNotEmpty) widget.onSubmit(v.trim()); },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton.filled(
              onPressed: widget.creating
                  ? null
                  : () {
                      final t = widget.controller.text.trim();
                      if (t.isNotEmpty) widget.onSubmit(t);
                    },
              borderRadius: BorderRadius.circular(12),
              child: widget.creating
                  ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                  : const Text('Create Case'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Access denied ──────────────────────────────────────────────────────────

class _AccessDenied extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔒', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text(
              'Access Required',
              style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Detective Mode requires access granted by your admin. Ask them to enable it from Admin → Detective Access.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: JournalColors.textMuted,
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateTap;
  const _EmptyState({required this.onCreateTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🕵️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text(
              'No Cases Yet',
              style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Create your first case to start building an investigation.',
              textAlign: TextAlign.center,
              style: TextStyle(color: JournalColors.textMuted, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 24),
            CupertinoButton(
              color: JournalColors.accent,
              borderRadius: BorderRadius.circular(12),
              onPressed: onCreateTap,
              child: const Text('Create First Case'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error view ─────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.exclamationmark_circle,
              color: JournalColors.textMuted, size: 40),
          const SizedBox(height: 12),
          Text(error,
              style: const TextStyle(color: JournalColors.textMuted, fontSize: 13)),
          const SizedBox(height: 16),
          CupertinoButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}