// lib/screens/settings_screen.dart
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage   = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();

  bool _biometricEnabled   = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricStatus();
  }

  Future<void> _checkBiometricStatus() async {
    try {
      final canCheck    = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      final storedUser  = await _storage.read(key: 'biometric_username');
      if (mounted) setState(() {
        _biometricAvailable = canCheck && isSupported;
        _biometricEnabled   = storedUser != null;
      });
    } catch (_) {}
  }

  Future<void> _enableBiometrics(BuildContext context, String username) async {
    final passwordCtrl = TextEditingController();
    final password = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Enable Face ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text('Enter your password to save for Face ID sign-in.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: passwordCtrl,
              placeholder: 'Password',
              obscureText: true,
              autofocus: true,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: JournalColors.bgSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: JournalColors.border),
              ),
              style: const TextStyle(color: JournalColors.textPrimary),
              placeholderStyle:
                  const TextStyle(color: JournalColors.textMuted),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, passwordCtrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    passwordCtrl.dispose();
    if (password == null || password.isEmpty) return;

    try {
      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Confirm to enable Face ID sign-in',
        options: AuthenticationOptions(biometricOnly: false),
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
        content: const Text(
            'You\'ll need to sign in with your password next time.'),
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
            child: const Text('Sign Out'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Settings'),
            backgroundColor: JournalColors.bgBase.withOpacity(0.9),
            border: const Border(
              bottom: BorderSide(color: JournalColors.border, width: 0.5),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── Account card ─────────────────────────────────────
                if (user != null) ...[
                  GlassCard(
                    child: Row(
                      children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [JournalColors.accent, JournalColors.accent2],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              (user['username'] as String? ?? '?')[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user['username'] as String? ?? '',
                                style: const TextStyle(
                                  color: JournalColors.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                user['email'] as String? ?? '',
                                style: const TextStyle(
                                    color: JournalColors.textSecondary,
                                    fontSize: 14),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: JournalColors.accent.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  (user['role'] as String? ?? '').toUpperCase(),
                                  style: const TextStyle(
                                    color: JournalColors.accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Security ──────────────────────────────────────────
                if (_biometricAvailable) ...[
                  const _SectionLabel('SECURITY'),
                  const SizedBox(height: 8),
                  GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: _biometricEnabled
                                  ? JournalColors.accent.withOpacity(0.15)
                                  : JournalColors.bgSurface,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              CupertinoIcons.person_crop_circle,
                              color: _biometricEnabled
                                  ? JournalColors.accent
                                  : JournalColors.textMuted,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Face ID / Touch ID',
                                  style: TextStyle(
                                      color: JournalColors.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _biometricEnabled
                                      ? 'Enabled — sign in without your password'
                                      : 'Sign in next time to enable',
                                  style: const TextStyle(
                                      color: JournalColors.textMuted,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          if (_biometricEnabled)
                            GestureDetector(
                              onTap: _disableBiometrics,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: Colors.red.withOpacity(0.25)),
                                ),
                                child: const Text(
                                  'Disable',
                                  style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            )
                          else
                            GestureDetector(
                              onTap: () => _enableBiometrics(
                                  context,
                                  user?['username'] as String? ?? ''),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: JournalColors.accent.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: JournalColors.accent
                                          .withOpacity(0.30)),
                                ),
                                child: const Text(
                                  'Enable',
                                  style: TextStyle(
                                      color: JournalColors.accent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // ── App info ─────────────────────────────────────────
                const _SectionLabel('APP'),
                const SizedBox(height: 8),
                GlassCard(
                  child: Column(
                    children: [
                      _InfoRow(
                        icon: CupertinoIcons.globe,
                        label: 'Server',
                        value: 'journal.williamthomas.name',
                      ),
                      const Divider(color: JournalColors.border, height: 1),
                      _InfoRow(
                        icon: CupertinoIcons.lock_shield_fill,
                        label: 'Auth',
                        value: 'JWT + Secure Cookie',
                      ),
                      const Divider(color: JournalColors.border, height: 1),
                      _InfoRow(
                        icon: CupertinoIcons.app_badge,
                        label: 'Version',
                        value: '1.0.0',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Links ─────────────────────────────────────────────
                const _SectionLabel('LINKS'),
                const SizedBox(height: 8),
                GlassCard(
                  child: Column(
                    children: const [
                      _LinkRow(
                        icon: CupertinoIcons.escape,
                        label: 'Exit Plan Engine',
                      ),
                      Divider(color: JournalColors.border, height: 1),
                      _LinkRow(
                        icon: CupertinoIcons.doc_text_search,
                        label: 'Detective Mode',
                      ),
                      Divider(color: JournalColors.border, height: 1),
                      _LinkRow(
                        icon: CupertinoIcons.chart_bar_alt_fill,
                        label: 'Mental Health Dashboard',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Sign out ─────────────────────────────────────────
                AdaptiveButton(
                  style: AdaptiveButtonStyle.prominentGlass,
                  onPressed: () => _confirmLogout(context),
                  label: 'Sign Out',
                ),

                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Journal Intelligence · iOS App',
                    style: TextStyle(color: JournalColors.textMuted, fontSize: 12),
                  ),
                ),

                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable row widgets ──────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: JournalColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, color: JournalColors.accent, size: 18),
          const SizedBox(width: 14),
          Text(label,
              style: const TextStyle(
                  color: JournalColors.textPrimary, fontSize: 15)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  color: JournalColors.textMuted, fontSize: 14)),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, color: JournalColors.accent, size: 18),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: JournalColors.textPrimary, fontSize: 15)),
          ),
          const Icon(CupertinoIcons.chevron_right,
              color: JournalColors.textMuted, size: 14),
        ],
      ),
    );
  }
}
