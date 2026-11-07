import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/painting.dart' show HSLColor;
import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'library_store.dart';
import 'offline_service.dart';
import 'player_service.dart';
import 'settings_store.dart';
import 'wave_service.dart';

/// Виджеты на рабочем столе (Android и iPhone).
///
/// Приложение кладёт в общую папку widget.json и картинки, а виджет
/// рисует их сам. Кнопки виджета: на Android — медиакнопки (их ловит
/// плеер даже без открытого приложения), на iPhone — через канал
/// `hutred/widget`. Нажатие на обложку или плейлист открывает
/// `hutred://widget/open?item=…`.
class WidgetSync {
  WidgetSync({
    required this.player,
    required this.store,
    required this.settings,
    required this.wave,
  });

  final PlayerService player;
  final LibraryStore store;
  final SettingsStore settings;
  final WaveService wave;

  static const _ch = MethodChannel('hutred/widget');
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Directory? _dir;
  Timer? _debounce;
  Timer? _tick;
  String _lastJson = '';
  String _lastKey = '';
  final _colors = <String, int>{};

  Future<void> start() async {
    if (!supported) return;
    try {
      final path = await _ch.invokeMethod<String>('dir');
      if (path == null) return;
      _dir = Directory(path);
      await _dir!.create(recursive: true);
    } catch (e) {
      debugPrint('[Виджет] нет папки: $e');
      return;
    }
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'command') await command('${call.arguments}');
      return null;
    });
    player.addListener(_soon);
    store.addListener(_soon);
    settings.addListener(_soon);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (player.playing) _soon();
    });
    _soon();
    try {
      await _ch.invokeMethod('ready');
    } catch (_) {}
  }

  void dispose() {
    _debounce?.cancel();
    _tick?.cancel();
    player.removeListener(_soon);
    store.removeListener(_soon);
    settings.removeListener(_soon);
  }

  /// Команда от виджета: toggle, next, prev, like, open:<item>.
  Future<void> command(String cmd) async {
    switch (cmd) {
      case 'toggle':
        if (player.current == null) {
          await wave.start();
        } else {
          await player.togglePlay();
        }
      case 'next':
        await player.next();
      case 'prev':
        await player.previous();
      case 'like':
        final t = player.current;
        if (t != null) store.toggleFavorite(t.id);
      default:
        if (cmd.startsWith('open:')) await openItem(cmd.substring(5));
    }
  }

  /// Включить то, что нажали на виджете.
  Future<void> openItem(String item) async {
    if (item == 'wave') {
      if (!wave.isWaveTrack(player.current)) await wave.start();
      return;
    }
    if (item == 'now') return;
    List<Track> tracks;
    if (item == 'fav') {
      tracks = store.favorites;
    } else if (item == 'downloads') {
      final off = OfflineService.instance;
      tracks = off == null ? const [] : store.tracks.where(off.isDownloaded).toList();
    } else if (item.startsWith('pl:')) {
      final id = item.substring(3);
      final p = store.playlists.where((p) => p.id == id).firstOrNull;
      tracks = p == null ? const [] : store.tracksOf(p);
    } else {
      return;
    }
    if (tracks.isNotEmpty) await player.playAll(tracks);
  }

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => unawaited(_push()));
  }

  Future<void> _push() async {
    final dir = _dir;
    if (dir == null) return;
    try {
      final t = player.current;
      final cover = t == null ? null : await _image(t.artworkUrl, 'cover');
      final palette = await _palette(t?.artworkUrl, cover);
      final tiles = await _tiles();
      final dur = player.duration?.inMilliseconds ?? 0;
      final pos = player.position.inMilliseconds;
      final data = {
        'title': t?.title ?? 'Hutred',
        'artist': t?.artist ?? 'Нажми, чтобы включить волну',
        'playing': player.playing,
        'progress': dur <= 0 ? 0.0 : (pos / dur).clamp(0.0, 1.0),
        'favorite': t?.favorite ?? false,
        'cover': cover,
        'sharp': settings.style == 'sharp' && !settings.widgetCover,
        ...palette,
        'tiles': tiles,
      };
      final json = jsonEncode(data);
      if (json == _lastJson) return;
      // На iPhone число перерисовок виджета ограничено системой — из-за
      // одного прогресса не перерисовываем.
      final key = jsonEncode({...data, 'progress': 0});
      final onlyProgress = key == _lastKey;
      _lastJson = json;
      _lastKey = key;
      final f = File('${dir.path}/widget.json');
      final tmp = File('${dir.path}/widget.json.part');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(f.path);
      if (onlyProgress && Platform.isIOS) return;
      await _ch.invokeMethod('refresh');
    } catch (e) {
      debugPrint('[Виджет] $e');
    }
  }

  /// Квадраты быстрого доступа: любимые, волна, скачанные, плейлисты.
  Future<List<Map<String, Object?>>> _tiles() async {
    final out = <Map<String, Object?>>[
      {'id': 'fav', 'name': 'Любимые', 'kind': 'fav'},
      {'id': 'wave', 'name': 'Моя волна', 'kind': 'wave'},
    ];
    final off = OfflineService.instance;
    if (off != null && store.tracks.any(off.isDownloaded)) {
      out.add({'id': 'downloads', 'name': 'Скачанные', 'kind': 'downloads'});
    }
    for (final p in store.playlists) {
      if (out.length >= 8) break;
      final tracks = store.tracksOf(p);
      final art = p.cover ??
          tracks.map((t) => t.artworkUrl).whereType<String>().firstOrNull;
      out.add({
        'id': 'pl:${p.id}',
        'name': p.name,
        'kind': 'playlist',
        'image': await _image(art, 'pl_${p.id}'),
      });
    }
    return out;
  }

  /// Картинка в общую папку (имя файла) или null.
  Future<String?> _image(String? src, String key) async {
    final dir = _dir;
    if (src == null || src.isEmpty || dir == null) return null;
    final name = '${key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}_${_hash(src)}.img';
    final f = File('${dir.path}/$name');
    if (await f.exists()) return name;
    try {
      Uint8List bytes;
      if (src.startsWith('http')) {
        final res = await http.get(Uri.parse(src)).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) return null;
        bytes = res.bodyBytes;
      } else {
        final local = File(OfflineService.fixPath(src));
        if (!await local.exists()) return null;
        bytes = await local.readAsBytes();
      }
      // Виджету большие картинки не нужны — сжимаем до 300 точек.
      final small = await _shrink(bytes, 300);
      // Старые версии этой же картинки убираем.
      final prefix = '${key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}_';
      await for (final e in dir.list()) {
        final n = e.uri.pathSegments.last;
        if (n.startsWith(prefix) && n != name) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
      await f.writeAsBytes(small ?? bytes, flush: true);
      return name;
    } catch (e) {
      debugPrint('[Виджет] картинка: $e');
      return null;
    }
  }

  static Future<Uint8List?> _shrink(Uint8List bytes, int size) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: size, targetHeight: size);
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      return png?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static String _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }

  /// Цвета виджета: под обложку или как стиль приложения.
  Future<Map<String, int>> _palette(String? art, String? coverFile) async {
    if (settings.widgetCover && coverFile != null) {
      final base = _colors[art ?? ''] ?? await _dominant(coverFile);
      if (base != null) {
        _colors[art ?? ''] = base;
        final hsl = HSLColor.fromColor(ui.Color(base));
        final bg = hsl
            .withSaturation(hsl.saturation.clamp(0.0, 0.7))
            .withLightness(0.26)
            .toColor()
            .toARGB32();
        return {
          'bg': bg,
          'fg': 0xFFFFFFFF,
          'muted': 0xC8FFFFFF,
          'play': 0xFFFFFFFF,
          'playFg': bg,
          'tile': 0x29FFFFFF,
        };
      }
    }
    return switch (settings.style) {
      'glass' => {
          'bg': 0xFF0C3B3D,
          'fg': 0xFFFFFFFF,
          'muted': 0xFFBFDCD8,
          'play': 0xFF3DDC97,
          'playFg': 0xFF06221F,
          'tile': 0x29FFFFFF,
        },
      'sharp' => {
          'bg': 0xFF0A0A0A,
          'fg': 0xFFF2F2F2,
          'muted': 0xFFA0A0A0,
          'play': 0xFF3DDC97,
          'playFg': 0xFF000000,
          'tile': 0xFF1C1C1C,
        },
      _ => {
          'bg': 0xFF141414,
          'fg': 0xFFF5F5F5,
          'muted': 0xFFA3A3A3,
          'play': 0xFFF5F5F5,
          'playFg': 0xFF000000,
          'tile': 0xFF262626,
        },
    };
  }

  /// Средний «живой» цвет обложки (яркие пиксели весят больше серых).
  Future<int?> _dominant(String file) async {
    try {
      final bytes = await File('${_dir!.path}/$file').readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 24, targetHeight: 24);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      if (data == null) return null;
      double r = 0, g = 0, b = 0, w = 0;
      for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
        final pr = data.getUint8(i), pg = data.getUint8(i + 1), pb = data.getUint8(i + 2);
        final mx = [pr, pg, pb].reduce((a, c) => a > c ? a : c);
        final mn = [pr, pg, pb].reduce((a, c) => a < c ? a : c);
        final weight = 0.15 + (mx - mn) / 255.0;
        r += pr * weight;
        g += pg * weight;
        b += pb * weight;
        w += weight;
      }
      if (w == 0) return null;
      return ui.Color.fromARGB(255, (r / w).round(), (g / w).round(), (b / w).round()).toARGB32();
    } catch (_) {
      return null;
    }
  }
}
