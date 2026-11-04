import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../models/track.dart';
import 'library_store.dart';
import 'player_service.dart';

/// Ссылки hutred://play?... — с сайта (кнопка «Слушать трек» в Discord)
/// открывают трек прямо в приложении.
class DeepLinks {
  /// Адрес сайта: страница трека (кнопка в Discord ведёт сюда).
  static const site = 'https://whenuknowmeuseemeshine.github.io/hutred';

  /// Ссылка на страницу трека для кнопки в Discord (не длиннее 512 символов).
  static String? pageFor(Track t) {
    if (t.source == TrackSource.local) return null;
    Uri build(bool withCover) => Uri.parse('$site/listen/').replace(queryParameters: {
          's': t.source.name,
          'u': t.uri,
          't': t.title,
          'a': t.artist,
          if (withCover && t.artworkUrl != null && t.artworkUrl!.startsWith('https://'))
            'c': t.artworkUrl!,
        });
    var u = build(true).toString();
    if (u.length > 512) u = build(false).toString();
    return u.length > 512 ? null : u;
  }

  /// Регистрирует hutred:// в Windows, чтобы браузер мог открыть приложение.
  static Future<void> registerWindows() async {
    if (kIsWeb || !Platform.isWindows) return;
    final exe = Platform.resolvedExecutable;
    const key = r'HKCU\Software\Classes\hutred';
    try {
      await Process.run('reg', ['add', key, '/ve', '/d', 'URL:Hutred', '/f']);
      await Process.run('reg', ['add', key, '/v', 'URL Protocol', '/d', '', '/f']);
      await Process.run(
          'reg', ['add', '$key\\shell\\open\\command', '/ve', '/d', '"$exe" "%1"', '/f']);
    } catch (e) {
      debugPrint('[Ссылки] не удалось зарегистрировать hutred://: $e');
    }
  }

  static Future<void> start({required LibraryStore store, required PlayerService player}) async {
    await registerWindows();
    final links = AppLinks();
    Future<void> handle(Uri uri) async {
      if (uri.scheme != 'hutred') return;
      final q = uri.queryParameters;
      final src = TrackSource.values.where((s) => s.name == q['s']).firstOrNull;
      final id = q['u'];
      if (src == null || id == null || id.isEmpty || src == TrackSource.local) return;
      final known = store.findBySource(src, id);
      final t = known ??
          Track(
            id: Track.newId(),
            title: q['t'] ?? 'Трек',
            artist: q['a'] ?? Track.unknownArtist,
            source: src,
            uri: id,
            artworkUrl: q['c'],
            addedAt: DateTime.now(),
          );
      await player.playTracks([t]);
    }

    try {
      final first = await links.getInitialLink();
      if (first != null) unawaited(handle(first));
    } catch (_) {}
    links.uriLinkStream.listen(handle, onError: (_) {});
  }
}
