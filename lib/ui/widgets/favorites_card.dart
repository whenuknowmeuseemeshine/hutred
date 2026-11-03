import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/offline_service.dart';
import '../../services/player_service.dart';
import '../actions.dart';
import '../icons.dart';
import '../theme.dart';

/// Карточка «Любимые треки» в медиатеке: сердце цвета акцента, справа
/// столбики эквалайзера — двигаются, пока играют любимые, на паузе замирают.
/// Внизу быстрые подборки: чаще всего, новые, скачанные.
class FavoritesCard extends StatelessWidget {
  const FavoritesCard({
    super.key,
    required this.favorites,
    required this.subtitle,
    required this.onOpen,
    this.height = 300,
  });

  final List<Track> favorites;
  final String subtitle;
  final VoidCallback onOpen;
  final double height;

  Future<void> _play(BuildContext context, List<Track> list, String empty) async {
    if (list.isEmpty) {
      AppActions.toast(context, empty);
      return;
    }
    await context.read<PlayerService>().playTracks(list);
  }

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final onAccent = HutredTheme.onAccent(accent);
    final player = context.watch<PlayerService>();
    final cur = player.current;
    // Столбики «живые», когда играет любимый трек.
    final live = player.playing && cur != null && favorites.any((t) => t.id == cur.id);
    final r = st.sharp ? 0.0 : st.glass ? 24.0 : 18.0;
    final compact = height < 220;

    final chips = <(String, VoidCallback)>[
      (
        'Чаще всего',
        () => _play(context, List.of(favorites)..sort((a, b) => b.plays.compareTo(a.plays)),
            'Пока нет любимых треков'),
      ),
      (
        'Новые',
        () => _play(context, List.of(favorites)..sort((a, b) => b.addedAt.compareTo(a.addedAt)),
            'Пока нет любимых треков'),
      ),
      (
        'Скачанные',
        () {
          final off = context.read<OfflineService>();
          _play(context, favorites.where(off.isDownloaded).toList(),
              'Скачанных любимых пока нет');
        },
      ),
    ];

    Widget chip((String, VoidCallback) c) => Material(
          color: st.sharp
              ? Colors.transparent
              : st.glass
                  ? Colors.white.withValues(alpha: 0.10)
                  : const Color(0xFF222222),
          shape: st.sharp
              ? const RoundedRectangleBorder(side: BorderSide(color: Color(0xFF3A3A3A)))
              : const StadiumBorder(),
          child: InkWell(
            customBorder: st.sharp ? const RoundedRectangleBorder() : const StadiumBorder(),
            onTap: c.$2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(st.sharp ? c.$1.toUpperCase() : c.$1,
                  style: st.sharp
                      ? st.caption(size: 11, color: HutredTheme.text)
                      : const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        );

    final heart = Container(
      width: compact ? 44 : 56,
      height: compact ? 44 : 56,
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(st.sharp ? 0 : compact ? 12 : 16),
      ),
      alignment: Alignment.center,
      child: Icon(Ic.favorite, color: onAccent, size: compact ? 22 : 28),
    );

    final playBtn = Material(
      color: st.glass ? accent : HutredTheme.text,
      shape: st.sharp ? const RoundedRectangleBorder() : const CircleBorder(),
      child: InkWell(
        customBorder: st.sharp ? const RoundedRectangleBorder() : const CircleBorder(),
        onTap: () => live || (cur != null && favorites.any((t) => t.id == cur.id))
            ? player.togglePlay()
            : _play(context, favorites, 'Пока нет любимых треков'),
        child: SizedBox.square(
          dimension: compact ? 48 : 60,
          child: Icon(live ? Ic.pause_rounded : Ic.play_arrow_rounded,
              size: compact ? 26 : 30, color: st.glass ? onAccent : Colors.black),
        ),
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(r),
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            color: st.sharp
                ? Colors.transparent
                : st.glass
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFF141414),
            borderRadius: BorderRadius.circular(r),
            border: Border.all(
                color: st.sharp
                    ? const Color(0xFF2A2A2A)
                    : st.glass
                        ? Colors.white.withValues(alpha: 0.14)
                        : const Color(0xFF222222)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(r),
            child: Stack(children: [
              Positioned(
                right: compact ? 16 : 24,
                top: compact ? 16 : 24,
                bottom: compact ? 70 : 110,
                width: compact ? 150 : 300,
                child: _EqBars(live: live, accent: accent, sharp: st.sharp),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(compact ? 16 : 28, compact ? 16 : 26,
                    compact ? 16 : 28, compact ? 16 : 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heart,
                    const Spacer(),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(st.sharp ? 'ЛЮБИМЫЕ ТРЕКИ' : 'Любимые треки',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: st.display(compact ? 24 : 40)),
                            const SizedBox(height: 4),
                            Text(subtitle,
                                style: st.sharp
                                    ? st.caption(color: HutredTheme.muted)
                                    : const TextStyle(color: HutredTheme.muted, fontSize: 14)),
                            if (!compact) ...[
                              const SizedBox(height: 12),
                              Wrap(spacing: 6, runSpacing: 6, children: [
                                for (final c in chips) chip(c),
                              ]),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      playBtn,
                    ]),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Столбики эквалайзера. [live] — двигаются, иначе стоят «как на фото».
class _EqBars extends StatefulWidget {
  const _EqBars({required this.live, required this.accent, required this.sharp});
  final bool live;
  final Color accent;
  final bool sharp;

  @override
  State<_EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends State<_EqBars> with SingleTickerProviderStateMixin {
  static const _rest = [
    .30, .55, .80, .62, .40, .70, .95, .78, .50, .35, .60, .88, .72, .45, .30, .52, .76, .58, .38, .24
  ];
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void initState() {
    super.initState();
    if (widget.live) _c.repeat();
  }

  @override
  void didUpdateWidget(_EqBars old) {
    super.didUpdateWidget(old);
    if (widget.live && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.live && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value * 2 * pi;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < _rest.length; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              Expanded(
                child: FractionallySizedBox(
                  heightFactor: widget.live
                      ? (0.18 +
                              0.82 *
                                  (0.5 +
                                      0.5 *
                                          sin(t * (2 + i % 4) + i * 1.7) *
                                          cos(t * (1 + i % 3) + i)))
                          .clamp(0.1, 1.0)
                      : _rest[i],
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.live && i % 3 == 0
                          ? widget.accent.withValues(alpha: 0.55)
                          : i % 3 == 0
                              ? const Color(0xFF3A3A3A)
                              : const Color(0xFF262626),
                      borderRadius: BorderRadius.circular(widget.sharp ? 0 : 4),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
