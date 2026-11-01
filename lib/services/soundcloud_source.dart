import 'dart:async';
import 'dart:convert';

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/remote.dart';
import '../models/track.dart';
import 'youtube_source.dart';
import 'yt_dlp.dart';

/// SoundCloud: поиск, добавление по ссылке, воспроизведение и похожие треки.
/// Работает через публичный API сайта (тот же, что использует soundcloud.com).
class SoundcloudSource {
  final http.Client _client = http.Client();
  String? _clientId;
  Future<String>? _clientIdFuture;

  static const _api = 'api-v2.soundcloud.com';
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/126.0 Safari/537.36',
  };

  static bool isSoundcloudUrl(String s) =>
      RegExp(r'(^|\.|//)(soundcloud\.com|snd\.sc|on\.soundcloud\.com)',
              caseSensitive: false)
          .hasMatch(s);

  /// Ключ клиента сайта: берём его из скриптов soundcloud.com.
  Future<String> _getClientId({bool refresh = false}) {
    if (refresh) {
      _clientId = null;
      _clientIdFuture = null;
    }
    if (_clientId != null) return Future.value(_clientId);
    return _clientIdFuture ??= () async {
      // Ключ, сохранённый с прошлого запуска, экономит 2–3 запроса.
      if (!refresh) {
        final saved = await _readSavedId();
        if (saved != null) return _clientId = saved;
      }
      try {
        final page = await _client
            .get(Uri.https('soundcloud.com', '/'), headers: _headers)
            .timeout(const Duration(seconds: 12));
        final scripts = RegExp(r'<script[^>]+src="(https://[^"]+\.js)"')
            .allMatches(page.body)
            .map((m) => m.group(1)!)
            .toList()
            .reversed;
        final idRe = RegExp(r'client_id\s*[:=]\s*"([a-zA-Z0-9]{20,40})"');
        for (final src in scripts) {
          final js = await _client
              .get(Uri.parse(src), headers: _headers)
              .timeout(const Duration(seconds: 12));
          final m = idRe.firstMatch(js.body);
          if (m != null) {
            _clientId = m.group(1)!;
            await _writeSavedId(_clientId!);
            return _clientId!;
          }
        }
        throw Exception('SoundCloud: не удалось получить ключ клиента');
      } catch (e) {
        _clientIdFuture = null;
        rethrow;
      }
    }();
  }

  /// GET к API с автоматическим обновлением ключа, если он протух.
  Future<dynamic> _getJson(String path, Map<String, String> params) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final id = await _getClientId(refresh: attempt > 0);
      final res = await _client
          .get(Uri.https(_api, path, {...params, 'client_id': id}),
              headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 401 || res.statusCode == 403) continue;
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) {
        throw Exception('SoundCloud ответил ${res.statusCode}');
      }
      return jsonDecode(utf8.decode(res.bodyBytes));
    }
    throw Exception('SoundCloud не принял ключ клиента');
  }

  /// Поиск с подгрузкой следующих страниц.
  Future<Paged<Track>> searchPaged(String query, {int offset = 0}) async {
    const limit = 20;
    final data = await _getJson('/search/tracks',
        {'q': query, 'limit': '$limit', 'offset': '$offset'});
    final items = data is Map ? data['collection'] as List? : null;
    final hasMore = data is Map && data['next_href'] != null;
    return Paged(
      _toTracks(items),
      hasMore ? () => searchPaged(query, offset: offset + limit) : null,
    );
  }

  Future<List<RemotePlaylist>> searchPlaylists(String query) async {
    final data = await _getJson(
        '/search/playlists', {'q': query, 'limit': '20', 'offset': '0'});
    final items = data is Map ? data['collection'] as List? : null;
    return (items ?? const []).whereType<Map>().where((p) {
      return (p['track_count'] as num? ?? 0) > 0 && p['permalink_url'] != null;
    }).map((p) {
      final user = p['user'] is Map ? p['user'] as Map : const {};
      final art = (p['artwork_url'] as String?) ?? (user['avatar_url'] as String?);
      return RemotePlaylist(
        source: TrackSource.soundcloud,
        url: p['permalink_url'] as String,
        title: '${p['title'] ?? 'Плейлист'}',
        owner: '${user['username'] ?? 'SoundCloud'}',
        count: (p['track_count'] as num?)?.toInt(),
        artworkUrl: art?.replaceFirst('-large.', '-t500x500.'),
      );
    }).toList();
  }

  Future<List<Track>> search(String query, {int limit = 20}) async {
    final data = await _getJson(
        '/search/tracks', {'q': query, 'limit': '$limit', 'offset': '0'});
    final items = data is Map ? data['collection'] as List? : null;
    return _toTracks(items);
  }

  /// Трек или плейлист (sets) по ссылке.
  Future<List<Track>> fromUrl(String url) async {
    final data = await _getJson('/resolve', {'url': url});
    if (data is! Map) throw Exception('Ссылка SoundCloud не найдена');
    final kind = data['kind'];
    if (kind == 'track') {
      final t = _toTrack(data);
      if (t == null) throw Exception('Этот трек на SoundCloud недоступен для прослушивания');
      return [t];
    }
    if (kind == 'playlist') {
      final tracks = (data['tracks'] as List? ?? const []).whereType<Map>().toList();
      // В плейлисте полные данные есть только у первых треков, остальные догружаем.
      final missing = tracks
          .where((t) => t['title'] == null)
          .map((t) => '${t['id']}')
          .toList();
      final full = <String, Map>{
        for (final t in tracks.where((t) => t['title'] != null)) '${t['id']}': t,
      };
      for (var i = 0; i < missing.length; i += 50) {
        final chunk = missing.sublist(i, i + 50 > missing.length ? missing.length : i + 50);
        final more = await _getJson('/tracks', {'ids': chunk.join(',')});
        for (final t in (more as List? ?? const []).whereType<Map>()) {
          full['${t['id']}'] = t;
        }
      }
      return _toTracks(tracks.map((t) => full['${t['id']}']).whereType<Map>().toList());
    }
    throw Exception('Поддерживаются ссылки на треки и плейлисты SoundCloud');
  }

  /// Похожие треки (для «Моей волны»).
  Future<List<Track>> related(String trackId, {int limit = 20}) async {
    final data = await _getJson('/tracks/$trackId/related', {'limit': '$limit'});
    final items = data is Map ? data['collection'] as List? : null;
    return _toTracks(items);
  }

  /// Страница исполнителя на SoundCloud: аватар, подписчики и популярные треки.
  Future<ScArtist?> artist(String name) async {
    final data = await _getJson('/search/users', {'q': name, 'limit': '8'});
    final users = (data is Map ? data['collection'] as List? : null) ?? const [];
    Map? best;
    var bestScore = -1.0;
    for (final u in users.whereType<Map>()) {
      final un = '${u['username'] ?? ''}';
      final full = '${u['full_name'] ?? ''}';
      String compact(String x) => _norm(x).replaceAll(' ', '');
      final sameCompact = compact(name).isNotEmpty &&
          (compact(name) == compact(un) || compact(name) == compact(full));
      final sim = sameCompact
          ? 1.0
          : [_similar(name, un), _similar(name, full)].reduce((a, b) => a > b ? a : b);
      if (sim < 0.99) continue;
      final followers = (u['followers_count'] as num?)?.toDouble() ?? 0;
      // Из одноимённых берём самого популярного (это обычно сам артист).
      final score = sim + followers / 1e9 + (u['verified'] == true ? 1 : 0);
      if (score > bestScore) {
        bestScore = score;
        best = u;
      }
    }
    if (best == null) return null;
    final id = best['id'];
    var tracks = <Track>[];
    try {
      final top = await _getJson('/users/$id/toptracks', {'limit': '30'});
      tracks = _toTracks(top is Map ? top['collection'] as List? : null);
    } catch (_) {}
    if (tracks.isEmpty) {
      final all = await _getJson('/users/$id/tracks', {'limit': '30'});
      tracks = _toTracks(all is Map ? all['collection'] as List? : null);
    }
    String? avatar = best['avatar_url'] as String?;
    avatar = avatar?.replaceFirst('-large.', '-t500x500.');
    return ScArtist(
      name: '${best['username'] ?? name}',
      avatarUrl: avatar,
      followers: (best['followers_count'] as num?)?.toInt() ?? 0,
      url: best['permalink_url'] as String?,
      tracks: tracks.where((t) => t.durationMs == null || t.durationMs! >= 60000).toList(),
    );
  }

  /// Находит трек на SoundCloud по исполнителю и названию.
  Future<Track?> match(String artist, String title) async {
    final hasArtist = artist.isNotEmpty && artist != Track.unknownArtist;
    final found = await search(hasArtist ? '$artist $title' : title, limit: 8);
    Track? best;
    var bestScore = 0.0;
    for (final t in found) {
      final score = _similar(title, t.title) * 2 +
          (hasArtist ? _similar(artist, '${t.artist} ${t.title}') : 1);
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    return bestScore >= 2.2 ? best : null;
  }

  Future<File> _idFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}soundcloud_id.txt');
  }

  Future<String?> _readSavedId() async {
    try {
      final f = await _idFile();
      if (!await f.exists()) return null;
      final v = (await f.readAsString()).trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSavedId(String id) async {
    try {
      await (await _idFile()).writeAsString(id);
    } catch (_) {}
  }

  final Map<String, Future<File>> _downloads = {};

  static Future<Directory> cacheDir() async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}soundcloud_audio');
    await dir.create(recursive: true);
    return dir;
  }

  /// Заранее скачивает следующий трек.
  void prefetch(String trackId) {
    cachedAudio(trackId).ignore();
  }

  /// Скачивает трек в кэш и возвращает файл. Плеер не всегда открывает
  /// потоки SoundCloud напрямую, а из файла играет всегда.
  Future<File> cachedAudio(String trackId) =>
      _downloads.putIfAbsent(trackId, () => _downloadOnce(trackId));

  Future<File> _downloadOnce(String trackId) async {
    try {
      return await _download(trackId);
    } finally {
      // Ошибку не запоминаем, чтобы можно было попробовать ещё раз.
      scheduleMicrotask(() => _downloads.remove(trackId));
    }
  }

  Future<File> _download(String trackId) async {
    final dir = await cacheDir();
    final cached = await YtDlp.findCached(dir, trackId);
    if (cached != null) return cached;

    Object? lastError;
    try {
      final file = await _downloadDirect(trackId, dir);
      if (file != null) return file;
    } catch (e) {
      lastError = e;
      debugPrint('[SoundCloud] $trackId: $e');
    }
    // Запасной путь: yt-dlp понимает SoundCloud по id трека.
    final viaYtDlp = await YtDlp.download(
        'https://api.soundcloud.com/tracks/$trackId', dir, trackId);
    if (viaYtDlp != null) return viaYtDlp;
    throw lastError ?? Exception('SoundCloud не отдал звук этого трека');
  }

  Future<File?> _downloadDirect(String trackId, Directory dir) async {
    final streams = await _resolveStreams(trackId);
    Object? lastError;
    for (final st in streams) {
      final file =
          File('${dir.path}${Platform.pathSeparator}$trackId.${st.ext}');
      final part = File('${file.path}.part');
      try {
        final sink = part.openWrite();
        try {
          if (st.hls) {
            await _downloadHls(st.url, sink);
          } else {
            await _downloadPlain(st.url, sink);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (await part.length() < 10 * 1024) {
          throw Exception('SoundCloud отдал слишком маленький файл');
        }
        await part.rename(file.path);
        return file;
      } catch (e) {
        lastError = e;
        debugPrint('[SoundCloud] $trackId, ${st.hls ? 'HLS' : 'файл'} ${st.ext}: $e');
        try {
          if (await part.exists()) await part.delete();
        } catch (_) {}
      }
    }
    if (lastError != null) throw lastError;
    return null;
  }

  Future<void> _downloadPlain(Uri url, IOSink sink) async {
    final req = http.Request('GET', url)..headers.addAll(_headers);
    final res = await _client.send(req).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('код ${res.statusCode}');
    await sink.addStream(res.stream);
  }

  /// HLS: плейлист из кусочков. Скачиваем кусочки по порядку в один файл.
  Future<void> _downloadHls(Uri url, IOSink sink, {int depth = 0}) async {
    final res = await _client
        .get(url, headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('плейлист: код ${res.statusCode}');
    final lines = const LineSplitter().convert(res.body).map((l) => l.trim()).toList();

    // Главный плейлист со ссылками на варианты качества — берём первый.
    if (lines.any((l) => l.startsWith('#EXT-X-STREAM-INF')) && depth == 0) {
      final variant = lines.firstWhere((l) => l.isNotEmpty && !l.startsWith('#'));
      return _downloadHls(url.resolve(variant), sink, depth: 1);
    }
    final key = lines.firstWhere((l) => l.startsWith('#EXT-X-KEY'), orElse: () => '');
    if (key.isNotEmpty && !key.contains('METHOD=NONE')) {
      throw Exception('поток зашифрован');
    }
    final map = lines.firstWhere((l) => l.startsWith('#EXT-X-MAP'), orElse: () => '');
    final mapUri = RegExp(r'URI="([^"]+)"').firstMatch(map)?.group(1);
    final segments = [
      if (mapUri != null) mapUri,
      ...lines.where((l) => l.isNotEmpty && !l.startsWith('#')),
    ];
    if (segments.isEmpty) throw Exception('пустой плейлист');
    for (final seg in segments) {
      final r = await _client
          .get(url.resolve(seg), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw Exception('кусок: код ${r.statusCode}');
      sink.add(r.bodyBytes);
    }
  }

  /// Ссылки на потоки трека, от лучшего к худшему.
  Future<List<({Uri url, bool hls, String ext})>> _resolveStreams(
      String trackId) async {
    final data = await _getJson('/tracks/$trackId', {});
    if (data is! Map) throw Exception('Трек удалён с SoundCloud');
    if (data['policy'] == 'BLOCK') {
      throw Exception('SoundCloud заблокировал трек в твоём регионе');
    }
    final media = data['media'];
    final transcodings = ((media is Map ? media['transcodings'] : null) as List? ??
            const [])
        .whereType<Map>()
        .where((t) => t['snipped'] != true)
        .toList();

    String protocolOf(Map t) =>
        '${(t['format'] is Map ? t['format'] as Map : const {})['protocol']}';
    String mimeOf(Map t) =>
        '${(t['format'] is Map ? t['format'] as Map : const {})['mime_type']}';
    int rank(Map t) {
      final p = protocolOf(t);
      final mime = mimeOf(t);
      if (p == 'progressive') return 0;
      if (p == 'hls' && mime.contains('mpeg')) return 1; // mp3-кусочки
      if (p == 'hls' && (mime.contains('mp4') || mime.contains('aac'))) return 2;
      return 9; // opus и зашифрованные варианты пропускаем
    }

    final usable = transcodings.where((t) => rank(t) < 9).toList()
      ..sort((a, b) => rank(a).compareTo(rank(b)));
    if (usable.isEmpty) {
      throw Exception('SoundCloud отдаёт этот трек только в защищённом виде');
    }

    final auth = data['track_authorization'] as String?;
    final out = <({Uri url, bool hls, String ext})>[];
    for (final t in usable) {
      final id = await _getClientId();
      final uri = Uri.parse(t['url'] as String).replace(queryParameters: {
        'client_id': id,
        if (auth != null) 'track_authorization': auth,
      });
      final res = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        debugPrint('[SoundCloud] $trackId: ссылка на поток, код ${res.statusCode}');
        continue;
      }
      final url = (jsonDecode(res.body) as Map)['url'] as String?;
      if (url == null) continue;
      final mime = mimeOf(t);
      out.add((
        url: Uri.parse(url),
        hls: protocolOf(t) == 'hls',
        ext: mime.contains('mpeg') ? 'mp3' : 'm4a',
      ));
    }
    if (out.isEmpty) throw Exception('SoundCloud не отдал ссылку на поток');
    return out;
  }

  List<Track> _toTracks(List? items) =>
      (items ?? const []).whereType<Map>().map(_toTrack).whereType<Track>().toList();

  Track? _toTrack(Map j) {
    final id = j['id'];
    final title = j['title'] as String?;
    if (id == null || title == null) return null;
    // SNIP — только превью (Go+), BLOCK — недоступен.
    final policy = j['policy'];
    if (policy == 'SNIP' || policy == 'BLOCK') return null;
    if (j['streamable'] == false) return null;
    // Треки только с зашифрованными потоками не показываем вовсе:
    // плеер их не откроет, а ждать ошибку — долго.
    final media = j['media'];
    if (media is Map && media['transcodings'] is List) {
      final playable = (media['transcodings'] as List).whereType<Map>().any((t) {
        final f = t['format'] is Map ? t['format'] as Map : const {};
        final p = '${f['protocol']}';
        return t['snipped'] != true && (p == 'progressive' || p == 'hls');
      });
      if (!playable) return null;
    }

    final user = j['user'] is Map ? j['user'] as Map : const {};
    final meta =
        j['publisher_metadata'] is Map ? j['publisher_metadata'] as Map : const {};
    final metaArtist = (meta['artist'] as String?)?.trim();
    final uploader = (user['username'] as String?)?.trim() ?? '';
    final split = YoutubeSource.splitTitle(
        title, (metaArtist != null && metaArtist.isNotEmpty) ? metaArtist : uploader);

    String? art = (j['artwork_url'] as String?) ?? (user['avatar_url'] as String?);
    art = art?.replaceFirst('-large.', '-t500x500.');

    return Track(
      id: Track.newId(),
      title: split.title,
      artist: split.artist,
      album: (meta['album_title'] as String?) ?? '',
      source: TrackSource.soundcloud,
      uri: '$id',
      durationMs: (j['duration'] as num?)?.toInt(),
      artworkUrl: art,
      addedAt: DateTime.now(),
    );
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  static double _similar(String a, String b) {
    final wa = _norm(a).split(' ').where((w) => w.isNotEmpty).toSet();
    final wb = _norm(b).split(' ').where((w) => w.isNotEmpty).toSet();
    if (wa.isEmpty || wb.isEmpty) return 0;
    return wa.intersection(wb).length / wa.length;
  }
}


/// Исполнитель на SoundCloud.
class ScArtist {
  const ScArtist({
    required this.name,
    required this.avatarUrl,
    required this.followers,
    required this.url,
    required this.tracks,
  });
  final String name;
  final String? avatarUrl;
  final int followers;
  final String? url;
  final List<Track> tracks;
}
