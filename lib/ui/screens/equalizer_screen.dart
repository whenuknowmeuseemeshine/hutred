import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/player_service.dart';
import '../../services/settings_store.dart';
import '../theme.dart';
import '../widgets/settings_kit.dart';

/// Эквалайзер: полосы частот и готовые настройки.
class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key, this.embedded = false, this.card = false});

  /// Карточкой по макету настроек: пресеты в шапке и 10 вертикальных полос.
  final bool card;

  /// Встроен прямо в настройки (без своей шапки и прокрутки).
  final bool embedded;

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  EqInfo? _params;
  bool _loading = true;
  late bool _on;
  late List<double> _gains;

  // Готовые настройки: доли от максимального усиления по полосам (от низких к высоким).
  static const _presets = <String, List<double>>{
    'Ровно': [0, 0, 0, 0, 0],
    'Громкие басы': [1, 0.6, 0.1, 0, 0.1],
    'Бас': [0.7, 0.4, 0, 0, 0.1],
    'Вокал': [-0.2, 0.1, 0.5, 0.4, 0.1],
    'Рок': [0.5, 0.2, -0.2, 0.3, 0.5],
    'Электроника': [0.6, 0.3, 0, 0.3, 0.6],
    'Тише басы': [-0.5, -0.3, 0, 0, 0],
  };

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsStore>();
    _on = s.eqOn;
    _gains = List.of(s.eqGains);
    _load();
  }

  Future<void> _load() async {
    final p = await context.read<PlayerService>().eqParameters();
    if (!mounted) return;
    setState(() {
      _params = p;
      _loading = false;
      if (p != null && _gains.length != p.bands.length) {
        _gains = List.filled(p.bands.length, 0.0);
      }
    });
  }

  void _apply() {
    context.read<SettingsStore>().setEqualizer(_on, _gains);
    context.read<PlayerService>().setEqualizer(_on, _gains);
  }

  String _freq(double hz) => hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz >= 10000 ? 0 : 1)} кГц' : '${hz.round()} Гц';

  List<double> _presetGains(List<double> pr, EqInfo p) => [
        for (var i = 0; i < p.bands.length; i++)
          (pr[(i * pr.length / p.bands.length).floor()] *
                  (pr[(i * pr.length / p.bands.length).floor()] >= 0 ? p.max : -p.min))
              .toDouble(),
      ];

  void _usePreset(List<double> pr, EqInfo p) {
    setState(() {
      _on = true;
      _gains = _presetGains(pr, p);
    });
    _apply();
  }

  String _short(double hz) => hz >= 1000
      ? '${(hz / 1000).toStringAsFixed(hz >= 10000 || hz % 1000 == 0 ? 0 : 1)}к'
      : '${hz.round()}';

  Widget _cardView(BuildContext context) {
    final k = Sk.of(context);
    final player = context.read<PlayerService>();
    final p = _params;
    String? note;
    if (!player.eqSupported) {
      note = 'На iPhone эквалайзер недоступен: системный плеер iOS не даёт менять частоты.';
    } else if (_loading) {
      note = 'Загружаю…';
    } else if (p == null) {
      note = 'Включи любой трек — полосы появятся.';
    }
    String? active;
    if (p != null && _on) {
      for (final e in _presets.entries) {
        final g = _presetGains(e.value, p);
        var same = g.length == _gains.length;
        for (var i = 0; same && i < g.length; i++) {
          if ((g[i] - _gains[i]).abs() > 0.05) same = false;
        }
        if (same) {
          active = e.key;
          break;
        }
      }
    }
    return SkCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, box) {
          final head = SkHead(
            title: 'Эквалайзер',
            sub: p == null
                ? 'Полосы частот и готовые настройки'
                : '${p.bands.length} полос${p.bands.length >= 10 ? ' на компьютере' : ''}',
            trailing: SkToggle(
              value: _on,
              onChanged: p == null
                  ? null
                  : (v) {
                      setState(() => _on = v);
                      _apply();
                    },
            ),
          );
          final chips = Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _presets.entries)
              SkChip(e.key,
                  selected: active == e.key,
                  onTap: p == null ? null : () => _usePreset(e.value, p)),
          ]);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            head,
            const SizedBox(height: 14),
            chips,
          ]);
        }),
        const SizedBox(height: 18),
        if (note != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(note, style: k.sub),
          )
        else
          SizedBox(
            height: 240,
            child: Row(children: [
              for (var i = 0; i < p!.bands.length; i++)
                Expanded(
                  child: Column(children: [
                    Text(
                        '${_gains[i] > 0 ? '+' : ''}${_gains[i].abs() < 10 ? _gains[i].toStringAsFixed(_gains[i] == _gains[i].roundToDouble() ? 0 : 1) : _gains[i].round()}',
                        style: k.small.copyWith(fontSize: 11)),
                    const SizedBox(height: 6),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 6,
                          activeTrackColor: k.off,
                          inactiveTrackColor: k.off,
                          thumbColor: k.btn,
                          overlayColor: k.btn.withValues(alpha: 0.12),
                          thumbShape: RoundSliderThumbShape(
                              enabledThumbRadius: 10, disabledThumbRadius: 8),
                          trackShape: const RectangularSliderTrackShape(),
                          disabledThumbColor: k.dim,
                          disabledActiveTrackColor: k.off,
                          disabledInactiveTrackColor: k.off,
                        ),
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Slider(
                            min: p.min,
                            max: p.max,
                            value: _gains[i].clamp(p.min, p.max),
                            onChanged: _on ? (v) => setState(() => _gains[i] = v) : null,
                            onChangeEnd: (_) => _apply(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_short(p.bands[i]),
                        style: k.st
                            .caption(color: k.text, size: 11)
                            .copyWith(fontWeight: FontWeight.w600)),
                  ]),
                ),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.card) return _cardView(context);
    final player = context.read<PlayerService>();
    final p = _params;
    final body = !player.eqSupported
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'На iPhone эквалайзер недоступен: системный плеер iOS не даёт '
                'менять частоты. На компьютере и Android он работает.',
                style: TextStyle(color: HutredTheme.muted),
              ),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : p == null
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Включи любой трек — и открой эквалайзер снова.',
                          style: TextStyle(color: HutredTheme.muted)),
                    )
                  : ListView(
                      shrinkWrap: widget.embedded,
                      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
                      padding: widget.embedded
                          ? const EdgeInsets.fromLTRB(16, 0, 16, 8)
                          : const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Включить эквалайзер'),
                          value: _on,
                          onChanged: (v) {
                            setState(() => _on = v);
                            _apply();
                          },
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final e in _presets.entries)
                              ActionChip(
                                label: Text(e.key),
                                onPressed: () {
                                  setState(() {
                                    _on = true;
                                    _gains = [
                                      for (var i = 0; i < p.bands.length; i++)
                                        (e.value[(i * e.value.length / p.bands.length).floor()] *
                                                (e.value[(i * e.value.length / p.bands.length).floor()] >= 0
                                                    ? p.max
                                                    : -p.min))
                                            .toDouble(),
                                    ];
                                  });
                                  _apply();
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 260,
                          child: Row(
                            children: [
                              for (var i = 0; i < p.bands.length; i++)
                                Expanded(
                                  child: Column(
                                    children: [
                                      Text('${_gains[i] >= 0 ? '+' : ''}${_gains[i].toStringAsFixed(1)}',
                                          style: const TextStyle(fontSize: 11, color: HutredTheme.muted)),
                                      Expanded(
                                        child: RotatedBox(
                                          quarterTurns: 3,
                                          child: Slider(
                                            min: p.min,
                                            max: p.max,
                                            value: _gains[i].clamp(p.min, p.max),
                                            onChanged: _on
                                                ? (v) => setState(() => _gains[i] = v)
                                                : null,
                                            onChangeEnd: (_) => _apply(),
                                          ),
                                        ),
                                      ),
                                      Text(_freq(p.bands[i]),
                                          style: const TextStyle(fontSize: 11)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Эквалайзер')), body: body);
  }
}
