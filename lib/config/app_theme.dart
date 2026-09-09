import 'package:flutter/material.dart';

/// AppTheme — Sistem Desain Terpadu (Material 3) untuk Kiosk Presensi Wajah
/// Standar Modern Enterprise Gov-Tech (Diskominfo Smart City).
class AppTheme {
  AppTheme._();

  // ===========================================================================
  // 1. PALET WARNA (Modern Enterprise Palette)
  // ===========================================================================
  
  // Brand & Primary
  static const Color primary = Color(0xFF2563EB);        // Royal Blue
  static const Color primaryDark = Color(0xFF1D4ED8);    // Sapphire Deep
  static const Color primaryLight = Color(0xFFDBEAFE);   // Tint Light Highlight
  static const Color primarySubtle = Color(0xFFEFF6FF);  // Soft Inset Active

  // Surfaces & Backgrounds (Light Mode)
  static const Color backgroundLight = Color(0xFFF8FAFC); // Slate 50
  static const Color surfaceLight = Color(0xFFFFFFFF);    // Pure White
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color fillLight = Color(0xFFF1F5F9);       // Slate 100 (Input field fill)
  static const Color borderLight = Color(0xFFE2E8F0);     // Slate 200 (Subtle border)

  // Surfaces & Backgrounds (Dark / Kiosk Mode)
  static const Color backgroundDark = Color(0xFF0F172A);  // Slate 950 (Kiosk Dark Canvas)
  static const Color surfaceDark = Color(0xFF1E293B);     // Slate 800 (Elevated Panel)
  static const Color cardDark = Color(0xFF1E293B);
  static const Color fillDark = Color(0xFF334155);        // Slate 700 (Input dark fill)
  static const Color borderDark = Color(0xFF334155);      // Slate 700 (Subtle border)

  // Typography & Neutrals
  static const Color textPrimary = Color(0xFF0F172A);     // Slate 900
  static const Color textSecondary = Color(0xFF475569);   // Slate 600
  static const Color textMuted = Color(0xFF94A3B8);       // Slate 400
  static const Color textLight = Color(0xFFF8FAFC);       // Slate 50 (Dark mode primary)

  // Functional & Status Colors (Presensi Biometrik)
  static const Color success = Color(0xFF10B981);         // Emerald Green (On Time / Face Match)
  static const Color successBg = Color(0xFFECFDF5);       // Emerald 50
  static const Color error = Color(0xFFEF4444);           // Crimson Red (Late / Unknown Face)
  static const Color errorBg = Color(0xFFFEF2F2);         // Red 50
  static const Color warning = Color(0xFFF59E0B);         // Amber (Non-ASN / Pending Approval)
  static const Color warningBg = Color(0xFFFFFBEB);       // Amber 50
  static const Color info = Color(0xFF0EA5E9);            // Sky Cyan (Device Online / Heartbeat)
  static const Color infoBg = Color(0xFFF0F9FF);          // Sky 50

  // ===========================================================================
  // 2. LIGHT THEME CONFIGURATION
  // ===========================================================================
  static ThemeData get lightTheme {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primarySubtle,
      onPrimaryContainer: primaryDark,
      secondary: primaryDark,
      onSecondary: Colors.white,
      secondaryContainer: primaryLight,
      onSecondaryContainer: primaryDark,
      surface: surfaceLight,
      onSurface: textPrimary,
      surfaceContainerHighest: fillLight,
      error: error,
      onError: Colors.white,
      outline: borderLight,
      outlineVariant: borderLight,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundLight,
      fontFamily: 'Roboto',

      // --- AppBar Theme ---
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: surfaceLight,
        foregroundColor: textPrimary,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),

      // --- Card Theme (Flat Clean with subtle border) ---
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardLight,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderLight, width: 1),
        ),
      ),

      // --- InputDecoration Theme (Seamless rounded filled style) ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fillLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: const TextStyle(
          color: textMuted,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: const TextStyle(
          color: textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderLight, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderLight, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 1.8),
        ),
      ),

      // --- ElevatedButton Theme (Modern Flat Accent) ---
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: primary.withOpacity(0.4),
          disabledForegroundColor: Colors.white.withOpacity(0.8),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // --- OutlinedButton Theme ---
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          elevation: 0,
          foregroundColor: primary,
          side: const BorderSide(color: borderLight, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // --- TextButton Theme ---
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // --- Dialog Theme ---
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderLight, width: 1),
        ),
        titleTextStyle: const TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(
          color: textSecondary,
          fontSize: 14,
          height: 1.5,
        ),
      ),

      // --- Chip Theme (Status / Role Pill) ---
      chipTheme: ChipThemeData(
        backgroundColor: fillLight,
        disabledColor: fillLight,
        selectedColor: primarySubtle,
        secondarySelectedColor: primarySubtle,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textSecondary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: borderLight, width: 1),
        ),
      ),
    );
  }

  // ===========================================================================
  // 3. DARK / KIOSK NIGHT THEME CONFIGURATION
  // ===========================================================================
  static ThemeData get darkTheme {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF1E3A8A),
      onPrimaryContainer: Colors.white,
      secondary: Color(0xFF60A5FA),
      onSecondary: Colors.black,
      surface: surfaceDark,
      onSurface: textLight,
      surfaceContainerHighest: fillDark,
      error: error,
      onError: Colors.white,
      outline: borderDark,
      outlineVariant: borderDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundDark,
      fontFamily: 'Roboto',

      // --- AppBar Theme ---
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: surfaceDark,
        foregroundColor: textLight,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textLight,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: textLight),
      ),

      // --- Card Theme ---
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardDark,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderDark, width: 1),
        ),
      ),

      // --- InputDecoration Theme ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fillDark,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: const TextStyle(
          color: textMuted,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: const TextStyle(
          color: textLight,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderDark, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderDark, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 1.8),
        ),
      ),

      // --- ElevatedButton Theme ---
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: primary.withOpacity(0.3),
          disabledForegroundColor: Colors.white.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // --- Dialog Theme ---
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: surfaceDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderDark, width: 1),
        ),
        titleTextStyle: const TextStyle(
          color: textLight,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(
          color: textMuted,
          fontSize: 14,
          height: 1.5,
        ),
      ),
    );
  }
}
