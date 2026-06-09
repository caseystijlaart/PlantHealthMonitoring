import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

ThemeData buildAppTheme(TargetPlatform platform) {
  final isDesktop = platform == TargetPlatform.windows ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.linux;

  final base = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.bg,
      secondary: AppColors.accentDim,
      surface: AppColors.surface,
      onSurface: AppColors.textHigh,
      outline: AppColors.border,
    ),
    platform: platform,
    useMaterial3: true,
    visualDensity: isDesktop ? VisualDensity.compact : VisualDensity.standard,
  );

  final outfitText = GoogleFonts.outfitTextTheme(base.textTheme)
      .apply(bodyColor: AppColors.textMid, displayColor: AppColors.textHigh);

  return base.copyWith(
    textTheme: outfitText,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: GoogleFonts.outfit(
        color: AppColors.textHigh,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      iconTheme: const IconThemeData(color: AppColors.textMid),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: GoogleFonts.outfit(color: AppColors.textMid, fontSize: 14),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      labelStyle: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: const Color(0xFF1C3D28),
      side: const BorderSide(color: AppColors.border),
      labelStyle: GoogleFonts.outfit(color: AppColors.textMid, fontSize: 13),
      secondaryLabelStyle: GoogleFonts.outfit(
        color: AppColors.accent,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      checkmarkColor: AppColors.accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.bg,
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textMid,
        side: const BorderSide(color: AppColors.border),
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w400, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFF2A3D2E), thickness: 1),
  );
}
