
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/player_service.dart';
import '../theme.dart';

/// Полоса перемотки с временем.
class SeekBar extends StatefulWidget {
  const SeekBar({super.key, this.compact = false});

  /// Время слева и справа от полосы, в одну строку (нижняя панель на ПК).
  final bool compact;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final dur = player.duration;
    const tabular = TextStyle(
      fontSize: 12,
      color: HutredTheme.muted,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final max = (dur?.inMilliseconds ?? 0).toDouble();
        final value = max <= 0
            ? 0.0
            : (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max);
        final shown = _drag != null
            ? Duration(milliseconds: _drag!.round())
            : pos;
        final slider = Slider(
          value: value,
          max: max <= 0 ? 1 : max,
          onChanged: max <= 0 ? null : (v) => setState(() => _drag = v),
          onChangeEnd: max <= 0
              ? null
              : (v) {
                  player.seek(Duration(milliseconds: v.round()));
                  setState(() => _drag = null);
                },
        );
        if (widget.compact) {
          return Row(
            children: [
              SizedBox(
                  width: 44,
                  child: Text(formatDuration(shown),
                      textAlign: TextAlign.right, style: tabular)),
              Expanded(child: SizedBox(height: 24, child: slider)),
              SizedBox(
                  width: 44,
                  child: Text(dur == null ? 'эфир' : formatDuration(dur),
                      style: tabular)),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Slider(
              value: value,
              max: max <= 0 ? 1 : max,
              onChanged: max <= 0 ? null : (v) => setState(() => _drag = v),
              onChangeEnd: max <= 0
                  ? null
                  : (v) {
                      player.seek(Duration(milliseconds: v.round()));
                      setState(() => _drag = null);
                    },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatDuration(shown), style: tabular),
                  Text(dur == null ? 'эфир' : formatDuration(dur),
                      style: tabular),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Кнопки: перемешать, назад, играть, вперёд, повтор.
class TransportControls extends StatelessWidget {
  const TransportControls({super.key, this.big = true, this.compact = false});
  final bool big;

  /// Маленькие кнопки рядом друг с другом (нижняя панель на ПК).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final accent = Theme.of(context).colorScheme.primary;
    final playSize = compact ? 36.0 : (big ? 68.0 : 52.0);
    final skipSize = compact ? 26.0 : 36.0;

    return Row(
      mainAxisAlignment:
          compact ? MainAxisAlignment.center : MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: !player.shuffle
              ? 'Перемешать'
              : (player.smartShuffle
                  ? 'Перемешано с рекомендациями — нажми, чтобы выключить'
                  : 'Перемешать с рекомендациями из «Моей волны»'),
          onPressed: player.toggleShuffle,
          icon: ShuffleIcon(on: player.shuffle, smart: player.smartShuffle, size: 20),
        ),
        IconButton(
          tooltip: 'Предыдущий',
          iconSize: skipSize,
          onPressed: player.previous,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        SizedBox.square(
          dimension: playSize,
          child: FilledButton(
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            onPressed: player.togglePlay,
            child: player.loading
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.black)),
                      // Грузится, но на паузе: значок «play» внутри кольца.
                      if (player.pausePending)
                        const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.black),
                    ],
                  )
                : Icon(
                    player.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: playSize * 0.55),
          ),
        ),
        IconButton(
          tooltip: 'Следующий',
          iconSize: skipSize,
          onPressed: player.next,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton(
          tooltip: switch (player.repeat) {
            RepeatSetting.off => 'Повтор выключен',
            RepeatSetting.all => 'Повторять очередь',
            RepeatSetting.one => 'Повторять трек',
          },
          onPressed: player.cycleRepeat,
          icon: Icon(
            player.repeat == RepeatSetting.one ? Icons.repeat_one : Icons.repeat,
            color: player.repeat == RepeatSetting.off ? Colors.white70 : accent,
          ),
        ),
      ],
    );
  }
}

class VolumeSlider extends StatelessWidget {
  const VolumeSlider({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    return Row(
      children: [
        Icon(player.volume == 0 ? Icons.volume_off : Icons.volume_down,
            size: 20, color: Colors.white70),
        Expanded(
          child: Slider(value: player.volume, onChanged: player.setVolume),
        ),
        const Icon(Icons.volume_up, size: 20, color: Colors.white70),
      ],
    );
  }
}

/// Значок перемешивания как в Spotify: стрелки, при умном перемешивании —
/// маленькая звёздочка сверху справа, а когда включено — точка снизу.
class ShuffleIcon extends StatelessWidget {
  const ShuffleIcon({
    super.key,
    required this.on,
    required this.smart,
    this.size = 22,
    this.color,
  });

  final bool on;
  final bool smart;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final c = color ?? (on ? accent : Colors.white70);
    return SizedBox(
      width: size + 6,
      height: size + 8,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(Icons.shuffle_rounded, size: size, color: c),
          if (smart)
            Positioned(
              right: -1,
              top: 0,
              child: CustomPaint(size: Size.square(size * 0.42), painter: _SparklePainter(c)),
            ),
          if (on)
            Positioned(
              bottom: 0,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }
}

/// Четырёхлучевая звёздочка (как у умного перемешивания Spotify).
class _SparklePainter extends CustomPainter {
  _SparklePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height, cx = w / 2, cy = h / 2;
    final p = Path()
      ..moveTo(cx, 0)
      ..quadraticBezierTo(cx + w * 0.08, cy - h * 0.08, w, cy)
      ..quadraticBezierTo(cx + w * 0.08, cy + h * 0.08, cx, h)
      ..quadraticBezierTo(cx - w * 0.08, cy + h * 0.08, 0, cy)
      ..quadraticBezierTo(cx - w * 0.08, cy - h * 0.08, cx, 0)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.color != color;
}
