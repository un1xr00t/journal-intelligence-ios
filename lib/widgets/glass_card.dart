// lib/widgets/glass_card.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.accentBorder = false,
    this.padding,
    this.onTap,
  });

  final Widget child;
  final bool accentBorder;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: JournalColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentBorder ? JournalColors.borderBright : JournalColors.border,
          width: accentBorder ? 1.5 : 1.0,
        ),
        boxShadow: accentBorder
            ? const [
                BoxShadow(
                  color: JournalColors.accentGlow,
                  blurRadius: 16,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: card);
    }
    return card;
  }
}
