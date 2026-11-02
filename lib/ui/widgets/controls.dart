
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/player_service.dart';
import '../theme.dart';
import '../icons.dart';

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
    final style = HutredStyle.of(context);
    // «Резкий»: прямоугольная кнопка цвета акцента, остальные — белый круг.
    final playBg = style.sharp ? accent : Colors.white;
    final playFg = style.sharp ? HutredTheme.onAccent(accent) : Colors.black;

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
          icon: Icon(Ic.skip_previous_rounded),
        ),
        SizedBox(
          width: style.sharp ? playSize * 1.35 : playSize,
          height: playSize,
          child: FilledButton(
            style: FilledButton.styleFrom(
              shape: style.sharp ? const RoundedRectangleBorder() : const CircleBorder(),
              padding: EdgeInsets.zero,
              backgroundColor: playBg,
              foregroundColor: playFg,
            ),
            onPressed: player.togglePlay,
            child: player.loading
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: playFg)),
                      // Грузится, но на паузе: значок «play» внутри кольца.
                      if (player.pausePending)
                        Icon(Ic.play_arrow_rounded, size: 16, color: playFg),
                    ],
                  )
                : Icon(
                    player.playing
                        ? Ic.pause_rounded
                        : Ic.play_arrow_rounded,
                    size: playSize * 0.55),
          ),
        ),
        IconButton(
          tooltip: 'Следующий',
          iconSize: skipSize,
          onPressed: player.next,
          icon: Icon(Ic.skip_next_rounded),
        ),
        IconButton(
          tooltip: switch (player.repeat) {
            RepeatSetting.off => 'Повтор выключен',
            RepeatSetting.all => 'Повторять очередь',
            RepeatSetting.one => 'Повторять трек',
          },
          onPressed: player.cycleRepeat,
          icon: Icon(
            player.repeat == RepeatSetting.one ? Ic.repeat_one : Ic.repeat,
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
        Icon(
            player.volume == 0
                ? Ic.volume_off
                : player.volume < 0.5
                    ? Ic.volume_down
                    : Ic.volume_up,
            size: 18,
            color: Colors.white70),
        Expanded(
          child: Slider(value: player.volume, onChanged: player.setVolume),
        ),
      ],
    );
  }
}

/// Значок перемешивания: две плавные перекрещённые стрелки,
/// при умном перемешивании — звёздочка слева сверху, когда включено — точка снизу.
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
      width: size,
      height: size + 7,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(size: Size.square(size), painter: _ShufflePainter(c, smart)),
          const SizedBox(height: 3),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: on ? c : Colors.transparent,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShufflePainter extends CustomPainter {
  _ShufflePainter(this.color, this.smart);
  final Color color;
  final bool smart;

  @override
  void paint(Canvas canvas, Size s) {
    canvas.scale(s.width / 24, s.height / 24);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (smart) {
      // Стрелки чуть меньше и правее-ниже — звёздочке нужен свой угол.
      canvas.save();
      canvas.translate(4.5, 4.5);
      canvas.scale(0.81);
    }
    // Снизу-слева вверх-вправо — сплошная.
    canvas.drawPath(
      Path()
        ..moveTo(2, 18)
        ..lineTo(5, 18)
        ..cubicTo(10, 18, 11, 6, 16, 6)
        ..lineTo(21, 6),
      line,
    );
    // Сверху-слева вниз-вправо — с разрывом на перекрестье.
    canvas.drawPath(
      Path()
        ..moveTo(2, 6)
        ..lineTo(5, 6)
        ..cubicTo(6.8, 6, 8, 7.6, 9, 9.6),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(12.6, 14.6)
        ..cubicTo(13.6, 16.6, 14.6, 18, 16, 18)
        ..lineTo(21, 18),
      line,
    );
    // Наконечники.
    for (final y in [6.0, 18.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(18, y - 3)
          ..lineTo(21, y)
          ..lineTo(18, y + 3),
        line,
      );
    }
    if (smart) {
      canvas.restore();
      // Четырёхлучевая звёздочка в левом верхнем углу.
      const cx = 3.6, cy = 3.6, r = 3.6, k = 0.6;
      canvas.drawPath(
        Path()
          ..moveTo(cx, cy - r)
          ..quadraticBezierTo(cx + k, cy - k, cx + r, cy)
          ..quadraticBezierTo(cx + k, cy + k, cx, cy + r)
          ..quadraticBezierTo(cx - k, cy + k, cx - r, cy)
          ..quadraticBezierTo(cx - k, cy - k, cx, cy - r)
          ..close(),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_ShufflePainter old) => old.color != color || old.smart != smart;
}
