import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/remote.dart';
import '../models/track.dart';
import 'genius_service.dart';
import 'meta_clean.dart';

/// Поиск обложек через официальный Spotify Web API.
/// Нужны Client ID и Client Secret своего приложения с developer.spotify.com.
class SpotifyService {
  final http.Client _client = _PacedClient();

  /// Spotify попросил подождать (код 429) — до этого времени не спрашиваем.
  static DateTime get coolingUntil => _PacedClient._blockedUntil;

  /// Spotify открывается только через облако Hutred.
  static bool get viaRelay => _PacedClient.viaRelay;
  String? _token;
  DateTime _tokenExpires = DateTime.fromMillisecondsSinceEpoch(0);
  String? _tokenFor;

  Future<String?> _getToken(String id, String secret) async {
    final key = '$id:$secret';
    if (_token != null && _tokenFor == key && DateTime.now().isBefore(_tokenExpires)) {
      return _token;
    }
    final res = await _client.post(
      Uri.https('accounts.spotify.com', '/api/token'),
      headers: {
        'Authorization': 'Basic ${base64Encode(utf8.encode(key))}',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: 'grant_type=client_credentials',
    ).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('Spotify не принял ключи (код ${res.statusCode})');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    _token = j['access_token'] as String?;
    _tokenFor = key;
    final ttl = (j['expires_in'] as num?)?.toInt() ?? 3600;
    _tokenExpires = DateTime.now().add(Duration(seconds: ttl - 60));
    return _token;
  }

  /// Проверка ключей из настроек.
  Future<void> checkKeys(String id, String secret) async {
    _token = null;
    await _getToken(id, secret);
  }

  /// Ссылка на обложку альбома (самую большую) или null.
  Future<String?> findCover(
      {required String id,
      required String secret,
      required String artist,
      required String title}) async {
    final token = await _getToken(id, secret);
    if (token == null) return null;
    final hasArtist = artist.isNotEmpty && artist != 'Неизвестный исполнитель';
    final res = await _client.get(
      Uri.https('api.spotify.com', '/v1/search', {
        'q': hasArtist ? 'track:$title artist:$artist' : title,
        'type': 'track',
        'limit': '5',
      }),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final tracks = data is Map ? data['tracks'] : null;
    final items = (tracks is Map ? tracks['items'] as List? : null) ?? const [];
    String? best;
    var bestScore = 0.0;
    for (final it in items.whereType<Map>()) {
      final name = it['name'] as String? ?? '';
      final artists = (it['artists'] as List? ?? const [])
          .whereType<Map>()
          .map((a) => a['name'] as String? ?? '')
          .join(' ');
      final score = GeniusService.similar(title, name) * 2 +
          (hasArtist ? GeniusService.similar(artist, artists) : 1);
      final images = (it['album'] is Map ? it['album']['images'] : null) as List?;
      if (images == null || images.isEmpty) continue;
      if (score > bestScore) {
        bestScore = score;
        best = (images.first as Map)['url'] as String?;
      }
    }
    return bestScore >= 2.3 ? best : null;
  }
}

extension SpotifyImport on SpotifyService {
  /// Лучшее совпадение в Spotify для трека (для сверки сведений) или null.
  Future<Track?> bestMatch(
      {required String id,
      required String secret,
      required String artist,
      required String title,
      int? durationMs}) async {
    final hasArtist = artist.isNotEmpty && artist != Track.unknownArtist;
    final page = await searchTracks(
        id: id, secret: secret, query: hasArtist ? '$artist $title' : title);
    Track? best;
    var bestScore = 0.0;
    for (final t in page.items.take(10)) {
      if (durationMs != null && t.durationMs != null &&
          (durationMs - t.durationMs!).abs() > 15000) {
        continue;
      }
      // Сравниваем в обе стороны: «Song (Official Video)» и «Song».
      // Нечётко: «сн» подходит к «сна», опечатка в одну букву прощается.
      final ts = [
        MetaClean.fuzzy(title, t.title),
        MetaClean.fuzzy(t.title, title),
      ].reduce((a, b) => a > b ? a : b);
      final ar = hasArtist
          ? [
              MetaClean.fuzzy(t.artist, '$artist $title'),
              MetaClean.fuzzy(artist, t.artist),
            ].reduce((a, b) => a > b ? a : b)
          // Исполнитель неизвестен — он мог оказаться в названии.
          : (MetaClean.fuzzy(t.artist, title) >= 0.99 ? 1.0 : 0.6);
      final score = ts * 2 + ar;
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    return bestScore >= 2.4 ? best : null;
  }

  /// Поиск треков в каталоге Spotify (нужны ключи). Сведения и обложки
  /// там самые точные — по ним лучше находятся тексты.
  Future<Paged<Track>> searchTracks(
      {required String id, required String secret, required String query, int offset = 0}) async {
    // Ключи Spotify общие на всех, и у них лимит запросов. Поэтому:
    // 1) одинаковые запросы помним на две недели;
    // 2) когда Spotify просит подождать (или недоступен) — ищем в каталоге
    //    Deezer: там те же названия, альбомы и обложки, а лимит — на каждого
    //    пользователя свой.
    final key = '${query.trim().toLowerCase()}|$offset';
    final cached = await _cacheGet(key);
    if (cached != null) return _paged(cached.$1, cached.$2, id, secret, query, offset);
    if (DateTime.now().isBefore(_PacedClient._blockedUntil)) {
      return _deezer(query, offset);
    }
    try {
      final page = await _spotifySearch(id: id, secret: secret, query: query, offset: offset);
      unawaited(_cachePut(key, page.$1, page.$2));
      return _paged(page.$1, page.$2, id, secret, query, offset);
    } catch (e) {
      try {
        return await _deezer(query, offset);
      } catch (_) {
        rethrow;
      }
    }
  }

  Paged<Track> _paged(List<Track> items, int total, String id, String secret, String query, int offset) {
    final next = offset + items.length;
    return Paged(
      items,
      items.isEmpty || next >= total || next >= 200
          ? null
          : () async => searchTracks(id: id, secret: secret, query: query, offset: next),
    );
  }

  // ---------- Кэш поиска ----------

  static Map<String, dynamic>? _cache;
  static File? _cacheFile;
  static Timer? _cacheSave;
  static const _cacheTtl = Duration(days: 14);

  Future<Map<String, dynamic>> _loadCache() async {
    if (_cache != null) return _cache!;
    try {
      final dir = await getApplicationSupportDirectory();
      _cacheFile = File('${dir.path}${Platform.pathSeparator}spotify_search_cache.json');
      if (await _cacheFile!.exists()) {
        final j = jsonDecode(await _cacheFile!.readAsString());
        if (j is Map<String, dynamic>) _cache = j;
      }
    } catch (_) {}
    return _cache ??= {};
  }

  Future<(List<Track>, int)?> _cacheGet(String key) async {
    final c = await _loadCache();
    final e = c[key];
    if (e is! Map) return null;
    final at = DateTime.tryParse('${e['at']}');
    if (at == null || DateTime.now().difference(at) > _cacheTtl) return null;
    try {
      return (
        [
          for (final t in (e['items'] as List))
            Track.fromJson(Map<String, dynamic>.from(t as Map)),
        ].map((t) => _fresh(t)).toList(),
        (e['total'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Новый id на каждую выдачу, как при настоящем поиске.
  static Track _fresh(Track t) => Track(
        id: Track.newId(),
        title: t.title,
        artist: t.artist,
        album: t.album,
        source: t.source,
        uri: t.uri,
        durationMs: t.durationMs,
        artworkUrl: t.artworkUrl,
        coverChecked: true,
        addedAt: DateTime.now(),
      );

  Future<void> _cachePut(String key, List<Track> items, int total) async {
    final c = await _loadCache();
    c[key] = {
      'at': DateTime.now().toIso8601String(),
      'total': total,
      'items': [for (final t in items) t.toJson()],
    };
    // Не даём файлу расти бесконечно.
    if (c.length > 3000) {
      final keys = c.keys.toList()
        ..sort((a, b) => '${(c[a] as Map)['at']}'.compareTo('${(c[b] as Map)['at']}'));
      for (final k in keys.take(c.length - 2500)) {
        c.remove(k);
      }
    }
    _cacheSave?.cancel();
    _cacheSave = Timer(const Duration(seconds: 3), () async {
      try {
        await _cacheFile?.writeAsString(jsonEncode(c));
      } catch (_) {}
    });
  }

  // ---------- Deezer: запасной каталог ----------

  final http.Client _dz = http.Client();

  Future<Paged<Track>> _deezer(String query, int offset) async {
    final res = await _dz
        .get(Uri.https('api.deezer.com', '/search', {
          'q': query,
          'limit': '10',
          'index': '$offset',
        }))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw Exception('Deezer ответил ${res.statusCode}');
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (j is! Map || j['error'] != null) throw Exception('Deezer: ${j is Map ? j['error'] : ''}');
    final out = <Track>[];
    for (final it in (j['data'] as List? ?? const []).whereType<Map>()) {
      final album = it['album'] is Map ? it['album'] as Map : const {};
      final artist = it['artist'] is Map ? it['artist'] as Map : const {};
      final title = '${it['title'] ?? ''}';
      if (title.isEmpty) continue;
      out.add(Track(
        id: Track.newId(),
        title: title,
        artist: '${artist['name'] ?? ''}',
        album: '${album['title'] ?? ''}',
        // Играет так же, как треки из каталога Spotify: звук с SoundCloud/YouTube.
        source: TrackSource.spotify,
        uri: 'deezer:${it['id']}',
        durationMs: (it['duration'] as num?) == null ? null : ((it['duration'] as num) * 1000).toInt(),
        artworkUrl: (album['cover_xl'] ?? album['cover_big']) as String?,
        coverChecked: true,
        addedAt: DateTime.now(),
      ));
    }
    final total = (j['total'] as num?)?.toInt() ?? out.length;
    final next = offset + out.length;
    return Paged(out, out.isEmpty || next >= total || next >= 200 ? null : () async => _deezer(query, next));
  }

  Future<(List<Track>, int)> _spotifySearch(
      {required String id, required String secret, required String query, int offset = 0}) async {
    final token = await _getToken(id, secret);
    final res = await _client.get(
      Uri.https('api.spotify.com', '/v1/search', {
        'q': query,
        'type': 'track',
        // Spotify теперь отдаёт в поиске не больше 10 за раз.
        'limit': '10',
        'offset': '$offset',
      }),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 12));
    if (res.statusCode == 429) {
      final left = _PacedClient._blockedUntil.difference(DateTime.now());
      throw Exception('Spotify просит подождать ещё ${_PacedClient._wait(left)}: '
          'слишком много запросов с общих ключей');
    }
    if (res.statusCode != 200) {
      String msg = '';
      try {
        final e = jsonDecode(utf8.decode(res.bodyBytes));
        msg = '${(e is Map ? e['error'] : null) is Map ? e['error']['message'] : ''}';
      } catch (_) {}
      throw Exception('Spotify ответил ${res.statusCode}${msg.isEmpty ? '' : ': $msg'}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final tracks = data is Map ? data['tracks'] : null;
    final items = (tracks is Map ? tracks['items'] as List? : null) ?? const [];
    final out = <Track>[];
    for (final it in items.whereType<Map>()) {
      final tid = it['id'] as String?;
      final name = it['name'] as String?;
      if (tid == null || name == null) continue;
      final album = it['album'] is Map ? it['album'] as Map : const {};
      final images = album['images'] as List? ?? const [];
      out.add(Track(
        id: Track.newId(),
        title: name,
        artist: (it['artists'] as List? ?? const [])
            .whereType<Map>()
            .map((a) => '${a['name'] ?? ''}')
            .where((a) => a.isNotEmpty)
            .join(', '),
        album: '${album['name'] ?? ''}',
        source: TrackSource.spotify,
        uri: tid,
        durationMs: (it['duration_ms'] as num?)?.toInt(),
        artworkUrl: images.isEmpty ? null : (images.first as Map)['url'] as String?,
        coverChecked: true,
        addedAt: DateTime.now(),
      ));
    }
    final total = (tracks is Map ? tracks['total'] as num? : null)?.toInt() ?? 0;
    return (out, total);
  }

  /// Без ключей: читаем открытую страницу-виджет Spotify (embed) —
  /// там есть название, исполнители и длительность каждого трека.
  Future<({String name, List<({String artist, String title, int? durationMs})> tracks})>
      listFromEmbed(String url) async {
    final m = RegExp(r'(playlist|album|track)[/:]([A-Za-z0-9]+)').firstMatch(url);
    if (m == null) throw Exception('Не понял ссылку Spotify');
    final res = await _client.get(
      Uri.https('open.spotify.com', '/embed/${m.group(1)}/${m.group(2)}'),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36',
        'Accept-Language': 'en',
      },
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Spotify не открыл ссылку (код ${res.statusCode})');
    }
    final html = utf8.decode(res.bodyBytes);
    final data = RegExp(
            r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
            dotAll: true)
        .firstMatch(html);
    if (data == null) throw Exception('Spotify изменил страницу — не смог прочитать треки');
    final j = jsonDecode(data.group(1)!);
    final e = j['props']?['pageProps']?['state']?['data']?['entity'];
    if (e is! Map) throw Exception('Плейлист закрытый или удалён');
    String clean(String s) => s.replaceAll('\u00a0', ' ').replaceAll('\u2060', '').trim();
    final out = <({String artist, String title, int? durationMs})>[];
    if (e['type'] == 'track') {
      final artists = (e['artists'] as List? ?? const [])
          .whereType<Map>()
          .map((a) => '${a['name'] ?? ''}')
          .where((a) => a.isNotEmpty)
          .join(', ');
      out.add((
        artist: clean(artists.isNotEmpty ? artists : '${e['subtitle'] ?? ''}'),
        title: clean('${e['title'] ?? e['name'] ?? ''}'),
        durationMs: (e['duration'] as num?)?.toInt(),
      ));
    } else {
      for (final t in (e['trackList'] as List? ?? const []).whereType<Map>()) {
        final title = clean('${t['title'] ?? ''}');
        if (title.isEmpty) continue;
        out.add((
          artist: clean('${t['subtitle'] ?? ''}'),
          title: title,
          durationMs: (t['duration'] as num?)?.toInt(),
        ));
      }
    }
    return (name: clean('${e['name'] ?? e['title'] ?? 'Из Spotify'}'), tracks: out);
  }

  /// Список «исполнитель — название» из плейлиста, альбома или трека Spotify.
  Future<List<({String artist, String title, int? durationMs})>> listFromUrl(
      {required String id, required String secret, required String url}) async {
    final m = RegExp(r'(playlist|album|track)[/:]([A-Za-z0-9]+)').firstMatch(url);
    if (m == null) throw Exception('Не понял ссылку Spotify');
    final kind = m.group(1)!;
    final itemId = m.group(2)!;
    final token = await _getToken(id, secret);
    final headers = {'Authorization': 'Bearer $token'};
    final out = <({String artist, String title, int? durationMs})>[];

    void addTrack(Map t) {
      final name = t['name'] as String?;
      if (name == null || name.isEmpty) return;
      final artists = (t['artists'] as List? ?? const [])
          .whereType<Map>()
          .map((a) => a['name'] as String? ?? '')
          .where((a) => a.isNotEmpty)
          .join(', ');
      out.add((artist: artists, title: name, durationMs: (t['duration_ms'] as num?)?.toInt()));
    }

    Future<dynamic> get(Uri u) async {
      final res = await _client.get(u, headers: headers).timeout(const Duration(seconds: 15));
      if (res.statusCode == 404) {
        throw Exception('Spotify не отдал плейлист: он закрытый или это подборка самого Spotify');
      }
      if (res.statusCode != 200) throw Exception('Spotify ответил кодом ${res.statusCode}');
      return jsonDecode(utf8.decode(res.bodyBytes));
    }

    if (kind == 'track') {
      final t = await get(Uri.https('api.spotify.com', '/v1/tracks/$itemId'));
      if (t is Map) addTrack(t);
      return out;
    }
    Uri? next = kind == 'playlist'
        ? Uri.https('api.spotify.com', '/v1/playlists/$itemId/tracks', {'limit': '100'})
        : Uri.https('api.spotify.com', '/v1/albums/$itemId/tracks', {'limit': '50'});
    while (next != null && out.length < 2000) {
      final page = await get(next);
      if (page is! Map) break;
      for (final it in (page['items'] as List? ?? const []).whereType<Map>()) {
        final t = kind == 'playlist' ? it['track'] : it;
        if (t is Map) addTrack(t);
      }
      final n = page['next'] as String?;
      next = n == null ? null : Uri.parse(n);
    }
    return out;
  }
}

/// Обложки из каталога iTunes: бесплатно и без ключей, хорошее качество.
class ItunesService {
  final http.Client _client = http.Client();

  /// Песни по запросу: название, исполнитель и обложка 1000×1000.
  Future<List<({String title, String artist, String album, String art})>> songs(
      String term) async {
    final res = await _client.get(
      Uri.https('itunes.apple.com', '/search', {'term': term, 'entity': 'song', 'limit': '15'}),
    ).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return const [];
    final results =
        (jsonDecode(utf8.decode(res.bodyBytes))['results'] as List?) ?? const [];
    return [
      for (final r in results.whereType<Map>())
        if (r['artworkUrl100'] is String)
          (
            title: '${r['trackName'] ?? ''}',
            artist: '${r['artistName'] ?? ''}',
            album: '${r['collectionName'] ?? ''}'
                .replaceAll(RegExp(r'\s*-\s*(Single|EP)$'), ''),
            art: (r['artworkUrl100'] as String).replaceFirst('100x100bb', '1000x1000bb'),
          ),
    ];
  }

  Future<String?> findCover(String artist, String title) async {
    final hasArtist = artist.isNotEmpty && artist != 'Неизвестный исполнитель';
    final res = await _client.get(
      Uri.https('itunes.apple.com', '/search', {
        'term': hasArtist ? '$artist $title' : title,
        'entity': 'song',
        'limit': '8',
      }),
    ).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final results =
        (jsonDecode(utf8.decode(res.bodyBytes))['results'] as List?) ?? const [];
    String? best;
    var bestScore = 0.0;
    for (final r in results.whereType<Map>()) {
      final art = r['artworkUrl100'] as String?;
      if (art == null) continue;
      final score = GeniusService.similar(title, r['trackName'] as String? ?? '') * 2 +
          (hasArtist
              ? GeniusService.similar(artist, r['artistName'] as String? ?? '')
              : 1);
      if (score > bestScore) {
        bestScore = score;
        // Та же картинка в большом размере.
        best = art.replaceFirst('100x100bb', '1000x1000bb');
      }
    }
    return bestScore >= 2.3 ? best : null;
  }
}


/// Spotify ограничивает частоту запросов на одно приложение, а ключи у нас
/// общие на всех. Поэтому: запросы идут по одному с паузой, а если Spotify
/// ответил 429 «слишком часто» — ждём столько, сколько он сказал,
/// и всё это время сразу отвечаем ошибкой, не дёргая его ещё сильнее.
class _PacedClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  static DateTime _blockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void> _queue = Future.value();
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  static const _gap = Duration(milliseconds: 400);

  /// Spotify напрямую не открывается (Россия: подменённый сертификат,
  /// замедление) — дальше ходим через облако Hutred.
  static bool viaRelay = false;

  static Uri? get _relay => HutredConfig.cloudEnabled
      ? Uri.parse('${HutredConfig.supabaseUrl}/functions/v1/spotify')
      : null;

  Future<http.StreamedResponse> _sendSmart(http.BaseRequest request) async {
    final relay = _relay;
    if (!viaRelay || relay == null || request is! http.Request) {
      if (relay == null || request is! http.Request) return _inner.send(request);
      try {
        final direct = await _inner.send(_copy(request, request.url));
        // Spotify не пускает из этой страны (403) — пробуем через облако.
        if (direct.statusCode != 403) return direct;
        await direct.stream.drain<void>();
        viaRelay = true;
      } on Exception catch (e) {
        // Сертификат подменили / соединение рвётся — пробуем через облако.
        if (e is! HandshakeException && e is! SocketException && e is! TlsException &&
            e is! http.ClientException && e is! TimeoutException) {
          rethrow;
        }
        viaRelay = true;
      }
    }
    final r = _copy(request, relay.replace(queryParameters: {'u': request.url.toString()}));
    final auth = request.headers['Authorization'] ?? request.headers['authorization'];
    r.headers
      ..remove('Authorization')
      ..remove('authorization')
      ..['apikey'] = HutredConfig.supabaseAnonKey;
    if (auth != null) r.headers['x-spotify-auth'] = auth;
    final res = await _inner.send(r).timeout(const Duration(seconds: 20));
    if (res.statusCode == 401 || res.statusCode == 404 || res.statusCode >= 500) {
      // Облачный ретранслятор недоступен (или не настроен) — не застреваем
      // на нём: в следующий раз снова пробуем напрямую.
      viaRelay = false;
      throw Exception('Spotify недоступен ни напрямую, ни через облако '
          '(облако ответило ${res.statusCode})');
    }
    return res;
  }

  static http.Request _copy(http.Request src, Uri url) {
    final r = http.Request(src.method, url)
      ..headers.addAll(src.headers)
      ..followRedirects = src.followRedirects;
    if (src.bodyBytes.isNotEmpty) r.bodyBytes = src.bodyBytes;
    return r;
  }

  static String _wait(Duration d) => d.inHours >= 1
      ? '${d.inHours} ч ${d.inMinutes % 60} мин'
      : d.inMinutes >= 1
          ? '${d.inMinutes + 1} мин'
          : '${d.inSeconds + 1} с';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final now = DateTime.now();
    if (now.isBefore(_blockedUntil)) {
      throw Exception(
          'Spotify просит подождать ещё ${_wait(_blockedUntil.difference(now))} (слишком много запросов)');
    }
    // Очередь: следующий запрос — не раньше чем через 0,4 с после прошлого.
    final prev = _queue;
    final done = Completer<void>();
    _queue = done.future;
    try {
      await prev;
      final since = DateTime.now().difference(_last);
      if (since < _gap) await Future<void>.delayed(_gap - since);
      _last = DateTime.now();
    } finally {
      done.complete();
    }
    final res = await _sendSmart(request);
    if (res.statusCode == 429) {
      final ra = int.tryParse(res.headers['retry-after'] ?? '') ?? 30;
      _blockedUntil = DateTime.now().add(Duration(seconds: ra.clamp(5, 24 * 3600)));
    }
    return res;
  }
}
