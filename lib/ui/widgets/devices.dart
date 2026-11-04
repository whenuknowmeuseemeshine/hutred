import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/device_sync.dart';
import '../../services/player_service.dart';
import '../icons.dart';
import '../theme.dart';
import 'artwork.dart';
import 'settings_kit.dart';

IconData _kindIcon(String kind) => kind == 'phone' ? Icons.smartphone_rounded : Icons.computer_rounded;

String _thisName() => DeviceSync.myKind == 'phone' ? 'Этот телефон' : 'Этот компьютер';

/// Кнопка «Где слушать»: зелёная, когда музыка играет на другом устройстве
/// или этим устройством управляют.
class DevicesButton extends StatelessWidget {
  const DevicesButton({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<DeviceSync>();
    if (!sync.online || sync.others.isEmpty) return const SizedBox.shrink();
    final k = Sk.of(context);
    final hot = sync.remoteMode || sync.controlledBy != null;
    return IconButton(
      tooltip: 'Где слушать',
      onPressed: () => showDevices(context),
      icon: Icon(hot ? _kindIcon(sync.active?.kind ?? 'phone') : Icons.devices_rounded,
          size: size, color: hot ? k.ok : null),
    );
  }
}

/// Зелёная полоса: где играет музыка или кто управляет этим устройством.
class DevicesStrip extends StatelessWidget {
  const DevicesStrip({super.key, this.radius = 0, this.align = MainAxisAlignment.start});
  final double radius;
  final MainAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<DeviceSync>();
    final k = Sk.of(context);
    final a = sync.active;
    final String text;
    final IconData icon;
    if (sync.remoteMode && a != null) {
      text = 'Играет на «${a.name}»';
      icon = _kindIcon(a.kind);
    } else if (sync.controlledBy != null) {
      text = 'Управляется с «${sync.controlledBy}» — звук идёт здесь';
      icon = Icons.smartphone_rounded;
    } else {
      return const SizedBox.shrink();
    }
    final fg = k.mono ? const Color(0xFF06210F) : HutredTheme.onAccent(k.ok);
    return Material(
      color: k.ok,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      child: InkWell(
        onTap: () => showDevices(context),
        child: SizedBox(
          height: 26,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(mainAxisAlignment: align, children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Окно «Где слушать»: на телефоне — снизу, на компьютере — по центру.
Future<void> showDevices(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= 800;
  if (wide) {
    return showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: const Padding(padding: EdgeInsets.all(18), child: _DevicesPanel()),
        ),
      ),
    );
  }
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const SafeArea(
      child: Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 20), child: _DevicesPanel()),
    ),
  );
}

class _DevicesPanel extends StatelessWidget {
  const _DevicesPanel();

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<DeviceSync>();
    final player = context.watch<PlayerService>();
    final k = Sk.of(context);
    final st = HutredStyle.of(context);
    final a = sync.active;
    final hereActive = player.playing || (player.current != null && a == null);

    Widget row({
      required IconData icon,
      required String name,
      required String sub,
      required bool on,
      VoidCallback? onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: on ? k.ok.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(k.ri),
          child: InkWell(
            borderRadius: BorderRadius.circular(k.ri),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: on ? k.ok : k.inner,
                    borderRadius: BorderRadius.circular(k.sharp ? 0 : 10),
                  ),
                  child: Icon(icon, size: 19, color: on ? Colors.black : k.text),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name,
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600, color: on ? k.ok : k.text)),
                    const SizedBox(height: 1),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: on ? k.ok : k.muted)),
                  ]),
                ),
                if (on) _Bars(color: k.ok),
              ]),
            ),
          ),
        ),
      );
    }

    final volume = a != null && sync.remoteMode ? a.volume : player.volume;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(st.sharp ? 'ГДЕ СЛУШАТЬ' : 'Где слушать', style: st.display(20)),
      const SizedBox(height: 4),
      Text('Твои устройства с Hutred, где ты вошёл в аккаунт', style: k.sub),
      const SizedBox(height: 12),
      row(
        icon: _kindIcon(DeviceSync.myKind),
        name: _thisName(),
        sub: hereActive
            ? (player.playing ? 'Играет здесь' : 'На паузе здесь')
            : a != null
                ? 'Переключить музыку сюда'
                : 'Ничего не играет',
        on: hereActive && player.playing,
        onTap: !hereActive && a != null
            ? () {
                sync.playHere(a);
                Navigator.of(context).maybePop();
              }
            : null,
      ),
      for (final d in sync.others)
        row(
          icon: _kindIcon(d.kind),
          name: d.name,
          sub: d.playing && d.track != null
              ? 'Играет · ${d.track!.title} — ${d.track!.artist}'
              : (hereActive || a != null)
                  ? 'В сети · переключить музыку туда'
                  : 'В сети · ничего не играет',
          on: d.playing && d.track != null,
          onTap: (d.playing && d.track != null) || (!hereActive && a == null)
              ? null
              : () {
                  sync.moveTo(d);
                  Navigator.of(context).maybePop();
                },
        ),
      if (sync.others.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Открой Hutred на другом устройстве с тем же аккаунтом — оно появится здесь',
              style: k.small),
        ),
      if (hereActive || a != null) ...[
        const SizedBox(height: 10),
        SkCap(sync.remoteMode && a != null ? 'Громкость: ${a.name}' : 'Громкость здесь'),
        Row(children: [
          Icon(Ic.volume_down_rounded, size: 18, color: k.muted),
          Expanded(
            child: _VolumeSlider(
              value: volume,
              onChanged: (v) => sync.remoteMode && a != null
                  ? sync.command(a.id, 'volume', v: v)
                  : player.setVolume(v),
            ),
          ),
        ]),
      ],
    ]);
  }
}

/// Ползунок, который не прыгает назад, пока ждём ответ от другого устройства.
class _VolumeSlider extends StatefulWidget {
  const _VolumeSlider({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) => Slider(
        value: (_drag ?? widget.value).clamp(0.0, 1.0),
        onChanged: (v) => setState(() => _drag = v),
        onChangeEnd: (v) {
          widget.onChanged(v);
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _drag = null);
          });
        },
      );
}

class _Bars extends StatelessWidget {
  const _Bars({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final h in const [9.0, 16.0, 6.0, 12.0]) ...[
            Container(width: 3, height: h, color: color),
            const SizedBox(width: 2),
          ],
        ],
      );
}

/// Перерисовка каждые полсекунды — для полоски времени у пульта.
class _Ticker extends StatefulWidget {
  const _Ticker({required this.builder});
  final WidgetBuilder builder;

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> {
  late final Timer _t = Timer.periodic(const Duration(milliseconds: 500), (_) {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    _t.isActive;
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Мини-плеер-пульт на телефоне: музыка играет на другом устройстве.
class RemoteMini extends StatelessWidget {
  const RemoteMini({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<DeviceSync>();
    final a = sync.active;
    final t = a?.track;
    if (a == null || t == null) return const SizedBox.shrink();
    final st = HutredStyle.of(context);
    final k = Sk.of(context);
    final scheme = Theme.of(context).colorScheme;
    final r = st.sharp ? 0.0 : st.glass ? 18.0 : 10.0;
    return Padding(
      padding: st.sharp
          ? EdgeInsets.zero
          : EdgeInsets.fromLTRB(st.glass ? 10 : 8, 0, st.glass ? 10 : 8, st.glass ? 8 : 6),
      child: Material(
        color: st.glass
            ? const Color(0xFF0C3B3D).withValues(alpha: 0.72)
            : st.sharp
                ? scheme.surface
                : scheme.surfaceContainerHighest,
        shape: st.sharp
            ? const Border(top: BorderSide(color: Color(0xFF222222)))
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context, rootNavigator: true)
              .push(MaterialPageRoute(builder: (_) => const RemoteNowScreen())),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Row(children: [
                Artwork(track: t, size: 46, radius: st.sharp ? 0 : st.glass ? 12 : 4),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(t.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: HutredTheme.muted)),
                  ]),
                ),
                const DevicesButton(),
                IconButton(
                  tooltip: 'Пауза на «${a.name}»',
                  iconSize: 32,
                  onPressed: () => sync.command(a.id, 'toggle'),
                  icon: Icon(Ic.pause_rounded),
                ),
                IconButton(
                  tooltip: 'Следующий',
                  onPressed: () => sync.command(a.id, 'next'),
                  icon: Icon(Ic.skip_next_rounded),
                ),
              ]),
            ),
            DevicesStrip(radius: k.sharp ? 0 : 0),
          ]),
        ),
      ),
    );
  }
}

/// Нижняя панель-пульт на компьютере: музыка играет на телефоне.
class RemoteBar extends StatelessWidget {
  const RemoteBar({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<DeviceSync>();
    final a = sync.active;
    final t = a?.track;
    if (a == null || t == null) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const DevicesStrip(align: MainAxisAlignment.end),
      Container(
        height: 84,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).canvasColor,
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
        ),
        child: Row(children: [
          Expanded(
            flex: 3,
            child: Row(children: [
              Artwork(track: t, size: 52, radius: 6),
              const SizedBox(width: 12),
              Flexible(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(t.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: HutredTheme.muted)),
                ]),
              ),
            ]),
          ),
          Expanded(
            flex: 4,
            child: _RemoteControls(device: a, compact: true),
          ),
          Expanded(
            flex: 3,
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              const DevicesButton(),
              SizedBox(
                width: 150,
                child: _VolumeSlider(value: a.volume, onChanged: (v) => sync.command(a.id, 'volume', v: v)),
              ),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

class _RemoteControls extends StatelessWidget {
  const _RemoteControls({required this.device, this.compact = false});
  final RemoteDevice device;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sync = context.read<DeviceSync>();
    final k = Sk.of(context);
    final big = compact ? 40.0 : 72.0;
    return Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          tooltip: 'Предыдущий',
          iconSize: compact ? 24 : 32,
          onPressed: () => sync.command(device.id, 'prev'),
          icon: Icon(Ic.skip_previous_rounded),
        ),
        SizedBox(width: compact ? 8 : 24),
        Material(
          color: k.btn,
          shape: k.sharp ? const RoundedRectangleBorder() : const CircleBorder(),
          child: InkWell(
            customBorder: k.sharp ? const RoundedRectangleBorder() : const CircleBorder(),
            onTap: () => sync.command(device.id, 'toggle'),
            child: SizedBox.square(
              dimension: big,
              child: Icon(device.playing ? Ic.pause_rounded : Ic.play_arrow_rounded,
                  size: big * 0.5, color: k.btnFg),
            ),
          ),
        ),
        SizedBox(width: compact ? 8 : 24),
        IconButton(
          tooltip: 'Следующий',
          iconSize: compact ? 24 : 32,
          onPressed: () => sync.command(device.id, 'next'),
          icon: Icon(Ic.skip_next_rounded),
        ),
      ]),
      _Ticker(builder: (context) {
        final pos = device.position;
        final dur = device.duration;
        final max = dur.inMilliseconds <= 0 ? 1.0 : dur.inMilliseconds.toDouble();
        return Row(children: [
          Text(_fmt(pos), style: k.small.copyWith(fontSize: 11)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Slider(
                  value: pos.inMilliseconds.toDouble().clamp(0, max),
                  max: max,
                  onChanged: (_) {},
                  onChangeEnd: (v) => sync.command(device.id, 'seek', ms: v.round()),
                ),
              ),
            ),
          ),
          Text(_fmt(dur), style: k.small.copyWith(fontSize: 11)),
        ]);
      }),
    ]);
  }
}

/// Полноэкранный пульт на телефоне.
class RemoteNowScreen extends StatelessWidget {
  const RemoteNowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<DeviceSync>();
    final a = sync.active;
    final t = a?.track;
    final st = HutredStyle.of(context);
    final k = Sk.of(context);
    if (a == null || t == null) {
      // Музыка остановилась или переехала сюда — пульт больше не нужен.
      WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.of(context).maybePop());
      return const Scaffold();
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Свернуть',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
        ),
        centerTitle: true,
        title: Text(st.sharp ? 'ПУЛЬТ' : 'Пульт', style: k.capStyle),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: LayoutBuilder(
                    builder: (context, box) => Artwork(
                        track: t, size: box.maxWidth, radius: st.sharp ? 0 : st.glass ? 22 : 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: st.display(24)),
                const SizedBox(height: 4),
                Text(t.artist, style: const TextStyle(fontSize: 16, color: HutredTheme.muted)),
              ]),
            ),
            const SizedBox(height: 12),
            _RemoteControls(device: a),
            const SizedBox(height: 16),
            Material(
              color: k.ok.withValues(alpha: 0.12),
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => showDevices(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_kindIcon(a.kind), size: 16, color: k.ok),
                    const SizedBox(width: 8),
                    Text('Играет на «${a.name}»',
                        style: TextStyle(fontWeight: FontWeight.w700, color: k.ok)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
