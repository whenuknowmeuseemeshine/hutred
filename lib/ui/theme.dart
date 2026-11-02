import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../services/settings_store.dart';

/// Тёмная тема, цвета которой выбирает пользователь в настройках.
class HutredTheme {
  static const text = Color(0xFFF2EFE8);
  static const muted = Color(0xFF9097A6);

  /// Цвет текста поверх акцента: тёмный на светлом, белый на тёмном.
  static Color onAccent(Color accent) =>
      accent.computeLuminance() > 0.45 ? const Color(0xFF16120A) : Colors.white;

  static bool get desktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

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
      // Без «андроидных» волн от нажатий на компьютере — только мягкая подсветка.
      splashFactory: desktop ? NoSplash.splashFactory : InkSparkle.splashFactory,
      hoverColor: Colors.white.withValues(alpha: 0.06),
      highlightColor: Colors.white.withValues(alpha: 0.04),
      fontFamily: desktop && Platform.isWindows ? 'Segoe UI' : null,
    );
    final round12 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    final round8 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    return base.copyWith(
      // Страницы с прозрачным фоном: старая быстро гаснет, новая проявляется —
      // без наложения двух страниц друг на друга.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: _FadeThrough(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: _FadeThrough(),
        TargetPlatform.linux: _FadeThrough(),
        TargetPlatform.macOS: _FadeThrough(),
      }),
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
      dialogTheme: DialogThemeData(
        backgroundColor: bg.raised,
        surfaceTintColor: Colors.transparent,
        shape: round12,
        elevation: 12,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bg.surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: bg.raised,
        surfaceTintColor: Colors.transparent,
        shape: round8,
        elevation: 8,
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        textStyle: const TextStyle(fontSize: 14, color: text),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(bg.raised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(round8),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        textStyle: const TextStyle(fontSize: 12.5, color: text),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          hoverColor: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: const StadiumBorder()),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          foregroundColor: text,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: const StadiumBorder()),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : const Color(0xFFB3B3B3)),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? accent : const Color(0xFF3E3E3E)),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        thumbIcon: const WidgetStatePropertyAll(null),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        border: UnderlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: UnderlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: UnderlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        labelStyle: const TextStyle(color: muted),
        floatingLabelStyle: TextStyle(color: accent),
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.7)),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.25)),
      ),
      dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.08)),
      sliderTheme: base.sliderTheme.copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: text,
        inactiveTrackColor: text.withValues(alpha: 0.2),
        thumbColor: text,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFEDEDED),
        contentTextStyle: const TextStyle(color: Colors.black, fontSize: 14),
        actionTextColor: Colors.black,
        shape: round8,
        width: desktop ? 420 : null,
      ),
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


/// Переход «через затухание»: уходящая страница гаснет в первой половине,
/// новая проявляется во второй. Дёшево и без просвечивания.
class _FadeThrough extends PageTransitionsBuilder {
  const _FadeThrough();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final inOpacity = CurvedAnimation(
        parent: animation, curve: const Interval(0.35, 1, curve: Curves.easeOut));
    final outOpacity = Tween<double>(begin: 1, end: 0).animate(CurvedAnimation(
        parent: secondaryAnimation, curve: const Interval(0, 0.35, curve: Curves.easeIn)));
    return FadeTransition(
      opacity: outOpacity,
      child: FadeTransition(opacity: inOpacity, child: child),
    );
  }
}
