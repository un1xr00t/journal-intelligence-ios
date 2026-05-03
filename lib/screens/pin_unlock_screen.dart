import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/journal_pin_service.dart';
import '../theme/app_theme.dart';

Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);

enum PinUnlockScreenMode { unlock, create }

class PinUnlockScreen extends StatefulWidget {
  const PinUnlockScreen({
    super.key,
    required this.mode,
    this.username,
    this.onUnlock,
    this.onSignOut,
    this.allowDismiss = false,
  });

  const PinUnlockScreen.unlock({
    super.key,
    this.username,
    required Future<bool> Function(String pin) this.onUnlock,
    this.onSignOut,
  })  : mode = PinUnlockScreenMode.unlock,
        allowDismiss = false;

  const PinUnlockScreen.create({
    super.key,
    this.username,
    this.allowDismiss = true,
  })  : mode = PinUnlockScreenMode.create,
        onUnlock = null,
        onSignOut = null;

  final PinUnlockScreenMode mode;
  final String? username;
  final Future<bool> Function(String pin)? onUnlock;
  final Future<void> Function()? onSignOut;
  final bool allowDismiss;

  @override
  State<PinUnlockScreen> createState() => _PinUnlockScreenState();
}

enum _CreateStage { enter, confirm }

class _PinUnlockScreenState extends State<PinUnlockScreen> {
  String _digits = '';
  String? _firstEntry;
  _CreateStage _createStage = _CreateStage.enter;
  String? _error;
  bool _submitting = false;

  bool get _isCreateMode => widget.mode == PinUnlockScreenMode.create;

  String get _title {
    if (!_isCreateMode) return 'Unlock Journal';
    return _createStage == _CreateStage.enter
        ? 'Create Journal PIN'
        : 'Confirm Journal PIN';
  }

  String get _subtitle {
    if (!_isCreateMode) {
      final user = widget.username?.trim();
      if (user != null && user.isNotEmpty) {
        return 'Enter your 4-digit PIN to reopen $user\'s journal on this device.';
      }
      return 'Enter your 4-digit PIN to reopen this journal on this device.';
    }
    if (_createStage == _CreateStage.enter) {
      return 'Choose a 4-digit PIN that will be required before a restored journal session can reopen.';
    }
    return 'Re-enter the same 4 digits to finish turning on the local unlock gate.';
  }

  String get _helperText {
    if (_submitting) {
      return _isCreateMode ? 'Saving PIN...' : 'Checking PIN...';
    }
    return _error ??
        (_isCreateMode
            ? (_createStage == _CreateStage.enter
                ? 'This PIN lives on this device only.'
                : 'Use the same 4 digits again.')
            : 'This only appears when the device already has a restorable journal session.');
  }

  Future<void> _handleDigit(String digit) async {
    if (_submitting || _digits.length >= JournalPinService.pinLength) return;
    setState(() {
      _digits += digit;
      _error = null;
    });
    if (_digits.length == JournalPinService.pinLength) {
      await Future<void>.delayed(const Duration(milliseconds: 90));
      if (mounted) {
        await _submitDigits();
      }
    }
  }

  void _handleDelete() {
    if (_submitting || _digits.isEmpty) return;
    setState(() {
      _digits = _digits.substring(0, _digits.length - 1);
      _error = null;
    });
  }

  Future<void> _submitDigits() async {
    final currentPin = _digits;
    if (_isCreateMode) {
      if (_createStage == _CreateStage.enter) {
        setState(() {
          _firstEntry = currentPin;
          _digits = '';
          _createStage = _CreateStage.confirm;
          _error = null;
        });
        return;
      }
      if (currentPin != _firstEntry) {
        setState(() {
          _digits = '';
          _firstEntry = null;
          _createStage = _CreateStage.enter;
          _error = 'Those PINs did not match. Try again.';
        });
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop(currentPin);
      return;
    }

    final onUnlock = widget.onUnlock;
    if (onUnlock == null) return;

    setState(() => _submitting = true);
    final unlocked = await onUnlock(currentPin);
    if (!mounted) return;
    if (unlocked) {
      setState(() {
        _submitting = false;
        _digits = '';
      });
      return;
    }
    setState(() {
      _submitting = false;
      _digits = '';
      _error = 'That PIN is not correct.';
    });
  }

  Future<void> _handleSignOut() async {
    final signOut = widget.onSignOut;
    if (signOut == null || _submitting) return;
    setState(() => _submitting = true);
    await signOut();
    if (!mounted) return;
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JournalColors.bgBase,
      body: Stack(
        children: [
          const Positioned.fill(child: _PinBackdrop()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth > 540
                    ? 500.0
                    : constraints.maxWidth - 32;
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Column(
                        children: [
                          if (widget.allowDismiss)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 0,
                                  vertical: 0,
                                ),
                                onPressed: _submitting
                                    ? null
                                    : () => Navigator.of(context).maybePop(),
                                child: const Icon(
                                  CupertinoIcons.chevron_back,
                                  color: JournalColors.textSecondary,
                                  size: 22,
                                ),
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                color: JournalColors.borderBright,
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  _withAlpha(JournalColors.bgCard, 0.97),
                                  _withAlpha(const Color(0xFF10172E), 0.93),
                                  _withAlpha(const Color(0xFF190F24), 0.88),
                                ],
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: JournalColors.accentGlow,
                                  blurRadius: 34,
                                  offset: Offset(0, 18),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        _withAlpha(JournalColors.accent, 0.54),
                                        _withAlpha(JournalColors.accent2, 0.34),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: _withAlpha(
                                        JournalColors.textPrimary,
                                        0.10,
                                      ),
                                    ),
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.lock_shield_fill,
                                    color: JournalColors.textPrimary,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  _title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: JournalColors.textPrimary,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _subtitle,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: JournalColors.textSecondary,
                                    fontSize: 14,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 22),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 18,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _withAlpha(Colors.white, 0.04),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: _withAlpha(Colors.white, 0.08),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      _PinDots(
                                        length: _digits.length,
                                        filledColor: _error == null
                                            ? JournalColors.accent
                                            : JournalColors.danger,
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        _helperText,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: _error == null
                                              ? JournalColors.textMuted
                                              : JournalColors.danger,
                                          fontSize: 12,
                                          height: 1.4,
                                          fontWeight: _error == null
                                              ? FontWeight.w500
                                              : FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          _PinKeypad(
                            onDigit: _handleDigit,
                            onDelete: _handleDelete,
                            deleteEnabled: _digits.isNotEmpty,
                            disabled: _submitting,
                          ),
                          const SizedBox(height: 16),
                          if (!_isCreateMode && widget.onSignOut != null)
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: _submitting ? null : _handleSignOut,
                              child: const Text(
                                'Sign out instead',
                                style: TextStyle(
                                  color: JournalColors.textSecondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PinBackdrop extends StatelessWidget {
  const _PinBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            JournalColors.bgBase,
            _withAlpha(const Color(0xFF0B1022), 0.96),
            JournalColors.bgBase,
          ],
        ),
      ),
      child: const Stack(
        children: [
          Positioned(
            top: -40,
            left: -30,
            child: _PinGlow(size: 220, color: JournalColors.accent),
          ),
          Positioned(
            top: 180,
            right: -50,
            child: _PinGlow(size: 240, color: JournalColors.accent2),
          ),
          Positioned(
            bottom: -30,
            left: 40,
            child: _PinGlow(size: 180, color: JournalColors.info),
          ),
        ],
      ),
    );
  }
}

class _PinGlow extends StatelessWidget {
  const _PinGlow({
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
              _withAlpha(color, 0.22),
              _withAlpha(color, 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.length,
    required this.filledColor,
  });

  final int length;
  final Color filledColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(
        JournalPinService.pinLength,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: index < length
                ? filledColor
                : _withAlpha(JournalColors.textMuted, 0.26),
            border: Border.all(
              color: index < length
                  ? _withAlpha(filledColor, 0.84)
                  : _withAlpha(JournalColors.textMuted, 0.18),
            ),
            boxShadow: index < length
                ? [
                    BoxShadow(
                      color: _withAlpha(filledColor, 0.24),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

class _PinKeypad extends StatelessWidget {
  const _PinKeypad({
    required this.onDigit,
    required this.onDelete,
    required this.deleteEnabled,
    required this.disabled,
  });

  final Future<void> Function(String digit) onDigit;
  final VoidCallback onDelete;
  final bool deleteEnabled;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'delete'],
    ];

    return Column(
      children: rows
          .map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: row.map((item) {
                  if (item.isEmpty) {
                    return const SizedBox(width: 96, height: 76);
                  }
                  if (item == 'delete') {
                    return _PinKeypadButton.icon(
                      icon: CupertinoIcons.delete_left,
                      enabled: deleteEnabled && !disabled,
                      onPressed: onDelete,
                    );
                  }
                  return _PinKeypadButton(
                    label: item,
                    enabled: !disabled,
                    onPressed: () => unawaited(onDigit(item)),
                  );
                }).toList(),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _PinKeypadButton extends StatelessWidget {
  const _PinKeypadButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  })  : icon = null,
        isIcon = false;

  const _PinKeypadButton.icon({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  })  : label = null,
        isIcon = true;

  final String? label;
  final IconData? icon;
  final bool enabled;
  final VoidCallback onPressed;
  final bool isIcon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled
                ? _withAlpha(JournalColors.bgCardAlt, 0.96)
                : _withAlpha(JournalColors.bgCardAlt, 0.42),
            border: Border.all(
              color: enabled
                  ? _withAlpha(JournalColors.borderBright, 0.92)
                  : _withAlpha(JournalColors.border, 0.56),
            ),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: _withAlpha(JournalColors.accentGlow, 0.55),
                      blurRadius: 18,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: isIcon
                ? Icon(
                    icon,
                    color: enabled
                        ? JournalColors.textPrimary
                        : JournalColors.textMuted,
                    size: 24,
                  )
                : Text(
                    label!,
                    style: TextStyle(
                      color: enabled
                          ? JournalColors.textPrimary
                          : JournalColors.textMuted,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
