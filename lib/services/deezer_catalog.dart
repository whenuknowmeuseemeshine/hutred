import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';

class DzArtist {
  DzArtist({required this.id, required this.name, this.picture, this.fans = 0, this.albums = 0});
  final int id;
  final String name;
  final String? picture;
  final int fans;
  final int albums;
}

class DzAlbum {
  DzAlbum({
    required this.id,
    required this.title,
    this.cover,
    this.released,
    this.type = 'album',
    this.tracks = 0,
  });
  final int id;
  final String title;
  final String? cover;
  final DateTime? released;

  /// album, single, ep, compile.
  final String type;
  final int tracks;

  String get typeLabel => switch (type) {
        'single' => 'Сингл',
        'ep' => 'EP',
        'compile' => 'Сборник',
        _ => 'Альбом',
      };
}

/// Каталог Deezer: открытый и без ключей — фото исполнителя, популярное,
/// альбомы, похожие. Треки играют так же, как найденные через поиск.
class DeezerCatalog {
  static final http.Client _http = http.Client();
  static final Map<String, Object?> _cache = {};

  static Future<Object?> _get(String path, [Map<String, String>? q]) async {
    final uri = Uri.https('api.deezer.com', path, q);
    final key = uri.toString();
    if (_cache.containsKey(key)) return _cache[key];
    final res = await _http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw Exception('Deezer ответил ${res.statusCode}');
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (j is Map && j['error'] != null) throw Exception('Deezer: ${j['error']}');
    _cache[key] = j;
    return j;
  }

  static List<Map> _data(Object? j) =>
      j is Map ? (j['data'] as List? ?? const []).whereType<Map>().toList() : const [];

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  /// Исполнитель по имени: точное совпадение, иначе самый популярный из найденных.
  static Future<DzArtist?> findArtist(String name) async {
    final list = _data(await _get('/search/artist', {'q': name, 'limit': '10'}));
    if (list.isEmpty) return null;
    final key = _norm(name);
    final exact = list.where((a) => _norm('${a['name']}') == key).toList()
      ..sort((a, b) => ((b['nb_fan'] as num?) ?? 0).compareTo((a['nb_fan'] as num?) ?? 0));
    final a = exact.isNotEmpty ? exact.first : null;
    if (a == null) return null;
    return _artist(a);
  }

  static DzArtist _artist(Map a) => DzArtist(
        id: (a['id'] as num).toInt(),
        name: '${a['name'] ?? ''}',
        picture: (a['picture_xl'] ?? a['picture_big'] ?? a['picture_medium']) as String?,
        fans: (a['nb_fan'] as num?)?.toInt() ?? 0,
        albums: (a['nb_album'] as num?)?.toInt() ?? 0,
      );

  static Track _track(Map it, {Map? album}) {
    final al = it['album'] is Map ? it['album'] as Map : (album ?? const {});
    final ar = it['artist'] is Map ? it['artist'] as Map : const {};
    return Track(
      id: Track.newId(),
      title: '${it['title'] ?? ''}',
      artist: '${ar['name'] ?? ''}',
      album: '${al['title'] ?? ''}',
      source: TrackSource.spotify,
      uri: 'deezer:${it['id']}',
      durationMs: (it['duration'] as num?) == null ? null : ((it['duration'] as num) * 1000).toInt(),
      artworkUrl: (al['cover_xl'] ?? al['cover_big'] ?? al['cover_medium']) as String?,
      coverChecked: true,
      addedAt: DateTime.now(),
    );
  }

  static Future<List<Track>> top(int artistId, {int limit = 10}) async => [
        for (final it in _data(await _get('/artist/$artistId/top', {'limit': '$limit'})))
          if ('${it['title'] ?? ''}'.isNotEmpty) _track(it),
      ];

  static Future<List<DzAlbum>> albums(int artistId) async {
    final out = [
      for (final a in _data(await _get('/artist/$artistId/albums', {'limit': '100'})))
        DzAlbum(
          id: (a['id'] as num).toInt(),
          title: '${a['title'] ?? ''}',
          cover: (a['cover_xl'] ?? a['cover_big'] ?? a['cover_medium']) as String?,
          released: DateTime.tryParse('${a['release_date'] ?? ''}'),
          type: '${a['record_type'] ?? 'album'}',
        ),
    ];
    // Свежие сверху; повторы (переиздания с тем же названием) убираем.
    out.sort((a, b) => (b.released ?? DateTime(1900)).compareTo(a.released ?? DateTime(1900)));
    final seen = <String>{};
    return [
      for (final a in out)
        if (seen.add('${_norm(a.title)}|${a.type}')) a,
    ];
  }

  static Future<List<DzArtist>> related(int artistId) async => [
        for (final a in _data(await _get('/artist/$artistId/related', {'limit': '12'}))) _artist(a),
      ];

  /// Треки альбома.
  static Future<List<Track>> albumTracks(int albumId) async {
    final j = await _get('/album/$albumId');
    if (j is! Map) return const [];
    final tracks = j['tracks'] is Map ? (j['tracks'] as Map)['data'] : null;
    return [
      for (final it in (tracks as List? ?? const []).whereType<Map>())
        if ('${it['title'] ?? ''}'.isNotEmpty) _track(it, album: j),
    ];
  }
}
