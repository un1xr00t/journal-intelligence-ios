import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'onboarding_screen.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

class InviteAccessScreen extends StatefulWidget {
  const InviteAccessScreen({super.key});

  @override
  State<InviteAccessScreen> createState() => _InviteAccessScreenState();
}

class _InviteAccessScreenState extends State<InviteAccessScreen> {
  final _api = ApiService();
  final _tokenCtrl = TextEditingController();
  final _passphraseCtrl = TextEditingController();

  Map<String, dynamic>? _status;
  bool _checking = false;
  bool _verifying = false;
  String? _error;
  String? _token;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _passphraseCtrl.dispose();
    super.dispose();
  }

  String? _parseToken(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final inviteIndex = uri.pathSegments.indexOf('invite');
      if (inviteIndex != -1 && inviteIndex + 1 < uri.pathSegments.length) {
        return uri.pathSegments[inviteIndex + 1];
      }
      return uri.pathSegments.last;
    }

    final match = RegExp(r'invite/([^/?#]+)').firstMatch(trimmed);
    if (match != null) return match.group(1);
    return trimmed;
  }

  String _parseError(dynamic e) {
    final str = e.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(str);
    return match?.group(1) ?? 'Something went wrong.';
  }

  Future<void> _checkInvite() async {
    final token = _parseToken(_tokenCtrl.text);
    if (token == null) {
      setState(() => _error = 'Paste an invite link or token first.');
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
      _status = null;
      _token = token;
    });

    try {
      final status = await _api.getInviteStatus(token);
      if (!mounted) return;
      setState(() {
        _checking = false;
        _status = status;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = _parseError(e);
      });
    }
  }

  Future<void> _verifyInvite() async {
    if (_token == null) {
      setState(() => _error = 'Check the invite first.');
      return;
    }
    if (_passphraseCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Enter the passphrase you were given.');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final result = await _api.verifyInvite(
        token: _token!,
        passphrase: _passphraseCtrl.text.trim(),
      );
      final accessToken = result['invite_access_token']?.toString();
      final tokenId = result['token_id']?.toString();
      if (accessToken != null &&
          accessToken.isNotEmpty &&
          tokenId != null &&
          tokenId.isNotEmpty) {
        await _api.setInviteAccessToken('$tokenId:$accessToken');
      }
      if (!mounted) return;
      setState(() => _verifying = false);
      Navigator.pushReplacement(
        context,
        CupertinoPageRoute(
          builder: (_) => const OnboardingScreen(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = _parseError(e);
      });
    }
  }

  bool get _inviteUnavailable {
    if (_status == null) return false;
    return (_status!['expired'] as bool? ?? false) ||
        (_status!['revoked'] as bool? ?? false) ||
        (_status!['invalidated'] as bool? ?? false) ||
        (_status!['notFound'] as bool? ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final label = status?['label']?.toString();

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      child: Stack(
        children: [
          const Positioned.fill(child: _InviteBackdrop()),
          SafeArea(
            child: CustomScrollView(
              slivers: [
                CupertinoSliverNavigationBar(
                  largeTitle: const Text('Invite Access'),
                  previousPageTitle: 'Login',
                  backgroundColor: _withAlpha(JournalColors.bgBase, 0.9),
                  border: const Border(
                    bottom: BorderSide(color: JournalColors.border, width: 0.5),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: JournalColors.borderBright),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              _withAlpha(JournalColors.bgCard, 0.96),
                              _withAlpha(JournalColors.bgCardAlt, 0.92),
                            ],
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: JournalColors.accentGlow,
                              blurRadius: 28,
                              offset: Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: _withAlpha(JournalColors.accent, 0.18),
                                border: Border.all(
                                    color: JournalColors.borderBright),
                              ),
                              child: const Icon(
                                CupertinoIcons.link_circle_fill,
                                color: JournalColors.textPrimary,
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Private access',
                              style: TextStyle(
                                color: JournalColors.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Paste the invite link you received, check that it is still active, then enter the passphrase to continue to account setup.',
                              style: TextStyle(
                                color: JournalColors.textSecondary,
                                fontSize: 14,
                                height: 1.55,
                              ),
                            ),
                            const SizedBox(height: 18),
                            _InviteField(
                              label: 'Invite link or token',
                              child: CupertinoTextField(
                                controller: _tokenCtrl,
                                placeholder:
                                    'https://.../invite/abc123 or abc123',
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                style: const TextStyle(
                                  color: JournalColors.textPrimary,
                                  fontSize: 15,
                                ),
                                placeholderStyle: const TextStyle(
                                  color: JournalColors.textMuted,
                                  fontSize: 15,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      _withAlpha(JournalColors.bgSurface, 0.96),
                                  borderRadius: BorderRadius.circular(14),
                                  border:
                                      Border.all(color: JournalColors.border),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            AdaptiveButton(
                              style: AdaptiveButtonStyle.prominentGlass,
                              onPressed: _checking ? null : _checkInvite,
                              label: _checking ? 'Checking...' : 'Check Invite',
                            ),
                            if (status != null) ...[
                              const SizedBox(height: 18),
                              _StatusCard(
                                label: label,
                                status: status,
                              ),
                            ],
                            if (status != null && !_inviteUnavailable) ...[
                              const SizedBox(height: 18),
                              _InviteField(
                                label: 'Passphrase',
                                child: CupertinoTextField(
                                  controller: _passphraseCtrl,
                                  placeholder: 'word-word-word-1234',
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                  style: const TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 15,
                                  ),
                                  placeholderStyle: const TextStyle(
                                    color: JournalColors.textMuted,
                                    fontSize: 15,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _withAlpha(
                                        JournalColors.bgSurface, 0.96),
                                    borderRadius: BorderRadius.circular(14),
                                    border:
                                        Border.all(color: JournalColors.border),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              AdaptiveButton(
                                style: AdaptiveButtonStyle.prominentGlass,
                                onPressed: _verifying ? null : _verifyInvite,
                                label: _verifying
                                    ? 'Unlocking...'
                                    : 'Unlock Access',
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: _withAlpha(JournalColors.danger, 0.12),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color:
                                        _withAlpha(JournalColors.danger, 0.3),
                                  ),
                                ),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: JournalColors.danger,
                                    fontSize: 13,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ]),
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

class _InviteBackdrop extends StatelessWidget {
  const _InviteBackdrop();

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
            top: -60,
            right: -40,
            child: _Glow(
              size: 190,
              color: _withAlpha(JournalColors.accent, 0.16),
            ),
          ),
          Positioned(
            bottom: 120,
            left: -30,
            child: _Glow(
              size: 160,
              color: _withAlpha(JournalColors.info, 0.09),
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({
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

class _InviteField extends StatelessWidget {
  const _InviteField({
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

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.label,
    required this.status,
  });

  final String? label;
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final bool notFound = status['notFound'] as bool? ?? false;
    final bool expired = status['expired'] as bool? ?? false;
    final bool revoked = status['revoked'] as bool? ?? false;
    final bool invalidated = status['invalidated'] as bool? ?? false;

    String title = 'Invite is active';
    String body =
        'This invite can still be used. Enter the passphrase below to continue.';
    Color color = JournalColors.success;

    if (notFound) {
      title = 'Link not found';
      body = 'This invite does not exist or has already been removed.';
      color = JournalColors.danger;
    } else if (expired) {
      title = 'Invite expired';
      body = 'This link is no longer valid. Ask for a fresh invite.';
      color = JournalColors.severity;
    } else if (revoked) {
      title = 'Invite revoked';
      body = 'This invite has already been revoked by an owner.';
      color = JournalColors.danger;
    } else if (invalidated) {
      title = 'Invite invalidated';
      body =
          'This link was invalidated for security reasons and can no longer be used.';
      color = JournalColors.severity;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _withAlpha(color, 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _withAlpha(color, 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (label != null && label!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              label!,
              style: const TextStyle(
                color: JournalColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            body,
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
