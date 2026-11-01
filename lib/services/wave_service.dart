import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import 'library_store.dart';
import 'player_service.dart';
import 'soundcloud_source.dart';

/// «Моя волна»: бесконечный поток похожей музыки по твоим лайкам
/// и прослушиваниям. Похожие треки берутся из рекомендаций SoundCloud,
/// дизлайки запоминаются и больше не попадаются.
class WaveService extends ChangeNotifier {
  WaveService({
    required this.store,
    required this.player,
    required this.soundcloud,
  });

  final LibraryStore store;
  final PlayerService player;
  final SoundcloudSource soundcloud;

  final _rand = Random();
  final Set<String> _disliked = {};
  final Map<String, int> _dislikedArtists = {};
  final Set<String> _suggested = {};
  final Map<String, String?> _scIdCache = {};
  File? _file;

  bool _active = false;
  bool _loading = false;
  String? _error;

  bool get active => _active;
  bool get loading => _loading;
  String? get error => _error;

  static String _key(Track t) => '${t.source.name}:${t.uri}';

  bool isWaveTrack(Track? t) => _active && t != null && _suggested.contains(_key(t));

  Future<void> load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}wave.json');
      if (!await _file!.exists()) return;
      final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
      _disliked.addAll(List<String>.from(j['disliked'] as List? ?? const []));
      (j['dislikedArtists'] as Map? ?? const {}).forEach((k, v) {
        _dislikedArtists['$k'] = (v as num).toInt();
      });
    } catch (e) {
      debugPrint('Волна: не удалось прочитать настройки: $e');
    }
  }

  Future<void> _save() async {
    try {
      await _file?.writeAsString(jsonEncode({
        'disliked': _disliked.toList(),
        'dislikedArtists': _dislikedArtists,
      }));
    } catch (_) {}
  }

  /// Треки, от которых отталкивается волна: лайки и часто слушаемые.
  List<({Track track, int weight})> _seeds() {
    final seeds = <({Track track, int weight})>[];
    for (final t in store.tracks) {
      final int w = (t.favorite ? 5 : 0) + (t.plays > 10 ? 10 : t.plays);
      if (w > 0) seeds.add((track: t, weight: w));
    }
    if (seeds.isEmpty) {
      // Нет лайков — берём последние добавленные.
      final recent = List.of(store.tracks)
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      for (final t in recent.take(15)) {
        seeds.add((track: t, weight: 1));
      }
    }
    return seeds;
  }

  Track _pickWeighted(List<({Track track, int weight})> seeds) {
    final total = seeds.fold<int>(0, (s, e) => s + e.weight);
    var r = _rand.nextInt(total);
    for (final s in seeds) {
      r -= s.weight;
      if (r < 0) return s.track;
    }
    return seeds.last.track;
  }

  Future<String?> _scIdFor(Track seed) async {
    if (seed.source == TrackSource.soundcloud) return seed.uri;
    final k = _key(seed);
    if (_scIdCache.containsKey(k)) return _scIdCache[k];
    final m = await soundcloud.match(seed.artist, seed.title);
    return _scIdCache[k] = m?.uri;
  }

  /// Рекомендации по заданным трекам (для умного перемешивания).
  Future<List<Track>> recommendFrom(List<Track> tracks, {int size = 8}) =>
      _nextBatch(size: size, from: tracks);

  Future<List<Track>> _nextBatch({int size = 8, List<Track>? from}) async {
    final seeds = from == null
        ? _seeds()
        : [for (final t in from) (track: t, weight: t.favorite ? 3 : 1)];
    if (seeds.isEmpty) {
      throw Exception(
          'Добавь в медиатеку несколько треков и поставь им ♥ — волна подстроится под них');
    }
    final candidates = <Track>[];
    final picked = <String>{};
    for (var attempt = 0; attempt < 6 && candidates.length < size * 3; attempt++) {
      final seed = _pickWeighted(seeds);
      if (!picked.add(seed.id) && picked.length < seeds.length) continue;
      try {
        final id = await _scIdFor(seed);
        if (id == null) continue;
        candidates.addAll(await soundcloud.related(id, limit: 25));
      } catch (e) {
        debugPrint('Волна: ${seed.title}: $e');
      }
    }

    final perArtist = <String, int>{};
    final out = <Track>[];
    candidates.shuffle(_rand);
    for (final t in candidates) {
      final k = _key(t);
      final artist = t.artist.toLowerCase();
      if (_suggested.contains(k) || _disliked.contains(k)) continue;
      if ((_dislikedArtists[artist] ?? 0) >= 2) continue;
      if (store.findBySource(t.source, t.uri) != null) continue;
      if ((perArtist[artist] ?? 0) >= 2) continue;
      if (t.durationMs != null && t.durationMs! < 60000) continue; // не сниппеты
      perArtist[artist] = (perArtist[artist] ?? 0) + 1;
      out.add(t);
      if (out.length >= size) break;
    }
    for (final t in out) {
      _suggested.add(_key(t));
    }
    return out;
  }

  Future<void> start() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final batch = await _nextBatch();
      if (batch.isEmpty) {
        throw Exception('Не получилось подобрать треки. Проверь интернет и попробуй ещё раз');
      }
      _active = true;
      player.onQueueLow = _refill;
      await player.playTracks(batch);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void stop() {
    _active = false;
    if (player.onQueueLow == _refill) player.onQueueLow = null;
    notifyListeners();
  }

  bool _refilling = false;

  Future<void> _refill() async {
    // Волна дозаправляется, только пока играет она сама.
    if (!_active || _refilling || !isWaveTrack(player.current)) return;
    _refilling = true;
    try {
      player.appendAll(await _nextBatch());
    } catch (e) {
      debugPrint('Волна: $e');
    } finally {
      _refilling = false;
    }
  }

  /// ♥ — трек в медиатеку и избранное, волна будет чаще давать похожее.
  void like(Track t) {
    var saved = store.findBySource(t.source, t.uri);
    if (saved == null) {
      store.addTracks([t.copyWith(favorite: true)]);
      saved = store.findBySource(t.source, t.uri);
    } else if (!saved.favorite) {
      store.toggleFavorite(saved.id);
    }
    notifyListeners();
  }

  /// «Не нравится» — трек больше не попадётся, а после двух дизлайков
  /// исполнитель тоже исчезнет из волны.
  Future<void> dislike(Track t) async {
    _disliked.add(_key(t));
    final a = t.artist.toLowerCase();
    _dislikedArtists[a] = (_dislikedArtists[a] ?? 0) + 1;
    await _save();
    notifyListeners();
    if (player.current?.id == t.id) await player.next();
  }

  Future<void> resetDislikes() async {
    _disliked.clear();
    _dislikedArtists.clear();
    await _save();
    notifyListeners();
  }

  int get dislikedCount => _disliked.length;
}
