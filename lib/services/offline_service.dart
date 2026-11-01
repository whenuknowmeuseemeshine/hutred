import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import 'library_store.dart';
import 'soundcloud_source.dart';
import 'youtube_source.dart';

/// Загрузки, как в Spotify: скачанные треки и их обложки лежат в папке
/// приложения (не в кэше, который можно очистить) и играют без интернета.
/// Можно скачать отдельный трек, плейлист или «Избранное» целиком —
/// тогда новые треки в них скачиваются сами.
class OfflineService extends ChangeNotifier {
  OfflineService({
    required this.store,
    required this.youtube,
    required this.soundcloud,
  }) {
    _instance = this;
    store.addListener(_onLibraryChanged);
  }

  /// Для обложек: виджету проще спросить напрямую.
  static OfflineService? _instance;
  static OfflineService? get instance => _instance;

  final LibraryStore store;
  final YoutubeSource youtube;
  final SoundcloudSource soundcloud;

  /// Где играть трек из Spotify (находит его на SoundCloud/YouTube).
  Future<Track?> Function(Track track)? resolveSpotify;

  /// Свой файл, которого нет на устройстве, — копия из облака.
  Future<String?> Function(Track track)? cloudFile;

  final _http = http.Client();
  Directory? _dir;
  File? _manifest;

  /// Ключ трека → {audio: путь, cover: путь}.
  final Map<String, Map<String, String>> _files = {};

  /// Плейлисты, которые скачиваются целиком ('favorites' — «Избранное»).
  final Set<String> _pinned = {};

  final Set<String> _queue = {};
  final Set<String> _failed = {};
  String? _active;
  bool _online = true;
  Timer? _probe;

  static String keyOf(Track t) => '${t.source.name}:${t.uri}';

  bool get online => _online;
  bool isDownloaded(Track t) => _files[keyOf(t)]?['audio'] != null;
  bool isDownloading(Track t) {
    final k = keyOf(t);
    return _active == k || _queue.contains(k);
  }

  bool isPinned(String? playlistId) => _pinned.contains(playlistId ?? 'favorites');
  int get count => _files.values.where((f) => f['audio'] != null).length;
  int get pending => _queue.length + (_active == null ? 0 : 1);

  /// Путь к скачанному звуку или null.
  String? audioFor(Track t) {
    final p = _files[keyOf(t)]?['audio'];
    return p != null && File(p).existsSync() ? p : null;
  }

  Map<String, String>? _covers;

  /// Путь к скачанной обложке по её ссылке или null.
  String? coverForUrl(String url) {
    _covers ??= {
      for (final f in _files.values)
        if (f['coverUrl'] != null && f['cover'] != null) f['coverUrl']!: f['cover']!,
    };
    return _covers![url];
  }

  @override
  void notifyListeners() {
    _covers = null;
    super.notifyListeners();
  }

  Future<void> load() async {
    try {
      final base = await getApplicationSupportDirectory();
      _dir = Directory('${base.path}${Platform.pathSeparator}offline');
      await _dir!.create(recursive: true);
      _manifest = File('${_dir!.path}${Platform.pathSeparator}downloads.json');
      if (await _manifest!.exists()) {
        final j = jsonDecode(await _manifest!.readAsString());
        if (j is Map) {
          (j['files'] as Map? ?? const {}).forEach((k, v) {
            if (v is Map) _files['$k'] = Map<String, String>.from(v);
          });
          _pinned.addAll(List<String>.from(j['pinned'] as List? ?? const []));
        }
      }
    } catch (e) {
      debugPrint('[Загрузки] $e');
    }
    unawaited(checkOnline());
    // Раз в 30 секунд проверяем, появился ли / пропал ли интернет.
    _probe = Timer.periodic(const Duration(seconds: 30), (_) => checkOnline());
    _onLibraryChanged();
  }

  Future<void> _save() async {
    try {
      await _manifest?.writeAsString(jsonEncode({'files': _files, 'pinned': _pinned.toList()}));
    } catch (_) {}
  }

  /// Быстрая проверка связи (без лишних пакетов).
  Future<bool> checkOnline() async {
    var ok = false;
    try {
      final r = await InternetAddress.lookup('api.soundcloud.com')
          .timeout(const Duration(seconds: 4));
      ok = r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      ok = false;
    }
    if (ok != _online) {
      _online = ok;
      notifyListeners();
      if (ok) _pump();
    }
    return ok;
  }

  // ---------- Что скачивать ----------

  void download(Track t) {
    final k = keyOf(t);
    if (isDownloaded(t) || _active == k) return;
    _failed.remove(k);
    _queue.add(k);
    notifyListeners();
    _pump();
  }

  void downloadAll(Iterable<Track> tracks) {
    for (final t in tracks) {
      final k = keyOf(t);
      if (!isDownloaded(t) && _active != k && !_failed.contains(k)) _queue.add(k);
    }
    notifyListeners();
    _pump();
  }

  Future<void> remove(Track t) async {
    final k = keyOf(t);
    _queue.remove(k);
    final f = _files.remove(k);
    for (final p in [f?['audio'], f?['cover']]) {
      if (p == null) continue;
      try {
        await File(p).delete();
      } catch (_) {}
    }
    await _save();
    notifyListeners();
  }

  /// Скачать плейлист (null — «Избранное») целиком и докачивать новое.
  void pin(String? playlistId, bool on) {
    final id = playlistId ?? 'favorites';
    if (on) {
      _pinned.add(id);
      downloadAll(_tracksOf(id));
    } else {
      _pinned.remove(id);
      // Убираем загрузки, которые больше ни одному скачанному плейлисту не нужны.
      final keep = {for (final p in _pinned) ..._tracksOf(p).map(keyOf)};
      for (final t in _tracksOf(id)) {
        if (!keep.contains(keyOf(t))) remove(t);
      }
    }
    unawaited(_save());
    notifyListeners();
  }

  List<Track> _tracksOf(String id) {
    if (id == 'favorites') return store.favorites;
    final p = store.playlistById(id);
    return p == null ? const [] : store.tracksOf(p);
  }

  void _onLibraryChanged() {
    if (_pinned.isEmpty) return;
    final want = <Track>[for (final p in _pinned) ..._tracksOf(p)];
    final missing = want.where((t) =>
        !isDownloaded(t) && !isDownloading(t) && !_failed.contains(keyOf(t)));
    if (missing.isNotEmpty) downloadAll(missing);
  }

  Future<void> removeAll() async {
    _queue.clear();
    _pinned.clear();
    _files.clear();
    try {
      if (_dir != null && await _dir!.exists()) {
        await _dir!.delete(recursive: true);
        await _dir!.create(recursive: true);
      }
    } catch (_) {}
    await _save();
    notifyListeners();
  }

  Future<int> sizeBytes() async {
    var total = 0;
    for (final f in _files.values) {
      for (final p in [f['audio'], f['cover']]) {
        if (p == null) continue;
        try {
          total += await File(p).length();
        } catch (_) {}
      }
    }
    return total;
  }

  // ---------- Сама загрузка (по одному треку) ----------

  Track? _findByKey(String k) {
    for (final t in store.tracks) {
      if (keyOf(t) == k) return t;
    }
    return _extra[k];
  }

  /// Треки не из медиатеки (например, из поиска), которые попросили скачать.
  final Map<String, Track> _extra = {};

  void downloadTrack(Track t) {
    if (store.findBySource(t.source, t.uri) == null) _extra[keyOf(t)] = t;
    download(t);
  }

  Future<void> _pump() async {
    if (_active != null || _queue.isEmpty || !_online || _dir == null) return;
    final k = _queue.first;
    _queue.remove(k);
    final t = _findByKey(k);
    if (t == null) {
      unawaited(_pump());
      return;
    }
    _active = k;
    notifyListeners();
    try {
      final audio = await _fetchAudio(t);
      if (audio == null) throw Exception('звук недоступен');
      final ext = audio.path.contains('.') ? audio.path.split('.').last : 'm4a';
      final safe = k.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final sep = Platform.pathSeparator;
      final dest = '${_dir!.path}$sep$safe.$ext';
      if (audio.path != dest) await audio.copy(dest);
      final entry = <String, String>{'audio': dest};
      final art = t.artworkUrl;
      if (art != null && art.startsWith('http')) {
        try {
          final r = await _http.get(Uri.parse(art)).timeout(const Duration(seconds: 15));
          if (r.statusCode == 200) {
            final cover = '${_dir!.path}$sep${safe}_cover.jpg';
            await File(cover).writeAsBytes(r.bodyBytes);
            entry['cover'] = cover;
            entry['coverUrl'] = art;
          }
        } catch (_) {}
      }
      _files[k] = entry;
      _extra.remove(k);
      await _save();
    } catch (e) {
      _failed.add(k);
      debugPrint('[Загрузки] ${t.title}: $e');
    } finally {
      _active = null;
      notifyListeners();
      unawaited(_pump());
    }
  }

  Future<File?> _fetchAudio(Track t) async {
    switch (t.source) {
      case TrackSource.youtube:
        return youtube.cachedAudio(t.uri);
      case TrackSource.soundcloud:
        return soundcloud.cachedAudio(t.uri);
      case TrackSource.spotify:
        final found = await resolveSpotify?.call(t);
        return found == null || found.source == TrackSource.spotify
            ? null
            : _fetchAudio(found);
      case TrackSource.local:
        if (File(t.uri).existsSync()) return File(t.uri);
        final p = await cloudFile?.call(t);
        return p == null ? null : File(p);
      case TrackSource.url:
        final tmp = File('${_dir!.path}${Platform.pathSeparator}_download.tmp');
        final req = await _http.send(http.Request('GET', Uri.parse(t.uri)))
            .timeout(const Duration(seconds: 20));
        // Радио-потоки бесконечные — их не скачиваем.
        if (req.contentLength == null || req.statusCode != 200) return null;
        final sink = tmp.openWrite();
        await req.stream.pipe(sink);
        final ext = Uri.parse(t.uri).path.split('.').last;
        return tmp.rename('${tmp.path}.${ext.length <= 4 ? ext : 'mp3'}');
    }
  }

  @override
  void dispose() {
    _probe?.cancel();
    super.dispose();
  }
}
