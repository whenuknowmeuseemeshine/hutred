import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/dpi_bypass.dart';

/// На телефонах и для обложек в Windows используем дисковый кэш и повтор загрузки.
ImageProvider netImage(String url, {bool cacheOnWindows = false}) {
  if (kIsWeb || !(Platform.isIOS || Platform.isAndroid ||
      (Platform.isWindows && cacheOnWindows))) {
    return NetworkImage(url);
  }
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
      MultiFrameImageStreamCompleter(codec: _load(key, decode), scale: scale, debugLabel: url);

  Future<ui.Codec> _load(NetArt key, ImageDecoderCallback decode) async {
    try {
      return await _decodeCover(decode);
    } catch (_) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  Future<ui.Codec> _decodeCover(ImageDecoderCallback decode) async {
    final got = await ArtCache.get(url);
    try {
      return await decode(await ui.ImmutableBuffer.fromUint8List(got.bytes));
    } catch (_) {
      await ArtCache.forget(url);
      if (!got.fromDisk) rethrow;
      final fresh = await ArtCache.get(url);
      try {
        return await decode(await ui.ImmutableBuffer.fromUint8List(fresh.bytes));
      } catch (_) {
        await ArtCache.forget(url);
        rethrow;
      }
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
  static const _maxCacheBytes = 128 * 1024 * 1024;
  static DateTime? _nextTrim;

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
      _inflight[url] ??= _get(url).whenComplete(() {
        // Без «=>»: remove вернул бы этот же Future, и whenComplete ждал бы сам себя.
        _inflight.remove(url);
      });

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
      if (file != null) {
        await _save(file, b);
        final now = DateTime.now();
        if (_nextTrim?.isAfter(now) != true) {
          _nextTrim = now.add(const Duration(minutes: 30));
          unawaited(_trim(file.parent));
        }
      }
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
      await part.writeAsBytes(b);
      await part.rename(file.path);
    } catch (_) {}
  }

  static Future<void> _trim(Directory dir) async {
    try {
      final entries = <({File file, FileStat stat})>[];
      var bytes = 0;
      await for (final file in dir.list(followLinks: false)) {
        if (file is! File || file.path.endsWith('.part')) continue;
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file) continue;
        entries.add((file: file, stat: stat));
        bytes += stat.size;
      }
      if (bytes <= _maxCacheBytes) return;
      entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
      for (final entry in entries) {
        if (bytes <= _maxCacheBytes) break;
        try {
          await entry.file.delete();
          bytes -= entry.stat.size;
        } on FileSystemException {
          // Файл мог исчезнуть после проверки или быть открыт другим процессом.
        }
      }
    } on FileSystemException {
      // Временная папка может стать недоступна во время очистки.
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

  /// Для «Проверки связи»: скачать картинку одним способом и описать итог.
  static Future<String> probe(String url, {required bool direct}) async {
    final b = await _fetch(Uri.parse(url), direct: direct);
    return 'картинка ${(b.length / 1024).toStringAsFixed(0)} КБ';
  }

  static Future<Uint8List> _fetch(
    Uri uri, {
    required bool direct,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    if (direct) c.findProxy = (_) => 'DIRECT';
    Future<Uint8List> read() async {
      final req = await c.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw NetworkImageLoadException(statusCode: res.statusCode, uri: uri);
      }
      final b = await consolidateHttpClientResponseBytes(res);
      if (!looksLikeImage(b)) throw HttpException('не картинка', uri: uri);
      return b;
    }
    try {
      return await read().timeout(timeout);
    } finally {
      c.close(force: true);
    }
  }

  static bool _permanentFailure(Object error) {
    if (error is! NetworkImageLoadException) return false;
    final status = error.statusCode;
    return status >= 400 && status < 500 && status != 408 && status != 429;
  }

  static Future<Uint8List> _download(String url) async {
    final uri = Uri.parse(url);
    // Обход блокировок включён, а своего VPN нет — картинки сначала
    // пробуем напрямую: сайты с обложками обычно не заблокированы,
    // а через обход сотня картинок разом идёт тяжело.
    if (DpiBypass.enabled && DpiBypass.mayGoDirect) {
      try {
        return await _fetch(uri, direct: true, timeout: const Duration(seconds: 10));
      } catch (e) {
        if (_permanentFailure(e)) rethrow;
      }
    }
    try {
      // Обычным путём (через обход/VPN, если включены).
      return await _fetch(uri, direct: false);
    } catch (e) {
      // Ответ сервера «нет такой картинки» — повторять бесполезно.
      if (_permanentFailure(e)) rethrow;
      // Прокси обхода мог умереть, пока приложение было в фоне.
      await DpiBypass.ensureAlive();
      if (DpiBypass.mayGoDirect) {
        try {
          return await _fetch(uri, direct: true);
        } catch (e) {
          if (_permanentFailure(e)) rethrow;
        }
      }
      return _fetch(uri, direct: false);
    }
  }
}
