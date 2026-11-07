import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/player_service.dart';
import '../../services/settings_store.dart';
import '../../services/wave_service.dart';
import '../actions.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_backdrop.dart';
import '../widgets/settings_kit.dart';
import '../widgets/track_tile.dart';

/// Открыть очередь. На телефоне — шторка на весь экран, которая
/// закрывается смахиванием вниз за верхнюю часть.
Future<void> showQueue(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const FractionallySizedBox(heightFactor: 1, child: QueueSheet()),
  );
}

class QueueSheet extends StatefulWidget {
  const QueueSheet({super.key});

  @override
  State<QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<QueueSheet> {
  bool _history = false;
  List<Track> _picks = const [];
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPicks());
  }

  /// «Подобрано для тебя»: похожие треки, которых нет в очереди.
  Future<void> _loadPicks() async {
    final player = context.read<PlayerService>();
    final rec = player.recommend;
    final cur = player.current;
    if (rec == null || cur == null) return;
    setState(() => _picking = true);
    try {
      final seeds = [cur, ...player.queue.skip(player.index + 1).take(4)];
      final got = await rec(seeds, 8).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final have = {for (final t in player.queue) '${t.source.name}:${t.uri}'};
      setState(() => _picks =
          got.where((t) => !have.contains('${t.source.name}:${t.uri}')).take(5).toList());
    } catch (_) {
      // Без подборки — не страшно.
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final st = HutredStyle.of(context);
    final k = Sk.of(context);
    final body = _content(context, k, st);
    final radius = BorderRadius.vertical(top: Radius.circular(k.sharp ? 0 : 20));
    return ClipRRect(
      borderRadius: radius,
      child: k.glass
          ? GlassBackdrop(accent: settings.accent, ink: settings.background.ink, child: body)
          : ColoredBox(color: Theme.of(context).scaffoldBackgroundColor, child: body),
    );
  }

  Widget _content(BuildContext context, Sk k, HutredStyle st) {
    final player = context.watch<PlayerService>();
    final queue = player.queue;
    final idx = player.index;
    final cur = player.current;
    final played = idx.clamp(0, queue.length);
    final upStart = idx + 1;
    final upCount = (queue.length - upStart).clamp(0, queue.length);
    final wave = context.watch<WaveService>();
    final from = wave.radioLabel ?? (wave.isWaveTrack(cur) ? 'Моя волна' : null);

    Widget chip(String label, IconData icon, bool on, VoidCallback onTap) => Material(
          color: on ? k.btn : k.chip,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(k.pill),
            side: k.sharp && !on ? BorderSide(color: k.ghost) : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                height: 34,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 16, color: on ? k.btnFg : k.text),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: on ? k.btnFg : k.text)),
                ]),
              ),
            ),
          ),
        );

    Widget heading(String title, String? note, {IconData? icon}) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (icon != null) ...[Icon(icon, size: 16, color: k.ok), const SizedBox(width: 6)],
            Text(st.sharp ? title.toUpperCase() : title,
                style: st.display(17).copyWith(fontWeight: FontWeight.w700)),
            if (note != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(note,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: k.small),
              ),
            ],
          ]),
        );

    Widget row(Track t, {required VoidCallback onTap, Widget? trailing, double opacity = 1}) =>
        TrackContextMenu(
          track: t,
          child: InkWell(
            onTap: onTap,
            child: Opacity(
              opacity: opacity,
              child: SizedBox(
                height: 60,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(children: [
                    Artwork(track: t, size: 44, radius: k.sharp ? 0 : 6),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Row(children: [
                              if (player.isRecommended(t)) ...[
                                Icon(Ic.auto_awesome, size: 12, color: k.ok),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(t.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: k.muted)),
                              ),
                            ]),
                          ]),
                    ),
                    if (trailing != null) trailing,
                  ]),
                ),
              ),
            ),
          ),
        );

    final repeatLabel = switch (player.repeat) {
      RepeatSetting.one => 'Повтор трека',
      _ => 'Повтор',
    };

    final slivers = <Widget>[
      // Шапка: ручка, заголовок, «Очистить».
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
          child: Column(children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(color: k.ghost, borderRadius: BorderRadius.circular(999)),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              IconButton(
                tooltip: 'Закрыть',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(Ic.expand_more, size: 28),
              ),
              Expanded(
                child: Text(st.sharp ? 'ОЧЕРЕДЬ' : 'Очередь',
                    style: st.display(st.glass ? 24 : 30)),
              ),
              if (upCount > 0)
                SkChip('Очистить', onTap: () {
                  final removed = upCount;
                  player.clearUpcoming();
                  AppActions.toast(context, 'Убрано из очереди: ${tracksWord(removed)}');
                }),
            ]),
          ]),
        ),
      ),
      // Прослушанные — спрятаны, пока не попросишь.
      if (_history && played > 0) ...[
        heading('Прослушано', tracksWord(played), icon: Ic.history),
        SliverList.builder(
          itemCount: played,
          itemBuilder: (_, i) => row(queue[i], onTap: () => player.jumpTo(i), opacity: 0.55),
        ),
      ],
      // Сейчас играет.
      if (cur != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: k.card,
                border: k.cardBorder,
                borderRadius: BorderRadius.circular(k.sharp ? 0 : k.glass ? 22 : 14),
              ),
              child: Row(children: [
                Artwork(track: cur, size: 56, radius: k.sharp ? 0 : 8),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('СЕЙЧАС ИГРАЕТ',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: k.ok)),
                    const SizedBox(height: 3),
                    Text(cur.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(cur.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: k.muted)),
                  ]),
                ),
                _Bars(color: k.ok, playing: player.playing),
              ]),
            ),
          ),
        ),
      // Перемешать / Повтор / Прослушано.
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            chip(player.smartShuffle ? 'Умное' : 'Перемешать', Ic.shuffle, player.shuffle,
                player.toggleShuffle),
            chip(repeatLabel, player.repeat == RepeatSetting.one ? Ic.repeat_one : Ic.repeat,
                player.repeat != RepeatSetting.off, player.cycleRepeat),
            if (played > 0)
              chip('Прослушано · $played', Ic.history, _history,
                  () => setState(() => _history = !_history)),
          ]),
        ),
      ),
      heading('Далее', upCount == 0 ? 'ничего нет' : from == null ? tracksWord(upCount) : 'из «$from» · ${tracksWord(upCount)}'),
      SliverReorderableList(
        itemCount: upCount,
        onReorder: (o, n) => player.reorderQueue(o + upStart, n + upStart),
        itemBuilder: (context, j) {
          final i = j + upStart;
          final t = queue[i];
          return Dismissible(
            key: ValueKey('${t.id}#$i'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: const Color(0xFFB4232A),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.remove_circle_outline, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Убрать', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ]),
            ),
            onDismissed: (_) => player.removeFromQueue(i),
            child: row(t,
                onTap: () => player.jumpTo(i),
                trailing: ReorderableDragStartListener(
                  index: j,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(Ic.drag_handle, color: k.muted),
                  ),
                )),
          );
        },
      ),
      if (_picks.isNotEmpty || _picking) ...[
        heading('Подобрано для тебя', 'похоже на то, что играет', icon: Ic.auto_awesome),
        if (_picking && _picks.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          ),
        SliverList.builder(
          itemCount: _picks.length,
          itemBuilder: (_, j) {
            final t = _picks[j];
            return row(t,
                opacity: 0.85,
                onTap: () async {
                  await player.playNext(t);
                  setState(() => _picks = List.of(_picks)..remove(t));
                },
                trailing: IconButton(
                  tooltip: 'Добавить в очередь',
                  onPressed: () async {
                    await player.addToQueue(t);
                    setState(() => _picks = List.of(_picks)..remove(t));
                  },
                  icon: Icon(Ic.add_circle_outline),
                ));
          },
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];

    return Column(children: [
      Expanded(child: CustomScrollView(slivers: slivers)),
      _Transport(k: k),
    ]);
  }
}

/// Перемотка и кнопки внизу очереди.
class _Transport extends StatelessWidget {
  const _Transport({required this.k});
  final Sk k;

  String _t(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final total = player.duration ?? Duration.zero;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: k.line))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, snap) {
            final pos = snap.data ?? player.position;
            final v = total.inMilliseconds <= 0
                ? 0.0
                : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
            return Column(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(k.sharp ? 0 : 99),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 3,
                  color: k.text,
                  backgroundColor: k.ghost,
                ),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Text(_t(pos), style: k.small),
                const Spacer(),
                Text(_t(total), style: k.small),
              ]),
            ]);
          },
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            tooltip: 'Предыдущий',
            iconSize: 30,
            onPressed: player.previous,
            icon: Icon(Ic.skip_previous_rounded),
          ),
          const SizedBox(width: 20),
          Material(
            color: k.btn,
            shape: k.sharp ? const RoundedRectangleBorder() : const CircleBorder(),
            child: InkWell(
              customBorder: k.sharp ? const RoundedRectangleBorder() : const CircleBorder(),
              onTap: player.togglePlay,
              child: SizedBox.square(
                dimension: 58,
                child: Icon(player.playing ? Ic.pause_rounded : Ic.play_arrow_rounded,
                    color: k.btnFg, size: 30),
              ),
            ),
          ),
          const SizedBox(width: 20),
          IconButton(
            tooltip: 'Следующий',
            iconSize: 30,
            onPressed: player.next,
            icon: Icon(Ic.skip_next_rounded),
          ),
        ]),
      ]),
    );
  }
}

/// Маленький «эквалайзер» у играющего трека.
class _Bars extends StatefulWidget {
  const _Bars({required this.color, required this.playing});
  final Color color;
  final bool playing;

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _Bars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.playing && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const base = [0.55, 1.0, 0.4, 0.8];
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => SizedBox(
        height: 18,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 4; i++)
            Container(
              width: 3,
              margin: const EdgeInsets.only(left: 3),
              height: 18 * (0.25 + 0.75 * ((base[i] + _c.value * (i.isEven ? 0.5 : -0.5)).abs() % 1)),
              color: widget.color,
            ),
        ]),
      ),
    );
  }
}
