import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── 컬러 팔레트 ──────────────────────────────────────────
  static const Color bgDark      = Color(0xFF0A0E1A);
  static const Color bgCard      = Color(0xFF111827);
  static const Color bgCardHover = Color(0xFF1A2235);
  static const Color borderColor = Color(0xFF1E293B);
  static const Color accentCyan  = Color(0xFF00D4FF);
  static const Color accentBlue  = Color(0xFF3B82F6);
  static const Color accentGreen = Color(0xFF10B981);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color textPrimary = Color(0xFFE2E8F0);
  static const Color textSecond  = Color(0xFF94A3B8);
  static const Color textMuted   = Color(0xFF475569);
  static const Color userBubble  = Color(0xFF1E3A5F);
  static const Color aiBubble    = Color(0xFF0F2027);

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bgDark,
    colorScheme: const ColorScheme.dark(
      primary: accentCyan,
      secondary: accentBlue,
      surface: bgCard,
      background: bgDark,
      onPrimary: bgDark,
      onSecondary: Colors.white,
      onSurface: textPrimary,
    ),
    textTheme: GoogleFonts.spaceGroteskTextTheme(
      const TextTheme(
        displayLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
        displayMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: textPrimary, fontSize: 15, height: 1.6),
        bodyMedium: TextStyle(color: textSecond, fontSize: 13, height: 1.5),
        labelLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: CardThemeData(
      color: bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: borderColor),
      ),
    ),
    dividerTheme: const DividerThemeData(color: borderColor),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: bgCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: accentCyan, width: 1.5),
      ),
      hintStyle: const TextStyle(color: textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
