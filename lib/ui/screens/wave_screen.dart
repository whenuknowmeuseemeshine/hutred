import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/library_store.dart';
import '../../services/player_service.dart';
import '../../services/settings_store.dart';
import '../../services/wave_service.dart';
import '../shell_nav.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/style_bits.dart';
import '../widgets/track_tile.dart';
import '../../models/track.dart';
import '../widgets/artwork.dart';
import 'now_playing_screen.dart';
import 'search_screen.dart';
import '../icons.dart';

/// «Моя волна»: один большой круг, который запускает поток музыки.
class WaveScreen extends StatelessWidget {
  const WaveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wave = context.watch<WaveService>();
    final player = context.watch<PlayerService>();
    final store = context.watch<LibraryStore>();
    final current = player.current;
    final onWave = wave.isWaveTrack(current);
    final accent = Theme.of(context).colorScheme.primary;

    final bg = context.watch<SettingsStore>().waveBackground;

    final content = LayoutBuilder(
        builder: (context, box) {
          final wideLayout = box.maxWidth >= 900;
          final size = wideLayout
              ? min(box.maxHeight * 0.5, 320.0)
              : min(box.maxWidth - 48, min(box.maxHeight * 0.48, 340.0));
          if (wideLayout) {
            // Компьютер по макету: слева круг и режимы, справа что играет и дальше.
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 12, 32, 120),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(children: [
                      const SizedBox(height: 20),
                      _WaveOrb(
                        size: size,
                        color: accent,
                        playing: onWave && player.playing,
                        loading: wave.loading,
                        glow: HutredStyle.of(context).glass,
                        onTap: () {
                          if (wave.loading) return;
                          if (onWave) {
                            player.togglePlay();
                          } else {
                            wave.start();
                          }
                        },
                        icon: onWave && player.playing
                            ? Ic.pause_rounded
                            : Ic.play_arrow_rounded,
                      ),
                      const SizedBox(height: 22),
                      Text('Моя волна', style: HutredStyle.of(context).display(44)),
                      const SizedBox(height: 8),
                      Text(
                          wave.radioLabel ??
                              (onWave ? 'Волна играет' : 'Бесконечный поток под твой вкус'),
                          style: const TextStyle(color: HutredTheme.muted)),
                      const SizedBox(height: 18),
                      const _ModeChips(center: true),
                      if (wave.error != null) ...[
                        const SizedBox(height: 14),
                        Text(wave.error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                      if (wave.dislikedCount > 0)
                        TextButton(
                          onPressed: wave.resetDislikes,
                          child: Text('Сбросить дизлайки (${wave.dislikedCount})'),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 40),
                  SizedBox(
                    width: 420,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const StyleCaption('Сейчас в волне'),
                        const SizedBox(height: 8),
                        if (onWave)
                          _NowOnWave()
                        else
                          const StylePanel(
                            child: Text(
                              'Нажми на круг — волна подберёт музыку по трекам с ♥ и тому, '
                              'что ты часто слушаешь. Лайк делает похожее чаще, '
                              '«не нравится» убирает трек навсегда.',
                              style: TextStyle(color: HutredTheme.muted, height: 1.45),
                            ),
                          ),
                        if (onWave) const _UpNext(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
            child: Column(
              children: [
                const SizedBox(height: 12),
                _WaveOrb(
                  size: size,
                  color: accent,
                  glow: HutredStyle.of(context).glass,
                  playing: onWave && player.playing,
                  loading: wave.loading,
                  onTap: () {
                    if (wave.loading) return;
                    if (onWave) {
                      player.togglePlay();
                    } else {
                      wave.start();
                    }
                  },
                  icon: onWave && player.playing
                      ? Ic.pause_rounded
                      : Ic.play_arrow_rounded,
                ),
                const SizedBox(height: 24),
                Text(
                  onWave ? 'Волна играет' : 'Бесконечный поток под твой вкус',
                  textAlign: TextAlign.center,
                  style: HutredStyle.of(context).display(24),
                ),
                const SizedBox(height: 8),
                Text(
                  'Подбирается по трекам с ♥ и тем, что ты часто слушаешь. '
                  'Лайк делает похожее чаще, дизлайк убирает трек навсегда.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: HutredTheme.muted, height: 1.4),
                ),
                const SizedBox(height: 16),
                const _ModeChips(center: true),
                if (wave.error != null) ...[
                  const SizedBox(height: 16),
                  Text(wave.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                if (onWave) ...[
                  const SizedBox(height: 28),
                  _NowOnWave(),
                ],
                const SizedBox(height: 28),
                if (store.favorites.isEmpty)
                  const Text(
                    'Совет: поставь ♥ нескольким любимым трекам — волна станет точнее.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: HutredTheme.muted, fontSize: 13),
                  ),
                if (wave.dislikedCount > 0)
                  TextButton(
                    onPressed: wave.resetDislikes,
                    child: Text('Сбросить дизлайки (${wave.dislikedCount})'),
                  ),
                if (wave.active && !onWave)
                  TextButton(
                    onPressed: wave.stop,
                    child: const Text('Выключить волну'),
                  ),
              ],
            ),
          );
        },
      );

    final sharp = HutredStyle.of(context).sharp;
    return Scaffold(
      extendBodyBehindAppBar: bg != null,
      appBar: AppBar(
        title: sharp ? null : const Text('Моя волна'),
        backgroundColor: bg != null ? Colors.transparent : null,
        actions: [
          // Вкладка «Поиск» скрыта (на телефоне по умолчанию) — поиск здесь.
          // Фон «Волны» меняется в Настройках → Фон.
          if (!context.watch<SettingsStore>().visibleNav.contains('search'))
            IconButton(
              tooltip: 'Поиск',
              icon: Icon(Ic.search_rounded),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SearchScreen())),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: bg == null
          ? (sharp ? const _SharpWave() : content)
          : Stack(
              fit: StackFit.expand,
              children: [
                // GIF анимируется сам; затемняем, чтобы читался текст.
                Image.file(File(bg), fit: BoxFit.cover, gaplessPlayback: true),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x66000000), Color(0x99000000), Color(0xCC000000)],
                    ),
                  ),
                ),
                SafeArea(child: sharp ? const _SharpWave() : content),
              ],
            ),
    );
  }
}

class _NowOnWave extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final wave = context.watch<WaveService>();
    final player = context.watch<PlayerService>();
    final store = context.watch<LibraryStore>();
    final t = player.current!;
    final saved = store.findBySource(t.source, t.uri);
    final liked = saved?.favorite ?? false;

    final st = HutredStyle.of(context);
    final r = BorderRadius.circular(st.glass ? 22 : st.sharp ? 0 : 12);
    return Material(
      color: st.glass ? Colors.white.withValues(alpha: 0.06) : const Color(0xFF141414),
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: st.glass
            ? BorderSide(color: Colors.white.withValues(alpha: 0.08))
            : st.sharp
                ? const BorderSide(color: Color(0xFF2A2A2A))
                : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: r,
        onTap: () => NowPlayingScreen.open(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Artwork(track: t, size: 56, radius: 6),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(t.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: HutredTheme.muted)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Не нравится',
                onPressed: () => wave.dislike(t),
                icon: Icon(Ic.thumb_down_alt_outlined),
              ),
              IconButton(
                tooltip: liked ? 'В избранном' : 'Нравится',
                onPressed: liked ? null : () => wave.like(t),
                icon: Icon(liked ? Ic.favorite : Ic.favorite_border,
                    color: liked ? Theme.of(context).colorScheme.primary : null),
              ),
              IconButton(
                tooltip: 'Следующий',
                onPressed: player.next,
                icon: Icon(Ic.skip_next_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Пульсирующий круг с волнами — кнопка запуска.
class _WaveOrb extends StatefulWidget {
  const _WaveOrb({
    required this.size,
    required this.color,
    required this.playing,
    required this.loading,
    required this.onTap,
    required this.icon,
    this.glow = false,
  });

  /// «Стекло»: светящийся шар.
  final bool glow;
  final double size;
  final Color color;
  final bool playing;
  final bool loading;
  final VoidCallback onTap;
  final IconData icon;

  @override
  State<_WaveOrb> createState() => _WaveOrbState();
}

class _WaveOrbState extends State<_WaveOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Semantics(
      button: true,
      label: widget.playing ? 'Пауза' : 'Запустить волну',
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: widget.glow
              ? BoxDecoration(shape: BoxShape.circle, boxShadow: [
                  BoxShadow(color: widget.color.withValues(alpha: 0.55), blurRadius: 90),
                  BoxShadow(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.2), blurRadius: 180),
                ])
              : null,
          // Пауза/игра: «дыхание» шара плавно затихает и разгоняется.
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: widget.playing ? 1 : 0.35),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOut,
            builder: (context, energy, child) => AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _OrbPainter(
                t: reduce ? 0 : _c.value,
                color: widget.color,
                energy: energy,
              ),
              child: Center(
                child: Container(
                  width: widget.size * 0.28,
                  height: widget.size * 0.28,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: widget.loading
                      ? const Padding(
                          padding: EdgeInsets.all(22),
                          child: CircularProgressIndicator(
                              strokeWidth: 3, color: Colors.black),
                        )
                      : SwapIcon(widget.icon,
                          size: widget.size * 0.16, color: Colors.black),
                ),
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.t, required this.color, required this.energy});
  final double t;
  final Color color;
  final double energy;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final hsl = HSLColor.fromColor(color);
    // Несколько полупрозрачных «лепестков», которые медленно вращаются.
    for (var layer = 0; layer < 4; layer++) {
      final hue = (hsl.hue + layer * 24) % 360;
      final paint = Paint()
        ..color = hsl
            .withHue(hue)
            .withLightness((hsl.lightness * (1 - layer * 0.12)).clamp(0.15, 0.85))
            .toColor()
            .withValues(alpha: 0.32)
        ..style = PaintingStyle.fill;
      final path = Path();
      const steps = 90;
      for (var i = 0; i <= steps; i++) {
        final a = i / steps * 2 * pi;
        final wobble = sin(a * (3 + layer) + t * 2 * pi * (layer.isEven ? 1 : -1)) *
            0.06 *
            energy;
        final rr = r * (0.62 + layer * 0.08 + wobble);
        final p = c + Offset(cos(a), sin(a)) * rr;
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.t != t || old.color != color || old.energy != energy;
}


/// «Резкий»: крупное «Моя волна», режимы, карточка текущего трека
/// и пронумерованный список «Дальше».
class _SharpWave extends StatelessWidget {
  const _SharpWave();

  @override
  Widget build(BuildContext context) {
    final wave = context.watch<WaveService>();
    final player = context.watch<PlayerService>();
    final store = context.read<LibraryStore>();
    final accent = Theme.of(context).colorScheme.primary;
    final style = HutredStyle.of(context);
    final current = player.current;
    final onWave = wave.isWaveTrack(current);
    final mono = style.caption(color: const Color(0xFF8A8A8A), size: 11);

    // Режимы: обычная волна, только по любимым, по недавно добавленным.
    final favs = store.favorites;
    final recent = List.of(store.tracks)..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final modes = waveModes(wave, favs, recent);
    final activeMode = onWave ? (wave.radioLabel) : '-';

    final next = player.queue.skip(player.index + 1).take(onWave ? 8 : 0).toList();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final nextList = <Widget>[
      if (next.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(wide ? 'ДАЛЬШЕ В ВОЛНЕ' : 'ДАЛЬШЕ', style: mono.copyWith(color: wide ? accent : null)),
          const SizedBox(height: 8),
          for (final (k, t) in next.indexed)
            InkWell(
              onTap: () => player.jumpTo(player.index + 1 + k),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFF1F1F1F)))),
                child: Row(children: [
                  SizedBox(
                      width: 28,
                      child: Text((k + 1).toString().padLeft(2, '0'),
                          style: mono.copyWith(color: const Color(0xFF555555)))),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF8A8A8A))),
                    ]),
                  ),
                  Text(formatDuration(t.duration), style: mono.copyWith(letterSpacing: 0)),
                ]),
              ),
            ),
        
      ],
    ];

    final left = ListView(
      padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 8, wide ? 32 : 20, 120),
      children: [
        if (MediaQuery.sizeOf(context).width < 800) ...[
          Row(children: [
            SharpWordmark(size: 18, accent: accent),
            const Spacer(),
            Text(_dayCaption(), style: mono),
          ]),
          const SizedBox(height: 28),
        ],
        Text('ПОД НАСТРОЕНИЕ', style: mono.copyWith(color: accent)),
        const SizedBox(height: 10),
        Text('Моя\nволна', style: style.display(wide ? 110 : 72).copyWith(height: 0.95)),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, key, run) in modes)
              InkWell(
                onTap: wave.loading ? null : run,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: activeMode == key ? accent : Colors.transparent,
                    border: Border.all(
                        color: activeMode == key ? accent : const Color(0xFF333333)),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: activeMode == key
                              ? HutredTheme.onAccent(accent)
                              : HutredTheme.text)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        // Карточка: что играет в волне, или кнопка запуска.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFF2A2A2A))),
          child: Row(children: [
            if (onWave && current != null)
              GestureDetector(
                onTap: () => NowPlayingScreen.open(context),
                child: Artwork(track: current, size: 64, radius: 0),
              )
            else
              Container(
                width: 64,
                height: 64,
                color: const Color(0xFF1B1B1B),
                child: Icon(Ic.graphic_eq_rounded, color: Color(0xFF555555)),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(onWave && current != null ? current.title : 'Волна выключена',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                Text(
                    onWave && current != null
                        ? current.artist
                        : 'Бесконечный поток под твой вкус',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF8A8A8A))),
                if (onWave)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: StreamBuilder<Duration>(
                      stream: player.positionStream,
                      builder: (context, snap) {
                        final d = player.duration?.inMilliseconds ?? 0;
                        final p = snap.data?.inMilliseconds ?? 0;
                        return LinearProgressIndicator(
                          value: d > 0 ? (p / d).clamp(0.0, 1.0) : 0,
                          minHeight: 2,
                          color: accent,
                          backgroundColor: const Color(0xFF2A2A2A),
                        );
                      },
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: 14),
            Material(
              color: accent,
              child: InkWell(
                onTap: () {
                  if (wave.loading) return;
                  if (onWave) {
                    player.togglePlay();
                  } else {
                    wave.start();
                  }
                },
                child: SizedBox.square(
                  dimension: 52,
                  child: wave.loading
                      ? Padding(
                          padding: const EdgeInsets.all(15),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: HutredTheme.onAccent(accent)),
                        )
                      : SwapIcon(
                          onWave && player.playing
                              ? Ic.pause_rounded
                              : Ic.play_arrow_rounded,
                          color: HutredTheme.onAccent(accent)),
                ),
              ),
            ),
          ]),
        ),
        if (wave.error != null) ...[
          const SizedBox(height: 12),
          Text(wave.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (!wide) ...nextList,
        const SizedBox(height: 20),
        if (wave.dislikedCount > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: wave.resetDislikes,
              child: Text('Сбросить дизлайки (${wave.dislikedCount})'),
            ),
          ),
      ],
    );
    if (!wide) return left;
    // Компьютер по макету C: слева «Моя волна» крупно, справа «Дальше в волне».
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        SizedBox(
          width: 440,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 32, 120),
            children: nextList.isEmpty
                ? [Text('ДАЛЬШЕ В ВОЛНЕ', style: mono.copyWith(color: accent)),
                   const SizedBox(height: 12),
                   const Text('Запусти волну — здесь появятся следующие треки.',
                       style: TextStyle(color: Color(0xFF8A8A8A)))]
                : nextList,
          ),
        ),
      ],
    );
  }
}

/// «ПН · ВЕЧЕР» — день недели и время суток для шапки «Резкого».
String _dayCaption() {
  final now = DateTime.now();
  const days = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];
  final h = now.hour;
  final part = h < 5 ? 'НОЧЬ' : h < 12 ? 'УТРО' : h < 18 ? 'ДЕНЬ' : 'ВЕЧЕР';
  return '${days[now.weekday - 1]} · $part';
}


/// Режимы волны: (подпись, метка режима в WaveService.radioLabel, запуск).
List<(String, String?, Future<void> Function())> waveModes(
        WaveService wave, List<Track> favs, List<Track> recent) =>
    [
      ('Как обычно', null, wave.start),
      if (favs.isNotEmpty)
        ('По любимым', 'По любимым',
            () => wave.startCustom([for (final t in favs) (track: t, weight: 3)],
                label: 'По любимым')),
      if (recent.isNotEmpty)
        ('По свежим', 'По свежим',
            () => wave.startCustom([for (final t in recent.take(20)) (track: t, weight: 3)],
                label: 'По свежим')),
      ('Незнакомое', 'Незнакомое',
          () => wave.startCustom(null, label: 'Незнакомое', unfamiliar: true)),
    ];

/// Ряд режимов волны фишками.
class _ModeChips extends StatelessWidget {
  const _ModeChips({this.center = false});
  final bool center;

  @override
  Widget build(BuildContext context) {
    final wave = context.watch<WaveService>();
    final player = context.watch<PlayerService>();
    final store = context.read<LibraryStore>();
    final onWave = wave.isWaveTrack(player.current);
    final recent = List.of(store.tracks)..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final active = onWave ? wave.radioLabel : '-';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: center ? WrapAlignment.center : WrapAlignment.start,
      children: [
        for (final (label, key, run) in waveModes(wave, store.favorites, recent))
          StyleChip(
            label: label,
            selected: active == key,
            onTap: wave.loading ? null : run,
          ),
      ],
    );
  }
}

/// «Дальше в волне»: следующие треки очереди.
class _UpNext extends StatelessWidget {
  const _UpNext();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final next = player.queue.skip(player.index + 1).take(5).toList();
    if (next.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const StyleCaption('Дальше'),
        const SizedBox(height: 6),
        for (final (k, t) in next.indexed)
          TrackTile(track: t, onTap: () => player.jumpTo(player.index + 1 + k)),
      ],
    );
  }
}
