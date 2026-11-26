import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'xray_vpn.dart';

/// Запуск внешней программы yt-dlp (только ПК). Она умеет скачивать звук
/// с YouTube, SoundCloud и сотен других сайтов и быстро чинится,
/// когда сайты что-то меняют.
class YtDlp {
  static bool? _available;

  /// Почему yt-dlp не скачал последний трек (для «Проверки связи» и ошибок).
  static String? lastError;

  static bool get _desktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Где искать yt-dlp: в PATH, в папке проекта, рядом с hutred.exe
  /// и в папке, куда его ставит winget.
  static List<String> _candidates() => [
        if (Platform.isWindows) bundled,
        'yt-dlp',
        '${Directory.current.path}${Platform.pathSeparator}yt-dlp.exe',
        '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}yt-dlp.exe',
        if (Platform.environment['LOCALAPPDATA'] != null)
          '${Platform.environment['LOCALAPPDATA']}\\Microsoft\\WinGet\\Links\\yt-dlp.exe',
      ];

  /// Свой yt-dlp, который ставится вместе с Hutred (Windows).
  static String get bundled =>
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}yt-dlp.exe';

  /// Есть ли yt-dlp, которым точно можно пользоваться.
  static bool get hasBundled => Platform.isWindows && File(bundled).existsSync();

  /// Раз в сутки обновляет свой yt-dlp: YouTube часто всё ломает,
  /// а yt-dlp чинят за день-два.
  static Future<void> selfUpdate(Directory stateDir) async {
    if (!hasBundled) return;
    try {
      final stamp = File('${stateDir.path}${Platform.pathSeparator}yt-dlp.updated');
      if (await stamp.exists()) {
        final last = await stamp.lastModified();
        if (DateTime.now().difference(last) < const Duration(hours: 20)) return;
      }
      final r = await Process.run(bundled, ['-U']).timeout(const Duration(minutes: 2));
      debugPrint('[yt-dlp] обновление: ${r.stdout}'.trim());
      await stamp.writeAsString(DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('[yt-dlp] не удалось обновить: $e');
    }
  }

  /// Прямая ссылка на звук без скачивания — чтобы Hutred сам качал её
  /// кусками и начинал играть сразу (yt-dlp целиком качает долго).
  static Future<({Uri url, int size, String ext, Map<String, String> headers})?> streamInfo(
    String url, {
    String cookiesBrowser = '',
  }) async {
    if (!_desktop || _available == false) return null;
    for (final exe in _candidates()) {
      if (exe != 'yt-dlp' && !File(exe).existsSync()) continue;
      try {
        final r = await Process.run(exe, [
          if (cookiesBrowser.isNotEmpty) ...['--cookies-from-browser', cookiesBrowser],
          if (XrayVpn.active && XrayVpn.port != null) ...['--proxy', 'http://127.0.0.1:${XrayVpn.port}'],
          '--no-playlist',
          '--js-runtimes', 'node',
          '--socket-timeout', '5',
          '--extractor-retries', '0',
          '-f', 'bestaudio[ext=m4a]/bestaudio[ext=mp3]/bestaudio',
          '-j',
          url,
        ], stdoutEncoding: utf8).timeout(const Duration(seconds: 40));
        _available = true;
        if (r.exitCode != 0) return null;
        final j = jsonDecode('${r.stdout}'.trim().split('\n').last);
        if (j is! Map) return null;
        final direct = j['url'];
        final size = (j['filesize'] ?? j['filesize_approx']) as num?;
        final proto = '${j['protocol'] ?? 'https'}';
        if (direct is! String || size == null || size <= 0 || !proto.startsWith('http')) return null;
        final h = j['http_headers'];
        return (
          url: Uri.parse(direct),
          // Приблизительный размер не годится: файл бы обрезался.
          size: j['filesize'] == null ? 0 : size.toInt(),
          ext: '${j['ext'] ?? 'm4a'}',
          headers: h is Map
              ? {
                  for (final e in h.entries)
                    // Сжатие не просим: иначе куски файла не сойдутся по размеру.
                    if ('${e.key}'.toLowerCase() != 'accept-encoding') '${e.key}': '${e.value}',
                }
              : <String, String>{},
        );
      } on ProcessException {
        continue;
      } catch (e) {
        debugPrint('[yt-dlp] ссылка $url: $e');
        return null;
      }
    }
    _available = false;
    return null;
  }

  /// Скачивает звук по ссылке в [dir] под именем [baseName].<расширение>.
  static Future<File?> download(
    String url,
    Directory dir,
    String baseName, {
    String cookiesBrowser = '',
  }) async {
    if (!_desktop || _available == false) return null;
    for (final exe in _candidates()) {
      if (exe != 'yt-dlp' && !File(exe).existsSync()) continue;
      try {
        final r = await Process.run(exe, [
          if (cookiesBrowser.isNotEmpty) ...['--cookies-from-browser', cookiesBrowser],
          if (XrayVpn.active && XrayVpn.port != null) ...['--proxy', 'http://127.0.0.1:${XrayVpn.port}'],
          '--no-playlist',
          '--no-progress',
          '--js-runtimes', 'node',
          '-f', 'bestaudio[ext=m4a]/bestaudio[ext=mp3]/bestaudio',
          '-o', '${dir.path}${Platform.pathSeparator}$baseName.%(ext)s',
          url,
        ]).timeout(const Duration(minutes: 3));
        _available = true;
        if (r.exitCode != 0) {
          debugPrint('[yt-dlp] $url: ${r.stderr}');
          final lines = '${r.stderr}'
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.startsWith('ERROR') || l.contains('error'))
              .toList();
          lastError = lines.isEmpty ? 'код ${r.exitCode}' : lines.last;
          return null;
        }
        lastError = null;
        return await findCached(dir, baseName);
      } on ProcessException {
        continue; // по этому пути yt-dlp нет
      } catch (e) {
        debugPrint('[yt-dlp] $url: $e');
        return null;
      }
    }
    _available = false;
    lastError = 'yt-dlp не найден рядом с Hutred';
    debugPrint('[yt-dlp] не найден: установи его или положи yt-dlp.exe в папку проекта');
    return null;
  }

  static const audioExts = ['m4a', 'mp3', 'webm', 'opus', 'ogg', 'aac'];

  static Future<File?> findCached(Directory dir, String baseName) async {
    for (final ext in audioExts) {
      final f = File('${dir.path}${Platform.pathSeparator}$baseName.$ext');
      if (await f.exists() && await f.length() > 0) return f;
    }
    return null;
  }
}
