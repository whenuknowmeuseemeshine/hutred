import 'package:flutter/material.dart';

import '../theme.dart';

/// Мелкие элементы, которые выглядят по-разному в каждом стиле
/// (по макетам A · Моно, B · Стекло, C · Резкий).

/// Фишка-фильтр: капсула (Моно, Стекло) или прямоугольник (Резкий).
class StyleChip extends StatelessWidget {
  const StyleChip({super.key, required this.label, this.selected = false, this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final Color bg;
    final Color fg;
    BoxBorder? border;
    if (st.sharp) {
      bg = selected ? accent : Colors.transparent;
      fg = selected ? HutredTheme.onAccent(accent) : HutredTheme.text;
      border = Border.all(color: selected ? accent : const Color(0xFF333333));
    } else if (st.glass) {
      bg = selected ? accent.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.07);
      fg = selected ? Colors.white : const Color(0xFFB4B4C6);
    } else {
      bg = selected ? const Color(0xFFF5F5F5) : const Color(0xFF1F1F1F);
      fg = selected ? const Color(0xFF0A0A0A) : const Color(0xFFE5E5E5);
    }
    final radius = BorderRadius.circular(st.sharp ? 0 : 99);
    return Material(
      color: bg,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: border, borderRadius: radius),
          padding: EdgeInsets.symmetric(horizontal: st.sharp ? 12 : 14, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 6)],
            Text(label,
                style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: st.glass ? FontWeight.w700 : FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// Подпись раздела: «ТРЕКИ», «ДАЛЬШЕ В ВОЛНЕ».
class StyleCaption extends StatelessWidget {
  const StyleCaption(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Text(text.toUpperCase(),
        style: st.caption(
            color: color ?? (st.sharp ? accent : const Color(0xFFA3A3A3))));
  }
}

/// Карточка/панель: заливка (Моно), стекло (Стекло) или рамка (Резкий).
class StylePanel extends StatelessWidget {
  const StylePanel({super.key, required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: st.glass
            ? Colors.white.withValues(alpha: 0.05)
            : st.sharp
                ? Colors.transparent
                : const Color(0xFF141414),
        borderRadius: BorderRadius.circular(st.glass ? 22 : st.sharp ? 0 : 12),
        border: st.glass
            ? Border.all(color: Colors.white.withValues(alpha: 0.08))
            : st.sharp
                ? Border.all(color: const Color(0xFF2A2A2A))
                : null,
      ),
      child: child,
    );
  }
}

/// Кнопка в стиле: главная (цвет акцента) или второстепенная (контур).
class StyleButton extends StatelessWidget {
  const StyleButton(
      {super.key, required this.label, this.onPressed, this.icon, this.primary = true});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final shape = st.sharp ? const RoundedRectangleBorder() : const StadiumBorder();
    final child = Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 8)],
      Text(label),
    ]);
    const pad = EdgeInsets.symmetric(horizontal: 18, vertical: 14);
    if (primary) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: shape,
          padding: pad,
          backgroundColor: accent,
          foregroundColor: HutredTheme.onAccent(accent),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        shape: shape,
        padding: pad,
        foregroundColor: HutredTheme.text,
        backgroundColor: st.glass ? Colors.white.withValues(alpha: 0.06) : null,
        side: BorderSide(
            color: st.sharp ? const Color(0xFF333333) : Colors.white.withValues(alpha: 0.18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      child: child,
    );
  }
}

/// Отступы страницы по макетам: сверху у Моно больше воздуха.
EdgeInsets stylePagePadding(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= 800;
  if (!wide) return const EdgeInsets.fromLTRB(16, 8, 16, 120);
  final st = HutredStyle.of(context);
  return EdgeInsets.fromLTRB(32, st.mono ? 20 : 8, 32, 120);
}
