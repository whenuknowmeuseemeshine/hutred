import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../config.dart';
import '../services/dpi_bypass.dart';
import '../services/settings_store.dart';
import '../services/soundcloud_source.dart';
import '../services/spotify_service.dart';
import 'theme.dart';

/// «Проверка связи»: что из сервисов открывается, а что нет.
/// Удобно, чтобы друг прислал скриншот, если что-то не работает.
Future<void> showNetCheck(BuildContext context) => showDialog(
      context: context,
      builder: (_) => const _NetCheckDialog(),
    );

class _Check {
  _Check(this.name, this.run);
  final String name;
  final Future<String> Function() run;
  String? result;
  bool ok = false;
  int ms = 0;
}

class _NetCheckDialog extends StatefulWidget {
  const _NetCheckDialog();

  @override
  State<_NetCheckDialog> createState() => _NetCheckDialogState();
}

class _NetCheckDialogState extends State<_NetCheckDialog> {
  late final List<_Check> _checks;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsStore>();
    final sc = context.read<SoundcloudSource>();
    final sp = context.read<SpotifyService>();

    Future<String> reach(String url) async {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      return 'отвечает (код ${r.statusCode}, ${(r.bodyBytes.length / 1024).toStringAsFixed(0)} КБ)';
    }

    _checks = [
      if (HutredConfig.cloudEnabled)
        _Check('Облако Hutred', () => reach(HutredConfig.supabaseUrl)),
      _Check('SoundCloud — поиск', () async {
        final r = await sc.search('lofi', limit: 3).timeout(const Duration(seconds: 15));
        return r.isEmpty ? throw Exception('пустой ответ') : 'нашёл ${r.length}';
      }),
      _Check('SoundCloud — звук', () async {
        final r = await sc.search('lofi', limit: 1).timeout(const Duration(seconds: 15));
        if (r.isEmpty) throw Exception('нечего проверить');
        final f = await sc.cachedAudio(r.first.uri).timeout(const Duration(seconds: 90));
        final kb = (await f.length()) ~/ 1024;
        return 'скачался ($kb КБ)${SoundcloudSource.throttled ? ', кусками' : ''}';
      }),
      _Check('Spotify', () async {
        if (!settings.hasSpotifyKeys) throw Exception('нет ключей Spotify');
        final r = await sp
            .searchTracks(id: settings.spotifyId, secret: settings.spotifySecret, query: 'test')
            .timeout(const Duration(seconds: 15));
        return 'нашёл ${r.items.length}';
      }),
      _Check('YouTube', () => reach('https://www.youtube.com/')),
    ];
    _runAll();
  }

  Future<void> _runAll() async {
    await Future.wait(_checks.map((c) async {
      final sw = Stopwatch()..start();
      try {
        c.result = await c.run();
        c.ok = true;
      } on TimeoutException {
        c.result = 'не ответил вовремя (соединение замирает)';
      } catch (e) {
        final t = '$e'.replaceFirst('Exception: ', '');
        c.result = t.length > 140 ? '${t.substring(0, 140)}…' : t;
      }
      c.ms = sw.elapsedMilliseconds;
      if (mounted) setState(() {});
    }));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Проверка связи'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Обход блокировок: ${DpiBypass.enabled ? 'включён' : 'выключен'}',
              style: const TextStyle(color: HutredTheme.muted),
            ),
            const SizedBox(height: 8),
            for (final c in _checks)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: c.result == null
                    ? const SizedBox.square(
                        dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(c.ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                        color: c.ok ? scheme.primary : Colors.redAccent),
                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(c.result == null
                    ? 'проверяю…'
                    : '${c.result} · ${(c.ms / 1000).toStringAsFixed(1)} с'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
      ],
    );
  }
}
