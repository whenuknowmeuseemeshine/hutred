import 'package:flutter/material.dart';

import '../services/settings_store.dart';

/// Тёмная тема, цвета которой выбирает пользователь в настройках.
class HutredTheme {
  static const text = Color(0xFFF2EFE8);
  static const muted = Color(0xFF9097A6);

  /// Цвет текста поверх акцента: тёмный на светлом, белый на тёмном.
  static Color onAccent(Color accent) =>
      accent.computeLuminance() > 0.45 ? const Color(0xFF16120A) : Colors.white;

  static ThemeData build(Color accent, BackgroundPreset bg) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accent,
      onPrimary: onAccent(accent),
      secondaryContainer: Color.alphaBlend(accent.withValues(alpha: 0.22), bg.raised),
      onSecondaryContainer: text,
      surface: bg.surface,
      onSurface: text,
      surfaceContainerHighest: bg.raised,
      surfaceContainerHigh: bg.raised,
      surfaceContainer: bg.surface,
      onSurfaceVariant: muted,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg.ink,
      canvasColor: bg.ink,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: bg.ink,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: text,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bg.surface,
        indicatorColor: accent.withValues(alpha: 0.2),
        surfaceTintColor: Colors.transparent,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: bg.surface,
        indicatorColor: accent.withValues(alpha: 0.2),
      ),
      dialogTheme: DialogThemeData(backgroundColor: bg.surface),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: bg.surface),
      popupMenuTheme: PopupMenuThemeData(color: bg.raised),
      sliderTheme: base.sliderTheme.copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: text,
        inactiveTrackColor: text.withValues(alpha: 0.2),
        thumbColor: text,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }
}

String formatDuration(Duration? d) {
  if (d == null) return '–:––';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

String tracksWord(int n) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return '$n трек';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return '$n трека';
  return '$n треков';
}
