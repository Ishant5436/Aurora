import 'package:flutter/material.dart';

/// Renaissance palette. The dark values come straight from the Lovable
/// prototype's CSS (#111014 ink, #F0DFC4 parchment, #D6B48A gold, #B97556
/// terracotta); the light "sunlit parchment" values are its oklch tokens
/// converted to sRGB.
@immutable
class AuroraColors extends ThemeExtension<AuroraColors> {
  const AuroraColors({
    required this.background,
    required this.foreground,
    required this.card,
    required this.primary,
    required this.onPrimary,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.parchment,
    required this.border,
    required this.silkTop,
    required this.silkBottom,
    required this.silkGlow,
  });

  final Color background;
  final Color foreground;
  final Color card;
  final Color primary;
  final Color onPrimary;
  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color parchment;
  final Color border;
  final Color silkTop;
  final Color silkBottom;
  final Color silkGlow;

  static const dark = AuroraColors(
    background: Color(0xFF111014),
    foreground: Color(0xFFF0DFC4),
    card: Color(0xFF242127),
    primary: Color(0xFFD6B48A),
    onPrimary: Color(0xFF111014),
    muted: Color(0xFF1D1B20),
    mutedForeground: Color(0xFFB3A58E),
    accent: Color(0xFFB97556),
    parchment: Color(0xFFF0DFC4),
    border: Color(0x59D6B48A),
    silkTop: Color(0xFF19171C),
    silkBottom: Color(0xFF0E0D10),
    silkGlow: Color(0xFF26232A),
  );

  static const light = AuroraColors(
    background: Color(0xFFF6F0E2),
    foreground: Color(0xFF3A353D),
    card: Color(0xFFFCFAF4),
    primary: Color(0xFFAA7C48),
    onPrimary: Color(0xFFFCF8EE),
    muted: Color(0xFFEDE6D6),
    mutedForeground: Color(0xFF6F6455),
    accent: Color(0xFFB0603B),
    parchment: Color(0xFF4B4234),
    border: Color(0x66AA7C48),
    silkTop: Color(0xFFFAF5E9),
    silkBottom: Color(0xFFEEE6D3),
    silkGlow: Color(0xFFFCF9F0),
  );

  /// Soft golden halo used behind hero elements.
  List<BoxShadow> get glow => [
        BoxShadow(color: primary.withValues(alpha: 0.45), blurRadius: 40, spreadRadius: -6),
      ];

  @override
  AuroraColors copyWith({
    Color? background,
    Color? foreground,
    Color? card,
    Color? primary,
    Color? onPrimary,
    Color? muted,
    Color? mutedForeground,
    Color? accent,
    Color? parchment,
    Color? border,
    Color? silkTop,
    Color? silkBottom,
    Color? silkGlow,
  }) {
    return AuroraColors(
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
      card: card ?? this.card,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      muted: muted ?? this.muted,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      accent: accent ?? this.accent,
      parchment: parchment ?? this.parchment,
      border: border ?? this.border,
      silkTop: silkTop ?? this.silkTop,
      silkBottom: silkBottom ?? this.silkBottom,
      silkGlow: silkGlow ?? this.silkGlow,
    );
  }

  @override
  AuroraColors lerp(ThemeExtension<AuroraColors>? other, double t) {
    if (other is! AuroraColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AuroraColors(
      background: mix(background, other.background),
      foreground: mix(foreground, other.foreground),
      card: mix(card, other.card),
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      muted: mix(muted, other.muted),
      mutedForeground: mix(mutedForeground, other.mutedForeground),
      accent: mix(accent, other.accent),
      parchment: mix(parchment, other.parchment),
      border: mix(border, other.border),
      silkTop: mix(silkTop, other.silkTop),
      silkBottom: mix(silkBottom, other.silkBottom),
      silkGlow: mix(silkGlow, other.silkGlow),
    );
  }
}

extension AuroraContext on BuildContext {
  AuroraColors get colors => Theme.of(this).extension<AuroraColors>()!;
}
