import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/account_service.dart';
import 'theme.dart';
import 'widgets/account_button.dart';
import 'widgets/logo.dart';

/// Вкладка для меню: id, значок, подпись.
typedef NavItem = ({String id, IconData icon, String label});

const _ink2 = Color(0xFF1A1A1A);

// ======================================================================
// A · Моно: боковая панель со словами, «Настройки» — внизу.
// ======================================================================

class MonoSidebar extends StatelessWidget {
  const MonoSidebar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.compact,
  });

  final List<NavItem> items;
  final String selected;
  final ValueChanged<String> onSelect;

  /// Узкое окно: только значки.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final top = items.where((i) => i.id != 'settings').toList();
    final settings = items.where((i) => i.id == 'settings').toList();
    Widget tile(NavItem i) => _MonoNavTile(
          item: i,
          selected: i.id == selected,
          compact: compact,
          onTap: () => onSelect(i.id),
        );
    return Container(
      width: compact ? 76 : 232,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFF1C1C1C))),
      ),
      padding: EdgeInsets.fromLTRB(12, MediaQuery.paddingOf(context).top + 18, 12, 16),
      child: Column(
        crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 0 : 10, 0, 0, 14),
            child: Row(
              mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                const HutredLogo(size: 30),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  const Text('Hutred',
                      style: TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                ],
              ],
            ),
          ),
          Align(
            alignment: compact ? Alignment.center : Alignment.centerLeft,
            child: AccountButton(extended: !compact),
          ),
          const SizedBox(height: 14),
          for (final i in top) tile(i),
          const Spacer(),
          for (final i in settings) tile(i),
        ],
      ),
    );
  }
}

class _MonoNavTile extends StatelessWidget {
  const _MonoNavTile({
    required this.item,
    required this.selected,
    required this.compact,
    required this.onTap,
  });
  final NavItem item;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? HutredTheme.text : const Color(0xFFA3A3A3);
    final child = Material(
      color: selected ? _ink2 : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: 10),
          child: Row(
            mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(item.icon, size: 20, color: color),
              if (!compact) ...[
                const SizedBox(width: 12),
                Text(item.label,
                    style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
              ],
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: compact
          ? Tooltip(message: item.label, child: SizedBox(width: 52, child: child))
          : child,
    );
  }
}

// ======================================================================
// B · Стекло: узкая полупрозрачная колонка значков, аватар внизу.
// ======================================================================

class GlassRail extends StatelessWidget {
  const GlassRail({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<NavItem> items;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GlassPanel(
      width: 76,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            // Логотип «Стекла»: буква на градиенте из акцента.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent,
                    HSLColor.fromColor(accent)
                        .withHue((HSLColor.fromColor(accent).hue + 60) % 360)
                        .toColor(),
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: Text('H',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: HutredTheme.onAccent(accent))),
            ),
            const SizedBox(height: 18),
            for (final i in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Tooltip(
                  message: i.label,
                  child: Material(
                    color: i.id == selected
                        ? accent.withValues(alpha: 0.25)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onSelect(i.id),
                      child: SizedBox.square(
                        dimension: 48,
                        child: Icon(i.icon,
                            size: 22,
                            color: i.id == selected ? Colors.white : const Color(0xFFB4B4C6)),
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            const AccountButton(),
          ],
        ),
      ),
    );
  }
}

/// Полупрозрачная скруглённая панель «Стекла».
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.width});
  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

// ======================================================================
// C · Резкий: меню словами сверху, выбранное — плашка цвета акцента.
// ======================================================================

class SharpTopNav extends StatelessWidget {
  const SharpTopNav({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<NavItem> items;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final acc = context.watch<AccountService>();
    return Container(
      padding: EdgeInsets.fromLTRB(28, MediaQuery.paddingOf(context).top + 12, 20, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF222222))),
      ),
      child: Row(
        children: [
          SharpWordmark(size: 20, accent: accent),
          const SizedBox(width: 28),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final i in items)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: () => onSelect(i.id),
                        child: Container(
                          color: i.id == selected ? accent : Colors.transparent,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          child: Text(
                            i.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: i.id == selected
                                  ? HutredTheme.onAccent(accent)
                                  : const Color(0xFF8A8A8A),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (acc.signedIn && acc.username != null) ...[
            Text('@${acc.username!.toUpperCase()}',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF8A8A8A), letterSpacing: 0.6)),
            const SizedBox(width: 10),
          ],
          const AccountButton(),
        ],
      ),
    );
  }
}

/// Надпись «HUTRED.» с точкой цвета акцента.
class SharpWordmark extends StatelessWidget {
  const SharpWordmark({super.key, required this.size, required this.accent});
  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'HUTRED'),
        TextSpan(text: '.', style: TextStyle(color: accent)),
      ]),
      style: TextStyle(
        fontFamily: HutredStyle.of(context).displayFont,
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
    );
  }
}

// ======================================================================
// Телефон: нижнее меню в трёх вариантах.
// ======================================================================

class PhoneNav extends StatelessWidget {
  const PhoneNav({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<NavItem> items;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final style = HutredStyle.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final ink = Theme.of(context).canvasColor;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final small = items.length > 5;

    Widget item(NavItem i) {
      final sel = i.id == selected;
      if (style.sharp) {
        return Expanded(
          child: InkWell(
            onTap: () => onSelect(i.id),
            child: Center(
              child: Container(
                color: sel ? accent : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  i.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: small ? 11 : 13,
                    fontWeight: FontWeight.w600,
                    color: sel ? HutredTheme.onAccent(accent) : const Color(0xFF8A8A8A),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      final color = sel ? HutredTheme.text : const Color(0xFFA3A3A3);
      Widget icon = Icon(i.icon, size: 24, color: color);
      if (style.glass && sel) {
        icon = Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: icon,
        );
      }
      return Expanded(
        child: InkWell(
          onTap: () => onSelect(i.id),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 4),
              Text(
                i.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: small ? 10 : 11,
                    color: color,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    final decoration = switch (style.id) {
      'sharp' => BoxDecoration(
          color: ink,
          border: const Border(top: BorderSide(color: Color(0xFF222222))),
        ),
      'glass' => BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        ),
      // Моно: меню плавно выходит из фона, без отдельной плашки.
      _ => BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ink.withValues(alpha: 0.85), ink],
          ),
        ),
    };
    return Container(
      decoration: decoration,
      padding: EdgeInsets.only(bottom: bottom),
      height: 64 + bottom,
      child: Row(children: [for (final i in items) item(i)]),
    );
  }
}
