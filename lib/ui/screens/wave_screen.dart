import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/library_store.dart';
import '../../services/player_service.dart';
import '../../services/settings_store.dart';
import '../../services/wave_service.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import 'now_playing_screen.dart';
import 'search_screen.dart';

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
          final size = min(box.maxWidth - 48, min(box.maxHeight * 0.48, 340.0));
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
            child: Column(
              children: [
                const SizedBox(height: 12),
                _WaveOrb(
                  size: size,
                  color: accent,
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
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                const SizedBox(height: 24),
                Text(
                  onWave ? 'Волна играет' : 'Бесконечный поток под твой вкус',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Подбирается по трекам с ♥ и тем, что ты часто слушаешь. '
                  'Лайк делает похожее чаще, дизлайк убирает трек навсегда.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: HutredTheme.muted, height: 1.4),
                ),
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

    return Scaffold(
      extendBodyBehindAppBar: bg != null,
      appBar: AppBar(
        title: const Text('Моя волна'),
        backgroundColor: bg != null ? Colors.transparent : null,
        actions: [
          // Вкладка «Поиск» скрыта (на телефоне по умолчанию) — поиск здесь.
          // Фон «Волны» меняется в Настройках → Фон.
          if (!context.watch<SettingsStore>().visibleNav.contains('search'))
            IconButton(
              tooltip: 'Поиск',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SearchScreen())),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: bg == null
          ? content
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
                SafeArea(child: content),
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

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
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
                icon: const Icon(Icons.thumb_down_alt_outlined),
              ),
              IconButton(
                tooltip: liked ? 'В избранном' : 'Нравится',
                onPressed: liked ? null : () => wave.like(t),
                icon: Icon(liked ? Icons.favorite : Icons.favorite_border,
                    color: liked ? Theme.of(context).colorScheme.primary : null),
              ),
              IconButton(
                tooltip: 'Следующий',
                onPressed: player.next,
                icon: const Icon(Icons.skip_next_rounded),
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
  });

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
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _OrbPainter(
                t: reduce ? 0 : _c.value,
                color: widget.color,
                energy: widget.playing ? 1 : 0.35,
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
                      : Icon(widget.icon,
                          size: widget.size * 0.16, color: Colors.black),
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
