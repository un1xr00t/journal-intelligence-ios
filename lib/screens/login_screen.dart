// lib/screens/login_screen.dart
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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

  bool _obscurePassword = true;
  bool _show2FA         = false;
  String? _partialToken;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final auth = context.read<AuthProvider>();
    final result = await auth.login(
      _usernameCtrl.text.trim(),
      _passwordCtrl.text,
    );

    if (result != null && result['requires_2fa'] == true) {
      setState(() {
        _partialToken = result['partial_token'] as String?;
        _show2FA      = true;
      });
    }
  }

  Future<void> _handle2FA() async {
    final auth = context.read<AuthProvider>();
    await auth.complete2FA(_partialToken!, _codeCtrl.text.trim());
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
                _show2FA ? _TwoFACard(
                  ctrl: _codeCtrl,
                  onSubmit: _handle2FA,
                  onBack: () => setState(() {
                    _show2FA = false;
                    _codeCtrl.clear();
                  }),
                ) : _LoginCard(
                  usernameCtrl: _usernameCtrl,
                  passwordCtrl: _passwordCtrl,
                  obscurePassword: _obscurePassword,
                  onToggleObscure: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  onSubmit: _handleLogin,
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
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [JournalColors.accent, JournalColors.accent2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(
                color: JournalColors.accentGlow,
                blurRadius: 28,
                spreadRadius: 2,
              ),
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
            letterSpacing: -0.5,
          ),
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
  });

  final TextEditingController usernameCtrl;
  final TextEditingController passwordCtrl;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: JournalColors.bgCard.withOpacity(0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: JournalColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 40,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Sign In',
            style: TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
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
                  color: JournalColors.textMuted,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Consumer<AuthProvider>(
            builder: (_, auth, __) => AdaptiveButton(
              style: AdaptiveButtonStyle.prominentGlass,
              onPressed: auth.loading ? null : onSubmit,
              label: auth.loading ? 'Signing in…' : 'Sign In',
            ),
          ),
        ],
      ),
    );
  }
}

// ── 2FA Card ──────────────────────────────────────────────────────────────────

class _TwoFACard extends StatelessWidget {
  const _TwoFACard({
    required this.ctrl,
    required this.onSubmit,
    required this.onBack,
  });

  final TextEditingController ctrl;
  final VoidCallback onSubmit;
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
          const Text(
            'Two-Factor Authentication',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the 6-digit code from your authenticator app.',
            textAlign: TextAlign.center,
            style: TextStyle(color: JournalColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          CupertinoTextField(
            controller: ctrl,
            placeholder: '000000',
            placeholderStyle: const TextStyle(color: JournalColors.textMuted),
            style: const TextStyle(
              color: JournalColors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 8,
            ),
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
          ),
          const SizedBox(height: 20),
          Consumer<AuthProvider>(
            builder: (_, auth, __) => AdaptiveButton(
              style: AdaptiveButtonStyle.prominentGlass,
              onPressed: auth.loading ? null : onSubmit,
              label: auth.loading ? 'Verifying…' : 'Verify',
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onBack,
            child: const Text(
              '← Back to login',
              textAlign: TextAlign.center,
              style: TextStyle(color: JournalColors.textSecondary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
