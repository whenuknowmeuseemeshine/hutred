import 'package:flutter/material.dart';

import '../theme.dart';

/// Цвета и формы страниц настроек по макету — для каждого стиля свои.
class Sk {
  Sk.of(BuildContext context)
      : st = HutredStyle.of(context),
        accent = Theme.of(context).colorScheme.primary;

  final HutredStyle st;
  final Color accent;

  bool get mono => st.mono;
  bool get glass => st.glass;
  bool get sharp => st.sharp;

  Color get card => sharp
      ? Colors.transparent
      : glass
          ? Colors.white.withValues(alpha: 0.07)
          : const Color(0xFF121212);
  BoxBorder? get cardBorder => sharp
      ? Border.all(color: const Color(0xFF2A2A2A))
      : glass
          ? Border.all(color: Colors.white.withValues(alpha: 0.12))
          : null;
  double get r => sharp ? 0 : glass ? 22 : 16;
  double get ri => sharp ? 0 : glass ? 14 : 10;
  double get pill => sharp ? 0 : 999;
  Color get inner => sharp
      ? const Color(0xFF121212)
      : glass
          ? Colors.white.withValues(alpha: 0.06)
          : const Color(0xFF1A1A1A);

  /// Тёмная «ниша» (превью текста, визуализации).
  Color get deep => sharp
      ? const Color(0xFF121212)
      : glass
          ? Colors.black.withValues(alpha: 0.18)
          : const Color(0xFF0B0B0B);
  Color get line => sharp
      ? const Color(0xFF222222)
      : glass
          ? Colors.white.withValues(alpha: 0.08)
          : const Color(0xFF1F1F1F);
  Color get btn => mono ? const Color(0xFFF5F5F5) : accent;
  Color get btnFg => mono ? Colors.black : HutredTheme.onAccent(accent);
  Color get ok => sharp
      ? accent
      : glass
          ? const Color(0xFF7CF0BE)
          : const Color(0xFF4ADE80);
  Color get warn => const Color(0xFFF5B84A);
  Color get bad => const Color(0xFFFF6B6B);
  Color get ghost => sharp
      ? const Color(0xFF3A3A3A)
      : glass
          ? Colors.white.withValues(alpha: 0.2)
          : const Color(0xFF333333);
  Color get off => sharp
      ? const Color(0xFF2A2A2A)
      : glass
          ? Colors.white.withValues(alpha: 0.18)
          : const Color(0xFF333333);
  Color get offKnob => sharp
      ? const Color(0xFF9E9E9E)
      : glass
          ? const Color(0xFFDFEEEA)
          : const Color(0xFFBDBDBD);
  Color get chip => sharp
      ? Colors.transparent
      : glass
          ? Colors.white.withValues(alpha: 0.10)
          : const Color(0xFF1F1F1F);
  Color get dim => sharp
      ? const Color(0xFF4A4A4A)
      : glass
          ? Colors.white.withValues(alpha: 0.35)
          : const Color(0xFF5A5A5A);
  Color get muted => sharp
      ? const Color(0xFF9E9E9E)
      : glass
          ? const Color(0xFFBCD6D2)
          : const Color(0xFF8F8F8F);
  Color get text => glass ? Colors.white : const Color(0xFFF5F5F5);

  double get titleSize => glass ? 30 : sharp ? 40 : 36;

  TextStyle get capStyle => st.caption(color: muted, size: 12).copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      );
  TextStyle get h => const TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
  TextStyle get sub => TextStyle(fontSize: 13, color: muted, height: 1.35);
  TextStyle get small => TextStyle(fontSize: 12, color: muted, height: 1.35);
  TextStyle get rowTitle => const TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
}

/// Карточка раздела.
class SkCard extends StatelessWidget {
  const SkCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final k = Sk.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: k.card,
        border: k.cardBorder,
        borderRadius: BorderRadius.circular(k.r),
      ),
      child: child,
    );
  }
}

/// Подпись раздела в карточке («ТЕКСТЫ ПЕСЕН»).
class SkCap extends StatelessWidget {
  const SkCap(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: Sk.of(context).capStyle);
}

/// Переключатель 44×26 по макету.
class SkToggle extends StatelessWidget {
  const SkToggle({super.key, required this.value, this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final k = Sk.of(context);
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      button: true,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 44,
              height: 26,
              padding: const EdgeInsets.all(3),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: value ? k.btn : k.off,
                borderRadius: BorderRadius.circular(k.pill),
              ),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: value ? k.btnFg : k.offKnob,
                  borderRadius: BorderRadius.circular(k.pill),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Заголовок карточки: название, пояснение и что-то справа.
class SkHead extends StatelessWidget {
  const SkHead({super.key, required this.title, this.sub, this.trailing});
  final String title;
  final String? sub;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final k = Sk.of(context);
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: k.h),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!, style: k.sub),
          ],
        ]),
      ),
      if (trailing != null) ...[const SizedBox(width: 12), trailing!],
    ]);
  }
}

/// Строка-плашка: название, пояснение, справа переключатель/статус.
class SkRow extends StatelessWidget {
  const SkRow({
    super.key,
    required this.title,
    this.sub,
    this.trailing,
    this.leading,
    this.filled = true,
    this.divider = false,
    this.onTap,
    this.titleColor,
  });
  final String title;
  final String? sub;
  final Widget? trailing;
  final Widget? leading;

  /// На подложке (true) или просто строкой с линией сверху.
  final bool filled;
  final bool divider;
  final VoidCallback? onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final k = Sk.of(context);
    final body = Padding(
      padding: filled
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
          : const EdgeInsets.symmetric(vertical: 11),
      child: Row(children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: k.rowTitle.copyWith(color: titleColor)),
            if (sub != null && sub!.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(sub!, style: k.small),
            ],
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ]),
    );
    final deco = filled
        ? BoxDecoration(color: k.inner, borderRadius: BorderRadius.circular(k.ri))
        : divider
            ? BoxDecoration(border: Border(top: BorderSide(color: k.line)))
            : const BoxDecoration();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(filled ? k.ri : 0),
        child: Ink(decoration: deco, child: body),
      ),
    );
  }
}

/// Кнопка по макету: заливкой (primary) или контуром.
class SkButton extends StatelessWidget {
  const SkButton(this.label,
      {super.key, this.onTap, this.primary = false, this.height = 36, this.icon, this.expand = false});
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final double height;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final k = Sk.of(context);
    final fg = primary ? k.btnFg : k.text;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(k.sharp ? 0 : height / 2),
      side: primary ? BorderSide.none : BorderSide(color: k.ghost),
    );
    final label0 = k.sharp ? label.toUpperCase() : label;
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: primary ? k.btn : Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            width: expand ? double.infinity : null,
            // Кнопка по ширине текста (Align без widthFactor растягивал её на всю строку).
            child: Align(
              widthFactor: expand ? null : 1,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
              Text(label0,
                  style: (k.sharp ? k.st.caption(color: fg, size: 12) : const TextStyle())
                      .copyWith(
                          color: fg,
                          fontSize: k.sharp ? 12 : 13,
                          fontWeight: primary ? FontWeight.w700 : FontWeight.w600)),
            ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Чип выбора (пресеты, серверы).
class SkChip extends StatelessWidget {
  const SkChip(this.label, {super.key, this.selected = false, this.onTap, this.height = 32});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final k = Sk.of(context);
    return Material(
      color: selected ? k.btn : k.chip,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(k.sharp ? 0 : height / 2),
        side: k.sharp && !selected ? BorderSide(color: k.ghost) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            widthFactor: 1,
            child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? k.btnFg : k.text)),
          ),
        ),
      ),
    );
  }
}

/// Сегменты в общей «таблетке» (масштаб, лимит кэша).
class SkSeg<T> extends StatelessWidget {
  const SkSeg({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final k = Sk.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: k.inner, borderRadius: BorderRadius.circular(k.pill)),
      child: Row(children: [
        for (final (v, l) in options) ...[
          if (v != options.first.$1) const SizedBox(width: 6),
          Expanded(
            child: Material(
              color: v == value ? k.btn : Colors.transparent,
              borderRadius: BorderRadius.circular(k.sharp ? 0 : 17),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onChanged(v),
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  child: Text(l,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: v == value ? k.btnFg : k.text)),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Точка статуса и текст («● Подключено»).
class SkStatus extends StatelessWidget {
  const SkStatus(this.text, {super.key, this.color, this.dot = true});
  final String text;
  final Color? color;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final k = Sk.of(context);
    return Text(dot ? '● $text' : text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color ?? k.ok));
  }
}

/// Карточки рядом (на узком экране — друг под другом).
class SkCols extends StatelessWidget {
  const SkCols({
    super.key,
    required this.children,
    this.flex,
    this.gap = 20,
    this.minWidth = 760,
    this.equal = false,
  });
  final List<Widget> children;
  final List<int>? flex;
  final double gap;
  final double minWidth;

  /// Одинаковая высота карточек (только для простого содержимого).
  final bool equal;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < minWidth) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) SizedBox(height: gap),
            c,
          ],
        ]);
      }
      final row = Row(
        crossAxisAlignment: equal ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(flex: flex?[i] ?? 10, child: c),
          ],
        ],
      );
      return equal ? IntrinsicHeight(child: row) : row;
    });
  }
}

/// Вертикальный набор с отступами.
class SkGap extends StatelessWidget {
  const SkGap({super.key, required this.children, this.gap = 14});
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) SizedBox(height: gap),
            c,
          ],
        ],
      );
}
