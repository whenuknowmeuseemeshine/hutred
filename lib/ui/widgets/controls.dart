
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
          icon: Icon(player.smartShuffle ? Icons.auto_awesome : Icons.shuffle,
              color: player.shuffle ? accent : Colors.white70),
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
