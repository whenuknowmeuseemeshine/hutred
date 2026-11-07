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

  /// Ссылка пришла снаружи — пускаем только то, что похоже на настоящий трек.
  static bool _validId(TrackSource src, String id) {
    if (id.length > 300) return false;
    switch (src) {
      case TrackSource.youtube:
        return RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(id);
      case TrackSource.soundcloud:
        if (RegExp(r'^\d{1,20}$').hasMatch(id)) return true;
        final u = Uri.tryParse(id);
        return u != null &&
            u.scheme == 'https' &&
            (u.host == 'soundcloud.com' || u.host.endsWith('.soundcloud.com'));
      case TrackSource.spotify:
        return RegExp(r'^(deezer:\d{1,15}|[A-Za-z0-9]{10,40})$').hasMatch(id);
      default:
        return false;
    }
  }

  static String? _https(String? url) {
    if (url == null || url.length > 600) return null;
    final u = Uri.tryParse(url);
    return u != null && u.scheme == 'https' && u.host.isNotEmpty ? url : null;
  }

  static String? _text(String? v) {
    if (v == null) return null;
    final t = v.replaceAll(RegExp(r'[\u0000-\u001f]'), ' ').trim();
    if (t.isEmpty) return null;
    return t.length > 200 ? t.substring(0, 200) : t;
  }

  /// Команды с виджета на рабочем столе (hutred://widget/…).
  static Future<void> Function(String cmd)? onWidget;

  static Future<void> start({required LibraryStore store, required PlayerService player}) async {
    await registerWindows();
    final links = AppLinks();
    Future<void> handle(Uri uri) async {
      // hutred://auth… — ссылки из писем (вход, сброс пароля), их
      // обрабатывает сам Supabase.
      if (uri.scheme == 'hutred' && uri.host == 'widget') {
        final w = onWidget;
        if (w == null) return;
        if (uri.path == '/open') {
          final item = uri.queryParameters['item'] ?? '';
          if (RegExp(r'^(fav|wave|downloads|now|pl:[A-Za-z0-9_.:-]{1,80})$').hasMatch(item)) {
            await w('open:$item');
          }
        } else if (const {'/toggle', '/next', '/prev', '/like'}.contains(uri.path)) {
          await w(uri.path.substring(1));
        }
        return;
      }
      if (uri.scheme != 'hutred' || uri.host != 'play') return;
      final q = uri.queryParameters;
      final src = TrackSource.values.where((s) => s.name == q['s']).firstOrNull;
      final id = q['u'];
      if (src == null || id == null || !_validId(src, id)) return;
      final known = store.findBySource(src, id);
      final t = known ??
          Track(
            id: Track.newId(),
            title: _text(q['t']) ?? 'Трек',
            artist: _text(q['a']) ?? Track.unknownArtist,
            source: src,
            uri: id,
            artworkUrl: _https(q['c']),
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
