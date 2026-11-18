import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/remote.dart';
import '../models/track.dart';
import 'genius_service.dart';

/// Audius — открытая музыкальная площадка (много андерграунда и рэпа).
/// Треки целиком, без ключей, звук — обычный mp3 по ссылке, поэтому
/// включается сразу. В приложении такой трек — «по ссылке» (TrackSource.url).
class AudiusSource {
  AudiusSource({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  static const _api = 'api.audius.co';
  static const _app = 'Hutred';

  /// Ссылка на звук трека Audius.
  static String streamUrl(String id) => 'https://$_api/v1/tracks/$id/stream?app_name=$_app';

  /// Трек из Audius? (по ссылке на звук)
  static bool isAudius(Track t) =>
      t.source == TrackSource.url && t.uri.startsWith('https://$_api/v1/tracks/');

  Future<dynamic> _get(String path, Map<String, String> q) async {
    final res = await _http
        .get(Uri.https(_api, path, {...q, 'app_name': _app}))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Audius ответил ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  List<Track> _tracks(dynamic j) {
    final list = j is Map ? j['data'] as List? : null;
    final out = <Track>[];
    for (final t in (list ?? const []).whereType<Map>()) {
      if (t['is_streamable'] == false) continue;
      final id = t['id'];
      final title = t['title'];
      if (id is! String || title is! String) continue;
      final user = t['user'] is Map ? t['user'] as Map : const {};
      final art = t['artwork'] is Map ? t['artwork'] as Map : const {};
      out.add(Track(
        id: Track.newId(),
        title: title.trim(),
        artist: '${user['name'] ?? Track.unknownArtist}'.trim(),
        source: TrackSource.url,
        uri: streamUrl(id),
        durationMs: (t['duration'] as num?) == null ? null : ((t['duration'] as num) * 1000).round(),
        artworkUrl: (art['480x480'] ?? art['1000x1000'] ?? art['150x150']) as String?,
        coverChecked: art.isNotEmpty,
        addedAt: DateTime.now(),
      ));
    }
    return out;
  }

  Future<List<Track>> search(String query, {int limit = 20}) async =>
      _tracks(await _get('/v1/tracks/search', {'query': query, 'limit': '$limit'}));

  Future<Paged<Track>> searchPaged(String query, {int offset = 0}) async {
    const limit = 20;
    final items = _tracks(await _get(
        '/v1/tracks/search', {'query': query, 'limit': '$limit', 'offset': '$offset'}));
    return Paged(
      items,
      items.length >= limit ? () => searchPaged(query, offset: offset + limit) : null,
    );
  }

  /// Тот же трек на Audius (исполнитель + название, длина ±20 с).
  Future<Track?> match(String artist, String title, {int? durationMs}) async {
    final hasArtist = artist.isNotEmpty && artist != Track.unknownArtist;
    final found = await search(hasArtist ? '$artist $title' : title, limit: 10);
    Track? best;
    var bestScore = 0.0;
    for (final t in found) {
      if (t.durationMs != null && t.durationMs! < 60000) continue;
      if (durationMs != null && t.durationMs != null && (durationMs - t.durationMs!).abs() > 20000) {
        continue;
      }
      final score = GeniusService.similar(title, t.title) * 2 +
          (hasArtist ? GeniusService.similar(artist, '${t.artist} ${t.title}') : 1);
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    // Порог строже, чем у SoundCloud: на Audius много ремиксов и «type beat».
    return bestScore >= 2.4 ? best : null;
  }
}
