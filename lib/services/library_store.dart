import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import 'youtube_source.dart';

/// Медиатека и плейлисты. Хранится в JSON-файле в папке приложения.
class LibraryStore extends ChangeNotifier {
  final List<Track> _tracks = [];
  final List<Playlist> _playlists = [];
  File? _file;
  Timer? _saveTimer;

  // Для синхронизации между устройствами: когда менялся каждый элемент
  // ('track:<id>' / 'playlist:<id>') и что удалено.
  final Map<String, DateTime> _stamps = {};
  final Map<String, DateTime> _tombs = {};
  String? _userId;

  /// Чья медиатека сейчас открыта (null — без входа, только это устройство).
  String? get userId => _userId;

  List<Track> get tracks => List.unmodifiable(_tracks);
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  List<Track> get favorites => _tracks.where((t) => t.favorite).toList();

  /// Загружает медиатеку. У каждого пользователя на устройстве своя.
  Future<void> load({String? userId}) async {
    _saveTimer?.cancel();
    if (_file != null) await _save();
    _tracks.clear();
    _playlists.clear();
    _stamps.clear();
    _tombs.clear();
    _userId = userId;
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      final name = userId == null ? 'library.json' : 'library_$userId.json';
      _file = File('${dir.path}${Platform.pathSeparator}$name');
      var fixed = false;
      if (await _file!.exists()) {
        final data =
            jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        for (final e in data['tracks'] as List? ?? const []) {
          var t = Track.fromJson(Map<String, dynamic>.from(e as Map));
          // Чиним названия вида «Исполнитель -- Песня», добавленные раньше.
          if (t.source == TrackSource.youtube) {
            final split = YoutubeSource.splitTitle(t.title, t.artist);
            if (split.title != t.title) {
              t = t.copyWith(
                  title: split.title,
                  artist: split.artist,
                  lyrics: null,
                  lyricsSource: null);
              fixed = true;
            }
          }
          _tracks.add(t);
        }
        for (final e in data['playlists'] as List? ?? const []) {
          _playlists
              .add(Playlist.fromJson(Map<String, dynamic>.from(e as Map)));
        }
        (data['stamps'] as Map? ?? const {}).forEach((k, v) {
          final t = DateTime.tryParse('$v');
          if (t != null) _stamps['$k'] = t;
        });
        (data['tombs'] as Map? ?? const {}).forEach((k, v) {
          final t = DateTime.tryParse('$v');
          if (t != null) _tombs['$k'] = t;
        });
      }
      if (fixed) _changed();
      notifyListeners();
    } catch (e) {
      debugPrint('Не удалось прочитать медиатеку: $e');
    }
  }

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    try {
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'version': 1,
        'tracks': _tracks.map((t) => t.toJson()).toList(),
        'playlists': _playlists.map((p) => p.toJson()).toList(),
        'stamps': _stamps.map((k, v) => MapEntry(k, v.toIso8601String())),
        'tombs': _tombs.map((k, v) => MapEntry(k, v.toIso8601String())),
      }));
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('Не удалось сохранить медиатеку: $e');
    }
  }

  // ---------- Треки ----------

  Track? byId(String id) {
    for (final t in _tracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  Track? findBySource(TrackSource source, String uri) {
    for (final t in _tracks) {
      if (t.source == source && t.uri == uri) return t;
    }
    return null;
  }

  bool contains(Track t) =>
      byId(t.id) != null || findBySource(t.source, t.uri) != null;

  /// Добавляет треки, пропуская дубликаты. Возвращает число новых.
  /// Вызывается после добавления новых треков (для сверки со Spotify).
  void Function(List<Track> added)? onTracksAdded;

  /// Как в Spotify: добавленный трек сразу попадает в любимые.
  bool autoFavorite = true;

  int addTracks(Iterable<Track> items) {
    final added = <Track>[];
    for (var t in items) {
      if (findBySource(t.source, t.uri) != null) continue;
      if (autoFavorite && !t.favorite) t = t.copyWith(favorite: true);
      _tracks.add(t);
      _touch('track:${t.id}');
      added.add(t);
    }
    if (added.isNotEmpty) {
      _changed();
      onTracksAdded?.call(added);
    }
    return added.length;
  }

  /// Ручная правка трека (текст, сдвиг, сведения, обложка): before → after.
  void Function(Track before, Track after)? onManualEdit;

  void updateTrack(Track t, {bool manual = false}) {
    final i = _tracks.indexWhere((e) => e.id == t.id);
    if (i < 0) return;
    final before = _tracks[i];
    _tracks[i] = t;
    if (manual) onManualEdit?.call(before, t);
    _touch('track:${t.id}');
    _changed();
  }

  /// Вызывается, когда трек удалили из медиатеки на этом устройстве.
  void Function(Track track)? onTrackRemoved;

  void removeTrack(String id) {
    final removed = byId(id);
    if (removed != null) onTrackRemoved?.call(removed);
    _tracks.removeWhere((t) => t.id == id);
    _bury('track:$id');
    for (var i = 0; i < _playlists.length; i++) {
      final p = _playlists[i];
      if (p.trackIds.contains(id)) {
        _playlists[i] =
            p.copyWith(trackIds: p.trackIds.where((e) => e != id).toList());
        _touch('playlist:${p.id}');
      }
    }
    _changed();
  }

  /// Поставить или снять ♥ сразу у многих треков.
  void setFavorite(Iterable<String> ids, bool value) {
    var changed = false;
    for (final id in ids) {
      final i = _tracks.indexWhere((e) => e.id == id);
      if (i < 0 || _tracks[i].favorite == value) continue;
      _tracks[i] = _tracks[i].copyWith(favorite: value);
      _touch('track:$id');
      changed = true;
    }
    if (changed) _changed();
  }

  /// Удалить сразу много треков.
  void removeTracks(Iterable<String> ids) {
    for (final id in ids.toList()) {
      removeTrack(id);
    }
  }

  /// Как в Spotify: любимые — это и есть медиатека. Снятое сердечко
  /// убирает трек из медиатеки (если он в плейлисте — остаётся только там).
  /// Показать «Вернуть» — [onUnliked].
  void toggleFavorite(String id) {
    final t = byId(id);
    if (t == null) return;
    if (!t.favorite) {
      updateTrack(t.copyWith(favorite: true));
      return;
    }
    unlike(t);
  }

  /// Вызывается после снятия сердечка: можно предложить «Вернуть».
  void Function(Track track, VoidCallback undo)? onUnliked;

  void unlike(Track t) {
    final inPlaylist = _playlists.any((p) => p.trackIds.contains(t.id));
    if (inPlaylist) {
      updateTrack(t.copyWith(favorite: false));
      onUnliked?.call(t, () {
        final now = byId(t.id);
        if (now != null) updateTrack(now.copyWith(favorite: true));
      });
    } else {
      removeTrack(t.id);
      onUnliked?.call(t, () => restore(t));
    }
  }

  /// Вернуть удалённый трек как был (тот же id, прослушивания, текст).
  void restore(Track t) {
    if (byId(t.id) != null || findBySource(t.source, t.uri) != null) return;
    _tracks.add(t.copyWith(favorite: true));
    _touch('track:${t.id}');
    _changed();
  }

  /// Один раз при переходе на «любимые = медиатека»: сердечко всем трекам,
  /// кроме тех, что только в плейлистах.
  void likeEverything() {
    setFavorite([for (final t in _tracks) if (!t.favorite) t.id], true);
  }

  /// Поиск по названию, исполнителю и альбому; все слова запроса должны совпасть.
  List<Track> search(String query) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const [];
    return _tracks.where((t) {
      final hay = '${t.title} ${t.artist} ${t.album}'.toLowerCase();
      return words.every(hay.contains);
    }).toList();
  }

  // ---------- Плейлисты ----------

  Playlist? playlistById(String id) {
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  Playlist createPlaylist(String name) {
    final p = Playlist(
      id: Track.newId(),
      name: name.trim().isEmpty ? 'Новый плейлист' : name.trim(),
      trackIds: const [],
      createdAt: DateTime.now(),
    );
    _playlists.add(p);
    _touch('playlist:${p.id}');
    _changed();
    return p;
  }

  void _replacePlaylist(Playlist p) {
    final i = _playlists.indexWhere((e) => e.id == p.id);
    if (i < 0) return;
    _playlists[i] = p;
    _touch('playlist:${p.id}');
    _changed();
  }

  void renamePlaylist(String id, String name) {
    final p = playlistById(id);
    if (p != null && name.trim().isNotEmpty) {
      _replacePlaylist(p.copyWith(name: name.trim()));
    }
  }

  /// Название, описание и обложка плейлиста.
  void updatePlaylist(String id,
      {String? name, String? description, String? cover, bool removeCover = false}) {
    final p = playlistById(id);
    if (p == null) return;
    _replacePlaylist(p.copyWith(
      name: (name ?? '').trim().isEmpty ? null : name!.trim(),
      description: description?.trim(),
      cover: cover,
      removeCover: removeCover,
    ));
  }

  void deletePlaylist(String id) {
    _playlists.removeWhere((p) => p.id == id);
    _bury('playlist:$id');
    _changed();
  }

  /// Возвращает число реально добавленных треков.
  int addToPlaylist(String playlistId, Iterable<String> trackIds) {
    final p = playlistById(playlistId);
    if (p == null) return 0;
    final ids = List<String>.from(p.trackIds);
    var added = 0;
    for (final id in trackIds) {
      if (!ids.contains(id)) {
        ids.add(id);
        added++;
      }
    }
    if (added > 0) _replacePlaylist(p.copyWith(trackIds: ids));
    return added;
  }

  void removeFromPlaylist(String playlistId, String trackId) {
    final p = playlistById(playlistId);
    if (p == null) return;
    _replacePlaylist(
        p.copyWith(trackIds: p.trackIds.where((e) => e != trackId).toList()));
  }

  void reorderPlaylist(String playlistId, int oldIndex, int newIndex) {
    final p = playlistById(playlistId);
    if (p == null) return;
    final ids = List<String>.from(p.trackIds);
    if (newIndex > oldIndex) newIndex--;
    ids.insert(newIndex, ids.removeAt(oldIndex));
    _replacePlaylist(p.copyWith(trackIds: ids));
  }

  List<Track> tracksOf(Playlist p) => p.followedTracks != null
      ? List.of(p.followedTracks!)
      : p.trackIds.map(byId).whereType<Track>().toList();

  /// Подписаться на чужой плейлист (уже подписан — вернуть его).
  Playlist followPlaylist({
    required String followId,
    required String name,
    required String description,
    String? cover,
    String? owner,
    required List<Track> tracks,
  }) {
    for (final p in _playlists) {
      if (p.followId == followId) return p;
    }
    final p = Playlist(
      id: Track.newId(),
      name: name,
      trackIds: const [],
      createdAt: DateTime.now(),
      description: description,
      cover: cover,
      followId: followId,
      owner: owner,
      followedTracks: tracks,
    );
    _playlists.add(p);
    _touch('playlist:${p.id}');
    _changed();
    return p;
  }

  /// Автор поменял плейлист — обновляем копию у подписчика.
  void refreshFollowed(String followId,
      {required String name,
      required String description,
      String? cover,
      String? owner,
      required List<Track> tracks}) {
    final i = _playlists.indexWhere((p) => p.followId == followId);
    if (i < 0) return;
    final old = _playlists[i];
    final updated = Playlist(
      id: old.id,
      name: name,
      trackIds: const [],
      createdAt: old.createdAt,
      description: description,
      cover: cover,
      followId: followId,
      owner: owner ?? old.owner,
      followedTracks: tracks,
    );
    if (jsonEncode(updated.toJson()) == jsonEncode(old.toJson())) return;
    _playlists[i] = updated;
    _touch('playlist:${old.id}');
    _changed();
  }

  // ---------- Синхронизация ----------

  void _touch(String key) {
    _stamps[key] = DateTime.now().toUtc();
    _tombs.remove(key);
  }

  void _bury(String key) {
    _stamps.remove(key);
    _tombs[key] = DateTime.now().toUtc();
  }

  /// Всё, что изменилось после [since]: для отправки в облако.
  List<SyncRecord> changesSince(DateTime? since) {
    final out = <SyncRecord>[];
    bool fresh(DateTime t) => since == null || t.isAfter(since);
    for (final t in _tracks) {
      final at = _stamps['track:${t.id}'];
      if (at != null && fresh(at)) {
        out.add(SyncRecord('track', t.id, t.toJson(), false, at));
      } else if (at == null && since == null) {
        out.add(SyncRecord('track', t.id, t.toJson(), false, t.addedAt.toUtc()));
      }
    }
    for (final p in _playlists) {
      final at = _stamps['playlist:${p.id}'];
      if (at != null && fresh(at)) {
        out.add(SyncRecord('playlist', p.id, p.toJson(), false, at));
      } else if (at == null && since == null) {
        out.add(SyncRecord('playlist', p.id, p.toJson(), false, p.createdAt.toUtc()));
      }
    }
    _tombs.forEach((key, at) {
      if (!fresh(at)) return;
      final i = key.indexOf(':');
      out.add(SyncRecord(key.substring(0, i), key.substring(i + 1), null, true, at));
    });
    return out;
  }

  /// Применяет изменения из облака. Побеждает более свежая версия.
  void applyRemote(List<SyncRecord> records) {
    var changed = false;
    for (final r in records) {
      final key = '${r.kind}:${r.id}';
      final local = _stamps[key] ?? _tombs[key];
      if (local != null && !r.updatedAt.isAfter(local)) continue;
      if (r.deleted) {
        if (r.kind == 'track') {
          _tracks.removeWhere((t) => t.id == r.id);
        } else {
          _playlists.removeWhere((p) => p.id == r.id);
        }
        _stamps.remove(key);
        _tombs[key] = r.updatedAt;
      } else if (r.data != null) {
        if (r.kind == 'track') {
          final t = Track.fromJson(r.data!);
          final i = _tracks.indexWhere((e) => e.id == t.id);
          if (i >= 0) {
            _tracks[i] = t;
          } else if (findBySource(t.source, t.uri) == null) {
            _tracks.add(t);
          }
        } else {
          final p = Playlist.fromJson(r.data!);
          final i = _playlists.indexWhere((e) => e.id == p.id);
          if (i >= 0) {
            _playlists[i] = p;
          } else {
            _playlists.add(p);
          }
        }
        _tombs.remove(key);
        _stamps[key] = r.updatedAt;
      }
      changed = true;
    }
    if (changed) {
      notifyListeners();
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 400), _save);
    }
  }
}

/// Одна запись для синхронизации.
class SyncRecord {
  const SyncRecord(this.kind, this.id, this.data, this.deleted, this.updatedAt);
  final String kind; // 'track' или 'playlist'
  final String id;
  final Map<String, dynamic>? data;
  final bool deleted;
  final DateTime updatedAt;
}
