import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/dpi_bypass.dart';

/// Картинка из сети, которая не сдаётся с первого раза:
/// берётся из кэша на диске, иначе качается через обход/VPN,
/// а если не вышло — ещё раз напрямую.
class NetArt extends ImageProvider<NetArt> {
  const NetArt(this.url, {this.scale = 1.0});

  final String url;
  final double scale;

  @override
  Future<NetArt> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(NetArt key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: scale, debugLabel: url);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await ArtCache.get(url);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is NetArt && other.url == url && other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale);
}

/// Скачанные картинки: кэш на диске и очередь, чтобы не забивать сеть
/// сотней запросов разом (на телефоне через обход это и роняло обложки).
class ArtCache {
  ArtCache._();

  static Future<Directory?>? _dir;
  static final _inflight = <String, Future<Uint8List>>{};
  static int _running = 0;
  static final _waiting = <Completer<void>>[];
  static const _maxParallel = 6;

  static Future<Directory?> _folder() => _dir ??= () async {
        try {
          final base = await getTemporaryDirectory();
          final d = Directory('${base.path}${Platform.pathSeparator}hutred_art');
          await d.create(recursive: true);
          return d;
        } catch (_) {
          return null;
        }
      }();

  static String _name(String url) {
    // FNV-1a 64 — стабильное имя файла для ссылки.
    var h = 0xcbf29ce484222325;
    for (final c in url.codeUnits) {
      h ^= c;
      h = h * 0x100000001b3;
    }
    return h.toUnsigned(64).toRadixString(16);
  }

  static Future<Uint8List> get(String url) =>
      _inflight[url] ??= _get(url).whenComplete(() => _inflight.remove(url));

  static Future<Uint8List> _get(String url) async {
    final dir = await _folder();
    final file = dir == null ? null : File('${dir.path}${Platform.pathSeparator}${_name(url)}');
    if (file != null) {
      try {
        if (await file.exists()) {
          final b = await file.readAsBytes();
          if (b.isNotEmpty) return b;
        }
      } catch (_) {}
    }
    await _slot();
    try {
      final b = await _download(url);
      if (file != null) unawaited(file.writeAsBytes(b, flush: false).catchError((_) => file));
      return b;
    } finally {
      _release();
    }
  }

  static Future<void> _slot() async {
    if (_running < _maxParallel) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
  }

  static void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _running--;
    }
  }

  static Future<Uint8List> _download(String url) async {
    final uri = Uri.parse(url);
    Object? last;
    // 1) как все запросы приложения (через обход/VPN, если включены);
    // 2) напрямую — если обход/прокси отвалились;
    // 3) ещё раз обычным путём (прокси мог перезапуститься).
    for (final direct in [false, true, false]) {
      if (direct && !DpiBypass.mayGoDirect) continue;
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      if (direct) c.findProxy = (_) => 'DIRECT';
      try {
        final req = await c.getUrl(uri).timeout(const Duration(seconds: 10));
        final res = await req.close().timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) {
          await res.drain<void>().catchError((_) {});
          throw HttpException('HTTP ${res.statusCode}', uri: uri);
        }
        final b = await consolidateHttpClientResponseBytes(res).timeout(const Duration(seconds: 20));
        if (b.isEmpty) throw HttpException('пусто', uri: uri);
        return b;
      } catch (e) {
        last = e;
        if (!direct) await DpiBypass.ensureAlive();
      } finally {
        c.close(force: true);
      }
    }
    throw last ?? HttpException('не загрузилось', uri: uri);
  }
}
