import 'dart:async';
import 'dart:convert';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'genius_service.dart';
import 'library_store.dart';
import 'settings_store.dart';
import 'soundcloud_source.dart';
import 'spotify_service.dart';
import 'youtube_source.dart';

/// Одна строка переноса: что искали и что нашли.
class TransferItem {
  TransferItem(this.artist, this.title, {this.durationMs, this.found});

  final String artist;
  final String title;
  final int? durationMs;

  /// Найденный трек (null — ещё ищем или не нашли).
  Track? found;
  bool done = false;

  /// Включён в перенос (можно снять галочку).
  bool selected = true;

  String get label => artist.isEmpty ? title : '$artist — $title';
}

enum TransferStage { idle, reading, matching, ready }

/// Перенос треков с других площадок: Spotify, Яндекс Музыка, YouTube,
/// SoundCloud, текстовый список или CSV (например, из Exportify).
/// Каждый трек ищется на SoundCloud и YouTube.
class TransferService extends ChangeNotifier {
  TransferService({
    required this.store,
    required this.settings,
    required this.youtube,
    required this.soundcloud,
    required this.spotify,
  });

  final LibraryStore store;
  final SettingsStore settings;
  final YoutubeSource youtube;
  final SoundcloudSource soundcloud;
  final SpotifyService spotify;
  final _http = http.Client();

  TransferStage stage = TransferStage.idle;
  String? error;
  String suggestedName = 'Перенесённое';
  final List<TransferItem> items = [];
  int _token = 0;

  /// Сначала искать на YouTube (иначе на SoundCloud).
  /// Где искать в первую очередь: 'spotify', 'soundcloud' или 'youtube'.
  /// Spotify даёт точные сведения и обложку, звук потом берётся с SC/YouTube.
  late String searchFirst = settings.hasSpotifyKeys ? 'spotify' : 'soundcloud';

  int get doneCount => items.where((i) => i.done).length;
  int get foundCount => items.where((i) => i.found != null).length;
  int get selectedCount => items.where((i) => i.found != null && i.selected).length;

  void setSelected(TransferItem item, bool v) {
    item.selected = v;
    notifyListeners();
  }

  void setSearchFirst(String v) {
    searchFirst = v;
    notifyListeners();
  }

  void reset() {
    _token++;
    stage = TransferStage.idle;
    error = null;
    items.clear();
    notifyListeners();
  }

  /// Ссылка, список строк или содержимое CSV.
  Future<void> start(String input, {String? fileName}) async {
    final token = ++_token;
    items.clear();
    error = null;
    stage = TransferStage.reading;
    notifyListeners();
    try {
      final text = input.trim();
      final firstLine = text.split('\n').first.trim();
      final isUrl = !text.contains('\n') && firstLine.startsWith('http');
      List<TransferItem> list;
      if (isUrl) {
        list = await _fromUrl(firstLine);
      } else if ((fileName != null && fileName.toLowerCase().endsWith('.csv')) ||
          _looksLikeCsv(text)) {
        list = _fromCsv(text);
        if (fileName != null) {
          suggestedName = fileName.replaceAll(RegExp(r'\.[^.]+$'), '').replaceAll('_', ' ');
        }
      } else {
        list = _fromLines(text);
        suggestedName = 'Перенесённое';
      }
      if (token != _token) return;
      if (list.isEmpty) throw Exception('Не нашёл ни одного трека в том, что ты вставил');
      items.addAll(list);
      stage = TransferStage.matching;
      notifyListeners();
      await _matchAll(token);
      if (token != _token) return;
      stage = TransferStage.ready;
    } catch (e) {
      if (token != _token) return;
      error = e.toString().replaceFirst('Exception: ', '');
      stage = items.isEmpty ? TransferStage.idle : TransferStage.ready;
    }
    notifyListeners();
  }

  // ---------- Чтение источников ----------

  Future<List<TransferItem>> _fromUrl(String url) async {
    final u = url.toLowerCase();
    if (u.contains('spotify.com') || u.startsWith('spotify:')) {
      suggestedName = 'Из Spotify';
      // Длинные плейлисты виджет показывает не целиком — с ключами берём через API.
      if (settings.hasSpotifyKeys && u.contains('playlist')) {
        try {
          final list = await spotify.listFromUrl(
              id: settings.spotifyId, secret: settings.spotifySecret, url: url);
          if (list.isNotEmpty) {
            return [
              for (final t in list) TransferItem(t.artist, t.title, durationMs: t.durationMs)
            ];
          }
        } catch (_) {}
      }
      final page = await spotify.listFromEmbed(url);
      suggestedName = page.name;
      return [
        for (final t in page.tracks) TransferItem(t.artist, t.title, durationMs: t.durationMs)
      ];
    }
    if (u.contains('music.yandex')) {
      suggestedName = 'Из Яндекс Музыки';
      return _fromYandex(url);
    }
    if (u.contains('youtube.com') || u.contains('youtu.be')) {
      suggestedName = 'Из YouTube';
      final tracks = YoutubeSource.isPlaylistUrl(url) || url.contains('list=')
          ? await youtube.fromPlaylistUrl(url)
          : [await youtube.fromVideoUrl(url)];
      return [for (final t in tracks) TransferItem(t.artist, t.title, found: t)..done = true];
    }
    if (u.contains('soundcloud.com')) {
      suggestedName = 'Из SoundCloud';
      final tracks = await soundcloud.fromUrl(url);
      return [for (final t in tracks) TransferItem(t.artist, t.title, found: t)..done = true];
    }
    throw Exception('Поддерживаются ссылки Spotify, Яндекс Музыки, YouTube и SoundCloud. '
        'Для других площадок вставь список «Исполнитель — Название» или CSV');
  }

  /// Открытый плейлист или альбом Яндекс Музыки.
  Future<List<TransferItem>> _fromYandex(String url) async {
    Uri api;
    final user = RegExp(r'users/([^/]+)/playlists/(\d+)').firstMatch(url);
    final uuid = RegExp(r'/playlists/([0-9a-fA-F-]{20,})').firstMatch(url);
    final album = RegExp(r'/album/(\d+)').firstMatch(url);
    if (user != null) {
      api = Uri.https('api.music.yandex.net', '/users/${user.group(1)}/playlists/${user.group(2)}');
    } else if (uuid != null) {
      api = Uri.https('api.music.yandex.net', '/playlist/${uuid.group(1)}');
    } else if (album != null) {
      api = Uri.https('api.music.yandex.net', '/albums/${album.group(1)}/with-tracks');
    } else {
      throw Exception('Нужна ссылка на открытый плейлист или альбом Яндекс Музыки');
    }
    final res = await _http.get(api).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Яндекс Музыка не отдала плейлист (код ${res.statusCode}). '
          'Проверь, что он открытый, или скопируй список треков текстом');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final result = data is Map ? data['result'] : null;
    if (result is! Map) throw Exception('Яндекс Музыка вернула пустой ответ');
    final name = result['title'] as String?;
    if (name != null && name.isNotEmpty) suggestedName = name;

    final raw = <Map>[];
    for (final e in (result['tracks'] as List? ?? const []).whereType<Map>()) {
      raw.add(e['track'] is Map ? e['track'] as Map : e);
    }
    for (final vol in (result['volumes'] as List? ?? const []).whereType<List>()) {
      raw.addAll(vol.whereType<Map>());
    }
    return [
      for (final t in raw)
        if ((t['title'] as String?)?.isNotEmpty == true)
          TransferItem(
            (t['artists'] as List? ?? const [])
                .whereType<Map>()
                .map((a) => a['name'] as String? ?? '')
                .where((a) => a.isNotEmpty)
                .join(', '),
            t['title'] as String,
            durationMs: (t['durationMs'] as num?)?.toInt(),
          ),
    ];
  }

  static final _sep = RegExp(r'\s+[—–-]\s+|\t');
  static final _numbering = RegExp(r'^\s*\d+[.)]\s*');

  List<TransferItem> _fromLines(String text) {
    final out = <TransferItem>[];
    for (var line in const LineSplitter().convert(text)) {
      line = line.replaceFirst(_numbering, '').trim();
      if (line.isEmpty) continue;
      final m = _sep.firstMatch(line);
      if (m == null) {
        out.add(TransferItem('', line));
      } else {
        out.add(TransferItem(
            line.substring(0, m.start).trim(), line.substring(m.end).trim()));
      }
    }
    return out;
  }

  static bool _looksLikeCsv(String text) {
    final head = text.split('\n').first.toLowerCase();
    return head.contains(',') &&
        (head.contains('track name') || head.contains('artist') || head.contains('title'));
  }

  List<TransferItem> _fromCsv(String text) {
    final rows = _parseCsv(text);
    if (rows.length < 2) return const [];
    final head = rows.first.map((h) => h.toLowerCase().trim()).toList();
    // Имена по приоритету: сначала точное совпадение, потом «содержит».
    int col(List<String> names) {
      for (final n in names) {
        final i = head.indexOf(n);
        if (i >= 0) return i;
      }
      for (final n in names) {
        final i = head.indexWhere((h) => h.contains(n) && !h.contains('uri'));
        if (i >= 0) return i;
      }
      return -1;
    }
    var titleCol = col(['track name', 'название', 'song', 'title', 'name']);
    final artistCol = col(['artist name(s)', 'artist name', 'artist', 'исполнитель']);
    if (titleCol == artistCol) titleCol = -1;
    if (titleCol < 0) {
      throw Exception('В CSV нет колонки с названием трека (Track Name / Title)');
    }
    final durCol = col(['duration (ms)', 'duration_ms']);
    return [
      for (final r in rows.skip(1))
        if (r.length > titleCol && r[titleCol].trim().isNotEmpty)
          TransferItem(
            artistCol >= 0 && r.length > artistCol
                ? r[artistCol].replaceAll(';', ', ').trim()
                : '',
            r[titleCol].trim(),
            durationMs: durCol >= 0 && r.length > durCol ? int.tryParse(r[durCol]) : null,
          ),
    ];
  }

  /// CSV с кавычками и запятыми внутри полей.
  static List<List<String>> _parseCsv(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == ',') {
        row.add(field.toString());
        field.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        if (row.any((f) => f.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        field.write(c);
      }
    }
    row.add(field.toString());
    if (row.any((f) => f.isNotEmpty)) rows.add(row);
    return rows;
  }

  // ---------- Поиск треков ----------

  Future<void> _matchAll(int token) async {
    var next = 0;
    Future<void> worker() async {
      while (token == _token) {
        final i = next++;
        if (i >= items.length) return;
        final item = items[i];
        if (item.done) continue;
        try {
          item.found = await _match(item);
        } catch (e) {
          debugPrint('[Перенос] ${item.label}: $e');
        }
        item.done = true;
        if (token == _token) notifyListeners();
      }
    }

    await Future.wait([for (var i = 0; i < 3; i++) worker()]);
  }

  Future<Track?> _match(TransferItem item) async {
    final order = switch (searchFirst) {
      'spotify' => [_matchSpotify, _matchSoundcloud, _matchYoutube],
      'youtube' => [_matchYoutube, _matchSoundcloud],
      _ => [_matchSoundcloud, _matchYoutube],
    };
    for (final f in order) {
      try {
        final t = await f(item).timeout(const Duration(seconds: 25));
        if (t != null) return t;
      } catch (_) {}
    }
    return null;
  }

  /// Трек из каталога Spotify: точные название, исполнитель и обложка.
  Future<Track?> _matchSpotify(TransferItem item) async {
    if (!settings.hasSpotifyKeys) return null;
    return spotify.bestMatch(
      id: settings.spotifyId,
      secret: settings.spotifySecret,
      artist: item.artist,
      title: item.title,
      durationMs: item.durationMs,
    );
  }

  Future<Track?> _matchSoundcloud(TransferItem item) async {
    final t = await soundcloud.match(item.artist, item.title);
    if (t == null) return null;
    // Пропускаем 30-секундные превью.
    if (t.durationMs != null && t.durationMs! < 60000) return null;
    if (!_durationOk(item, t)) return null;
    return t;
  }

  Future<Track?> _matchYoutube(TransferItem item) async {
    final q = item.artist.isEmpty ? item.title : '${item.artist} - ${item.title}';
    final found = await youtube.search(q);
    Track? best;
    var bestScore = 0.0;
    for (final t in found.take(8)) {
      if (!_durationOk(item, t)) continue;
      final score = GeniusService.similar(item.title, t.title) * 2 +
          (item.artist.isEmpty
              ? 1
              : GeniusService.similar(item.artist, '${t.artist} ${t.title}'));
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    return bestScore >= 2.0 ? best : null;
  }

  static bool _durationOk(TransferItem item, Track t) {
    if (item.durationMs == null || t.durationMs == null) return true;
    return (item.durationMs! - t.durationMs!).abs() < 20000;
  }

  // ---------- Треки из Spotify ----------

  final Map<String, Map<String, String>> _spotifyMatches = {};
  bool _matchesLoaded = false;
  final Map<String, Future<Track?>> _resolving = {};

  Future<File> _matchesFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}spotify_matches.json');
  }

  /// Где играть трек из Spotify: ищем на SoundCloud/YouTube один раз и запоминаем.
  Future<Track?> resolveSpotify(Track t) =>
      _resolving.putIfAbsent(t.uri, () => _resolveOnce(t));

  Future<Track?> _resolveOnce(Track t) async {
    try {
      if (!_matchesLoaded) {
        _matchesLoaded = true;
        try {
          final f = await _matchesFile();
          if (await f.exists()) {
            final j = jsonDecode(await f.readAsString());
            if (j is Map) {
              j.forEach((k, v) {
                if (v is Map) _spotifyMatches['$k'] = Map<String, String>.from(v);
              });
            }
          }
        } catch (_) {}
      }
      final saved = _spotifyMatches[t.uri];
      if (saved != null) {
        final src = TrackSource.values.asNameMap()[saved['source']];
        if (src != null) {
          return Track(
            id: t.id,
            title: t.title,
            artist: t.artist,
            source: src,
            uri: saved['uri']!,
            addedAt: t.addedAt,
          );
        }
      }
      final found = await _match(TransferItem(t.artist, t.title, durationMs: t.durationMs));
      if (found == null) return null;
      _spotifyMatches[t.uri] = {'source': found.source.name, 'uri': found.uri};
      try {
        await (await _matchesFile()).writeAsString(jsonEncode(_spotifyMatches));
      } catch (_) {}
      return found;
    } finally {
      // Неудачу не кэшируем навсегда — можно попробовать снова.
      _resolving.remove(t.uri);
    }
  }

  /// Повторить поиск для одной строки (например, на другой площадке).
  Future<void> retry(TransferItem item, {required String where}) async {
    item.done = false;
    notifyListeners();
    try {
      item.found = await switch (where) {
        'spotify' => _matchSpotify(item),
        'youtube' => _matchYoutube(item),
        _ => _matchSoundcloud(item),
      };
    } catch (_) {
      item.found = null;
    }
    item.done = true;
    notifyListeners();
  }

  /// Добавляет найденное в медиатеку и (по желанию) в новый плейлист.
  ({int added, String? playlist}) save({String? playlistName}) {
    final picked = [
      for (final i in items)
        if (i.found != null && i.selected) i.found!
    ];
    final added = store.addTracks(picked);
    // id уже сохранённых треков (у дубликатов id из медиатеки).
    final ids = [
      for (final t in picked) (store.findBySource(t.source, t.uri) ?? t).id,
    ];
    String? name;
    if (playlistName != null && playlistName.trim().isNotEmpty && ids.isNotEmpty) {
      final p = store.createPlaylist(playlistName);
      store.addToPlaylist(p.id, ids);
      name = p.name;
    }
    return (added: added, playlist: name);
  }
}
