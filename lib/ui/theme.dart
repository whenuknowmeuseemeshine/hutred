import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../services/settings_store.dart';

/// Стиль оформления (Моно / Стекло / Резкий): шрифты и формы.
/// Достаётся через `HutredStyle.of(context)`.
class HutredStyle extends ThemeExtension<HutredStyle> {
  const HutredStyle({
    required this.id,
    required this.font,
    required this.displayFont,
    required this.radius,
    required this.cardRadius,
    required this.artScale,
  });

  final String id;

  /// Основной шрифт и шрифт крупных заголовков.
  final String font;
  final String displayFont;

  /// Скругление строк, полей и кнопок-плашек; карточек и окон.
  final double radius;
  final double cardRadius;

  /// Во сколько раз скруглять обложки (0 — острые углы).
  final double artScale;

  bool get glass => id == 'glass';
  bool get mono => id == 'mono';
  bool get sharp => id == 'sharp';

  static const monoStyle = HutredStyle(
      id: 'mono', font: 'Inter', displayFont: 'Inter', radius: 8, cardRadius: 12, artScale: 1);
  static const glassStyle = HutredStyle(
      id: 'glass', font: 'Manrope', displayFont: 'Manrope', radius: 14, cardRadius: 22, artScale: 2);
  static const sharpStyle = HutredStyle(
      id: 'sharp', font: 'Inter', displayFont: 'Unbounded', radius: 0, cardRadius: 0, artScale: 0);

  static HutredStyle byId(String id) => switch (id) {
        'glass' => glassStyle,
        'sharp' => sharpStyle,
        _ => monoStyle,
      };

  static HutredStyle of(BuildContext context) =>
      Theme.of(context).extension<HutredStyle>() ?? monoStyle;

  /// Стиль крупного заголовка экрана (название плейлиста, «Моя волна»).
  TextStyle display(double size) => TextStyle(
        fontFamily: displayFont,
        fontSize: sharp ? size * 0.82 : size,
        fontWeight: sharp ? FontWeight.w700 : FontWeight.w800,
        letterSpacing: sharp ? -size * 0.03 : -size * 0.035,
        height: 1.05,
      );

  /// Форма кнопок: капсула или прямоугольник.
  OutlinedBorder get buttonShape => sharp
      ? const RoundedRectangleBorder()
      : const StadiumBorder();

  @override
  HutredStyle copyWith() => this;

  @override
  HutredStyle lerp(HutredStyle? other, double t) => t < 0.5 ? this : (other ?? this);
}

/// Тёмная тема, цвета которой выбирает пользователь в настройках.
class HutredTheme {
  static const text = Color(0xFFF2EFE8);
  static const muted = Color(0xFF9097A6);

  /// Цвет текста поверх акцента: тёмный на светлом, белый на тёмном.
  static Color onAccent(Color accent) =>
      accent.computeLuminance() > 0.45 ? const Color(0xFF16120A) : Colors.white;

  static bool get desktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  static ThemeData build(Color accent, BackgroundPreset bg, [String styleId = 'mono']) {
    final style = HutredStyle.byId(styleId);
    // У «Стекла» страницы прозрачные: под ними светящийся фон.
    final page = style.glass ? Colors.transparent : bg.ink;
    final panel = style.glass ? Colors.white.withValues(alpha: 0.04) : bg.surface;
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
      scaffoldBackgroundColor: page,
      canvasColor: bg.ink,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      // Без «андроидных» волн от нажатий на компьютере — только мягкая подсветка.
      splashFactory: desktop ? NoSplash.splashFactory : InkSparkle.splashFactory,
      hoverColor: Colors.white.withValues(alpha: 0.06),
      highlightColor: Colors.white.withValues(alpha: 0.04),
      fontFamily: style.font,
    );
    final round12 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(style.cardRadius));
    final round8 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(style.radius));
    final indicator = style.sharp ? accent : Colors.white.withValues(alpha: style.glass ? 0.12 : 0.10);
    final indicatorShape = style.sharp
        ? const RoundedRectangleBorder()
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(style.glass ? 14 : 8));
    final onIndicator = style.sharp ? onAccent(accent) : text;
    return base.copyWith(
      extensions: [style],
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
        backgroundColor: page,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: style.display(28).copyWith(color: text),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: style.glass ? Colors.black.withValues(alpha: 0.35) : bg.surface,
        indicatorColor: indicator,
        indicatorShape: indicatorShape,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? onIndicator : muted)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: panel,
        indicatorColor: indicator,
        indicatorShape: indicatorShape,
        selectedIconTheme: IconThemeData(color: onIndicator),
        unselectedIconTheme: const IconThemeData(color: muted),
        selectedLabelTextStyle:
            const TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelTextStyle:
            const TextStyle(color: muted, fontWeight: FontWeight.w500, fontSize: 14),
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
          borderRadius: BorderRadius.circular(style.sharp ? 0 : 6),
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
        style: FilledButton.styleFrom(
          shape: style.buttonShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: style.buttonShape,
          foregroundColor: text,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: style.buttonShape),
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
          borderRadius: BorderRadius.circular(style.radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: UnderlineInputBorder(
          borderRadius: BorderRadius.circular(style.radius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: UnderlineInputBorder(
          borderRadius: BorderRadius.circular(style.radius),
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
        trackHeight: style.sharp ? 2 : style.glass ? 5 : 4,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: style.sharp ? 0 : 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: style.mono ? text : accent,
        inactiveTrackColor: text.withValues(alpha: 0.2),
        thumbColor: style.mono ? text : accent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFEDEDED),
        contentTextStyle: const TextStyle(color: Colors.black, fontSize: 14),
        actionTextColor: Colors.black,
        shape: round8,
        width: desktop ? 420 : null,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: round8,
      ),
      cardTheme: CardThemeData(
        color: style.glass ? Colors.white.withValues(alpha: 0.06) : bg.raised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: round12,
      ),
      chipTheme: ChipThemeData(
        shape: style.sharp ? const RoundedRectangleBorder() : const StadiumBorder(),
        side: BorderSide(color: Colors.white.withValues(alpha: style.sharp ? 0.2 : 0.1)),
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
