import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../services/player_service.dart';
import '../../services/settings_store.dart';
import '../theme.dart';

/// Эквалайзер: полосы частот и готовые настройки.
class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  AndroidEqualizerParameters? _params;
  bool _loading = true;
  late bool _on;
  late List<double> _gains;

  // Готовые настройки: доли от максимального усиления по полосам (от низких к высоким).
  static const _presets = <String, List<double>>{
    'Ровно': [0, 0, 0, 0, 0],
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

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerService>();
    final p = _params;
    return Scaffold(
      appBar: AppBar(title: const Text('Эквалайзер')),
      body: !player.eqSupported
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Эквалайзер пока работает только на Android. На компьютере и iPhone '
                'для него нужен другой движок воспроизведения — это следующий шаг.',
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
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
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
                                                    ? p.maxDecibels
                                                    : -p.minDecibels))
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
                                            min: p.minDecibels,
                                            max: p.maxDecibels,
                                            value: _gains[i].clamp(p.minDecibels, p.maxDecibels),
                                            onChanged: _on
                                                ? (v) => setState(() => _gains[i] = v)
                                                : null,
                                            onChangeEnd: (_) => _apply(),
                                          ),
                                        ),
                                      ),
                                      Text(_freq(p.bands[i].centerFrequency),
                                          style: const TextStyle(fontSize: 11)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }
}
