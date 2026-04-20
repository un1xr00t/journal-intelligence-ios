// lib/screens/login_screen.dart
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeCtrl     = TextEditingController();
  final _backupCtrl   = TextEditingController();

  bool    _obscurePassword = true;
  bool    _show2FA         = false;
  bool    _backupMode      = false;
  String? _partialToken;

  // Biometrics / Face ID
  bool _biometricAvailable = false;
  bool _hasBiometricCreds  = false;
  bool _biometricLoading   = false;
  final _localAuth = LocalAuthentication();
  final _storage   = const FlutterSecureStorage();

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
      final canCheck    = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      final storedUser  = await _storage.read(key: 'biometric_username');
      if (mounted) setState(() {
        _biometricAvailable = canCheck && isSupported;
        _hasBiometricCreds  = storedUser != null;
      });
    } catch (_) {}
  }

  Future<void> _handleBiometricLogin() async {
    setState(() => _biometricLoading = true);
    try {
      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Sign in to Journal Intelligence',
        options: AuthenticationOptions(biometricOnly: false),
      );
      if (!didAuth) {
        if (mounted) setState(() => _biometricLoading = false);
        return;
      }

      final username = await _storage.read(key: 'biometric_username');
      final password = await _storage.read(key: 'biometric_password');
      if (username == null || password == null) {
        if (mounted) setState(() { _biometricLoading = false; _hasBiometricCreds = false; });
        return;
      }

      if (!mounted) return;
      final auth   = context.read<AuthProvider>();
      final result = await auth.login(username, password);
      if (!mounted) return;
      if (result != null && result['requires_2fa'] == true) {
        setState(() {
          _partialToken    = result['partial_token'] as String?;
          _show2FA         = true;
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
        content: const Text('Sign in faster next time with Face ID or Touch ID.'),
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
    final auth     = context.read<AuthProvider>();
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
        _show2FA      = true;
      });
      return;
    }

    // Screen is still alive — safe to show the dialog now.
    if (!_hasBiometricCreds && _biometricAvailable) {
      await _offerBiometricSave(username, password);
    }

    // NOW hand off to HomeShell.
    if (mounted) {
      auth.completeAuthentication(result['user'] as Map<String, dynamic>);
    }
  }

  Future<void> _handle2FA() async {
    await context.read<AuthProvider>().complete2FA(_partialToken!, _codeCtrl.text.trim());
  }

  Future<void> _handleBackupCode() async {
    final code = _backupCtrl.text.trim();
    if (code.isEmpty) return;
    await context.read<AuthProvider>().completeWithBackupCode(_partialToken!, code);
  }

  String _parseError(dynamic e) {
    final str   = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    return match?.group(1) ?? 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JournalColors.bgBase,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Logo(),
                const SizedBox(height: 48),
                _show2FA
                    ? _TwoFACard(
                        ctrl:           _codeCtrl,
                        backupCtrl:     _backupCtrl,
                        backupMode:     _backupMode,
                        onSubmit:       _handle2FA,
                        onBackupSubmit: _handleBackupCode,
                        onToggleBackup: () => setState(() {
                          _backupMode = !_backupMode;
                          _codeCtrl.clear();
                          _backupCtrl.clear();
                          context.read<AuthProvider>().clearError();
                        }),
                        onBack: () => setState(() {
                          _show2FA    = false;
                          _backupMode = false;
                          _codeCtrl.clear();
                          _backupCtrl.clear();
                        }),
                      )
                    : _LoginCard(
                        usernameCtrl:     _usernameCtrl,
                        passwordCtrl:     _passwordCtrl,
                        obscurePassword:  _obscurePassword,
                        onToggleObscure:  () => setState(() => _obscurePassword = !_obscurePassword),
                        onSubmit:         _handleLogin,
                        onBiometricLogin: (_hasBiometricCreds && _biometricAvailable)
                            ? _handleBiometricLogin
                            : null,
                        biometricLoading: _biometricLoading,
                      ),
                const SizedBox(height: 24),
                Consumer<AuthProvider>(
                  builder: (_, auth, __) {
                    if (auth.error == null) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.exclamationmark_circle,
                              color: Colors.red, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(auth.error!,
                                style: const TextStyle(color: Colors.red, fontSize: 14)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Logo ──────────────────────────────────────────────────────────────────────

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [JournalColors.accent, JournalColors.accent2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(color: JournalColors.accentGlow, blurRadius: 28, spreadRadius: 2),
            ],
          ),
          child: const Icon(CupertinoIcons.book_fill, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 20),
        const Text(
          'Journal Intelligence',
          style: TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5),
        ),
        const SizedBox(height: 6),
        const Text(
          'Your private intelligence platform',
          style: TextStyle(color: JournalColors.textSecondary, fontSize: 15),
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
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: JournalColors.bgCard.withOpacity(0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: JournalColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 40, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Sign In',
            style: TextStyle(
                color: JournalColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 24),

          // Username
          CupertinoTextField(
            controller: usernameCtrl,
            placeholder: 'Username',
            placeholderStyle: const TextStyle(color: JournalColors.textMuted),
            style: const TextStyle(color: JournalColors.textPrimary),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: JournalColors.border),
            ),
            textInputAction: TextInputAction.next,
            autocorrect: false,
            prefix: const Padding(
              padding: EdgeInsets.only(left: 14),
              child: Icon(CupertinoIcons.person, color: JournalColors.textMuted, size: 18),
            ),
          ),
          const SizedBox(height: 14),

          // Password
          CupertinoTextField(
            controller: passwordCtrl,
            placeholder: 'Password',
            placeholderStyle: const TextStyle(color: JournalColors.textMuted),
            style: const TextStyle(color: JournalColors.textPrimary),
            obscureText: obscurePassword,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: JournalColors.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: JournalColors.border),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            prefix: const Padding(
              padding: EdgeInsets.only(left: 14),
              child: Icon(CupertinoIcons.lock, color: JournalColors.textMuted, size: 18),
            ),
            suffix: GestureDetector(
              onTap: onToggleObscure,
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Icon(
                  obscurePassword ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                  color: JournalColors.textMuted, size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Sign In
          Consumer<AuthProvider>(
            builder: (_, auth, __) => AdaptiveButton(
              style: AdaptiveButtonStyle.prominentGlass,
              onPressed: auth.loading ? null : onSubmit,
              label: auth.loading ? 'Signing in…' : 'Sign In',
            ),
          ),

          // Face ID — only shown if biometric credentials are saved
          if (onBiometricLogin != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: biometricLoading ? null : onBiometricLogin,
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: JournalColors.bgSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: JournalColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (biometricLoading)
                      const CupertinoActivityIndicator(
                          color: JournalColors.accent, radius: 9)
                    else ...[
                      const Icon(CupertinoIcons.person_crop_circle,
                          color: JournalColors.accent, size: 20),
                      const SizedBox(width: 10),
                      const Text(
                        'Sign In with Face ID',
                        style: TextStyle(
                            color: JournalColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500),
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
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: JournalColors.bgCard.withOpacity(0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: JournalColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(CupertinoIcons.shield_lefthalf_fill,
              color: JournalColors.accent, size: 36),
          const SizedBox(height: 16),
          Text(
            backupMode ? 'Backup Code' : 'Two-Factor Authentication',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            backupMode
                ? 'Enter one of your saved backup codes.'
                : 'Enter the 6-digit code from your authenticator app.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: JournalColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),

          // TOTP input
          if (!backupMode)
            CupertinoTextField(
              controller: ctrl,
              placeholder: '000000',
              placeholderStyle: const TextStyle(color: JournalColors.textMuted),
              style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 8),
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 6,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: JournalColors.bgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: JournalColors.borderBright),
              ),
              onSubmitted: (_) => onSubmit(),
            )
          else
            // Backup code input
            CupertinoTextField(
              controller: backupCtrl,
              placeholder: 'XXXXXXXX-XXXXXXXX',
              placeholderStyle: const TextStyle(color: JournalColors.textMuted),
              style: const TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 15,
                  letterSpacing: 1.5),
              textAlign: TextAlign.center,
              autocorrect: false,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: JournalColors.bgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: JournalColors.borderBright),
              ),
              onSubmitted: (_) => onBackupSubmit(),
            ),

          const SizedBox(height: 20),

          // Verify button
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

          // Toggle between TOTP and backup code
          GestureDetector(
            onTap: onToggleBackup,
            child: Text(
              backupMode
                  ? '← Use authenticator app instead'
                  : 'Use a backup code instead',
              textAlign: TextAlign.center,
              style: const TextStyle(color: JournalColors.textSecondary, fontSize: 13),
            ),
          ),

          const SizedBox(height: 10),

          GestureDetector(
            onTap: onBack,
            child: const Text(
              '← Back to login',
              textAlign: TextAlign.center,
              style: TextStyle(color: JournalColors.textMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}