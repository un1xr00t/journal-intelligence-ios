// lib/screens/settings_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:share_plus/share_plus.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import '../providers/app_shell_mode_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/user_settings_sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'notification_nudges_screen.dart';
import 'pin_unlock_screen.dart';
import 'resources_screen.dart';
import 'sage_settings_screen.dart';

// ── Option constants ──────────────────────────────────────────────────────────

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

typedef _StrOpt = ({String id, String label});

const _kSituations = <_StrOpt>[
  (id: 'relationship', label: 'Relationship'),
  (id: 'custody', label: 'Custody/Parenting'),
  (id: 'workplace', label: 'Workplace'),
  (id: 'housing', label: 'Housing'),
  (id: 'legal', label: 'Legal Matter'),
  (id: 'mental_health', label: 'Mental Health'),
  (id: 'growth', label: 'Personal Growth'),
  (id: 'other', label: 'Something Else'),
];

const _kTopics = <String>[
  'Anxiety',
  'Sleep',
  'Health',
  'Work',
  'Relationships',
  'Family',
  'Money',
  'Safety',
  'Legal',
  'Housing',
  'Trauma',
  'Boundaries',
  'Self-worth',
  'Healing',
  'Documentation',
  'Growth',
  'Addiction',
  'Children',
  'Isolation',
  'Identity',
];

const _kGoals = <_StrOpt>[
  (id: 'document', label: 'Document my experience'),
  (id: 'patterns', label: "Find patterns I'm missing"),
  (id: 'case_file', label: 'Build a case file'),
  (id: 'mental', label: 'Track my mental health'),
  (id: 'exit', label: 'Plan a major life change'),
  (id: 'process', label: 'Process my feelings'),
  (id: 'evidence', label: 'Gather legal evidence'),
  (id: 'heal', label: 'Grow and heal'),
];

const _kPronounOpts = <String>[
  'she/her',
  'he/him',
  'they/them',
  'prefer not to say'
];

typedef _ToneOpt = ({String id, String label, String desc});

const _kTones = <_ToneOpt>[
  (
    id: 'therapist',
    label: 'Therapist',
    desc: 'Clinical, reflective, structured'
  ),
  (id: 'best_friend', label: 'Best Friend', desc: 'Warm, casual, validating'),
  (id: 'coach', label: 'Coach', desc: 'Goal-focused, motivational'),
  (id: 'mentor', label: 'Mentor', desc: 'Wise, long-view perspective'),
  (
    id: 'inner_critic',
    label: 'Inner Critic',
    desc: 'Challenging, honest, unfiltered'
  ),
  (
    id: 'chaos_agent',
    label: 'Chaos Agent',
    desc: 'Unconventional, pattern-breaking'
  ),
];

typedef _ProviderOpt = ({String id, String label, String desc, bool needsUrl});

const _kProviders = <_ProviderOpt>[
  (
    id: 'anthropic',
    label: 'Anthropic Claude',
    desc: 'Sonnet / Opus / Haiku',
    needsUrl: false
  ),
  (
    id: 'openai',
    label: 'OpenAI',
    desc: 'GPT-4o, GPT-4o-mini…',
    needsUrl: false
  ),
  (
    id: 'openai_compat',
    label: 'OpenAI-compatible',
    desc: 'OpenRouter, Groq…',
    needsUrl: true
  ),
  (
    id: 'local',
    label: 'Local Model',
    desc: 'Ollama, LM Studio…',
    needsUrl: true
  ),
];

// ── Main Screen ───────────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();
  final _api = ApiService();
  final _settingsSync = UserSettingsSyncService();
  AuthProvider? _authProvider;

  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _autoReflect = true;
  bool _reflectLoaded = false;

  bool _hasRecoveryQuestions = false;
  bool _twoFAEnabled = false;
  bool _securityLoaded = false;
  bool _journalExporting = false;
  String? _journalExportStatus;
  bool _journalExportError = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricStatus();
    _loadReflectMode();
    _loadSecurityStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authProvider = context.read<AuthProvider>();
    if (_authProvider == authProvider) return;
    _authProvider?.removeListener(_handleAuthProviderChanged);
    _authProvider = authProvider;
    _authProvider!.addListener(_handleAuthProviderChanged);
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_handleAuthProviderChanged);
    super.dispose();
  }

  void _handleAuthProviderChanged() {
    if (!mounted || _authProvider?.isAuthenticated != true) return;
    _loadReflectMode();
  }

  Future<void> _checkBiometricStatus() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      final storedUser = await _storage.read(key: 'biometric_username');
      if (mounted)
        setState(() {
          _biometricAvailable = canCheck && isSupported;
          _biometricEnabled = storedUser != null;
        });
    } catch (_) {}
  }

  Future<void> _loadSecurityStatus() async {
    try {
      final results = await Future.wait([
        _api.hasSecurityQuestions(),
        _api.get2FAStatus(),
      ]);
      if (mounted)
        setState(() {
          _hasRecoveryQuestions = results[0] as bool;
          _twoFAEnabled =
              ((results[1] as Map<String, dynamic>)['enabled'] as bool?) ??
                  false;
          _securityLoaded = true;
        });
    } catch (_) {
      if (mounted) setState(() => _securityLoaded = true);
    }
  }

  Future<void> _loadReflectMode() async {
    try {
      final autoReflect = await _settingsSync.loadCachedAutoReflect();
      if (mounted)
        setState(() {
          _autoReflect = autoReflect;
          _reflectLoaded = true;
        });
    } catch (_) {
      if (mounted) setState(() => _reflectLoaded = true);
    }
  }

  Future<void> _toggleReflectMode(bool val) async {
    setState(() => _autoReflect = val);
    try {
      await _settingsSync.saveAutoReflect(val);
    } catch (_) {
      if (mounted) setState(() => _autoReflect = !val);
    }
  }

  Future<void> _enableBiometrics(BuildContext context, String username) async {
    final passwordCtrl = TextEditingController();
    final password = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Enable Face ID'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          const Text('Enter your password to save for Face ID sign-in.',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          CupertinoTextField(
            controller: passwordCtrl,
            placeholder: 'Password',
            obscureText: true,
            autofocus: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: JournalColors.border),
            ),
            style: const TextStyle(color: JournalColors.textPrimary),
            placeholderStyle: const TextStyle(color: JournalColors.textMuted),
          ),
        ]),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel')),
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, passwordCtrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    passwordCtrl.dispose();
    if (password == null || password.isEmpty) return;
    try {
      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Confirm to enable Face ID sign-in',
        options: const AuthenticationOptions(biometricOnly: false),
      );
      if (!didAuth) return;
      await _storage.write(key: 'biometric_username', value: username);
      await _storage.write(key: 'biometric_password', value: password);
      if (mounted) setState(() => _biometricEnabled = true);
    } catch (_) {}
  }

  Future<void> _disableBiometrics() async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Disable Face ID?'),
        content:
            const Text('You\'ll need to sign in with your password next time.'),
        actions: [
          CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Disable')),
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
        ],
      ),
    );
    if (confirm == true) {
      await _storage.delete(key: 'biometric_username');
      await _storage.delete(key: 'biometric_password');
      if (mounted) setState(() => _biometricEnabled = false);
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign Out')),
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  Future<T?> _push<T>(Widget screen) {
    return Navigator.of(context, rootNavigator: true).push<T>(
      CupertinoPageRoute(
        builder: (_) => DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: screen,
        ),
      ),
    );
  }

  Future<void> _toggleQuietJournalMode(bool enabled) async {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator.canPop()) {
      rootNavigator.popUntil((route) => route.isFirst);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (!mounted) return;
    await context.read<AppShellModeProvider>().setQuietJournal(enabled);
  }

  Future<void> _manageJournalPin() async {
    final appLock = context.read<AppLockProvider>();
    if (!appLock.canManagePin) return;

    if (!appLock.pinEnabled) {
      final pin = await _push<String>(const PinUnlockScreen.create());
      if (pin == null || !mounted) return;
      await appLock.setPin(pin);
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Journal PIN Enabled'),
          content: const Text(
            'This device will now ask for your 4-digit PIN before reopening a restored journal session.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Journal PIN'),
        message: const Text(
          'Change the local unlock PIN for this device or turn it off entirely.',
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'change'),
            child: const Text('Change PIN'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, 'disable'),
            child: const Text('Disable PIN'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: const Text('Cancel'),
        ),
      ),
    );

    if (!mounted || action == null || action == 'cancel') return;

    if (action == 'change') {
      final pin = await _push<String>(const PinUnlockScreen.create());
      if (pin == null || !mounted) return;
      await appLock.setPin(pin);
      return;
    }

    if (action == 'disable') {
      final confirm = await showCupertinoDialog<bool>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Disable Journal PIN?'),
          content: const Text(
            'Restored sessions on this device will open directly again without the local unlock screen.',
          ),
          actions: [
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Disable'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await appLock.disablePin();
      }
    }
  }

  Future<void> _confirmJournalExport() async {
    if (_journalExporting) return;
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Export Full Journal CSV'),
        content: const Text(
          'This creates a CSV backup of every journal entry with dates, timestamps, text, and entry metadata, then opens the share sheet so you can save it anywhere.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Export'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _exportJournalBackup();
    }
  }

  Future<void> _exportJournalBackup() async {
    setState(() {
      _journalExporting = true;
      _journalExportStatus = 'Preparing your full journal backup…';
      _journalExportError = false;
    });

    try {
      final entries = await _api.getAllEntriesForExport(pageSize: 100);
      if (entries.isEmpty) {
        if (!mounted) return;
        setState(() {
          _journalExportStatus = 'No journal entries to export yet.';
          _journalExportError = false;
        });
        return;
      }

      entries.sort(_compareEntriesForExport);
      final csv = _buildJournalCsv(entries);
      final dir = await Directory.systemTemp.createTemp('journal_backup_');
      final timestamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${dir.path}/journal_backup_$timestamp.csv');
      await file.writeAsString(csv, flush: true);

      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Journal backup CSV',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );

      if (!mounted) return;
      setState(() {
        _journalExportStatus =
            'CSV ready. Use the share sheet to save or send your full journal backup.';
        _journalExportError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _journalExportStatus = _parseError(e);
        _journalExportError = true;
      });
    } finally {
      if (mounted) {
        setState(() => _journalExporting = false);
      }
    }
  }

  int _compareEntriesForExport(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final aPrimary = _entrySortValue(a);
    final bPrimary = _entrySortValue(b);
    final primaryCompare = aPrimary.compareTo(bPrimary);
    if (primaryCompare != 0) return primaryCompare;

    final aId = (a['id'] as num?)?.toInt() ?? 0;
    final bId = (b['id'] as num?)?.toInt() ?? 0;
    return aId.compareTo(bId);
  }

  String _entrySortValue(Map<String, dynamic> entry) {
    final entryDate = entry['entry_date']?.toString().trim() ?? '';
    if (entryDate.isNotEmpty) return entryDate;
    return entry['ingested_at']?.toString().trim() ?? '';
  }

  String _buildJournalCsv(List<Map<String, dynamic>> entries) {
    const headers = <String>[
      'id',
      'user_id',
      'entry_date',
      'ingested_at',
      'source',
      'is_current',
      'word_count',
      'mood_score',
      'severity_score',
      'summary_text',
      'text',
      'normalized_text',
    ];

    final buffer = StringBuffer();
    buffer.writeln(headers.map(_csvCell).join(','));
    for (final entry in entries) {
      final row = <String>[
        _stringValue(entry['id']),
        _stringValue(entry['user_id']),
        _stringValue(entry['entry_date']),
        _stringValue(entry['ingested_at']),
        _stringValue(entry['source']),
        _stringValue(entry['is_current']),
        _stringValue(entry['word_count']),
        _stringValue(entry['mood_score']),
        _stringValue(entry['severity_score']),
        _stringValue(entry['summary_text']),
        _stringValue(entry['text']),
        _stringValue(entry['normalized_text']),
      ];
      buffer.writeln(row.map(_csvCell).join(','));
    }
    return buffer.toString();
  }

  String _stringValue(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  String _csvCell(String value) {
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final escaped = normalized.replaceAll('"', '""');
    return '"$escaped"';
  }

  String _parseError(dynamic e) {
    final str = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    return match?.group(1) ?? 'Something went wrong.';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final appLock = context.watch<AppLockProvider>();
    final shellMode = context.watch<AppShellModeProvider>();
    final user = auth.user;

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: Stack(
        children: [
          const Positioned.fill(child: _SettingsBackdrop()),
          CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('Settings'),
                backgroundColor: _withAlpha(JournalColors.bgBase, 0.9),
                border: const Border(
                  bottom: BorderSide(color: JournalColors.border, width: 0.5),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _SettingsHero(
                      username: user?['username'] as String?,
                      email: user?['email'] as String?,
                      biometricAvailable: _biometricAvailable,
                      biometricEnabled: _biometricEnabled,
                      pinEnabled: appLock.pinEnabled,
                      reflectLoaded: _reflectLoaded,
                      autoReflect: _autoReflect,
                      securityLoaded: _securityLoaded,
                      twoFAEnabled: _twoFAEnabled,
                    ),
                    const SizedBox(height: 22),
                    const _SectionLabel(
                      'Account',
                      subtitle: 'Profile details and sign-in tools.',
                    ),
                    const SizedBox(height: 10),
                    _SettingsSectionCard(
                      accentColor: JournalColors.accent,
                      children: [
                        _SettingsActionRow(
                          icon: CupertinoIcons.person_crop_circle_fill,
                          iconColor: JournalColors.accent,
                          label: 'Memory Profile',
                          subtitle: 'Name, situation, topics, and goals.',
                          onTap: () => _push(const _MemoryProfileScreen()),
                        ),
                        const _SectionDivider(),
                        _SettingsActionRow(
                          icon: CupertinoIcons.lock_fill,
                          iconColor: JournalColors.info,
                          label: 'Change Password',
                          subtitle: 'Update your password.',
                          onTap: () => _push(const _ChangePasswordScreen()),
                        ),
                        const _SectionDivider(),
                        _SettingsActionRow(
                          icon: CupertinoIcons.link,
                          iconColor: JournalColors.accent2,
                          label: 'API Key',
                          subtitle: 'For iPhone Shortcut uploads.',
                          onTap: () => _push(const _ApiKeyScreen()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const _SectionLabel(
                      'AI',
                      subtitle: 'Provider, tone, and assistant behavior.',
                    ),
                    const SizedBox(height: 10),
                    _SettingsSectionCard(
                      accentColor: JournalColors.accent2,
                      children: [
                        _SettingsActionRow(
                          icon: CupertinoIcons.command,
                          iconColor: JournalColors.accent2,
                          label: 'AI Provider',
                          subtitle: 'Anthropic, OpenAI, or local model.',
                          onTap: () => _push(const _AIProviderScreen()),
                        ),
                        const _SectionDivider(),
                        _SettingsActionRow(
                          icon: CupertinoIcons.chat_bubble_fill,
                          iconColor: JournalColors.info,
                          label: 'Reflection Tone',
                          subtitle: 'Voice used for insights and summaries.',
                          onTap: () => _push(const _ToneScreen()),
                        ),
                        const _SectionDivider(),
                        _SettingsActionRow(
                          icon: CupertinoIcons.sparkles,
                          iconColor: JournalColors.accent,
                          label: 'Sage Settings',
                          subtitle: 'Voice, memory, playback, and personality.',
                          onTap: () => _push(const SageSettingsScreen()),
                        ),
                        if (_reflectLoaded) ...[
                          const _SectionDivider(),
                          _SettingsSwitchRow(
                            icon: CupertinoIcons.bolt_fill,
                            iconColor: JournalColors.severity,
                            label: 'Auto-Reflect',
                            subtitle:
                                'Generate reflections automatically after new entries.',
                            value: _autoReflect,
                            onChanged: _toggleReflectMode,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 22),
                    const _SectionLabel(
                      'Authentication',
                      subtitle:
                          'Sign-in recovery, device sessions, and local unlock.',
                    ),
                    const SizedBox(height: 10),
                    _SettingsSectionCard(
                      accentColor: JournalColors.info,
                      children: [
                        _SettingsActionRow(
                          icon: CupertinoIcons.lock_shield_fill,
                          iconColor: JournalColors.accent2,
                          label: 'Journal PIN',
                          subtitle: appLock.pinEnabled
                              ? 'Require a 4-digit PIN before this device can reopen your persistent journal session.'
                              : 'Add a 4-digit PIN so restored sessions on this device stop opening straight into the journal.',
                          trailing: _StatusBadge(
                            label: appLock.pinEnabled ? 'Enabled' : 'Off',
                            color: appLock.pinEnabled
                                ? JournalColors.success
                                : JournalColors.textMuted,
                          ),
                          onTap: _manageJournalPin,
                        ),
                        const _SectionDivider(),
                        if (_biometricAvailable) ...[
                          _SettingsActionRow(
                            icon: CupertinoIcons.person_crop_circle,
                            iconColor: JournalColors.info,
                            label: 'Face ID',
                            subtitle: _biometricEnabled
                                ? 'Enabled for faster sign-in.'
                                : 'Save credentials after sign-in to enable it.',
                            trailing: _InlineActionButton(
                              label: _biometricEnabled ? 'Disable' : 'Enable',
                              color: _biometricEnabled
                                  ? JournalColors.danger
                                  : JournalColors.accent,
                              onTap: _biometricEnabled
                                  ? _disableBiometrics
                                  : () => _enableBiometrics(
                                        context,
                                        user?['username'] as String? ?? '',
                                      ),
                            ),
                          ),
                          const _SectionDivider(),
                        ],
                        _SettingsActionRow(
                          icon: CupertinoIcons.device_laptop,
                          iconColor: JournalColors.accent,
                          label: 'Active Sessions',
                          subtitle: 'Devices with an active login.',
                          onTap: () => _push(const _SessionsScreen()),
                        ),
                        if (_securityLoaded) ...[
                          const _SectionDivider(),
                          _SettingsActionRow(
                            icon: CupertinoIcons.question_circle_fill,
                            iconColor: JournalColors.severity,
                            label: 'Recovery Questions',
                            subtitle:
                                'Reset your password without email access.',
                            trailing: _StatusBadge(
                              label:
                                  _hasRecoveryQuestions ? 'Set up' : 'Not set',
                              color: _hasRecoveryQuestions
                                  ? JournalColors.success
                                  : JournalColors.severity,
                            ),
                            onTap: () async {
                              await _push(
                                _RecoveryQuestionsScreen(
                                  hasExisting: _hasRecoveryQuestions,
                                ),
                              );
                              _loadSecurityStatus();
                            },
                          ),
                          const _SectionDivider(),
                          _SettingsActionRow(
                            icon: CupertinoIcons.shield_lefthalf_fill,
                            iconColor: JournalColors.success,
                            label: 'Two-Factor Authentication',
                            subtitle:
                                'Google Authenticator, Authy, or any TOTP app.',
                            trailing: _StatusBadge(
                              label: _twoFAEnabled ? 'Enabled' : 'Disabled',
                              color: _twoFAEnabled
                                  ? JournalColors.success
                                  : JournalColors.textMuted,
                            ),
                            onTap: () async {
                              await _push(_TwoFAScreen(enabled: _twoFAEnabled));
                              _loadSecurityStatus();
                            },
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 22),
                    const _SectionLabel(
                      'Journal',
                      subtitle: 'Entry capture and support access.',
                    ),
                    const SizedBox(height: 10),
                    _SettingsSectionCard(
                      accentColor: JournalColors.orange,
                      children: [
                        _SettingsSwitchRow(
                          icon: CupertinoIcons.book_circle_fill,
                          iconColor: JournalColors.severity,
                          label: 'Quiet Journal',
                          subtitle: shellMode.isQuietJournal
                              ? 'Return to the full intelligence workspace with Sage, analysis, and the current advanced shell.'
                              : 'Switch into a calmer, memory-first journal shell with a minimal writing flow and photo-friendly entries.',
                          value: shellMode.isQuietJournal,
                          onChanged: _toggleQuietJournalMode,
                        ),
                        const _SectionDivider(),
                        _SettingsActionRow(
                          icon: CupertinoIcons.bell_fill,
                          iconColor: JournalColors.accent,
                          label: 'Notification Nudges',
                          subtitle:
                              'Location prompts, Wyatt reminders, and local lock-screen nudges.',
                          onTap: () => _push(const NotificationNudgesScreen()),
                        ),
                        const _SectionDivider(),
                        _SettingsActionRow(
                          icon: CupertinoIcons.chat_bubble_2_fill,
                          iconColor: JournalColors.orange,
                          label: 'Text Journal',
                          subtitle: 'Journal via SMS from your phone.',
                          onTap: () => _push(const _SmsScreen()),
                        ),
                        const _SectionDivider(),
                        _SettingsActionRow(
                          icon: CupertinoIcons.square_arrow_up_fill,
                          iconColor: JournalColors.success,
                          label: 'Backup Your Journal',
                          subtitle: _journalExportStatus ??
                              'Export every raw entry into a neatly organized CSV backup.',
                          trailing: _journalExporting
                              ? const CupertinoActivityIndicator(
                                  color: JournalColors.accent,
                                )
                              : _journalExportStatus == null
                                  ? const Icon(
                                      CupertinoIcons.chevron_right,
                                      color: JournalColors.textMuted,
                                      size: 14,
                                    )
                                  : _StatusBadge(
                                      label: _journalExportError
                                          ? 'Error'
                                          : 'Ready',
                                      color: _journalExportError
                                          ? JournalColors.danger
                                          : JournalColors.success,
                                    ),
                          onTap: _confirmJournalExport,
                        ),
                        const _SectionDivider(),
                        _SettingsActionRow(
                          icon: CupertinoIcons.heart_fill,
                          iconColor: JournalColors.danger,
                          label: 'Resources',
                          subtitle: 'Personalized support tools and services.',
                          onTap: () => _push(const ResourcesScreen()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const _SectionLabel(
                      'App',
                      subtitle: 'System details and session controls.',
                    ),
                    const SizedBox(height: 10),
                    const _SettingsSectionCard(
                      accentColor: JournalColors.textSecondary,
                      children: [
                        _SettingsInfoRow(
                          icon: CupertinoIcons.globe,
                          iconColor: JournalColors.info,
                          label: 'Server',
                          value: 'journal.williamthomas.name',
                        ),
                        _SectionDivider(),
                        _SettingsInfoRow(
                          icon: CupertinoIcons.lock_shield_fill,
                          iconColor: JournalColors.accent,
                          label: 'Auth',
                          value: 'JWT + Secure Cookie',
                        ),
                        _SectionDivider(),
                        _SettingsInfoRow(
                          icon: CupertinoIcons.app_badge,
                          iconColor: JournalColors.textSecondary,
                          label: 'Version',
                          value: '1.0.0',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    AdaptiveButton(
                      style: AdaptiveButtonStyle.prominentGlass,
                      onPressed: () => _confirmLogout(context),
                      label: 'Sign Out',
                    ),
                    const SizedBox(height: 10),
                    const Center(
                      child: Text(
                        'Journal Intelligence · iOS App',
                        style: TextStyle(
                          color: JournalColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
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

// ── Memory Profile Screen ─────────────────────────────────────────────────────

class _MemoryProfileScreen extends StatefulWidget {
  const _MemoryProfileScreen();

  @override
  State<_MemoryProfileScreen> createState() => _MemoryProfileScreenState();
}

class _MemoryProfileScreenState extends State<_MemoryProfileScreen> {
  final _api = ApiService();

  Map<String, dynamic>? _form;
  bool _saving = false;
  bool _saved = false;
  String _error = '';

  final _prefNameCtrl = TextEditingController();
  final _storyCtrl = TextEditingController();
  final _addNameCtrl = TextEditingController();
  final _addRoleCtrl = TextEditingController();
  final _customTopicCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _prefNameCtrl.dispose();
    _storyCtrl.dispose();
    _addNameCtrl.dispose();
    _addRoleCtrl.dispose();
    _customTopicCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _api.getMemory();
      final m = Map<String, dynamic>.from(
          (data['memory'] ?? data) as Map<String, dynamic>);
      if (mounted) {
        _prefNameCtrl.text = m['preferred_name'] as String? ?? '';
        _storyCtrl.text = m['situation_story'] as String? ?? '';
        setState(() => _form = m);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to load memory profile');
    }
  }

  void _updField(String key, dynamic val) {
    setState(() {
      _form![key] = val;
      _saved = false;
    });
  }

  void _toggleList(String key, String item) {
    final cur = List<String>.from((_form![key] as List?) ?? []);
    cur.contains(item) ? cur.remove(item) : cur.add(item);
    _updField(key, cur);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = '';
    });
    _form!['preferred_name'] = _prefNameCtrl.text;
    _form!['situation_story'] = _storyCtrl.text;
    try {
      final body = Map<String, dynamic>.from(_form!)..remove('preferred_tone');
      await _api.updateMemory(body);
      if (mounted)
        setState(() {
          _saving = false;
          _saved = true;
        });
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) setState(() => _saved = false);
    } catch (e, s) {
      debugPrint('⚠️ MemoryProfile save error: $e\n$s');
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'Failed to save: $e';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Memory Profile'),
        backgroundColor: JournalColors.bgBase,
      ),
      child: _form == null
          ? Center(
              child: _error.isNotEmpty
                  ? Text(_error,
                      style: const TextStyle(color: JournalColors.textMuted))
                  : const CupertinoActivityIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Name + Pronouns
                  GlassCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('PREFERRED NAME'),
                          CupertinoTextField(
                            controller: _prefNameCtrl,
                            placeholder: 'What should AI call you?',
                            style: const TextStyle(
                                color: JournalColors.textPrimary),
                            placeholderStyle:
                                const TextStyle(color: JournalColors.textMuted),
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: _fieldDeco(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          const SizedBox(height: 16),
                          const _FieldLabel('PRONOUNS'),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _kPronounOpts
                                .map((p) => _Pill(
                                      label: p,
                                      active: _form!['pronouns'] == p,
                                      onTap: () => _updField('pronouns', p),
                                    ))
                                .toList(),
                          ),
                        ]),
                  ),

                  const SizedBox(height: 16),

                  // Situation
                  GlassCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('SITUATION TYPE'),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _kSituations
                                .map((s) => _Pill(
                                      label: s.label,
                                      active: _form!['situation_type'] == s.id,
                                      onTap: () =>
                                          _updField('situation_type', s.id),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 16),
                          const _FieldLabel('SITUATION STORY'),
                          CupertinoTextField(
                            controller: _storyCtrl,
                            placeholder:
                                "Brief context for your AI — what's going on?",
                            maxLines: 4,
                            style: const TextStyle(
                                color: JournalColors.textPrimary),
                            placeholderStyle:
                                const TextStyle(color: JournalColors.textMuted),
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: _fieldDeco(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ]),
                  ),

                  const SizedBox(height: 16),

                  // Topics
                  GlassCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('FOCUS TOPICS'),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ..._kTopics.map((t) => _Pill(
                                    label: t,
                                    active: ((_form!['topics'] as List?) ?? [])
                                        .contains(t),
                                    onTap: () => _toggleList('topics', t),
                                  )),
                              ...((_form!['topics'] as List?) ?? [])
                                  .whereType<String>()
                                  .where((t) => !_kTopics.contains(t))
                                  .map((t) => _Pill(
                                        label: t,
                                        active: true,
                                        onTap: () => _toggleList('topics', t),
                                      )),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                              child: CupertinoTextField(
                                controller: _customTopicCtrl,
                                placeholder: 'Add your own topic…',
                                style: const TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 13),
                                placeholderStyle: const TextStyle(
                                    color: JournalColors.textMuted,
                                    fontSize: 13),
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: _fieldDeco(),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                onSubmitted: (v) {
                                  if (v.trim().isNotEmpty) {
                                    _toggleList('topics', v.trim());
                                    _customTopicCtrl.clear();
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                if (_customTopicCtrl.text.trim().isNotEmpty) {
                                  _toggleList(
                                      'topics', _customTopicCtrl.text.trim());
                                  _customTopicCtrl.clear();
                                }
                              },
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: JournalColors.accent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: JournalColors.accent
                                          .withOpacity(0.3)),
                                ),
                                child: const Icon(CupertinoIcons.plus,
                                    color: JournalColors.accent, size: 18),
                              ),
                            ),
                          ]),
                        ]),
                  ),

                  const SizedBox(height: 16),

                  // Goals
                  GlassCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('GOALS'),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _kGoals
                                .map((g) => _Pill(
                                      label: g.label,
                                      active: ((_form!['goals'] as List?) ?? [])
                                          .contains(g.id),
                                      onTap: () => _toggleList('goals', g.id),
                                    ))
                                .toList(),
                          ),
                        ]),
                  ),

                  const SizedBox(height: 16),

                  // Key People
                  GlassCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('KEY PEOPLE'),
                          ...((_form!['people'] as List?) ?? [])
                              .asMap()
                              .entries
                              .map((e) {
                            final p = e.value as Map;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: JournalColors.bgSurface,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: JournalColors.border),
                                    ),
                                    child: Row(children: [
                                      Text(p['role'] as String? ?? '—',
                                          style: const TextStyle(
                                              color: JournalColors.accent,
                                              fontSize: 11)),
                                      const SizedBox(width: 10),
                                      Text(p['name'] as String? ?? '',
                                          style: const TextStyle(
                                              color: JournalColors.textPrimary,
                                              fontSize: 13)),
                                    ]),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    final people = List<dynamic>.from(
                                        _form!['people'] as List? ?? []);
                                    people.removeAt(e.key);
                                    _updField('people', people);
                                  },
                                  child: const Icon(
                                      CupertinoIcons.xmark_circle_fill,
                                      color: Colors.red,
                                      size: 20),
                                ),
                              ]),
                            );
                          }),
                          const SizedBox(height: 4),
                          Row(children: [
                            Expanded(
                              child: CupertinoTextField(
                                controller: _addNameCtrl,
                                placeholder: 'Name',
                                style: const TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 13),
                                placeholderStyle: const TextStyle(
                                    color: JournalColors.textMuted,
                                    fontSize: 13),
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: _fieldDeco(),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: CupertinoTextField(
                                controller: _addRoleCtrl,
                                placeholder: 'Role',
                                style: const TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 13),
                                placeholderStyle: const TextStyle(
                                    color: JournalColors.textMuted,
                                    fontSize: 13),
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: _fieldDeco(),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                if (_addNameCtrl.text.trim().isEmpty) return;
                                final people = List<dynamic>.from(
                                    _form!['people'] as List? ?? []);
                                people.add({
                                  'name': _addNameCtrl.text.trim(),
                                  'role': _addRoleCtrl.text.trim(),
                                });
                                _updField('people', people);
                                _addNameCtrl.clear();
                                _addRoleCtrl.clear();
                              },
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: JournalColors.accent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: JournalColors.accent
                                          .withOpacity(0.3)),
                                ),
                                child: const Icon(CupertinoIcons.plus,
                                    color: JournalColors.accent, size: 18),
                              ),
                            ),
                          ]),
                        ]),
                  ),

                  const SizedBox(height: 16),

                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _StatusBanner(type: 'error', message: _error),
                    ),

                  AdaptiveButton(
                    style: AdaptiveButtonStyle.prominentGlass,
                    onPressed: _saving ? null : _save,
                    label: _saving
                        ? 'Saving…'
                        : _saved
                            ? '✓ Saved'
                            : 'Save Changes',
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}

// ── Change Password Screen ────────────────────────────────────────────────────

class _ChangePasswordScreen extends StatefulWidget {
  const _ChangePasswordScreen();

  @override
  State<_ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<_ChangePasswordScreen> {
  final _api = ApiService();
  final _curCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confCtrl = TextEditingController();
  bool _saving = false;
  String _error = '';
  String _success = '';

  @override
  void dispose() {
    _curCtrl.dispose();
    _newCtrl.dispose();
    _confCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_newCtrl.text != _confCtrl.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    if (_newCtrl.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
      _success = '';
    });
    try {
      await _api.changePassword(_curCtrl.text, _newCtrl.text);
      if (mounted) {
        setState(() {
          _saving = false;
          _success = 'Password changed successfully';
        });
        _curCtrl.clear();
        _newCtrl.clear();
        _confCtrl.clear();
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'Failed to change password';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Change Password'),
        backgroundColor: JournalColors.bgBase,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            GlassCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel('CURRENT PASSWORD'),
                    CupertinoTextField(
                      controller: _curCtrl,
                      placeholder: 'Current password',
                      obscureText: true,
                      style: const TextStyle(color: JournalColors.textPrimary),
                      placeholderStyle:
                          const TextStyle(color: JournalColors.textMuted),
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: _fieldDeco(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    const SizedBox(height: 12),
                    const _FieldLabel('NEW PASSWORD'),
                    CupertinoTextField(
                      controller: _newCtrl,
                      placeholder: 'New password (min 8 chars)',
                      obscureText: true,
                      style: const TextStyle(color: JournalColors.textPrimary),
                      placeholderStyle:
                          const TextStyle(color: JournalColors.textMuted),
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: _fieldDeco(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    const SizedBox(height: 12),
                    const _FieldLabel('CONFIRM PASSWORD'),
                    CupertinoTextField(
                      controller: _confCtrl,
                      placeholder: 'Confirm new password',
                      obscureText: true,
                      style: const TextStyle(color: JournalColors.textPrimary),
                      placeholderStyle:
                          const TextStyle(color: JournalColors.textMuted),
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: _fieldDeco(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ]),
            ),
            const SizedBox(height: 12),
            if (_error.isNotEmpty)
              _StatusBanner(type: 'error', message: _error),
            if (_success.isNotEmpty)
              _StatusBanner(type: 'success', message: _success),
            const SizedBox(height: 12),
            AdaptiveButton(
              style: AdaptiveButtonStyle.prominentGlass,
              onPressed: _saving ? null : _save,
              label: _saving ? 'Saving…' : 'Change Password',
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ── API Key Screen ────────────────────────────────────────────────────────────

class _ApiKeyScreen extends StatefulWidget {
  const _ApiKeyScreen();

  @override
  State<_ApiKeyScreen> createState() => _ApiKeyScreenState();
}

class _ApiKeyScreenState extends State<_ApiKeyScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _info;
  bool _loading = true;
  bool _regenerating = false;
  bool _confirmRegen = false;
  String? _newKey;
  bool _copied = false;
  String _status = '';
  bool _statusErr = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.getApiKey();
      if (mounted)
        setState(() {
          _info = data;
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _info = {'has_key': false};
          _loading = false;
        });
    }
  }

  Future<void> _regenerate() async {
    if (!_confirmRegen) {
      setState(() => _confirmRegen = true);
      return;
    }
    setState(() {
      _regenerating = true;
      _confirmRegen = false;
      _status = '';
    });
    try {
      final data = await _api.regenerateApiKey();
      if (mounted)
        setState(() {
          _regenerating = false;
          _newKey = data['api_key'] as String?;
          _info = {'has_key': true, 'prefix': data['prefix']};
          _status = "New key generated. Copy it now — it won't be shown again.";
          _statusErr = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _regenerating = false;
          _status = 'Failed to regenerate key';
          _statusErr = true;
        });
    }
  }

  Future<void> _copyKey(String key) async {
    await Clipboard.setData(ClipboardData(text: key));
    if (mounted) setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('API Key'),
        backgroundColor: JournalColors.bgBase,
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  GlassCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('API KEY'),
                          const SizedBox(height: 4),
                          const Text(
                            'Used in the X-API-Key header for iPhone Shortcut uploads.',
                            style: TextStyle(
                                color: JournalColors.textMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 14),
                          if (_newKey != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: JournalColors.accent.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color:
                                        JournalColors.accent.withOpacity(0.25)),
                              ),
                              child: SelectableText(
                                _newKey!,
                                style: const TextStyle(
                                  color: JournalColors.accent,
                                  fontSize: 12,
                                  fontFamily: 'Courier',
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            AdaptiveButton(
                              style: AdaptiveButtonStyle.prominentGlass,
                              onPressed: () => _copyKey(_newKey!),
                              label: _copied ? '✓ Copied!' : 'Copy Key',
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () => setState(() => _newKey = null),
                              child: const Center(
                                child: Text("I've saved it — dismiss",
                                    style: TextStyle(
                                        color: JournalColors.textMuted,
                                        fontSize: 12)),
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: JournalColors.bgSurface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: JournalColors.border),
                              ),
                              child: Text(
                                _info?['has_key'] == true
                                    ? '${_info?['prefix'] ?? ''}${'•' * 28}'
                                    : 'No key generated',
                                style: const TextStyle(
                                  color: JournalColors.textMuted,
                                  fontSize: 13,
                                  fontFamily: 'Courier',
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (_confirmRegen)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                '⚠ This will invalidate your current key.',
                                style: TextStyle(
                                    color: CupertinoColors.systemYellow
                                        .withOpacity(0.9),
                                    fontSize: 12),
                              ),
                            ),
                          Row(children: [
                            if (_confirmRegen) ...[
                              Expanded(
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _confirmRegen = false),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: JournalColors.bgSurface,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: JournalColors.border),
                                    ),
                                    child: const Center(
                                      child: Text('Cancel',
                                          style: TextStyle(
                                              color:
                                                  JournalColors.textSecondary,
                                              fontSize: 13)),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            Expanded(
                              child: GestureDetector(
                                onTap: _regenerating ? null : _regenerate,
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _confirmRegen
                                        ? Colors.red.withOpacity(0.1)
                                        : JournalColors.accent.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _confirmRegen
                                          ? Colors.red.withOpacity(0.3)
                                          : JournalColors.accent
                                              .withOpacity(0.3),
                                    ),
                                  ),
                                  child: Center(
                                    child: _regenerating
                                        ? const CupertinoActivityIndicator()
                                        : Text(
                                            _confirmRegen
                                                ? '⚠ Confirm Regenerate'
                                                : _info?['has_key'] == true
                                                    ? '↻ Regenerate Key'
                                                    : '+ Generate Key',
                                            style: TextStyle(
                                              color: _confirmRegen
                                                  ? Colors.red
                                                  : JournalColors.accent,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ]),
                        ]),
                  ),
                  if (_status.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _StatusBanner(
                        type: _statusErr ? 'error' : 'success',
                        message: _status),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
      ),
    );
  }
}

// ── AI Provider Screen ────────────────────────────────────────────────────────

class _AIProviderScreen extends StatefulWidget {
  const _AIProviderScreen();

  @override
  State<_AIProviderScreen> createState() => _AIProviderScreenState();
}

class _AIProviderScreenState extends State<_AIProviderScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _settings;
  bool _loading = true;
  bool _editing = false;
  String _provider = 'anthropic';

  final _keyCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();

  bool _saving = false;
  String _status = '';
  bool _statusErr = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _urlCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _api.getAiProvider();
      if (mounted)
        setState(() {
          _settings = data;
          _provider = data['provider'] as String? ?? 'anthropic';
          _urlCtrl.text = data['base_url'] as String? ?? '';
          _modelCtrl.text = data['model'] as String? ?? '';
          _editing = data['has_key'] != true;
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _settings = {'provider': 'anthropic', 'has_key': false};
          _editing = true;
          _loading = false;
        });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _status = '';
    });
    try {
      await _api.updateAiProvider({
        'provider': _provider,
        if (_keyCtrl.text.trim().isNotEmpty) 'api_key': _keyCtrl.text.trim(),
        if (_urlCtrl.text.trim().isNotEmpty) 'base_url': _urlCtrl.text.trim(),
        if (_modelCtrl.text.trim().isNotEmpty) 'model': _modelCtrl.text.trim(),
      });
      _keyCtrl.clear();
      if (mounted) {
        setState(() {
          _saving = false;
          _status = 'Settings saved.';
          _statusErr = false;
          _editing = false;
        });
        await _load();
      }
    } catch (e, s) {
      debugPrint('⚠️ AIProvider save error: $e\n$s');
      if (mounted)
        setState(() {
          _saving = false;
          _status = 'Error: $e';
          _statusErr = true;
        });
    }
  }

  bool get _needsUrl => _kProviders
      .firstWhere((p) => p.id == _provider, orElse: () => _kProviders.first)
      .needsUrl;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('AI Provider'),
        backgroundColor: JournalColors.bgBase,
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (!_editing && _settings?['has_key'] == true) ...[
                    GlassCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel('CURRENT CONFIGURATION'),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _kProviders
                                            .firstWhere(
                                                (p) => p.id == _provider,
                                                orElse: () => _kProviders.first)
                                            .label,
                                        style: const TextStyle(
                                            color: JournalColors.textPrimary,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _settings?['preview'] as String? ??
                                            '••••',
                                        style: const TextStyle(
                                            color: JournalColors.textMuted,
                                            fontSize: 12,
                                            fontFamily: 'Courier'),
                                      ),
                                      if ((_settings?['model'] as String? ?? '')
                                          .isNotEmpty)
                                        Text(
                                          'Model: ${_settings!['model']}',
                                          style: const TextStyle(
                                              color: JournalColors.textMuted,
                                              fontSize: 11),
                                        ),
                                    ]),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setState(() => _editing = true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color:
                                        JournalColors.accent.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: JournalColors.accent
                                            .withOpacity(0.3)),
                                  ),
                                  child: const Text('Change',
                                      style: TextStyle(
                                          color: JournalColors.accent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ]),
                          ]),
                    ),
                  ] else ...[
                    GlassCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel('PROVIDER'),
                            const SizedBox(height: 8),
                            ..._kProviders.map((p) => GestureDetector(
                                  onTap: () => setState(() => _provider = p.id),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _provider == p.id
                                          ? JournalColors.accent
                                              .withOpacity(0.1)
                                          : JournalColors.bgSurface,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: _provider == p.id
                                              ? JournalColors.accent
                                                  .withOpacity(0.4)
                                              : JournalColors.border),
                                    ),
                                    child: Row(children: [
                                      Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                p.label,
                                                style: TextStyle(
                                                  color: _provider == p.id
                                                      ? JournalColors
                                                          .textPrimary
                                                      : JournalColors
                                                          .textSecondary,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(p.desc,
                                                  style: const TextStyle(
                                                      color: JournalColors
                                                          .textMuted,
                                                      fontSize: 11)),
                                            ]),
                                      ),
                                      if (_provider == p.id)
                                        const Icon(CupertinoIcons.checkmark_alt,
                                            color: JournalColors.accent,
                                            size: 16),
                                    ]),
                                  ),
                                )),
                            const SizedBox(height: 8),
                            _FieldLabel(_settings?['has_key'] == true
                                ? 'API KEY (leave blank to keep existing)'
                                : 'API KEY'),
                            CupertinoTextField(
                              controller: _keyCtrl,
                              placeholder: _provider == 'anthropic'
                                  ? 'sk-ant-api03-…'
                                  : _provider == 'openai'
                                      ? 'sk-proj-…'
                                      : 'your-api-key',
                              obscureText: true,
                              style: const TextStyle(
                                  color: JournalColors.textPrimary),
                              placeholderStyle: const TextStyle(
                                  color: JournalColors.textMuted),
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: _fieldDeco(),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            if (_needsUrl) ...[
                              const SizedBox(height: 12),
                              const _FieldLabel('BASE URL'),
                              CupertinoTextField(
                                controller: _urlCtrl,
                                placeholder: _provider == 'local'
                                    ? 'http://localhost:11434/v1'
                                    : 'https://openrouter.ai/api/v1',
                                style: const TextStyle(
                                    color: JournalColors.textPrimary),
                                placeholderStyle: const TextStyle(
                                    color: JournalColors.textMuted),
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: _fieldDeco(),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ],
                            const SizedBox(height: 12),
                            const _FieldLabel('MODEL OVERRIDE (optional)'),
                            CupertinoTextField(
                              controller: _modelCtrl,
                              placeholder: _provider == 'anthropic'
                                  ? 'claude-sonnet-4-6'
                                  : _provider == 'openai'
                                      ? 'gpt-4o-mini'
                                      : 'model-name',
                              style: const TextStyle(
                                  color: JournalColors.textPrimary),
                              placeholderStyle: const TextStyle(
                                  color: JournalColors.textMuted),
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: _fieldDeco(),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ]),
                    ),
                    const SizedBox(height: 12),
                    AdaptiveButton(
                      style: AdaptiveButtonStyle.prominentGlass,
                      onPressed: _saving ? null : _save,
                      label: _saving ? 'Saving…' : 'Save',
                    ),
                  ],
                  if (_status.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _StatusBanner(
                        type: _statusErr ? 'error' : 'success',
                        message: _status),
                  ],
                  const SizedBox(height: 12),
                  GlassCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _provider == 'anthropic'
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.info_circle_fill,
                          color: _provider == 'anthropic'
                              ? JournalColors.success
                              : JournalColors.info,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _provider == 'anthropic'
                                ? 'Anthropic Claude is still the premium provider path for Sage, but the feature that is live today is text-based file review inside chat.'
                                : 'Sage can review text-based files by injecting their contents into chat. Richer live tools still depend on backend support, regardless of provider.',
                            style: const TextStyle(
                              color: JournalColors.textSecondary,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
      ),
    );
  }
}

// ── Tone Screen ───────────────────────────────────────────────────────────────

class _ToneScreen extends StatefulWidget {
  const _ToneScreen();

  @override
  State<_ToneScreen> createState() => _ToneScreenState();
}

class _ToneScreenState extends State<_ToneScreen> {
  final _api = ApiService();
  String? _tone;
  bool _loading = true;
  bool _saving = false;
  bool _saved = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.getMemory();
      final m = (data['memory'] ?? data) as Map<String, dynamic>;
      if (mounted)
        setState(() {
          _tone = m['preferred_tone'] as String? ?? 'therapist';
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _tone = 'therapist';
          _loading = false;
        });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await _api.updateMemory({'preferred_tone': _tone});
      if (mounted)
        setState(() {
          _saving = false;
          _saved = true;
        });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saved = false);
    } catch (e, s) {
      debugPrint('⚠️ Tone save error: $e\n$s');
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'Error: $e';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Reflection Tone'),
        backgroundColor: JournalColors.bgBase,
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Voice used for therapist insights, pattern summaries, and daily reflections.',
                      style: TextStyle(
                          color: JournalColors.textMuted, fontSize: 12),
                    ),
                  ),
                  GlassCard(
                    child: Column(
                      children: _kTones.asMap().entries.map((e) {
                        final t = e.value;
                        final active = _tone == t.id;
                        return Column(children: [
                          if (e.key > 0)
                            const Divider(
                                color: JournalColors.border, height: 1),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() {
                              _tone = t.id;
                              _saved = false;
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 4),
                              child: Row(children: [
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t.label,
                                          style: TextStyle(
                                            color: active
                                                ? JournalColors.textPrimary
                                                : JournalColors.textSecondary,
                                            fontSize: 15,
                                            fontWeight: active
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(t.desc,
                                            style: const TextStyle(
                                                color: JournalColors.textMuted,
                                                fontSize: 12)),
                                      ]),
                                ),
                                if (active)
                                  const Icon(CupertinoIcons.checkmark_alt,
                                      color: JournalColors.accent, size: 18),
                              ]),
                            ),
                          ),
                        ]);
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error.isNotEmpty)
                    _StatusBanner(type: 'error', message: _error),
                  AdaptiveButton(
                    style: AdaptiveButtonStyle.prominentGlass,
                    onPressed: _saving ? null : _save,
                    label: _saving
                        ? 'Saving…'
                        : _saved
                            ? '✓ Saved'
                            : 'Save',
                  ),
                  const SizedBox(height: 40),
                ],
              ),
      ),
    );
  }
}

// ── Sessions Screen ───────────────────────────────────────────────────────────

class _SessionsScreen extends StatefulWidget {
  const _SessionsScreen();

  @override
  State<_SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<_SessionsScreen> {
  final _api = ApiService();
  List<dynamic> _sessions = [];
  bool _loading = true;
  String? _revoking;
  bool _revokingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _api.getSessions();
      if (mounted)
        setState(() {
          _sessions = data;
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _sessions = [];
          _loading = false;
        });
    }
  }

  Future<void> _revoke(dynamic id) async {
    setState(() => _revoking = id.toString());
    try {
      await _api.revokeSession(id);
      if (mounted)
        setState(() {
          _sessions = _sessions.where((s) => s['id'] != id).toList();
          _revoking = null;
        });
    } catch (_) {
      if (mounted) setState(() => _revoking = null);
    }
  }

  Future<void> _revokeAll() async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Revoke All Sessions?'),
        content: const Text('All other devices will be logged out.'),
        actions: [
          CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Revoke All')),
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _revokingAll = true);
    try {
      await _api.revokeAllSessions();
      if (mounted) await _load();
    } catch (_) {
      if (mounted) setState(() => _revokingAll = false);
    }
  }

  String _fmt(String? dt) {
    if (dt == null) return '—';
    try {
      final d = DateTime.parse(dt);
      return '${d.month}/${d.day}/${d.year}';
    } catch (_) {
      return dt;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Active Sessions'),
        backgroundColor: JournalColors.bgBase,
        trailing: _sessions.length > 1
            ? GestureDetector(
                onTap: _revokingAll ? null : _revokeAll,
                child: Text(
                  'Revoke All',
                  style: TextStyle(
                      color: Colors.red.withOpacity(0.85), fontSize: 14),
                ),
              )
            : null,
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : _sessions.isEmpty
                ? const Center(
                    child: Text('No active sessions',
                        style: TextStyle(color: JournalColors.textMuted)))
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _sessions.length,
                    itemBuilder: (ctx, i) {
                      final s = _sessions[i] as Map;
                      final id = s['id'];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassCard(
                          child: Row(children: [
                            const Icon(CupertinoIcons.device_laptop,
                                color: JournalColors.accent, size: 20),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s['device_hint'] as String? ??
                                          'Unknown device',
                                      style: const TextStyle(
                                          color: JournalColors.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${s['ip_address'] ?? ''} · ${_fmt(s['last_used_at'] as String?)}',
                                      style: const TextStyle(
                                          color: JournalColors.textMuted,
                                          fontSize: 11),
                                    ),
                                  ]),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _revoking == id.toString()
                                  ? null
                                  : () => _revoke(id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: Colors.red.withOpacity(0.2)),
                                ),
                                child: _revoking == id.toString()
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CupertinoActivityIndicator())
                                    : const Text('Revoke',
                                        style: TextStyle(
                                            color: Colors.red,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

// ── SMS / Text Journal Screen ─────────────────────────────────────────────────

class _SmsScreen extends StatefulWidget {
  const _SmsScreen();

  @override
  State<_SmsScreen> createState() => _SmsScreenState();
}

class _SmsScreenState extends State<_SmsScreen> {
  final _api = ApiService();
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  Map<String, dynamic>? _status;
  bool _loading = true;
  String _phase = 'idle'; // idle | enter | verify
  bool _sending = false;
  bool _verifying = false;
  String _error = '';
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _api.getSmsStatus();
      if (mounted)
        setState(() {
          _status = data;
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _status = null;
          _loading = false;
        });
    }
  }

  Future<void> _sendCode() async {
    setState(() {
      _sending = true;
      _error = '';
    });
    try {
      await _api.requestSmsVerification(_phoneCtrl.text.trim());
      if (mounted)
        setState(() {
          _sending = false;
          _phase = 'verify';
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _sending = false;
          _error = 'Failed to send code';
        });
    }
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _error = '';
    });
    try {
      await _api.verifySmsCode(_phoneCtrl.text.trim(), _codeCtrl.text.trim());
      if (mounted) {
        setState(() {
          _verifying = false;
          _phase = 'idle';
          _msg = 'Phone verified! You can now text journal entries.';
        });
        _phoneCtrl.clear();
        _codeCtrl.clear();
        await _load();
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _verifying = false;
          _error = 'Invalid or expired code';
        });
    }
  }

  Future<void> _remove() async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Remove Phone Number?'),
        content:
            const Text('You will no longer be able to text journal entries.'),
        actions: [
          CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.removeSmsPhone();
      if (mounted) {
        setState(() => _msg = 'Phone number removed.');
        await _load();
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to remove phone number');
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Text Journal'),
        backgroundColor: JournalColors.bgBase,
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_msg.isNotEmpty) ...[
                    _StatusBanner(type: 'success', message: _msg),
                    const SizedBox(height: 12),
                  ],

                  // Verified number
                  if (_status?['verified'] == true && _phase == 'idle') ...[
                    GlassCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel('VERIFIED PHONE NUMBER'),
                            const SizedBox(height: 8),
                            Text(
                              _status?['phone_number'] as String? ?? '',
                              style: const TextStyle(
                                  color: JournalColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Verified · Active since ${(_status?['created_at'] as String? ?? '').length >= 10 ? (_status!['created_at'] as String).substring(0, 10) : '—'}',
                              style: const TextStyle(
                                  color: JournalColors.textMuted, fontSize: 11),
                            ),
                            const SizedBox(height: 14),
                            Row(children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _phase = 'enter';
                                    _error = '';
                                    _msg = '';
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    decoration: BoxDecoration(
                                      color:
                                          JournalColors.accent.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: JournalColors.accent
                                              .withOpacity(0.3)),
                                    ),
                                    child: const Center(
                                      child: Text('Change',
                                          style: TextStyle(
                                              color: JournalColors.accent,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: GestureDetector(
                                  onTap: _remove,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.red.withOpacity(0.2)),
                                    ),
                                    child: const Center(
                                      child: Text('Remove',
                                          style: TextStyle(
                                              color: Colors.red,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                ),
                              ),
                            ]),
                          ]),
                    ),
                  ]

                  // No number linked
                  else if (_phase == 'idle') ...[
                    GlassCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel('NO PHONE LINKED'),
                            const SizedBox(height: 8),
                            const Text(
                              'Link a verified mobile number to text journal entries anytime — no app needed. Only your registered number can submit entries.',
                              style: TextStyle(
                                  color: JournalColors.textMuted, fontSize: 13),
                            ),
                            const SizedBox(height: 14),
                            AdaptiveButton(
                              style: AdaptiveButtonStyle.prominentGlass,
                              onPressed: () => setState(() {
                                _phase = 'enter';
                                _error = '';
                                _msg = '';
                              }),
                              label: '+ Add Phone Number',
                            ),
                          ]),
                    ),
                  ],

                  // Enter phone
                  if (_phase == 'enter') ...[
                    const SizedBox(height: 12),
                    GlassCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel('ENTER YOUR MOBILE NUMBER'),
                            CupertinoTextField(
                              controller: _phoneCtrl,
                              placeholder: '+1 555 000 0000',
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(
                                  color: JournalColors.textPrimary,
                                  fontSize: 16),
                              placeholderStyle: const TextStyle(
                                  color: JournalColors.textMuted),
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: _fieldDeco(),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                                'US: 10 digits. International: include + country code.',
                                style: TextStyle(
                                    color: JournalColors.textMuted,
                                    fontSize: 11)),
                            if (_error.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _StatusBanner(type: 'error', message: _error),
                            ],
                            const SizedBox(height: 14),
                            Row(children: [
                              GestureDetector(
                                onTap: () => setState(() {
                                  _phase = 'idle';
                                  _error = '';
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: JournalColors.bgSurface,
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: JournalColors.border),
                                  ),
                                  child: const Text('Cancel',
                                      style: TextStyle(
                                          color: JournalColors.textSecondary,
                                          fontSize: 13)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AdaptiveButton(
                                  style: AdaptiveButtonStyle.prominentGlass,
                                  onPressed: _sending ? null : _sendCode,
                                  label: _sending ? 'Sending…' : 'Send Code',
                                ),
                              ),
                            ]),
                          ]),
                    ),
                  ],

                  // Verify code
                  if (_phase == 'verify') ...[
                    const SizedBox(height: 12),
                    GlassCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel('ENTER VERIFICATION CODE'),
                            Text(
                                'Sent to ${_phoneCtrl.text} · expires in 10 min',
                                style: const TextStyle(
                                    color: JournalColors.textMuted,
                                    fontSize: 11)),
                            const SizedBox(height: 12),
                            CupertinoTextField(
                              controller: _codeCtrl,
                              placeholder: '000000',
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: JournalColors.textPrimary,
                                  fontSize: 26,
                                  letterSpacing: 10,
                                  fontWeight: FontWeight.w700),
                              placeholderStyle: const TextStyle(
                                  color: JournalColors.textMuted, fontSize: 26),
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: _fieldDeco(),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 14),
                            ),
                            if (_error.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _StatusBanner(type: 'error', message: _error),
                            ],
                            const SizedBox(height: 14),
                            Row(children: [
                              GestureDetector(
                                onTap: () => setState(() {
                                  _phase = 'enter';
                                  _error = '';
                                  _codeCtrl.clear();
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: JournalColors.bgSurface,
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: JournalColors.border),
                                  ),
                                  child: const Text('Resend',
                                      style: TextStyle(
                                          color: JournalColors.textSecondary,
                                          fontSize: 13)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AdaptiveButton(
                                  style: AdaptiveButtonStyle.prominentGlass,
                                  onPressed: _verifying ? null : _verify,
                                  label: _verifying
                                      ? 'Verifying…'
                                      : 'Verify Number',
                                ),
                              ),
                            ]),
                          ]),
                    ),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
      ),
    );
  }
}

// ── Recovery Questions Screen ─────────────────────────────────────────────────

const _kSecurityQuestionsBank = <String>[
  'What was the name of your first pet?',
  'What city were you born in?',
  "What is your mother's maiden name?",
  'What was the name of your first school?',
  'What was the make and model of your first car?',
  'What is the middle name of your oldest sibling?',
  'What street did you grow up on?',
  'What was the name of your childhood best friend?',
  'What is the name of the town where your nearest relative lives?',
  'What was your childhood nickname?',
  'What is the name of the hospital where you were born?',
  'What was the first concert you attended?',
];

class _RecoveryQuestionsScreen extends StatefulWidget {
  const _RecoveryQuestionsScreen({required this.hasExisting});
  final bool hasExisting;

  @override
  State<_RecoveryQuestionsScreen> createState() =>
      _RecoveryQuestionsScreenState();
}

class _RecoveryQuestionsScreenState extends State<_RecoveryQuestionsScreen> {
  final _api = ApiService();

  // 'idle' | 'gate' | 'form' | 'saved'
  String _phase = 'idle';

  String _q1 = _kSecurityQuestionsBank[0];
  String _q2 = _kSecurityQuestionsBank[1];
  String _q3 = _kSecurityQuestionsBank[2];
  final _a1 = TextEditingController();
  final _a2 = TextEditingController();
  final _a3 = TextEditingController();
  final _pwCtrl = TextEditingController();

  bool _verifying = false;
  bool _saving = false;
  String? _err;

  @override
  void dispose() {
    _a1.dispose();
    _a2.dispose();
    _a3.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _verifyPassword() async {
    if (_pwCtrl.text.trim().isEmpty) return;
    setState(() {
      _verifying = true;
      _err = null;
    });
    try {
      await _api.verifyPassword(_pwCtrl.text.trim());
      if (mounted)
        setState(() {
          _phase = 'form';
          _verifying = false;
          _pwCtrl.clear();
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _verifying = false;
          _err = 'Incorrect password.';
        });
    }
  }

  Future<void> _save() async {
    if (_a1.text.trim().isEmpty ||
        _a2.text.trim().isEmpty ||
        _a3.text.trim().isEmpty) {
      setState(() => _err = 'Please answer all three questions.');
      return;
    }
    if ({_q1, _q2, _q3}.length < 3) {
      setState(() => _err = 'Please choose three different questions.');
      return;
    }
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      await _api.setupSecurityQuestions(
        q1: _q1,
        a1: _a1.text.trim(),
        q2: _q2,
        a2: _a2.text.trim(),
        q3: _q3,
        a3: _a3.text.trim(),
      );
      if (mounted) {
        setState(() {
          _saving = false;
          _phase = 'saved';
        });
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _saving = false;
          _err = 'Failed to save. Please try again.';
        });
    }
  }

  List<String> _opts(String self) => _kSecurityQuestionsBank
      .where((q) => q == self || (q != _q1 && q != _q2 && q != _q3))
      .toList();

  void _pickQuestion(int idx, String current) {
    final opts = _opts(current);
    if (opts.isEmpty) return;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => Container(
        height: 300,
        color: JournalColors.bgCard,
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            CupertinoButton(
              child: const Text('Done'),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
          Expanded(
            child: CupertinoPicker(
              scrollController: FixedExtentScrollController(
                  initialItem: opts.isEmpty
                      ? 0
                      : opts.indexOf(current).clamp(0, opts.length - 1)),
              itemExtent: 40,
              onSelectedItemChanged: (i) {
                if (mounted)
                  setState(() {
                    if (idx == 1) _q1 = opts[i];
                    if (idx == 2) _q2 = opts[i];
                    if (idx == 3) _q3 = opts[i];
                  });
              },
              children: opts
                  .map((q) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(q,
                            style: const TextStyle(
                                color: JournalColors.textPrimary,
                                fontSize: 13)),
                      ))
                  .toList(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _questionBlock(int idx, String q, TextEditingController ctrl) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _FieldLabel('QUESTION $idx'),
      GestureDetector(
        onTap: () => _pickQuestion(idx, q),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: JournalColors.bgSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: JournalColors.border),
          ),
          child: Row(children: [
            Expanded(
                child: Text(q,
                    style: const TextStyle(
                        color: JournalColors.textSecondary,
                        fontSize: 13,
                        height: 1.4))),
            const Icon(CupertinoIcons.chevron_down,
                color: JournalColors.textMuted, size: 14),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      CupertinoTextField(
        controller: ctrl,
        placeholder: 'Your answer (not case-sensitive)',
        placeholderStyle: const TextStyle(color: JournalColors.textMuted),
        style: const TextStyle(color: JournalColors.textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: _fieldDeco(),
        autocorrect: false,
        textInputAction: idx < 3 ? TextInputAction.next : TextInputAction.done,
      ),
      const SizedBox(height: 20),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Recovery Questions'),
        backgroundColor: JournalColors.bgBase.withOpacity(0.9),
        border: const Border(
            bottom: BorderSide(color: JournalColors.border, width: 0.5)),
        leading: _phase == 'form'
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => setState(() {
                  _phase = 'idle';
                  _err = null;
                }),
                child: const Text('Cancel',
                    style: TextStyle(color: JournalColors.accent)),
              )
            : null,
      ),
      child: SafeArea(
        child: _phase == 'saved'
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(CupertinoIcons.checkmark_circle_fill,
                        color: Color(0xFF4ade80), size: 52),
                    const SizedBox(height: 16),
                    const Text('Recovery questions saved',
                        style: TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text(
                        'Your account can now be recovered without email access.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: JournalColors.textSecondary, fontSize: 14)),
                  ]),
                ),
              )
            : SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Info banner ──
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: JournalColors.bgSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: JournalColors.border),
                        ),
                        child: Text(
                          widget.hasExisting
                              ? 'Offline recovery is active. You can update your questions below.'
                              : 'Set up security questions so you can recover your account without email access.',
                          style: const TextStyle(
                              color: JournalColors.textSecondary,
                              fontSize: 13,
                              height: 1.5),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Gate phase: password confirm ──
                      if (_phase == 'idle') ...[
                        AdaptiveButton(
                          style: AdaptiveButtonStyle.prominentGlass,
                          onPressed: () => setState(() {
                            _phase = 'gate';
                            _err = null;
                            _pwCtrl.clear();
                          }),
                          label: widget.hasExisting
                              ? '↻ Update Questions'
                              : 'Set Up Recovery Questions',
                        ),
                      ],

                      if (_phase == 'gate') ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFf59e0b).withOpacity(0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    const Color(0xFFf59e0b).withOpacity(0.20)),
                          ),
                          child: const Text(
                            'Enter your current password to continue.',
                            style: TextStyle(
                                color: Color(0xFFf59e0b),
                                fontSize: 13,
                                height: 1.5),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _FieldLabel('CURRENT PASSWORD'),
                        CupertinoTextField(
                          controller: _pwCtrl,
                          placeholder: 'Your current password',
                          placeholderStyle:
                              const TextStyle(color: JournalColors.textMuted),
                          style:
                              const TextStyle(color: JournalColors.textPrimary),
                          obscureText: true,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: _fieldDeco(),
                          onSubmitted: (_) => _verifyPassword(),
                        ),
                        const SizedBox(height: 12),
                        if (_err != null) ...[
                          _StatusBanner(type: 'error', message: _err!),
                          const SizedBox(height: 12),
                        ],
                        Row(children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _phase = 'idle';
                                _err = null;
                                _pwCtrl.clear();
                              }),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: JournalColors.bgSurface,
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: JournalColors.border),
                                ),
                                child: const Text('Cancel',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: JournalColors.textSecondary,
                                        fontSize: 15)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AdaptiveButton(
                              style: AdaptiveButtonStyle.prominentGlass,
                              onPressed: _verifying ? null : _verifyPassword,
                              label: _verifying ? 'Verifying…' : 'Confirm →',
                            ),
                          ),
                        ]),
                      ],

                      // ── Form phase: question setup ──
                      if (_phase == 'form') ...[
                        _questionBlock(1, _q1, _a1),
                        _questionBlock(2, _q2, _a2),
                        _questionBlock(3, _q3, _a3),
                        if (_err != null) ...[
                          _StatusBanner(type: 'error', message: _err!),
                          const SizedBox(height: 12),
                        ],
                        AdaptiveButton(
                          style: AdaptiveButtonStyle.prominentGlass,
                          onPressed: _saving ? null : _save,
                          label: _saving ? 'Saving…' : 'Save Questions',
                        ),
                      ],

                      const SizedBox(height: 32),
                    ]),
              ),
      ),
    );
  }
}

// ── Two-Factor Authentication Screen ─────────────────────────────────────────

class _TwoFAScreen extends StatefulWidget {
  const _TwoFAScreen({required this.enabled});
  final bool enabled;

  @override
  State<_TwoFAScreen> createState() => _TwoFAScreenState();
}

class _TwoFAScreenState extends State<_TwoFAScreen> {
  final _api = ApiService();

  // 'idle' | 'setup' | 'verify' | 'backup_codes' | 'disable'
  String _phase = 'idle';

  Map<String, dynamic>? _setupData;
  List<String> _backupCodes = [];

  final _codeCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();

  bool _busy = false;
  bool _done = false;
  String? _err;

  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.enabled;
    _phase = widget.enabled ? 'idle' : 'idle';
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _startSetup() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final data = await _api.setup2FA();
      if (mounted)
        setState(() {
          _setupData = data;
          _phase = 'setup';
          _busy = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _busy = false;
          _err = 'Failed to start setup. Try again.';
        });
    }
  }

  Future<void> _verifyAndEnable() async {
    final code = _codeCtrl.text.trim().replaceAll(' ', '');
    if (code.length != 6) {
      setState(
          () => _err = 'Enter the 6-digit code from your authenticator app.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await _api.enable2FA(code);
      final codes =
          (_setupData?['backup_codes'] as List?)?.cast<String>() ?? [];
      if (mounted)
        setState(() {
          _enabled = true;
          _backupCodes = codes;
          _phase = 'backup_codes';
          _busy = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _busy = false;
          _err = 'Invalid code. Try again.';
        });
    }
  }

  Future<void> _disable() async {
    final code = _pwCtrl.text.trim().replaceAll(' ', '');
    if (code.length != 6) {
      setState(
          () => _err = 'Enter the 6-digit code from your authenticator app.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await _api.disable2FA(code);
      if (mounted)
        setState(() {
          _enabled = false;
          _phase = 'idle';
          _busy = false;
          _done = true;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _busy = false;
          _err = 'Invalid code. Try again.';
        });
    }
  }

  Widget _idleView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: JournalColors.bgSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: JournalColors.border),
        ),
        child: Text(
          _enabled
              ? '2FA is currently enabled. Your account requires a 6-digit code from your authenticator app each time you sign in.'
              : 'Add a second layer of protection. Each login will require a 6-digit code from an authenticator app like Google Authenticator or Authy.',
          style: const TextStyle(
              color: JournalColors.textSecondary, fontSize: 13, height: 1.5),
        ),
      ),
      const SizedBox(height: 24),
      if (_enabled) ...[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF10b981).withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: const Color(0xFF10b981).withOpacity(0.25)),
          ),
          child: const Row(children: [
            Icon(CupertinoIcons.shield_lefthalf_fill,
                color: Color(0xFF10b981), size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text('Two-factor authentication is active',
                  style: TextStyle(
                      color: Color(0xFF10b981),
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => setState(() {
            _phase = 'disable';
            _err = null;
            _pwCtrl.clear();
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.25)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.xmark_shield_fill,
                    color: Colors.red, size: 18),
                SizedBox(width: 8),
                Text('Disable 2FA',
                    style: TextStyle(
                        color: Colors.red,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ] else ...[
        if (_err != null) ...[
          _StatusBanner(type: 'error', message: _err!),
          const SizedBox(height: 12),
        ],
        AdaptiveButton(
          style: AdaptiveButtonStyle.prominentGlass,
          onPressed: _busy ? null : _startSetup,
          label: _busy ? 'Setting up…' : 'Enable 2FA',
        ),
      ],
    ]);
  }

  Widget _setupView() {
    final secret = _setupData?['secret'] as String? ?? '';
    final qrRaw = _setupData?['qr_base64'] as String? ?? '';

    Uint8List? qrBytes;
    if (qrRaw.isNotEmpty) {
      try {
        final b64 =
            qrRaw.startsWith('data:image') ? qrRaw.split(',').last : qrRaw;
        qrBytes = base64Decode(b64);
      } catch (_) {}
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('1. Scan this QR code',
          style: TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      const Text(
          'Open Google Authenticator, Authy, or any TOTP app and scan the code below.',
          style: TextStyle(
              color: JournalColors.textSecondary, fontSize: 13, height: 1.5)),
      const SizedBox(height: 16),
      if (qrBytes != null)
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.memory(qrBytes, width: 180, height: 180),
          ),
        )
      else
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: JournalColors.bgSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: JournalColors.border),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Manual entry key:',
                style: TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 11,
                    letterSpacing: 0.8)),
            const SizedBox(height: 6),
            Text(secret,
                style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 14,
                    fontFamily: 'monospace',
                    letterSpacing: 1.5)),
          ]),
        ),
      const SizedBox(height: 24),
      const Text('2. Enter the 6-digit code',
          style: TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      CupertinoTextField(
        controller: _codeCtrl,
        placeholder: '000 000',
        placeholderStyle: const TextStyle(color: JournalColors.textMuted),
        style: const TextStyle(
            color: JournalColors.textPrimary,
            fontSize: 22,
            letterSpacing: 6,
            fontWeight: FontWeight.w600),
        keyboardType: TextInputType.number,
        maxLength: 7,
        textAlign: TextAlign.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: _fieldDeco(),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _verifyAndEnable(),
      ),
      const SizedBox(height: 12),
      if (_err != null) ...[
        _StatusBanner(type: 'error', message: _err!),
        const SizedBox(height: 12),
      ],
      AdaptiveButton(
        style: AdaptiveButtonStyle.prominentGlass,
        onPressed: _busy ? null : _verifyAndEnable,
        label: _busy ? 'Verifying…' : 'Verify & Enable',
      ),
    ]);
  }

  Widget _backupCodesView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFf59e0b).withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFf59e0b).withOpacity(0.30)),
        ),
        child: const Row(children: [
          Icon(CupertinoIcons.exclamationmark_triangle_fill,
              color: Color(0xFFf59e0b), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Save these backup codes somewhere safe. Each can only be used once if you lose access to your authenticator.',
              style: TextStyle(
                  color: Color(0xFFf59e0b), fontSize: 12, height: 1.5),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: JournalColors.bgSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: JournalColors.border),
        ),
        child: _backupCodes.isEmpty
            ? const Text('No backup codes provided.',
                style: TextStyle(color: JournalColors.textMuted, fontSize: 13))
            : Wrap(
                spacing: 12,
                runSpacing: 8,
                children: _backupCodes
                    .map((c) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: JournalColors.bgCard,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: JournalColors.border),
                          ),
                          child: Text(c,
                              style: const TextStyle(
                                  color: JournalColors.textPrimary,
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                  letterSpacing: 1.2)),
                        ))
                    .toList(),
              ),
      ),
      const SizedBox(height: 24),
      const Icon(CupertinoIcons.checkmark_circle_fill,
          color: Color(0xFF10b981), size: 40),
      const SizedBox(height: 12),
      const Text('2FA is now enabled',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700)),
      const SizedBox(height: 24),
      AdaptiveButton(
        style: AdaptiveButtonStyle.prominentGlass,
        onPressed: () => Navigator.pop(context),
        label: 'Done',
      ),
    ]);
  }

  Widget _disableView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.withOpacity(0.20)),
        ),
        child: const Text(
          'Enter your current 6-digit authenticator code to confirm disabling 2FA.',
          style: TextStyle(color: Colors.red, fontSize: 13, height: 1.5),
        ),
      ),
      const SizedBox(height: 20),
      _FieldLabel('AUTHENTICATOR CODE'),
      CupertinoTextField(
        controller: _pwCtrl,
        placeholder: '000000',
        placeholderStyle: const TextStyle(color: JournalColors.textMuted),
        style: const TextStyle(
            color: JournalColors.textPrimary,
            fontSize: 22,
            letterSpacing: 6,
            fontWeight: FontWeight.w600),
        keyboardType: TextInputType.number,
        maxLength: 6,
        textAlign: TextAlign.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: _fieldDeco(),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _disable(),
      ),
      const SizedBox(height: 12),
      if (_err != null) ...[
        _StatusBanner(type: 'error', message: _err!),
        const SizedBox(height: 12),
      ],
      Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _phase = 'idle';
              _err = null;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: JournalColors.bgSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: JournalColors.border),
              ),
              child: const Text('Cancel',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: JournalColors.textSecondary, fontSize: 15)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: _busy ? null : _disable,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.30)),
              ),
              child: _busy
                  ? const Center(
                      child: CupertinoActivityIndicator(
                          color: Colors.red, radius: 9))
                  : const Text('Disable 2FA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.red,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    String title = 'Two-Factor Auth';
    if (_phase == 'setup') title = 'Scan QR Code';
    if (_phase == 'backup_codes') title = 'Backup Codes';
    if (_phase == 'disable') title = 'Disable 2FA';

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        backgroundColor: JournalColors.bgBase.withOpacity(0.9),
        border: const Border(
            bottom: BorderSide(color: JournalColors.border, width: 0.5)),
        leading: _phase != 'backup_codes'
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  if (_phase == 'setup' || _phase == 'disable') {
                    setState(() {
                      _phase = 'idle';
                      _err = null;
                    });
                  } else {
                    Navigator.pop(context);
                  }
                },
                child: const Text('Back',
                    style: TextStyle(color: JournalColors.accent)),
              )
            : null,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: _done && _phase == 'idle'
              ? Column(children: [
                  const Icon(CupertinoIcons.shield_slash_fill,
                      color: JournalColors.textMuted, size: 40),
                  const SizedBox(height: 12),
                  const Text('2FA has been disabled',
                      style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 24),
                  AdaptiveButton(
                    style: AdaptiveButtonStyle.prominentGlass,
                    onPressed: () => Navigator.pop(context),
                    label: 'Done',
                  ),
                ])
              : _phase == 'setup'
                  ? _setupView()
                  : _phase == 'backup_codes'
                      ? _backupCodesView()
                      : _phase == 'disable'
                          ? _disableView()
                          : _idleView(),
        ),
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

BoxDecoration _fieldDeco() => BoxDecoration(
      color: JournalColors.bgSurface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: JournalColors.border),
    );

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            color: JournalColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.subtitle});
  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: const BoxDecoration(
              color: JournalColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.toUpperCase(),
                  style: const TextStyle(
                    color: JournalColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
}

class _SettingsBackdrop extends StatelessWidget {
  const _SettingsBackdrop();

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
            top: 92,
            left: -44,
            child: _GlowOrb(
              size: 190,
              color: _withAlpha(JournalColors.accent, 0.18),
            ),
          ),
          Positioned(
            top: 230,
            right: -32,
            child: _GlowOrb(
              size: 150,
              color: _withAlpha(JournalColors.info, 0.14),
            ),
          ),
          Positioned(
            bottom: 140,
            left: 20,
            child: _GlowOrb(
              size: 120,
              color: _withAlpha(JournalColors.accent2, 0.10),
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

class _SettingsHero extends StatelessWidget {
  const _SettingsHero({
    required this.username,
    required this.email,
    required this.biometricAvailable,
    required this.biometricEnabled,
    required this.pinEnabled,
    required this.reflectLoaded,
    required this.autoReflect,
    required this.securityLoaded,
    required this.twoFAEnabled,
  });

  final String? username;
  final String? email;
  final bool biometricAvailable;
  final bool biometricEnabled;
  final bool pinEnabled;
  final bool reflectLoaded;
  final bool autoReflect;
  final bool securityLoaded;
  final bool twoFAEnabled;

  @override
  Widget build(BuildContext context) {
    final displayName = username?.trim().isNotEmpty == true ? username! : 'You';
    final initials = displayName[0].toUpperCase();

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
            _withAlpha(const Color(0xFF191122), 0.90),
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: JournalColors.accentGlow,
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: [
                      _withAlpha(JournalColors.accent, 0.34),
                      _withAlpha(JournalColors.accent2, 0.22),
                    ],
                  ),
                  border: Border.all(color: JournalColors.borderBright),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: JournalColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ACCOUNT SETTINGS',
                      style: TextStyle(
                        color: JournalColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Manage account, privacy, and assistant preferences.',
                      style: TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _withAlpha(Colors.white, 0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _withAlpha(Colors.white, 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (email?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    email!,
                    style: const TextStyle(
                      color: JournalColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Use this screen to update credentials, tune assistant behavior, and review security status.',
                  style: TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroMetric(
                label: 'Face ID',
                value: biometricAvailable
                    ? (biometricEnabled ? 'Enabled' : 'Available')
                    : 'Unavailable',
                color: biometricEnabled
                    ? JournalColors.success
                    : JournalColors.info,
              ),
              _HeroMetric(
                label: 'Journal PIN',
                value: pinEnabled ? 'Enabled' : 'Off',
                color: pinEnabled
                    ? JournalColors.accent2
                    : JournalColors.textMuted,
              ),
              _HeroMetric(
                label: 'Auto-Reflect',
                value:
                    reflectLoaded ? (autoReflect ? 'On' : 'Off') : 'Checking',
                color: autoReflect
                    ? JournalColors.accent
                    : JournalColors.textSecondary,
              ),
              _HeroMetric(
                label: '2FA',
                value: securityLoaded
                    ? (twoFAEnabled ? 'Enabled' : 'Off')
                    : 'Checking',
                color: twoFAEnabled
                    ? JournalColors.success
                    : JournalColors.severity,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
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
      constraints: const BoxConstraints(minWidth: 104),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _withAlpha(color, 0.10),
        border: Border.all(color: _withAlpha(color, 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: _withAlpha(color, 0.92),
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
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.children,
    required this.accentColor,
  });

  final List<Widget> children;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JournalColors.bgCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _withAlpha(accentColor, 0.22)),
        boxShadow: [
          BoxShadow(
            color: _withAlpha(accentColor, 0.10),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 18),
      color: _withAlpha(Colors.white, 0.06),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _withAlpha(iconColor, 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 19),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing ??
              const Icon(
                CupertinoIcons.chevron_right,
                color: JournalColors.textMuted,
                size: 14,
              ),
        ],
      ),
    );

    if (onTap == null) return content;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _withAlpha(iconColor, 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 19),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Transform.scale(
            scale: 0.94,
            child: CupertinoSwitch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: JournalColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineActionButton extends StatelessWidget {
  const _InlineActionButton({
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _withAlpha(color, 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _withAlpha(color, 0.28)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _withAlpha(color, 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _withAlpha(color, 0.24)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

class _SettingsInfoRow extends StatelessWidget {
  const _SettingsInfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _withAlpha(iconColor, 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 19),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: JournalColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? JournalColors.accent.withOpacity(0.18)
                : JournalColors.bgSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active
                  ? JournalColors.accent.withOpacity(0.5)
                  : JournalColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color:
                  active ? JournalColors.accent : JournalColors.textSecondary,
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.type, required this.message});
  final String type;
  final String message;

  @override
  Widget build(BuildContext context) {
    final isError = type == 'error';
    final color = isError ? Colors.red : JournalColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(message,
          style: TextStyle(color: color.withOpacity(0.9), fontSize: 12)),
    );
  }
}
