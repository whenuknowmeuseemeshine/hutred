import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/account_service.dart';
import 'theme.dart';
import 'widgets/account_button.dart';
import 'widgets/logo.dart';
import 'widgets/user_avatar.dart';
import 'screens/account_screen.dart';

/// Вкладка для меню: id, значок, подпись.
typedef NavItem = ({String id, IconData icon, String label, int badge});

/// Счётчик на вкладке (новые заявки в друзья).
class NavBadge extends StatelessWidget {
  const NavBadge(this.count, {super.key, this.small = false});
  final int count;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final bg = st.glass ? const Color(0xFFF472B6) : st.sharp ? accent : const Color(0xFFEF4444);
    final fg = st.glass ? const Color(0xFF0B0B12) : st.sharp ? HutredTheme.onAccent(accent) : Colors.white;
    return Container(
      constraints: BoxConstraints(minWidth: small ? 16 : 20),
      padding: EdgeInsets.symmetric(horizontal: small ? 4 : 6, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(st.sharp ? 0 : 99)),
      child: Text('$count',
          textAlign: TextAlign.center,
          style: TextStyle(color: fg, fontSize: small ? 10 : 11, fontWeight: FontWeight.w800)),
    );
  }
}

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
          AccountBadge(compact: compact),
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
                if (item.badge > 0) ...[const Spacer(), NavBadge(item.badge)],
              ] else if (item.badge > 0) ...[
                const SizedBox(width: 2),
                NavBadge(item.badge, small: true),
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
            // Логотип Hutred в скруглённой «стеклянной» рамке.
            const HutredLogo(size: 42, radius: 14),
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
                        child: Stack(children: [
                          Center(
                            child: Icon(i.icon,
                                size: 22,
                                color: i.id == selected ? Colors.white : const Color(0xFFB4B4C6)),
                          ),
                          if (i.badge > 0)
                            Positioned(top: 5, right: 5, child: NavBadge(i.badge, small: true)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            const AccountBadge(),
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
    
    return Container(
      padding: EdgeInsets.fromLTRB(28, MediaQuery.paddingOf(context).top + 12, 20, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF222222))),
      ),
      child: Row(
        children: [
          const HutredLogo(size: 30, radius: 0),
          const SizedBox(width: 10),
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
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(
                              i.label,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: i.id == selected
                                    ? HutredTheme.onAccent(accent)
                                    : const Color(0xFF8A8A8A),
                              ),
                            ),
                            if (i.badge > 0) ...[const SizedBox(width: 6), NavBadge(i.badge, small: true)],
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const AccountBadge(),
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
                  i.badge > 0 ? '${i.label} ${i.badge}' : i.label,
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
      if (i.badge > 0) {
        icon = Stack(clipBehavior: Clip.none, children: [
          icon,
          Positioned(top: -4, right: -10, child: NavBadge(i.badge, small: true)),
        ]);
      }
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


// ======================================================================
// Аккаунт: где видно, под кем ты вошёл. Нажатие — экран аккаунта.
// ======================================================================

class AccountBadge extends StatelessWidget {
  const AccountBadge({super.key, this.compact = false});
  final bool compact;

  static void open(BuildContext context) => Navigator.of(context, rootNavigator: true)
      .push(MaterialPageRoute(builder: (_) => const AccountScreen()));

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccountService>();
    if (!acc.enabled) return const SizedBox.shrink();
    final st = HutredStyle.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    if (!acc.signedIn) {
      return compact || st.glass ? const AccountButton() : const AccountButton(extended: true);
    }
    final name = acc.username != null ? '@${acc.username}' : (acc.email ?? '');
    final status = acc.syncError != null
        ? 'Ошибка синхронизации'
        : acc.syncing
            ? 'Синхронизация…'
            : 'Синхронизировано';
    final dotColor = acc.syncError != null
        ? Theme.of(context).colorScheme.error
        : acc.syncing
            ? Colors.amber
            : const Color(0xFF4ADE80);

    Widget avatar(double r, Color ring) => Stack(clipBehavior: Clip.none, children: [
          Container(
            decoration: st.glass
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.6), spreadRadius: 2)])
                : null,
            child: UserAvatar(radius: r),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: r * 0.62,
              height: r * 0.62,
              decoration: BoxDecoration(
                shape: st.sharp ? BoxShape.rectangle : BoxShape.circle,
                color: dotColor,
                border: Border.all(color: ring, width: 2),
              ),
            ),
          ),
        ]);

    final Widget child;
    if (st.sharp) {
      child = Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, color: acc.syncError != null ? dotColor : accent),
        const SizedBox(width: 8),
        Text(acc.syncError != null ? 'ОШИБКА СИНХР.' : acc.syncing ? 'СИНХР…' : 'СИНХР.',
            style: st.caption(color: HutredTheme.muted)),
        const SizedBox(width: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFF333333))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const UserAvatar(radius: 13),
            const SizedBox(width: 10),
            Text(name.toUpperCase(), style: st.caption(color: HutredTheme.text)),
          ]),
        ),
      ]);
    } else if (st.glass || compact) {
      child = avatar(st.glass ? 20 : 15, st.glass ? const Color(0xFF14121F) : const Color(0xFF0A0A0A));
    } else {
      child = Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          avatar(15, const Color(0xFF141414)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text(status,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 11, color: Color(0xFFA3A3A3))),
            ]),
          ),
          const Icon(Icons.chevron_right, size: 16, color: Color(0xFFA3A3A3)),
        ]),
      );
    }
    return Tooltip(
      message: acc.syncError ?? '$name · $status',
      child: InkWell(
        borderRadius: BorderRadius.circular(st.sharp ? 0 : 12),
        onTap: () => open(context),
        child: child,
      ),
    );
  }
}
