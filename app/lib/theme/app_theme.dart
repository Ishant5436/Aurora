import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Typography: Cinzel for headings, Cormorant Garamond for reading text and
/// DM Sans for UI chrome, as in the Lovable design.
class Typo {
  /// Widget tests switch this off so they never fetch fonts over the network.
  static bool useGoogleFonts = true;

  static TextStyle display(double size, {Color? color, double? letterSpacing, FontWeight? weight}) {
    final base = TextStyle(
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: letterSpacing ?? size * 0.04,
    );
    return useGoogleFonts ? GoogleFonts.cinzel(textStyle: base) : base.copyWith(fontFamily: 'serif');
  }

  static TextStyle serif(double size, {Color? color, bool italic = false, FontWeight? weight}) {
    final base = TextStyle(
      fontSize: size,
      color: color,
      fontWeight: weight,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      height: 1.25,
    );
    return useGoogleFonts ? GoogleFonts.cormorantGaramond(textStyle: base) : base.copyWith(fontFamily: 'serif');
  }

  static TextStyle sans(double size, {Color? color, FontWeight? weight, double? letterSpacing}) {
    final base = TextStyle(fontSize: size, color: color, fontWeight: weight, letterSpacing: letterSpacing);
    return useGoogleFonts ? GoogleFonts.dmSans(textStyle: base) : base;
  }
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AuroraColors.dark : AuroraColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    secondary: c.accent,
    onSecondary: c.onPrimary,
    error: c.accent,
    onError: c.onPrimary,
    surface: c.card,
    onSurface: c.foreground,
  );
  final base = ThemeData(brightness: brightness, colorScheme: scheme, useMaterial3: true);
  // google_fonts 9 returns a TextTheme from its own material package, so the
  // theme's styles are assembled from the plain TextStyle helpers instead.
  final textTheme = base.textTheme.copyWith(
    bodyLarge: Typo.sans(16),
    bodyMedium: Typo.sans(14),
    bodySmall: Typo.sans(12),
    titleMedium: Typo.sans(16),
    titleSmall: Typo.sans(14),
    labelLarge: Typo.sans(14, weight: FontWeight.w600),
    labelMedium: Typo.sans(12),
  );
  final border = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(2),
    side: BorderSide(color: c.border),
  );

  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    textTheme: textTheme.apply(bodyColor: c.foreground, displayColor: c.foreground),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    extensions: [c],
    sliderTheme: SliderThemeData(
      trackHeight: 2,
      activeTrackColor: c.primary,
      inactiveTrackColor: c.border,
      thumbColor: c.primary,
      overlayColor: c.primary.withValues(alpha: 0.12),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.card,
      contentTextStyle: Typo.sans(14, color: c.foreground),
      behavior: SnackBarBehavior.floating,
      shape: border,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.card,
      shape: border,
      titleTextStyle: Typo.display(18, color: c.primary),
      contentTextStyle: Typo.serif(18, color: c.foreground),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.card,
      modalBackgroundColor: c.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(8))),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.primary,
      selectionHandleColor: c.primary,
      selectionColor: c.primary.withValues(alpha: 0.25),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
  );
}
