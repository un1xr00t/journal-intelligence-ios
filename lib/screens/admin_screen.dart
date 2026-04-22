import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

const _kAdminTabs = [
  'Summary',
  'Users',
  'Invites',
  'Detection',
  'AI Spend',
];

const Map<String, String> _kFeatureLabels = {
  'extraction': 'Entry extraction',
  'daily_summary': 'Daily summary',
  'master_summary': 'Master summary',
  'reflection': 'Reflection tones',
  'exit_plan': 'Exit plan generation',
  'resources': 'Resources ranking',
  'journal_prompt': 'Journal prompt',
  'rag_search': 'Ask my journal',
  'export_narrative': 'Export narrative',
  'pattern_analysis': 'Pattern analysis',
  'unknown': 'Unknown',
};

const Map<String, ({double input, double output})> _kModelPricing = {
  'claude-opus-4-6': (input: 5.0, output: 25.0),
  'claude-opus-4-5-20251101': (input: 5.0, output: 25.0),
  'claude-opus-4-5': (input: 5.0, output: 25.0),
  'claude-sonnet-4-6': (input: 3.0, output: 15.0),
  'claude-sonnet-4-5': (input: 3.0, output: 15.0),
  'claude-sonnet-4-20250514': (input: 3.0, output: 15.0),
  'claude-sonnet-4-5-20250514': (input: 3.0, output: 15.0),
  'claude-haiku-4-5': (input: 1.0, output: 5.0),
  'claude-haiku-4-5-20251001': (input: 1.0, output: 5.0),
  'claude-opus-4-1': (input: 15.0, output: 75.0),
  'claude-sonnet-4-1': (input: 3.0, output: 15.0),
  'claude-3-7-sonnet-20250219': (input: 3.0, output: 15.0),
  'claude-3-5-sonnet-20241022': (input: 3.0, output: 15.0),
  'claude-3-5-sonnet-20240620': (input: 3.0, output: 15.0),
  'claude-3-5-haiku-20241022': (input: 0.8, output: 4.0),
  'claude-3-opus-20240229': (input: 15.0, output: 75.0),
  'claude-3-sonnet-20240229': (input: 3.0, output: 15.0),
  'claude-3-haiku-20240307': (input: 0.25, output: 1.25),
  'gpt-4o': (input: 2.5, output: 10.0),
  'gpt-4o-2024-11-20': (input: 2.5, output: 10.0),
  'gpt-4o-2024-08-06': (input: 2.5, output: 10.0),
  'gpt-4o-mini': (input: 0.15, output: 0.6),
  'gpt-4o-mini-2024-07-18': (input: 0.15, output: 0.6),
  'gpt-4.1': (input: 2.0, output: 8.0),
  'gpt-4.1-mini': (input: 0.4, output: 1.6),
  'gpt-4.1-nano': (input: 0.1, output: 0.4),
  'gpt-4-turbo': (input: 10.0, output: 30.0),
  'gpt-4-turbo-preview': (input: 10.0, output: 30.0),
};

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _api = ApiService();

  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _inviteLabelCtrl = TextEditingController();

  Map<String, dynamic>? _masterSummary;
  Map<String, dynamic>? _aiUsage;
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _invites = const [];

  bool _loading = true;
  bool _refreshing = false;
  bool _addingUser = false;
  bool _creatingInvite = false;
  bool _runningDetection = false;

  String? _error;
  String? _addUserError;
  String? _addUserSuccess;
  String? _inviteError;
  String? _inviteCopyKey;
  String _newUserRole = 'viewer';
  String _inviteExpiry = '30d';
  int _tabIndex = 0;

  Map<String, dynamic>? _inviteResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _inviteLabelCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool refreshing = false}) async {
    if (refreshing) {
      setState(() {
        _refreshing = true;
        _error = null;
      });
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait([
        _api.getMasterSummary(),
        _api.getAdminUsers(),
        _api.getAdminAiUsage(),
        _api.getAdminInvites(),
      ]);

      if (!mounted) return;
      setState(() {
        _masterSummary = results[0] as Map<String, dynamic>?;
        _users = (results[1] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _aiUsage = results[2] as Map<String, dynamic>;
        _invites = (results[3] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _parseError(e);
        _loading = false;
        _refreshing = false;
      });
    }
  }

  String _parseError(dynamic e) {
    final str = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    return match?.group(1) ?? 'Something went wrong.';
  }

  Future<void> _addUser() async {
    final username = _usernameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (username.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() {
        _addUserError = 'Username, email, and password are required.';
        _addUserSuccess = null;
      });
      return;
    }

    setState(() {
      _addingUser = true;
      _addUserError = null;
      _addUserSuccess = null;
    });

    try {
      await _api.createAdminUser(
        username: username,
        email: email,
        password: password,
        role: _newUserRole,
      );
      if (!mounted) return;
      setState(() {
        _addingUser = false;
        _addUserSuccess = 'User $username created.';
        _usernameCtrl.clear();
        _emailCtrl.clear();
        _passwordCtrl.clear();
        _newUserRole = 'viewer';
      });
      await _load(refreshing: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _addingUser = false;
        _addUserError = _parseError(e);
      });
    }
  }

  Future<void> _removeUser(Map<String, dynamic> user) async {
    final id = user['id'] as int?;
    final username = user['username']?.toString() ?? 'this user';
    if (id == null) return;

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Remove User'),
        content: Text('Remove "$username" from the app?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _api.deleteAdminUser(id);
      await _load(refreshing: true);
    } catch (e) {
      if (!mounted) return;
      _showNotice(
        title: 'Couldn’t remove user',
        message: _parseError(e),
      );
    }
  }

  Future<void> _revokeSessions(Map<String, dynamic> user) async {
    final id = user['id'] as int?;
    final username = user['username']?.toString() ?? 'this user';
    if (id == null) return;

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Revoke Sessions'),
        content: Text('Revoke all active sessions for "$username"?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _api.revokeAdminUserSessions(id);
      if (!mounted) return;
      _showNotice(
        title: 'Sessions revoked',
        message: 'Active sessions for $username were cleared.',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotice(
        title: 'Couldn’t revoke sessions',
        message: _parseError(e),
      );
    }
  }

  Future<void> _createInvite() async {
    setState(() {
      _creatingInvite = true;
      _inviteError = null;
      _inviteResult = null;
    });

    try {
      final result = await _api.createAdminInvite(
        label: _inviteLabelCtrl.text,
        expiresIn: _inviteExpiry,
      );
      if (!mounted) return;
      setState(() {
        _creatingInvite = false;
        _inviteResult = result;
        _inviteLabelCtrl.clear();
      });
      await _load(refreshing: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creatingInvite = false;
        _inviteError = _parseError(e);
      });
    }
  }

  Future<void> _revokeInvite(Map<String, dynamic> invite) async {
    final id = invite['id'] as int?;
    if (id == null) return;

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Revoke Invite'),
        content: const Text(
          'This link will stop working immediately for the recipient.',
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _api.deleteAdminInvite(id);
      await _load(refreshing: true);
    } catch (e) {
      if (!mounted) return;
      _showNotice(
        title: 'Couldn’t revoke invite',
        message: _parseError(e),
      );
    }
  }

  Future<void> _copyInviteValue(String key, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    setState(() => _inviteCopyKey = key);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _inviteCopyKey = null);
    });
  }

  Future<void> _runDetectors() async {
    setState(() => _runningDetection = true);
    try {
      await _api.runPatternDetection();
      if (!mounted) return;
      _showNotice(
        title: 'Detection complete',
        message: 'Pattern checks finished successfully.',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotice(
        title: 'Detection failed',
        message: _parseError(e),
      );
    } finally {
      if (mounted) setState(() => _runningDetection = false);
    }
  }

  Future<void> _showNotice({
    required String title,
    required String message,
  }) async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  double? _costForRow(Map<String, dynamic> row) {
    final models = row['models']?.toString();
    if (models == null || models.trim().isEmpty) return null;

    final parsedModels = models
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (parsedModels.length != 1) return null;

    final pricing = _kModelPricing[parsedModels.first];
    if (pricing == null) return null;

    final input = _readInt(row['total_input']);
    final output = _readInt(row['total_output']);
    return ((input ?? 0) / 1000000) * pricing.input +
        ((output ?? 0) / 1000000) * pricing.output;
  }

  bool get _hasUnknownPricing {
    final rows = (_aiUsage?['per_user'] as List?) ?? const [];
    for (final item in rows) {
      final row = Map<String, dynamic>.from(item as Map);
      if (_costForRow(row) == null &&
          (row['models']?.toString().trim().isNotEmpty ?? false)) {
        return true;
      }
    }
    return false;
  }

  int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String _formatNumber(dynamic value) {
    final parsed = _readInt(value) ?? 0;
    return parsed.toString();
  }

  String _formatCost(double? value) {
    if (value == null) return '?';
    if (value == 0) return '\$0.00';
    if (value < 0.0001) return '<\$0.0001';
    return '\$${value.toStringAsFixed(4)}';
  }

  String _formatDate(dynamic raw) {
    final value = raw?.toString();
    if (value == null || value.isEmpty) return '—';
    final parsed = DateTime.tryParse(value.replaceFirst(
      RegExp(r'([+-]\d{2}:\d{2})$'),
      'Z',
    ));
    if (parsed == null) return value;
    final local = parsed.toLocal();
    return '${local.month}/${local.day}/${local.year}';
  }

  String _inviteUrl(Map<String, dynamic> result) {
    final raw = result['url']?.toString() ?? '';
    if (raw.startsWith('http')) return raw;
    return '${ApiService.baseUrl}$raw';
  }

  Color _inviteStatusColor(String status) {
    return switch (status) {
      'active' => JournalColors.accent,
      'claimed' => JournalColors.success,
      'expired' => JournalColors.textMuted,
      'revoked' => JournalColors.danger,
      'invalidated' => JournalColors.severity,
      _ => JournalColors.textSecondary,
    };
  }

  Widget _buildBody(Map<String, dynamic>? user) {
    if ((user?['role']?.toString() ?? '') != 'owner') {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Column(
            children: [
              const Spacer(),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: _withAlpha(JournalColors.bgSurface, 0.84),
                            border: Border.all(color: JournalColors.border),
                          ),
                          child: const Icon(
                            CupertinoIcons.lock_fill,
                            color: JournalColors.textSecondary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'Admin access is limited to owner accounts.',
                            style: TextStyle(
                              color: JournalColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'This area manages users, invite links, and backend operations. If you need access, have an owner open this screen.',
                      style: TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return const SliverFillRemaining(
        child: Center(
          child: CupertinoActivityIndicator(color: JournalColors.accent),
        ),
      );
    }

    if (_error != null) {
      return SliverFillRemaining(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.wifi_slash,
                    color: JournalColors.textMuted,
                    size: 26,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AdaptiveButton(
                    style: AdaptiveButtonStyle.prominentGlass,
                    onPressed: () => _load(),
                    label: 'Retry',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          _AdminHero(
            userCount: _users.length,
            inviteCount: _invites.length,
            totalCalls:
                _readInt((_aiUsage?['totals'] as Map?)?['total_calls']) ?? 0,
            isRefreshing: _refreshing,
          ),
          const SizedBox(height: 18),
          _AdminTabBar(
            labels: _kAdminTabs,
            selectedIndex: _tabIndex,
            onSelected: (index) => setState(() => _tabIndex = index),
          ),
          const SizedBox(height: 18),
          _buildTabContent(),
        ]),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tabIndex) {
      case 0:
        return _buildSummaryTab();
      case 1:
        return _buildUsersTab();
      case 2:
        return _buildInvitesTab();
      case 3:
        return _buildDetectionTab();
      case 4:
        return _buildSpendTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSummaryTab() {
    final summary = _masterSummary;
    final content = (summary?['content'] is Map)
        ? Map<String, dynamic>.from(summary!['content'] as Map)
        : const <String, dynamic>{};
    final sections = [
      'overall_arc',
      'current_state',
      'key_themes',
      'key_people',
      'active_threads',
      'notable_patterns',
    ];

    final children = <Widget>[
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Master summary',
              style: TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Reference view for the backend summary payload. This is primarily for inspection rather than daily reading.',
              style: TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
            if (summary?['version'] != null || summary?['last_updated'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (summary?['version'] != null)
                      _MetaPill(
                        label: 'Version ${summary!['version']}',
                        color: JournalColors.accent,
                      ),
                    if (summary?['last_updated'] != null)
                      _MetaPill(
                        label: 'Updated ${summary!['last_updated']}',
                        color: JournalColors.info,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];

    if (summary == null ||
        (summary['message']?.toString().toLowerCase().contains('no master') ??
            false)) {
      children.addAll([
        const SizedBox(height: 14),
        const GlassCard(
          child: Text(
            'No master summary is available yet for this account.',
            style: TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ),
      ]);
      return Column(children: children);
    }

    for (final key in sections) {
      final text = summary[key]?.toString().trim().isNotEmpty == true
          ? summary[key].toString().trim()
          : content[key]?.toString().trim();
      if (text == null || text.isEmpty) continue;

      children.addAll([
        const SizedBox(height: 14),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: key.replaceAll('_', ' ')),
              const SizedBox(height: 10),
              Text(
                text,
                style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 14,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
      ]);
    }

    if (children.length == 1) {
      children.addAll([
        const SizedBox(height: 14),
        GlassCard(
          child: Text(
            summary.toString(),
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ),
      ]);
    }

    return Column(children: children);
  }

  Widget _buildUsersTab() {
    return Column(
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Current users',
                style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Manage account access and clear active sessions when needed.',
                style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 16),
              if (_users.isEmpty)
                const _EmptyStateCopy(message: 'No users found.')
              else
                Column(
                  children: _users.map((user) {
                    final role = user['role']?.toString() ?? 'viewer';
                    final isOwner = role == 'owner';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _AdminUserRow(
                        user: user,
                        isOwner: isOwner,
                        onRevokeSessions: () => _revokeSessions(user),
                        onRemove: isOwner ? null : () => _removeUser(user),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add user',
                style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              _LabeledField(
                label: 'Username',
                child: _AdminTextField(
                  controller: _usernameCtrl,
                  placeholder: 'Username',
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'Email',
                child: _AdminTextField(
                  controller: _emailCtrl,
                  placeholder: 'Email',
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'Password',
                child: _AdminTextField(
                  controller: _passwordCtrl,
                  placeholder: 'Password',
                  obscureText: true,
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'Role',
                child: CupertinoSlidingSegmentedControl<String>(
                  backgroundColor: _withAlpha(JournalColors.bgSurface, 0.92),
                  thumbColor: _withAlpha(JournalColors.accent, 0.32),
                  groupValue: _newUserRole,
                  children: const {
                    'viewer': Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text(
                        'Viewer',
                        style: TextStyle(color: JournalColors.textPrimary),
                      ),
                    ),
                    'owner': Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text(
                        'Owner',
                        style: TextStyle(color: JournalColors.textPrimary),
                      ),
                    ),
                  },
                  onValueChanged: (value) {
                    if (value != null) setState(() => _newUserRole = value);
                  },
                ),
              ),
              if (_addUserError != null) ...[
                const SizedBox(height: 12),
                _InlineNotice(
                  message: _addUserError!,
                  color: JournalColors.danger,
                ),
              ],
              if (_addUserSuccess != null) ...[
                const SizedBox(height: 12),
                _InlineNotice(
                  message: _addUserSuccess!,
                  color: JournalColors.success,
                ),
              ],
              const SizedBox(height: 16),
              AdaptiveButton(
                style: AdaptiveButtonStyle.prominentGlass,
                onPressed: _addingUser ? null : _addUser,
                label: _addingUser ? 'Creating...' : 'Create User',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInvitesTab() {
    return Column(
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Create invite',
                style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Generate a link and passphrase for a single recipient. Keep both pieces together when you share it.',
                style: TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 14),
              _LabeledField(
                label: 'Label',
                child: _AdminTextField(
                  controller: _inviteLabelCtrl,
                  placeholder: 'Optional note for your reference',
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'Expires in',
                child: CupertinoSlidingSegmentedControl<String>(
                  backgroundColor: _withAlpha(JournalColors.bgSurface, 0.92),
                  thumbColor: _withAlpha(JournalColors.accent, 0.32),
                  groupValue: _inviteExpiry,
                  children: const {
                    '24h': Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: Text(
                        '24h',
                        style: TextStyle(color: JournalColors.textPrimary),
                      ),
                    ),
                    '7d': Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: Text(
                        '7d',
                        style: TextStyle(color: JournalColors.textPrimary),
                      ),
                    ),
                    '30d': Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: Text(
                        '30d',
                        style: TextStyle(color: JournalColors.textPrimary),
                      ),
                    ),
                    '90d': Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: Text(
                        '90d',
                        style: TextStyle(color: JournalColors.textPrimary),
                      ),
                    ),
                    'permanent': Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: Text(
                        'Open',
                        style: TextStyle(color: JournalColors.textPrimary),
                      ),
                    ),
                  },
                  onValueChanged: (value) {
                    if (value != null) setState(() => _inviteExpiry = value);
                  },
                ),
              ),
              if (_inviteError != null) ...[
                const SizedBox(height: 12),
                _InlineNotice(
                  message: _inviteError!,
                  color: JournalColors.danger,
                ),
              ],
              const SizedBox(height: 16),
              AdaptiveButton(
                style: AdaptiveButtonStyle.prominentGlass,
                onPressed: _creatingInvite ? null : _createInvite,
                label: _creatingInvite ? 'Generating...' : 'Generate Invite',
              ),
            ],
          ),
        ),
        if (_inviteResult != null) ...[
          const SizedBox(height: 14),
          GlassCard(
            accentBorder: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Invite ready',
                  style: TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The passphrase is only shown now. Share it separately from the link if you want a little more separation.',
                  style: TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 16),
                _CopyField(
                  label: 'Invite URL',
                  value: _inviteUrl(_inviteResult!),
                  copied: _inviteCopyKey == 'url',
                  onCopy: () => _copyInviteValue(
                    'url',
                    _inviteUrl(_inviteResult!),
                  ),
                ),
                const SizedBox(height: 12),
                _CopyField(
                  label: 'Passphrase',
                  value: _inviteResult!['passphrase']?.toString() ?? '',
                  copied: _inviteCopyKey == 'passphrase',
                  onCopy: () => _copyInviteValue(
                    'passphrase',
                    _inviteResult!['passphrase']?.toString() ?? '',
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Invite history',
                style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              if (_invites.isEmpty)
                const _EmptyStateCopy(
                  message: 'No invites yet. Generate one above to get started.',
                )
              else
                Column(
                  children: _invites.map((invite) {
                    final status = invite['status']?.toString() ?? 'unknown';
                    final color = _inviteStatusColor(status);
                    final canRevoke = !const [
                      'revoked',
                      'invalidated',
                      'expired',
                    ].contains(status);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _InviteRow(
                        invite: invite,
                        color: color,
                        onRevoke:
                            canRevoke ? () => _revokeInvite(invite) : null,
                        formatDate: _formatDate,
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetectionTab() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pattern detection',
            style: TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Runs the rule-based detectors for mood spikes, severity streaks, instability clusters, and contradiction flagging. Use this when you want a fresh backend pass.',
            style: TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          AdaptiveButton(
            style: AdaptiveButtonStyle.prominentGlass,
            onPressed: _runningDetection ? null : _runDetectors,
            label: _runningDetection ? 'Running...' : 'Run All Detectors',
          ),
        ],
      ),
    );
  }

  Widget _buildSpendTab() {
    final totals = (_aiUsage?['totals'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), value),
        ) ??
        const <String, dynamic>{};
    final byFeature = ((_aiUsage?['by_feature'] as List?) ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final perUser = ((_aiUsage?['per_user'] as List?) ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    final totalTokens = _readInt(totals['total_tokens']) ?? 0;
    final knownCostRows = perUser
        .map(_costForRow)
        .whereType<double>()
        .fold<double>(0, (sum, value) => sum + value);
    final allCostsKnown =
        perUser.isNotEmpty && perUser.every((row) => _costForRow(row) != null);

    return Column(
      children: [
        if (_hasUnknownPricing)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: _InlineNotice(
              message:
                  'Some models have unknown pricing, so estimated cost is partial.',
              color: JournalColors.severity,
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SpendStatCard(
              label: 'Est. total cost',
              value: allCostsKnown ? _formatCost(knownCostRows) : '?',
              color: JournalColors.accent,
            ),
            _SpendStatCard(
              label: 'Total tokens',
              value: _formatNumber(totals['total_tokens']),
              color: JournalColors.info,
            ),
            _SpendStatCard(
              label: 'Input tokens',
              value: _formatNumber(totals['total_input']),
              color: JournalColors.success,
            ),
            _SpendStatCard(
              label: 'Output tokens',
              value: _formatNumber(totals['total_output']),
              color: JournalColors.accent2,
            ),
            _SpendStatCard(
              label: 'Total calls',
              value: _formatNumber(totals['total_calls']),
              color: JournalColors.severity,
            ),
          ],
        ),
        const SizedBox(height: 14),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'By feature',
                style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              if (byFeature.isEmpty)
                const _EmptyStateCopy(
                  message: 'No AI usage has been logged yet.',
                )
              else
                Column(
                  children: byFeature.map((row) {
                    final feature = row['feature']?.toString() ?? 'unknown';
                    final tokens = _readInt(row['total_tokens']) ?? 0;
                    final calls = _readInt(row['total_calls']) ?? 0;
                    final pct = totalTokens > 0
                        ? ((tokens / totalTokens) * 100).round()
                        : 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _FeatureUsageRow(
                        label: _kFeatureLabels[feature] ?? feature,
                        tokens: tokens,
                        calls: calls,
                        percent: pct,
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Per user',
                style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              if (perUser.isEmpty)
                const _EmptyStateCopy(
                  message:
                      'Per-user usage will appear after the first AI call.',
                )
              else
                Column(
                  children: perUser.map((row) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SpendUserRow(
                        row: row,
                        cost: _costForRow(row),
                        formatCost: _formatCost,
                        formatDate: _formatDate,
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: Stack(
        children: [
          const Positioned.fill(child: _AdminBackdrop()),
          CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('Admin'),
                backgroundColor: _withAlpha(JournalColors.bgBase, 0.9),
                border: const Border(
                  bottom: BorderSide(color: JournalColors.border, width: 0.5),
                ),
                trailing: GestureDetector(
                  onTap: _refreshing ? null : () => _load(refreshing: true),
                  child: Text(
                    _refreshing ? 'Syncing' : 'Refresh',
                    style: TextStyle(
                      color: _refreshing
                          ? JournalColors.textMuted
                          : JournalColors.accent,
                    ),
                  ),
                ),
              ),
              _buildBody(user),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminBackdrop extends StatelessWidget {
  const _AdminBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            JournalColors.bgBase,
            JournalColors.bgBase,
            JournalColors.bgSurface,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            left: -40,
            child: _AmbientGlow(
              size: 220,
              color: _withAlpha(JournalColors.accent, 0.18),
            ),
          ),
          Positioned(
            top: 140,
            right: -30,
            child: _AmbientGlow(
              size: 180,
              color: _withAlpha(JournalColors.info, 0.1),
            ),
          ),
          Positioned(
            bottom: 120,
            left: 30,
            child: _AmbientGlow(
              size: 160,
              color: _withAlpha(JournalColors.success, 0.08),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: size * 0.45,
              spreadRadius: size * 0.12,
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminHero extends StatelessWidget {
  const _AdminHero({
    required this.userCount,
    required this.inviteCount,
    required this.totalCalls,
    required this.isRefreshing,
  });

  final int userCount;
  final int inviteCount;
  final int totalCalls;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accentBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _withAlpha(JournalColors.accent, 0.26),
                      _withAlpha(JournalColors.info, 0.16),
                    ],
                  ),
                  border: Border.all(color: JournalColors.borderBright),
                ),
                child: const Icon(
                  CupertinoIcons.person_3_fill,
                  color: JournalColors.textPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System administration',
                      style: TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Users, invite access, detection controls, and AI usage.',
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
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroMetric(value: '$userCount', label: 'Users'),
              _HeroMetric(value: '$inviteCount', label: 'Invites'),
              _HeroMetric(value: '$totalCalls', label: 'AI Calls'),
              _HeroMetric(
                value: isRefreshing ? 'Syncing' : 'Live',
                label: 'Status',
                accent:
                    isRefreshing ? JournalColors.info : JournalColors.success,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminTabBar extends StatelessWidget {
  const _AdminTabBar({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? labels.length : 3;
        const gap = 8.0;
        final totalGap = gap * (columns - 1);
        final itemWidth = (constraints.maxWidth - 16 - totalGap) / columns;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _withAlpha(JournalColors.bgCardAlt, 0.96),
                _withAlpha(JournalColors.bgSurface, 0.9),
              ],
            ),
            border: Border.all(color: JournalColors.border),
            boxShadow: const [
              BoxShadow(
                color: JournalColors.accentGlow,
                blurRadius: 12,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: List.generate(labels.length, (index) {
              final isSelected = index == selectedIndex;
              return SizedBox(
                width: itemWidth,
                child: _AdminTabChip(
                  label: labels[index],
                  isSelected: isSelected,
                  onTap: () => onSelected(index),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.value,
    required this.label,
    this.accent = JournalColors.accent,
  });

  final String value;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _withAlpha(JournalColors.bgSurface, 0.82),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTabChip extends StatelessWidget {
  const _AdminTabChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: isSelected
              ? JournalColors.textPrimary
              : _withAlpha(JournalColors.bgBase, 0.42),
          border: Border.all(
            color: isSelected
                ? _withAlpha(JournalColors.textPrimary, 0.9)
                : _withAlpha(JournalColors.borderBright, 0.45),
          ),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: JournalColors.accentGlow,
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color:
                isSelected ? JournalColors.bgBase : JournalColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: _withAlpha(color, 0.12),
        border: Border.all(color: _withAlpha(color, 0.32)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

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
        child,
      ],
    );
  }
}

class _AdminTextField extends StatelessWidget {
  const _AdminTextField({
    required this.controller,
    required this.placeholder,
    this.keyboardType,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String placeholder;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      placeholder: placeholder,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      style: const TextStyle(
        color: JournalColors.textPrimary,
        fontSize: 15,
      ),
      placeholderStyle: const TextStyle(
        color: JournalColors.textMuted,
        fontSize: 15,
      ),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JournalColors.border),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.message,
    required this.color,
  });

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _withAlpha(color, 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _withAlpha(color, 0.3)),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: color,
          fontSize: 13,
          height: 1.45,
        ),
      ),
    );
  }
}

class _EmptyStateCopy extends StatelessWidget {
  const _EmptyStateCopy({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.84),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JournalColors.border),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: JournalColors.textSecondary,
          fontSize: 14,
          height: 1.55,
        ),
      ),
    );
  }
}

class _AdminUserRow extends StatelessWidget {
  const _AdminUserRow({
    required this.user,
    required this.isOwner,
    required this.onRevokeSessions,
    required this.onRemove,
  });

  final Map<String, dynamic> user;
  final bool isOwner;
  final VoidCallback onRevokeSessions;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final username = user['username']?.toString() ?? 'User';
    final email = user['email']?.toString() ?? '—';
    final role = user['role']?.toString() ?? 'viewer';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _withAlpha(JournalColors.bgSurface, 0.82),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _withAlpha(
                    isOwner ? JournalColors.accent : JournalColors.bgCardAlt,
                    isOwner ? 0.22 : 0.94,
                  ),
                  border: Border.all(
                    color: isOwner
                        ? JournalColors.borderBright
                        : JournalColors.border,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  username.isNotEmpty ? username[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _MetaPill(
                label: role,
                color: isOwner ? JournalColors.accent : JournalColors.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionChip(
                label: 'Revoke Sessions',
                color: JournalColors.severity,
                onTap: onRevokeSessions,
              ),
              if (onRemove != null)
                _ActionChip(
                  label: 'Remove User',
                  color: JournalColors.danger,
                  onTap: onRemove!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({
    required this.invite,
    required this.color,
    required this.onRevoke,
    required this.formatDate,
  });

  final Map<String, dynamic> invite;
  final Color color;
  final VoidCallback? onRevoke;
  final String Function(dynamic) formatDate;

  @override
  Widget build(BuildContext context) {
    final label = invite['label']?.toString();
    final status = invite['status']?.toString() ?? 'unknown';
    final claimedIp = invite['claimed_ip']?.toString();
    final invalidReason = invite['invalidated_reason']?.toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _withAlpha(JournalColors.bgSurface, 0.82),
        border: Border.all(color: JournalColors.border),
      ),
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
                      (label == null || label.trim().isEmpty)
                          ? 'No label'
                          : label,
                      style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Created ${formatDate(invite['created_at'])} · Expires ${formatDate(invite['expires_at'])}${claimedIp != null && claimedIp.isNotEmpty ? ' · Claimed by $claimedIp' : ''}',
                      style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    if (invalidReason != null && invalidReason.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          invalidReason,
                          style: const TextStyle(
                            color: JournalColors.severity,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _MetaPill(label: status, color: color),
            ],
          ),
          if (onRevoke != null) ...[
            const SizedBox(height: 12),
            _ActionChip(
              label: 'Revoke Invite',
              color: JournalColors.danger,
              onTap: onRevoke!,
            ),
          ],
        ],
      ),
    );
  }
}

class _CopyField extends StatelessWidget {
  const _CopyField({
    required this.label,
    required this.value,
    required this.copied,
    required this.onCopy,
  });

  final String label;
  final String value;
  final bool copied;
  final VoidCallback onCopy;

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
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _withAlpha(JournalColors.bgSurface, 0.9),
            border: Border.all(color: JournalColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _ActionChip(
                label: copied ? 'Copied' : 'Copy',
                color: copied ? JournalColors.success : JournalColors.accent,
                onTap: onCopy,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: _withAlpha(color, 0.12),
          border: Border.all(color: _withAlpha(color, 0.28)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SpendStatCard extends StatelessWidget {
  const _SpendStatCard({
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
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _withAlpha(JournalColors.bgCard, 0.94),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: JournalColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureUsageRow extends StatelessWidget {
  const _FeatureUsageRow({
    required this.label,
    required this.tokens,
    required this.calls,
    required this.percent,
  });

  final String label;
  final int tokens;
  final int calls;
  final int percent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$tokens tok · $calls calls · $percent%',
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 6,
            color: JournalColors.border,
            child: FractionallySizedBox(
              widthFactor: (percent / 100).clamp(0, 1),
              alignment: Alignment.centerLeft,
              child: Container(color: JournalColors.accent),
            ),
          ),
        ),
      ],
    );
  }
}

class _SpendUserRow extends StatelessWidget {
  const _SpendUserRow({
    required this.row,
    required this.cost,
    required this.formatCost,
    required this.formatDate,
  });

  final Map<String, dynamic> row;
  final double? cost;
  final String Function(double?) formatCost;
  final String Function(dynamic) formatDate;

  @override
  Widget build(BuildContext context) {
    final username = row['username']?.toString() ?? 'Deleted user';
    final models = row['models']?.toString() ?? '—';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _withAlpha(JournalColors.bgSurface, 0.82),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  username,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                formatCost(cost),
                style: const TextStyle(
                  color: JournalColors.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaPill(
                label: '${row['total_tokens'] ?? 0} tokens',
                color: JournalColors.info,
              ),
              _MetaPill(
                label: '${row['total_calls'] ?? 0} calls',
                color: JournalColors.success,
              ),
              _MetaPill(
                label: 'Input ${row['total_input'] ?? 0}',
                color: JournalColors.textSecondary,
              ),
              _MetaPill(
                label: 'Output ${row['total_output'] ?? 0}',
                color: JournalColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Model: $models · Last call ${formatDate(row['last_call'])}',
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
