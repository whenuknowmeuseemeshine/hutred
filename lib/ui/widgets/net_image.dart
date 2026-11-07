import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/dpi_bypass.dart';

/// Картинка из сети. На компьютере — обычная загрузка Flutter (она там
/// работает надёжно), на телефоне — своя: с кэшем на диске и повтором,
/// потому что iOS рвёт соединения, пока приложение в фоне.
ImageProvider netImage(String url) {
  if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) return NetworkImage(url);
  return NetArt(url);
}

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
    final got = await ArtCache.get(url);
    try {
      return await decode(await ui.ImmutableBuffer.fromUint8List(got.bytes));
    } catch (_) {
      // Испорченный файл в кэше — выбрасываем и качаем заново.
      if (!got.fromDisk) rethrow;
      await ArtCache.forget(url);
      final fresh = await ArtCache.get(url);
      return decode(await ui.ImmutableBuffer.fromUint8List(fresh.bytes));
    }
  }

  @override
  bool operator ==(Object other) => other is NetArt && other.url == url && other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale);
}

/// Скачанные картинки: кэш на диске и ограничение одновременных загрузок.
class ArtCache {
  ArtCache._();

  static Future<Directory?>? _dir;
  static final _inflight = <String, Future<({Uint8List bytes, bool fromDisk})>>{};
  static int _running = 0;
  static final _waiting = <Completer<void>>[];
  static const _maxParallel = 8;

  static Future<Directory?> _folder() => _dir ??= () async {
        try {
          final base = await getTemporaryDirectory();
          final d = Directory('${base.path}${Platform.pathSeparator}hutred_art2');
          await d.create(recursive: true);
          return d;
        } catch (_) {
          return null;
        }
      }();

  static String _name(String url) {
    // FNV-1a — стабильное имя файла для ссылки (без знака минус).
    var h = 0x811c9dc5;
    var g = 0;
    for (final c in url.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
      g = (g * 31 + c) & 0x7FFFFFFF;
    }
    return '${h.toRadixString(16)}${g.toRadixString(16)}_${url.length}';
  }

  static Future<File?> _file(String url) async {
    final dir = await _folder();
    return dir == null ? null : File('${dir.path}${Platform.pathSeparator}${_name(url)}');
  }

  /// Похоже на картинку (jpeg, png, gif, webp, bmp)?
  static bool looksLikeImage(Uint8List b) {
    if (b.length < 12) return false;
    if (b[0] == 0xFF && b[1] == 0xD8) return true; // jpeg
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return true; // png
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true; // gif
    if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return true; // webp
    }
    if (b[0] == 0x42 && b[1] == 0x4D) return true; // bmp
    return false;
  }

  static Future<void> forget(String url) async {
    try {
      await (await _file(url))?.delete();
    } catch (_) {}
  }

  static Future<({Uint8List bytes, bool fromDisk})> get(String url) =>
      _inflight[url] ??= _get(url).whenComplete(() => _inflight.remove(url));

  static Future<({Uint8List bytes, bool fromDisk})> _get(String url) async {
    final file = await _file(url);
    if (file != null) {
      try {
        if (await file.exists()) {
          final b = await file.readAsBytes();
          if (looksLikeImage(b)) return (bytes: b, fromDisk: true);
          await file.delete();
        }
      } catch (_) {}
    }
    await _slot();
    try {
      final b = await _download(url);
      if (file != null) unawaited(_save(file, b));
      return (bytes: b, fromDisk: false);
    } finally {
      _release();
    }
  }

  /// Пишем во временный файл и переименовываем — недописанный файл
  /// никогда не окажется в кэше.
  static Future<void> _save(File file, Uint8List b) async {
    try {
      final part = File('${file.path}.part');
      await part.writeAsBytes(b, flush: true);
      await part.rename(file.path);
    } catch (_) {}
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

  static Future<Uint8List> _fetch(Uri uri, {required bool direct}) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    if (direct) c.findProxy = (_) => 'DIRECT';
    try {
      final req = await c.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) {
        await res.drain<void>().catchError((_) {});
        throw HttpException('HTTP ${res.statusCode}', uri: uri);
      }
      final b = await consolidateHttpClientResponseBytes(res);
      if (!looksLikeImage(b)) throw HttpException('не картинка', uri: uri);
      return b;
    } finally {
      c.close(force: true);
    }
  }

  static Future<Uint8List> _download(String url) async {
    final uri = Uri.parse(url);
    try {
      // Обычным путём (через обход/VPN, если включены).
      return await _fetch(uri, direct: false).timeout(const Duration(seconds: 20));
    } catch (e) {
      // Ответ сервера «нет такой картинки» — повторять бесполезно.
      if (e is HttpException && e.message.startsWith('HTTP 4')) rethrow;
      // Прокси обхода мог умереть, пока приложение было в фоне.
      await DpiBypass.ensureAlive();
      if (DpiBypass.mayGoDirect) {
        try {
          return await _fetch(uri, direct: true).timeout(const Duration(seconds: 20));
        } catch (_) {}
      }
      return _fetch(uri, direct: false).timeout(const Duration(seconds: 20));
    }
  }
}
