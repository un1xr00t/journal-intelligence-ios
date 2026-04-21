// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

class JournalColors {
  // ── Core backgrounds (matches web CSS vars) ─────────────────
  static const bgBase = Color(0xFF07070F);
  static const bgSurface = Color(0xFF0C0C18);
  static const bgCard = Color(0xFF10101E);
  static const bgCardAlt = Color(0xFF13131F);

  // ── Accent ──────────────────────────────────────────────────
  static const accent = Color(0xFF6366F1); // indigo
  static const accent2 = Color(0xFF8B5CF6); // purple
  static const accentGlow = Color(0x336366F1);

  // ── Text ────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFE8E8F0);
  static const textSecondary = Color(0xFF9898B0);
  static const textMuted = Color(0xFF55556A);

  // ── Borders ─────────────────────────────────────────────────
  static const border = Color(0x1F6366F1); // rgba(99,102,241,0.12)
  static const borderBright = Color(0x4D6366F1); // rgba(99,102,241,0.3)

  // ── Severity / warning ───────────────────────────────────────
  static const severity = Color(0xFFF59E0B);
  static const success = Color(0xFF22C55E);
  static const danger = Color(0xFFEF4444);
  static const orange = Color(0xFFF97316);
  static const info = Color(0xFF3B82F6);

  // ── Glass overlay (Liquid Glass substrate) ──────────────────
  static const glassBg = Color(0x2210101E);
  static const glassBorder = Color(0x336366F1);
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: JournalColors.bgBase,
      colorScheme: const ColorScheme.dark(
        primary: JournalColors.accent,
        secondary: JournalColors.accent2,
        surface: JournalColors.bgSurface,
        onPrimary: Colors.white,
        onSurface: JournalColors.textPrimary,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
            color: JournalColors.textPrimary, fontWeight: FontWeight.w700),
        displayMedium: TextStyle(
            color: JournalColors.textPrimary, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: JournalColors.textPrimary, height: 1.6),
        bodyMedium: TextStyle(color: JournalColors.textSecondary, height: 1.5),
        bodySmall: TextStyle(color: JournalColors.textMuted),
        labelLarge: TextStyle(
            color: JournalColors.textPrimary, fontWeight: FontWeight.w600),
      ),
      dividerColor: JournalColors.border,
      cardColor: JournalColors.bgCard,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: JournalColors.bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: JournalColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: JournalColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: JournalColors.accent, width: 1.5),
        ),
        labelStyle: const TextStyle(color: JournalColors.textSecondary),
        hintStyle: const TextStyle(color: JournalColors.textMuted),
      ),
    );
  }
}
