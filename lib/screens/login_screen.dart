// lib/screens/login_screen.dart
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import 'invite_access_screen.dart';
import 'onboarding_screen.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _backupCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _show2FA = false;
  bool _backupMode = false;
  String? _partialToken;

  // Biometrics / Face ID
  bool _biometricAvailable = false;
  bool _hasBiometricCreds = false;
  bool _biometricLoading = false;
  final _localAuth = LocalAuthentication();
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    _backupCtrl.dispose();
    super.dispose();
  }

  // ── Biometrics ─────────────────────────────────────────────────────────────

  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      final storedUser = await _storage.read(key: 'biometric_username');
      if (mounted) {
        setState(() {
          _biometricAvailable = canCheck && isSupported;
          _hasBiometricCreds = storedUser != null;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleBiometricLogin() async {
    setState(() => _biometricLoading = true);
    try {
      // Security (H6): biometricOnly true — device passcode fallback would
      // let anyone with the PIN replay the stored credentials.
      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Sign in to Journal Intelligence',
        options: const AuthenticationOptions(biometricOnly: true),
      );
      if (!didAuth) {
        if (mounted) setState(() => _biometricLoading = false);
        return;
      }

      final username = await _storage.read(key: 'biometric_username');
      final password = await _storage.read(key: 'biometric_password');
      if (username == null || password == null) {
        if (mounted) {
          setState(() {
            _biometricLoading = false;
            _hasBiometricCreds = false;
          });
        }
        return;
      }

      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final result = await auth.login(username, password);
      if (!mounted) return;
      if (result != null && result['requires_2fa'] == true) {
        setState(() {
          _partialToken = result['partial_token'] as String?;
          _show2FA = true;
          _biometricLoading = false;
        });
      } else {
        setState(() => _biometricLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _biometricLoading = false);
    }
  }

  Future<void> _offerBiometricSave(String username, String password) async {
    if (!_biometricAvailable || _hasBiometricCreds || !mounted) return;
    final save = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Enable Face ID?'),
        content:
            const Text('Sign in faster next time with Face ID or Touch ID.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enable'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not Now'),
          ),
        ],
      ),
    );
    if (save == true && mounted) {
      await _storage.write(key: 'biometric_username', value: username);
      await _storage.write(key: 'biometric_password', value: password);
      setState(() => _hasBiometricCreds = true);
    }
  }

  // ── Login handlers ─────────────────────────────────────────────────────────

  Future<void> _handleLogin() async {
    final auth = context.read<AuthProvider>();
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    // loginGetToken sets the access token but does NOT transition to
    // AuthState.authenticated yet — so this screen stays mounted.
    final result = await auth.loginGetToken(username, password);
    if (!mounted) return;

    if (result == null) return; // error shown by Consumer<AuthProvider>

    if (result['requires_2fa'] == true) {
      setState(() {
        _partialToken = result['partial_token'] as String?;
        _show2FA = true;
      });
      return;
    }

    // Screen is still alive — safe to show the dialog now.
    if (!_hasBiometricCreds && _biometricAvailable) {
      await _offerBiometricSave(username, password);
    }

    // NOW hand off to HomeShell.
    if (mounted) {
      await auth.completeAuthentication(result['user'] as Map<String, dynamic>);
    }
  }

  Future<void> _handle2FA() async {
    await context
        .read<AuthProvider>()
        .complete2FA(_partialToken!, _codeCtrl.text.trim());
  }

  Future<void> _handleBackupCode() async {
    final code = _backupCtrl.text.trim();
    if (code.isEmpty) return;
    await context
        .read<AuthProvider>()
        .completeWithBackupCode(_partialToken!, code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JournalColors.bgBase,
      body: Stack(
        children: [
          const Positioned.fill(child: _LoginBackdrop()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    children: [
                      _Logo(showSecurityBadge: !_show2FA),
                      const SizedBox(height: 28),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: _show2FA
                                ? JournalColors.borderBright
                                : JournalColors.border,
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              _withAlpha(JournalColors.bgCard, 0.96),
                              _withAlpha(JournalColors.bgCardAlt, 0.9),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _withAlpha(JournalColors.accentGlow, 0.7),
                              blurRadius: 42,
                              offset: const Offset(0, 22),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            children: [
                              _show2FA
                                  ? _TwoFACard(
                                      ctrl: _codeCtrl,
                                      backupCtrl: _backupCtrl,
                                      backupMode: _backupMode,
                                      onSubmit: _handle2FA,
                                      onBackupSubmit: _handleBackupCode,
                                      onToggleBackup: () => setState(() {
                                        _backupMode = !_backupMode;
                                        _codeCtrl.clear();
                                        _backupCtrl.clear();
                                        context
                                            .read<AuthProvider>()
                                            .clearError();
                                      }),
                                      onBack: () => setState(() {
                                        _show2FA = false;
                                        _backupMode = false;
                                        _codeCtrl.clear();
                                        _backupCtrl.clear();
                                      }),
                                    )
                                  : _LoginCard(
                                      usernameCtrl: _usernameCtrl,
                                      passwordCtrl: _passwordCtrl,
                                      obscurePassword: _obscurePassword,
                                      onToggleObscure: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                      onSubmit: _handleLogin,
                                      onBiometricLogin: (_hasBiometricCreds &&
                                              _biometricAvailable)
                                          ? _handleBiometricLogin
                                          : null,
                                      biometricLoading: _biometricLoading,
                                    ),
                              Consumer<AuthProvider>(
                                builder: (_, auth, __) {
                                  if (auth.error == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 14),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: _withAlpha(
                                            JournalColors.danger, 0.14),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: _withAlpha(
                                              JournalColors.danger, 0.35),
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(top: 1),
                                            child: Icon(
                                              CupertinoIcons
                                                  .exclamationmark_triangle_fill,
                                              color: JournalColors.danger,
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              auth.error!,
                                              style: const TextStyle(
                                                color:
                                                    JournalColors.textPrimary,
                                                fontSize: 14,
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!_show2FA) ...[
                        const SizedBox(height: 18),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => const OnboardingScreen(),
                            ),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              color: _withAlpha(JournalColors.bgCardAlt, 0.7),
                              border: Border.all(color: JournalColors.border),
                            ),
                            child: const Row(
                              children: [
                                _OrbBadge(
                                  icon: CupertinoIcons.person_add_solid,
                                  size: 18,
                                ),
                                SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Create an account',
                                        style: TextStyle(
                                          color: JournalColors.textPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Set up your journal and recovery options.',
                                        style: TextStyle(
                                          color: JournalColors.textSecondary,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 10),
                                Icon(
                                  CupertinoIcons.arrow_up_right,
                                  color: JournalColors.accent,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => const InviteAccessScreen(),
                            ),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              color: _withAlpha(JournalColors.bgCardAlt, 0.46),
                              border: Border.all(color: JournalColors.border),
                            ),
                            child: const Row(
                              children: [
                                _OrbBadge(
                                  icon: CupertinoIcons.link_circle_fill,
                                  size: 18,
                                ),
                                SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Use an invite',
                                        style: TextStyle(
                                          color: JournalColors.textPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Unlock private access before creating an account.',
                                        style: TextStyle(
                                          color: JournalColors.textSecondary,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 10),
                                Icon(
                                  CupertinoIcons.arrow_up_right,
                                  color: JournalColors.accent,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Logo ──────────────────────────────────────────────────────────────────────

class _Logo extends StatelessWidget {
  const _Logo({this.showSecurityBadge = true});

  final bool showSecurityBadge;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showSecurityBadge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _withAlpha(JournalColors.bgCardAlt, 0.74),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: JournalColors.border),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.lock_shield_fill,
                  color: JournalColors.accent,
                  size: 14,
                ),
                SizedBox(width: 8),
                Text(
                  'PRIVATE',
                  style: TextStyle(
                    color: JournalColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
        if (showSecurityBadge) const SizedBox(height: 18),
        Container(
          width: 122,
          height: 122,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _withAlpha(JournalColors.bgCardAlt, 0.96),
                _withAlpha(JournalColors.bgSurface, 0.9),
              ],
            ),
            border:
                Border.all(color: _withAlpha(JournalColors.borderBright, 0.85)),
            boxShadow: [
              BoxShadow(
                color: _withAlpha(JournalColors.accentGlow, 0.8),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: _withAlpha(Colors.black, 0.32),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _withAlpha(JournalColors.accent, 0.16),
                  _withAlpha(JournalColors.accent2, 0.08),
                ],
              ),
              border: Border.all(color: _withAlpha(JournalColors.border, 1)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Journal Intelligence',
          style: TextStyle(
            color: JournalColors.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Your private journal, reflections,\nand analysis in one place.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: JournalColors.textSecondary,
            fontSize: 15,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 18),
        const Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            _SignalChip(
              icon: CupertinoIcons.sparkles,
              label: 'Timeline',
            ),
            _SignalChip(
              icon: CupertinoIcons.lock_fill,
              label: 'Secure access',
            ),
            _SignalChip(
              icon: CupertinoIcons.waveform_path_ecg,
              label: 'Insights',
            ),
          ],
        ),
      ],
    );
  }
}

// ── Login Card ────────────────────────────────────────────────────────────────

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.usernameCtrl,
    required this.passwordCtrl,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.onSubmit,
    this.onBiometricLogin,
    this.biometricLoading = false,
  });

  final TextEditingController usernameCtrl;
  final TextEditingController passwordCtrl;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final VoidCallback? onBiometricLogin;
  final bool biometricLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgCard, 0.5),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelHeader(
            eyebrow: 'WELCOME BACK',
            title: 'Sign in to continue.',
            body: 'Open your entries, reflections, and saved tools.',
          ),
          const SizedBox(height: 20),
          _AuthField(
            controller: usernameCtrl,
            placeholder: 'Username',
            icon: CupertinoIcons.person_crop_circle,
            textInputAction: TextInputAction.next,
            autocorrect: false,
          ),
          const SizedBox(height: 14),
          _AuthField(
            controller: passwordCtrl,
            placeholder: 'Password',
            icon: CupertinoIcons.lock_shield_fill,
            obscureText: obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            suffix: GestureDetector(
              onTap: onToggleObscure,
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Icon(
                  obscurePassword
                      ? CupertinoIcons.eye
                      : CupertinoIcons.eye_slash,
                  color: JournalColors.textMuted,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              _MicroStat(
                value: 'Encrypted',
                label: 'session layer',
              ),
              SizedBox(width: 10),
              _MicroStat(
                value: 'Fast',
                label: 'resume flow',
              ),
            ],
          ),
          const SizedBox(height: 18),
          Consumer<AuthProvider>(
            builder: (_, auth, __) => AdaptiveButton(
              style: AdaptiveButtonStyle.prominentGlass,
              onPressed: auth.loading ? null : onSubmit,
              label: auth.loading ? 'Signing in…' : 'Sign In',
            ),
          ),
          if (onBiometricLogin != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: biometricLoading ? null : onBiometricLogin,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.bgSurface, 0.78),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: JournalColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (biometricLoading)
                      const CupertinoActivityIndicator(
                        color: JournalColors.accent,
                        radius: 9,
                      )
                    else ...[
                      const Icon(
                        CupertinoIcons.person_crop_circle_badge_checkmark,
                        color: JournalColors.accent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Resume with Face ID',
                        style: TextStyle(
                          color: JournalColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 2FA Card ──────────────────────────────────────────────────────────────────

class _TwoFACard extends StatelessWidget {
  const _TwoFACard({
    required this.ctrl,
    required this.backupCtrl,
    required this.backupMode,
    required this.onSubmit,
    required this.onBackupSubmit,
    required this.onToggleBackup,
    required this.onBack,
  });

  final TextEditingController ctrl;
  final TextEditingController backupCtrl;
  final bool backupMode;
  final VoidCallback onSubmit;
  final VoidCallback onBackupSubmit;
  final VoidCallback onToggleBackup;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgCard, 0.5),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: JournalColors.borderBright),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            eyebrow: backupMode ? 'RECOVERY PATH' : 'SECURE CHECKPOINT',
            title: backupMode
                ? 'Use a backup code to finish signing in.'
                : 'Verify the device with your authenticator code.',
            body: backupMode
                ? 'Enter one of your saved backup codes to regain access without the authenticator app.'
                : 'A second layer keeps your journal and summaries protected from device-level access.',
            leading: const _OrbBadge(
              icon: CupertinoIcons.shield_lefthalf_fill,
              size: 22,
            ),
          ),
          const SizedBox(height: 20),
          if (!backupMode)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _withAlpha(JournalColors.bgSurface, 0.84),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: JournalColors.borderBright),
              ),
              child: CupertinoTextField(
                controller: ctrl,
                placeholder: '000000',
                placeholderStyle:
                    const TextStyle(color: JournalColors.textMuted),
                style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 8,
                ),
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 6,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: _withAlpha(JournalColors.bgBase, 0.18),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: JournalColors.border),
                ),
                onSubmitted: (_) => onSubmit(),
              ),
            )
          else
            _AuthField(
              controller: backupCtrl,
              placeholder: 'XXXXXXXX-XXXXXXXX',
              icon: CupertinoIcons.ticket_fill,
              autocorrect: false,
              textAlign: TextAlign.center,
              onSubmitted: (_) => onBackupSubmit(),
            ),
          const SizedBox(height: 20),
          Consumer<AuthProvider>(
            builder: (_, auth, __) => AdaptiveButton(
              style: AdaptiveButtonStyle.prominentGlass,
              onPressed: auth.loading
                  ? null
                  : (backupMode ? onBackupSubmit : onSubmit),
              label: auth.loading ? 'Verifying…' : 'Verify',
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onToggleBackup,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: _withAlpha(JournalColors.bgSurface, 0.55),
                border: Border.all(color: JournalColors.border),
              ),
              child: Text(
                backupMode
                    ? 'Use authenticator app instead'
                    : 'Use a backup code instead',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onBack,
            child: const Text(
              '← Back to login',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: JournalColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            JournalColors.bgBase,
            JournalColors.bgSurface,
            JournalColors.bgBase,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            left: -40,
            child: _GlowBubble(
              size: 220,
              color: _withAlpha(JournalColors.accent, 0.18),
            ),
          ),
          Positioned(
            top: 180,
            right: -70,
            child: _GlowBubble(
              size: 260,
              color: _withAlpha(JournalColors.accent2, 0.14),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 80,
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _withAlpha(JournalColors.borderBright, 0.18),
                    _withAlpha(JournalColors.bgBase, 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowBubble extends StatelessWidget {
  const _GlowBubble({
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
          gradient: RadialGradient(
            colors: [
              color,
              _withAlpha(color, 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.eyebrow,
    required this.title,
    required this.body,
    this.leading,
  });

  final String eyebrow;
  final String title;
  final String body;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: 14),
        ],
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
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.12,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: const TextStyle(
                  color: JournalColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.placeholder,
    required this.icon,
    this.obscureText = false,
    this.textInputAction,
    this.onSubmitted,
    this.suffix,
    this.autocorrect = false,
    this.textAlign = TextAlign.start,
  });

  final TextEditingController controller;
  final String placeholder;
  final IconData icon;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;
  final bool autocorrect;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      placeholderStyle: const TextStyle(color: JournalColors.textMuted),
      style: const TextStyle(
        color: JournalColors.textPrimary,
        fontSize: 15,
      ),
      obscureText: obscureText,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      autocorrect: autocorrect,
      textAlign: textAlign,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgSurface, 0.74),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: JournalColors.border),
      ),
      prefix: Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Icon(
          icon,
          color: JournalColors.textMuted,
          size: 18,
        ),
      ),
      suffix: suffix,
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _withAlpha(JournalColors.bgCardAlt, 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: JournalColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: JournalColors.accent,
            size: 14,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbBadge extends StatelessWidget {
  const _OrbBadge({
    required this.icon,
    this.size = 20,
  });

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _withAlpha(JournalColors.accent, 0.28),
            _withAlpha(JournalColors.accent2, 0.18),
          ],
        ),
        border: Border.all(color: JournalColors.borderBright),
      ),
      child: Icon(
        icon,
        color: JournalColors.textPrimary,
        size: size,
      ),
    );
  }
}

class _MicroStat extends StatelessWidget {
  const _MicroStat({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _withAlpha(JournalColors.bgBase, 0.18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: JournalColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: JournalColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
