import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import 'library_store.dart';
import 'player_service.dart';
import 'meta_clean.dart';
import 'soundcloud_source.dart';
import 'youtube_source.dart';

/// «Моя волна»: бесконечный поток похожей музыки по твоим лайкам
/// и прослушиваниям. Похожие треки берутся из рекомендаций SoundCloud,
/// дизлайки запоминаются и больше не попадаются.
class WaveService extends ChangeNotifier {
  WaveService({
    required this.store,
    required this.player,
    required this.soundcloud,
  }) {
    _watchSkips();
  }

  final LibraryStore store;
  final PlayerService player;
  final SoundcloudSource soundcloud;

  final _rand = Random();

  // ---------- Пропуски, как в Яндекс Музыке ----------
  // Пропустил трек «Волны» в первые 30 секунд — его больше не предлагаем,
  // а похожее от того же исполнителя попадается реже.

  /// Исполнитель → сколько раз его быстро пропускали в «Волне».
  final Map<String, int> _skippedArtists = {};
  final Set<String> _skippedTracks = {};
  Track? _watchTrack;
  Duration _watchPos = Duration.zero;
  bool _watching = false;

  void _watchSkips() {
    if (_watching) return;
    _watching = true;
    player.positionStream.listen((p) => _watchPos = p);
    player.addListener(() {
      final cur = player.current;
      final prev = _watchTrack;
      if (cur?.id == prev?.id) return;
      if (prev != null && isWaveTrack(prev)) {
        final dur = prev.duration ?? const Duration(minutes: 3);
        final early = _watchPos > Duration.zero &&
            _watchPos < const Duration(seconds: 30) &&
            _watchPos < dur * 0.5;
        if (early) _onSkipped(prev);
      }
      _watchTrack = cur;
      _watchPos = Duration.zero;
    });
  }

  void _onSkipped(Track t) {
    _skippedTracks.add(_key(t));
    if (_skippedTracks.length > 1000) _skippedTracks.remove(_skippedTracks.first);
    for (final a in artistsOf(t)) {
      final k = a.toLowerCase();
      _skippedArtists[k] = (_skippedArtists[k] ?? 0) + 1;
    }
    unawaited(_save());
  }

  /// Понравился трек — его исполнителя больше не «штрафуем» за пропуски.
  void forgiveArtist(Track t) {
    var changed = false;
    for (final a in artistsOf(t)) {
      changed |= _skippedArtists.remove(a.toLowerCase()) != null;
    }
    if (changed) unawaited(_save());
  }
  final Set<String> _disliked = {};

  /// Название и исполнитель скрытых треков — чтобы показать их списком.
  final Map<String, ({String title, String artist})> _dislikedInfo = {};
  final Map<String, int> _dislikedArtists = {};

  /// Чёрный список: исполнители, которых не должно быть нигде, даже на фитах.
  final Set<String> _blocked = {};
  final Map<String, String> _blockedNames = {};
  final Set<String> _suggested = {};

  /// Любимые исполнители, выбранные при знакомстве: их треки — стартовые
  /// семена «Волны», пока своих лайков мало.
  final Map<String, List<Track>> _favArtists = {};

  List<String> get favoriteArtists => _favArtists.keys.toList();

  Future<void> setFavoriteArtists(Map<String, List<Track>> artists) async {
    _favArtists
      ..clear()
      ..addAll(artists);
    await _save();
    notifyListeners();
  }
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
      (j['dislikedInfo'] as Map? ?? const {}).forEach((k, v) {
        if (v is Map) {
          _dislikedInfo['$k'] = (title: '${v['title'] ?? ''}', artist: '${v['artist'] ?? ''}');
        }
      });
      (j['dislikedArtists'] as Map? ?? const {}).forEach((k, v) {
        _dislikedArtists['$k'] = (v as num).toInt();
      });
      (j['skippedArtists'] as Map? ?? const {}).forEach((k, v) {
        _skippedArtists['$k'] = (v as num).toInt();
      });
      _skippedTracks.addAll(List<String>.from(j['skippedTracks'] as List? ?? const []));
      (j['favoriteArtists'] as Map? ?? const {}).forEach((k, v) {
        _favArtists['$k'] = [
          for (final t in (v as List? ?? const []))
            if (t is Map) Track.fromJson(Map<String, dynamic>.from(t)),
        ];
      });
      for (final name in List<String>.from(j['blockedArtists'] as List? ?? const [])) {
        _blocked.add(_norm(name));
        _blockedNames[_norm(name)] = name;
      }
    } catch (e) {
      debugPrint('Волна: не удалось прочитать настройки: $e');
    }
  }

  Future<void> _save() async {
    try {
      await _file?.writeAsString(jsonEncode({
        'disliked': _disliked.toList(),
        'dislikedInfo': {
          for (final e in _dislikedInfo.entries)
            if (_disliked.contains(e.key)) e.key: {'title': e.value.title, 'artist': e.value.artist},
        },
        'dislikedArtists': _dislikedArtists,
        'blockedArtists': _blockedNames.values.toList(),
        'skippedArtists': _skippedArtists,
        'skippedTracks': _skippedTracks.toList(),
        'favoriteArtists': {
          for (final e in _favArtists.entries) e.key: [for (final t in e.value) t.toJson()],
        },
      }));
    } catch (_) {}
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  static final _split = RegExp(
    r'\s*[,&;]\s*|\s+(?:feat\.?|ft\.?|x|при участии|featuring)\s+',
    caseSensitive: false,
  );

  /// Все исполнители трека: из поля «исполнитель» и из «(feat. …)» в названии.
  static List<String> artistsOf(Track t) {
    final names = t.artist.split(_split).toList();
    final feat = RegExp(r'(?:feat\.?|ft\.?|при участии|w/)\s+([^\)\]]+)', caseSensitive: false)
        .firstMatch(t.title);
    if (feat != null) names.addAll(feat.group(1)!.split(_split));
    return names.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  bool isDisliked(Track t) => _disliked.contains(_key(t));

  // Название (без мусора) → исполнители: чтобы не советовать то, что уже есть,
  // даже если у тебя этот трек с другой площадки.
  Map<String, Set<String>>? _owned;
  int _ownedFor = -1;

  static String _titleKey(String title) => _norm(MetaClean.clean(
      YoutubeSource.searchTitle(title)));

  /// Такой трек уже есть в медиатеке (или его версия с другой площадки).
  bool isOwnedLike(Track t) {
    if (store.findBySource(t.source, t.uri) != null) return true;
    if (_owned == null || _ownedFor != store.tracks.length) {
      _ownedFor = store.tracks.length;
      _owned = {};
      for (final o in store.tracks) {
        _owned!.putIfAbsent(_titleKey(o.title), () => {}).addAll(artistsOf(o).map(_norm));
      }
    }
    final key = _titleKey(t.title);
    if (key.isEmpty) return false;
    final mine = _owned![key];
    if (mine == null) return false;
    final theirs = artistsOf(t).map(_norm).toSet();
    // Совпало название и хоть один исполнитель (или исполнитель неизвестен).
    return mine.isEmpty ||
        theirs.isEmpty ||
        mine.contains(_norm(Track.unknownArtist)) ||
        mine.intersection(theirs).isNotEmpty;
  }

  /// Трек скрыт («не нравится») или кто-то из его исполнителей в чёрном списке.
  bool isBlocked(Track t) =>
      isDisliked(t) || (_blocked.isNotEmpty && artistsOf(t).any((a) => _blocked.contains(_norm(a))));

  bool isArtistBlocked(String name) => _blocked.contains(_norm(name));

  /// Исполнитель трека из чёрного списка (или null).
  String? blockedArtistOf(Track t) {
    for (final a in artistsOf(t)) {
      if (isArtistBlocked(a)) return _blockedNames[_norm(a)] ?? a;
    }
    return null;
  }

  /// Чёрный список исполнителей (как их написали).
  List<String> get blockedArtists => _blockedNames.values.toList()..sort();

  Future<void> blockArtist(String name) async {
    final n = _norm(name);
    if (n.isEmpty) return;
    _blocked.add(n);
    _blockedNames[n] = name.trim();
    await _save();
    notifyListeners();
    final cur = player.current;
    if (cur != null && isBlocked(cur)) await player.next();
  }

  Future<void> unblockArtist(String name) async {
    final n = _norm(name);
    _blocked.remove(n);
    _blockedNames.remove(n);
    await _save();
    notifyListeners();
  }

  /// 👎 у трека: скрыть его (не будет играть в очередях и волне) или вернуть.
  Future<void> toggleDislike(Track t) async {
    final k = _key(t);
    if (_disliked.remove(k)) {
      _dislikedInfo.remove(k);
      await _save();
      notifyListeners();
      return;
    }
    await dislike(t);
  }

  /// Треки, от которых отталкивается волна: лайки и часто слушаемые.
  List<({Track track, int weight})> _seeds() {
    final seeds = <({Track track, int weight})>[];
    for (final t in store.tracks) {
      final int w = (t.favorite ? 5 : 0) + (t.plays > 10 ? 10 : t.plays);
      if (w > 0) seeds.add((track: t, weight: w));
    }
    // Любимые исполнители со знакомства: заметны, пока своих лайков мало.
    final favWeight = seeds.length < 20 ? 6 : 2;
    for (final list in _favArtists.values) {
      for (final t in list) {
        seeds.add((track: t, weight: favWeight));
      }
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

  // ---------- Джем по треку и микс джема ----------
  // Волна, которая отталкивается не от всей медиатеки, а от заданных треков:
  // одного (джем по треку) или общих любимых треков всех в джеме.

  List<({Track track, int weight})>? _custom;
  String? _customLabel;
  bool _unfamiliar = false;

  /// Что сейчас играет вместо обычной волны: «Джем по треку «nuts»» и т. п.
  String? get radioLabel => _active ? _customLabel : null;

  /// Джем по треку: сначала сам трек, дальше — похожие на него.
  Future<void> startFromTrack(Track seed) => startCustom(
        [(track: seed, weight: 10)],
        label: 'Джем по треку «${seed.title}»',
        first: seed,
      );

  /// Волна по своему набору треков (вес — насколько сильно на него опираться).
  /// seeds == null — опора как у обычной волны (вся медиатека).
  /// unfamiliar — только исполнители, которых в медиатеке ещё нет.
  Future<void> startCustom(List<({Track track, int weight})>? seeds,
      {required String label, Track? first, bool unfamiliar = false}) async {
    _custom = seeds;
    _customLabel = label;
    _unfamiliar = unfamiliar;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final batch = await _nextBatch();
      if (batch.isEmpty && first == null) {
        throw Exception('Не получилось подобрать треки. Проверь интернет и попробуй ещё раз');
      }
      _active = true;
      player.onQueueLow = _refill;
      if (first != null) _suggested.add(_key(first));
      await player.playTracks([if (first != null) first, ...batch]);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _custom = null;
      _customLabel = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<List<Track>> _nextBatch({int size = 8, List<Track>? from}) async {
    final seeds = from != null
        ? [for (final t in from) (track: t, weight: t.favorite ? 3 : 1)]
        : _custom ?? _seeds();
    if (seeds.isEmpty) {
      throw Exception(
          'Добавь в медиатеку несколько треков и поставь им ♥ — волна подстроится под них');
    }
    final candidates = <Track>[];
    final picked = <String>{};
    for (var attempt = 0; attempt < (_unfamiliar ? 10 : 6) && candidates.length < size * 3; attempt++) {
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
    // Для режима «Незнакомое»: исполнители, которые уже есть в медиатеке.
    final known = _unfamiliar
        ? {for (final t in store.tracks) t.artist.toLowerCase()}
        : const <String>{};
    final out = <Track>[];
    candidates.shuffle(_rand);
    for (final t in candidates) {
      final k = _key(t);
      final artist = t.artist.toLowerCase();
      if (_suggested.contains(k) || isBlocked(t)) continue;
      if ((_dislikedArtists[artist] ?? 0) >= 2) continue;
      // Быстро пропущенное — не предлагаем; часто пропускаемых — реже.
      if (_skippedTracks.contains(k)) continue;
      final skips = _skippedArtists[artist] ?? 0;
      if (skips > 0 && _rand.nextDouble() < min(0.85, skips * 0.25)) continue;
      if (isOwnedLike(t)) continue;
      if (_unfamiliar && known.contains(artist)) continue;
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
    _custom = null;
    _customLabel = null;
    _unfamiliar = false;
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
    _custom = null;
    _customLabel = null;
    if (player.onQueueLow == _refill) player.onQueueLow = null;
    notifyListeners();
  }

  bool _refilling = false;

  Future<void> _refill() async {
    // Волна дозаправляется, только пока играет она сама.
    if (!_active || _refilling || !isWaveTrack(player.current)) return;
    _refilling = true;
    try {
      final batch = await _nextBatch();
      // Джем по треку понемногу «плывёт»: сыгранные треки тоже становятся опорой.
      final c = _custom;
      if (c != null && c.length < 40) {
        final cur = player.current;
        if (cur != null) c.add((track: cur, weight: 2));
      }
      player.appendAll(batch);
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
    _dislikedInfo[_key(t)] = (title: t.title, artist: t.artist);
    final a = t.artist.toLowerCase();
    _dislikedArtists[a] = (_dislikedArtists[a] ?? 0) + 1;
    await _save();
    notifyListeners();
    if (player.current?.id == t.id) await player.next();
  }

  Future<void> resetDislikes() async {
    _disliked.clear();
    _dislikedInfo.clear();
    _dislikedArtists.clear();
    await _save();
    notifyListeners();
  }

  int get dislikedCount => _disliked.length;

  /// Скрытые треки списком (ключ, название, исполнитель). У старых записей
  /// без сведений ищем трек в медиатеке.
  List<({String key, String title, String artist})> get dislikedTracks {
    if (_disliked.any((k) => !_dislikedInfo.containsKey(k))) {
      // Названия подтянутся в фоне (из медиатеки или SoundCloud).
      Future.microtask(resolveDislikedNames);
    }
    return [
      for (final k in _disliked)
        _dislikedInfo[k] != null
            ? (key: k, title: _dislikedInfo[k]!.title, artist: _dislikedInfo[k]!.artist)
            : (key: k, title: 'Загружаю название…', artist: k.split(':').first),
    ];
  }

  bool _resolving = false;

  /// Дописывает названия старым скрытым трекам с SoundCloud (без сведений).
  Future<void> resolveDislikedNames() async {
    if (_resolving) return;
    _resolving = true;
    var changed = false;
    try {
      final known = {for (final t in store.tracks) _key(t): t};
      for (final k in _disliked.toList()) {
        if (_dislikedInfo.containsKey(k)) continue;
        final t = known[k];
        if (t != null) {
          _dislikedInfo[k] = (title: t.title, artist: t.artist);
          changed = true;
          continue;
        }
        if (!k.startsWith('soundcloud:')) continue;
        try {
          final sc = await soundcloud.trackById(k.substring('soundcloud:'.length));
          if (sc != null) {
            _dislikedInfo[k] = (title: sc.title, artist: sc.artist);
            changed = true;
          }
        } catch (_) {}
      }
    } finally {
      _resolving = false;
    }
    if (changed) {
      await _save();
      notifyListeners();
    }
  }

  /// Вернуть один скрытый трек.
  Future<void> undislikeKey(String key) async {
    if (!_disliked.remove(key)) return;
    _dislikedInfo.remove(key);
    await _save();
    notifyListeners();
  }
}
