import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import 'soundcloud_source.dart';
import 'youtube_source.dart';

enum RepeatSetting { off, all, one }

/// Очередь воспроизведения и управление плеером.
class PlayerService extends ChangeNotifier {
  /// Скачанный файл трека (раздел «Загрузки») или null.
  String? Function(Track track)? offlineAudio;

  /// true — интернета нет: играем только скачанное.
  bool Function()? isOffline;

  /// Находит, где играть трек из Spotify (SoundCloud или YouTube).
  Future<Track?> Function(Track track)? resolveSpotify;

  /// Скачивает копию своего файла из облака, если на устройстве его нет.
  Future<String?> Function(Track track)? cloudFile;

  PlayerService({
    required this.youtube,
    required this.soundcloud,
    this.onDurationKnown,
    this.onStarted,
    this.onVolumeChanged,
  }) {
    _subs.add(_player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed && !_completing) {
        _completing = true;
        _onCompleted().whenComplete(() => _completing = false);
      }
      notifyListeners();
    }));
    _subs.add(_player.durationStream.listen((d) {
      final t = current;
      if (d != null && t != null && t.durationMs == null) {
        onDurationKnown?.call(t, d);
      }
      notifyListeners();
    }));
    _subs.add(_player.playbackEventStream.listen((_) {}, onError: (Object e) {
      _error = 'Ошибка воспроизведения: $e';
      notifyListeners();
    }));
  }

  final YoutubeSource youtube;
  final SoundcloudSource soundcloud;
  final void Function(Track track, Duration duration)? onDurationKnown;

  /// Трек успешно запустился (счётчик прослушиваний).
  final void Function(Track track)? onStarted;

  /// Пользователь поменял громкость (чтобы запомнить её).
  final void Function(double volume)? onVolumeChanged;

  /// Вызывается, когда в очереди осталось мало треков (подгрузка «Волны»).
  Future<void> Function()? onQueueLow;

  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];

  List<Track> _queue = [];
  List<Track> _unshuffled = [];
  int _index = -1;
  bool _shuffle = false;
  RepeatSetting _repeat = RepeatSetting.off;
  bool _loading = false;
  bool _completing = false;
  String? _error;
  int _loadToken = 0;

  List<Track> get queue => List.unmodifiable(_queue);
  int get index => _index;
  Track? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;
  bool get shuffle => _shuffle;
  RepeatSetting get repeat => _repeat;
  bool get loading => _loading;
  String? get error => _error;
  bool get playing => _player.playing;
  double get volume => _player.volume;
  Duration get position => _player.position;
  Duration? get duration => _player.duration ?? current?.duration;

  Stream<Duration> get positionStream => _player.positionStream;

  /// Частый поток позиции — для плавной заливки караоке.
  late final Stream<Duration> smoothPositionStream = _player
      .createPositionStream(
        steps: 4000,
        minPeriod: const Duration(milliseconds: 16),
        maxPeriod: const Duration(milliseconds: 50),
      )
      .asBroadcastStream();

  // ---------- Запуск ----------

  Future<void> playTracks(List<Track> tracks, {int start = 0}) async {
    if (tracks.isEmpty) return;
    _recommended.clear();
    _unshuffled = List.of(tracks);
    _queue = List.of(tracks);
    _index = start.clamp(0, tracks.length - 1);
    // Трек, на который нажали сами, играет, даже если он скрыт.
    _allowId = _queue[_index].id;
    // Режим перемешивания действует при любом запуске, в том числе по нажатию на трек.
    if (_shuffle) _shuffleRest();
    final load = _loadCurrent();
    if (_smart) unawaited(_ensureRecsAhead());
    await load;
  }

  /// «Слушать всё»: если перемешивание включено — начинаем со случайного трека.
  Future<void> playAll(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    await playTracks(tracks, start: _shuffle ? Random().nextInt(tracks.length) : 0);
  }

  Future<void> shufflePlay(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    _shuffle = true;
    await playTracks(tracks, start: Random().nextInt(tracks.length));
  }

  /// Трек скрыт («не нравится») или исполнитель в чёрном списке.
  bool Function(Track track)? isBlocked;
  String? _allowId;

  Future<void> _loadCurrent({bool autoplay = true}) async {
    var t = current;
    if (t == null) return;
    // Скрытые треки пропускаем (кроме того, на который нажали сами).
    final blocked = isBlocked;
    if (blocked != null && t.id != _allowId && blocked(t)) {
      var j = _index + 1;
      while (j < _queue.length && blocked(_queue[j])) {
        j++;
      }
      if (j >= _queue.length) {
        _error = 'Дальше в очереди только скрытые треки';
        await _player.pause();
        notifyListeners();
        return;
      }
      _index = j;
      t = _queue[j];
    }
    _allowId = null;
    final token = ++_loadToken;
    _loading = true;
    _pauseRequested = false;
    _error = null;
    notifyListeners();
    // Сразу глушим прошлый трек: если новый не загрузится,
    // старый не должен продолжать играть.
    try {
      // После сбоя плеер иногда «залипает», поэтому ждём не дольше 3 секунд.
      await _player.stop().timeout(const Duration(seconds: 3));
    } catch (_) {}
    if (token != _loadToken) return;
    try {
      final source = await _sourceFor(t)
          .timeout(const Duration(minutes: 2), onTimeout: () {
        throw Exception('источник не ответил за 2 минуты');
      });
      if (token != _loadToken) return;
      await _player.setAudioSource(source).timeout(
          const Duration(seconds: 12), onTimeout: () {
        throw Exception('плеер не смог открыть поток');
      });
      if (token != _loadToken) return;
      // Пока грузилось, нажали паузу — не включаем.
      if (autoplay && !_pauseRequested) unawaited(_player.play());
      _failedInRow = 0;
      onStarted?.call(t);
      // Умное перемешивание: держим рекомендации на несколько треков вперёд.
      if (_smart) unawaited(_ensureRecsAhead());
      _prefetchNext();
      final low = onQueueLow;
      if (low != null && _queue.length - _index <= 3) unawaited(low());
    } on PlayerInterruptedException {
      // Загрузку прервал следующий трек — это нормально.
    } catch (e) {
      if (token == _loadToken) {
        _error = 'Не удалось включить «${t.title}»: ${_shortError(e)}';
        _failedInRow++;
        // Как в Spotify: недоступный трек пропускаем и играем следующий.
        // Если поставили на паузу — остаёмся на этом треке.
        if (autoplay &&
            !_pauseRequested &&
            _index + 1 < _queue.length &&
            _failedInRow < _queue.length) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (token == _loadToken) next();
          });
        }
      }
    } finally {
      if (token == _loadToken) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  int _failedInRow = 0;

  /// Пауза нажата, пока трек ещё грузится.
  bool _pauseRequested = false;
  bool get pausePending => _loading && _pauseRequested;

  static String _shortError(Object e) {
    final text = e.toString();
    if (text.contains('VideoUnavailable') || text.contains('unavailable')) {
      return 'YouTube не отдал звук этого видео';
    }
    if (text.contains('SocketException') || text.contains('Failed host lookup')) {
      return 'нет подключения к интернету';
    }
    final firstLine = text.split('\n').first;
    return firstLine.length > 160 ? '${firstLine.substring(0, 160)}…' : firstLine;
  }

  /// Заранее качаем следующий трек с YouTube, чтобы переход был без паузы.
  void _prefetchNext() {
    // Два следующих трека готовим заранее, чтобы они включались сразу.
    for (var i = _index + 1; i <= _index + 2 && i < _queue.length; i++) {
      final next = _queue[i];
      if (next.source == TrackSource.youtube) {
        youtube.cachedAudio(next.uri).ignore();
      } else if (next.source == TrackSource.soundcloud) {
        soundcloud.prefetch(next.uri);
      }
    }
  }

  Future<AudioSource> _sourceFor(Track t) async {
    final downloaded = offlineAudio?.call(t);
    if (downloaded != null) return AudioSource.file(downloaded);
    if (isOffline?.call() == true &&
        !(t.source == TrackSource.local && File(t.uri).existsSync())) {
      throw Exception('нет интернета, а трек не скачан');
    }
    switch (t.source) {
      case TrackSource.local:
        if (File(t.uri).existsSync()) return AudioSource.file(t.uri);
        // Файла на этом устройстве нет — берём копию из облака.
        final fromCloud = await cloudFile?.call(t);
        if (fromCloud != null) return AudioSource.file(fromCloud);
        throw Exception(t.cloudPath == null
            ? 'файл не найден: ${t.uri}'
            : 'не удалось скачать файл из облака');
      case TrackSource.url:
        return AudioSource.uri(Uri.parse(t.uri));
      case TrackSource.youtube:
        return await youtube.playableSource(t.uri);
      case TrackSource.soundcloud:
        return AudioSource.file((await soundcloud.cachedAudio(t.uri)).path);
      case TrackSource.spotify:
        // Spotify звук не отдаёт: играем тот же трек с SoundCloud/YouTube.
        final found = await resolveSpotify?.call(t);
        if (found == null || found.source == TrackSource.spotify) {
          throw Exception('не нашёл этот трек на SoundCloud и YouTube');
        }
        return _sourceFor(found);
    }
  }

  // ---------- Управление ----------

  Future<void> togglePlay() async {
    if (current == null) return;
    // Трек ещё грузится: запоминаем паузу, после загрузки он не заиграет
    // и при ошибке не перескочит на следующий.
    if (_loading) {
      _pauseRequested = !_pauseRequested;
      notifyListeners();
      return;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      if (_player.processingState == ProcessingState.idle) {
        await _loadCurrent();
        return;
      }
      unawaited(_player.play());
    }
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_index < _queue.length - 1) {
      _index++;
    } else if (_repeat == RepeatSetting.all) {
      _index = 0;
    } else {
      await _player.pause();
      await _player.seek(Duration.zero);
      return;
    }
    await _loadCurrent();
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (_player.position > const Duration(seconds: 3) || _index == 0) {
      await _player.seek(Duration.zero);
      return;
    }
    _index--;
    await _loadCurrent();
  }

  Future<void> jumpTo(int i) async {
    if (i < 0 || i >= _queue.length) return;
    _index = i;
    _allowId = _queue[i].id;
    await _loadCurrent();
  }

  Future<void> _onCompleted() async {
    if (_repeat == RepeatSetting.one) {
      await _player.seek(Duration.zero);
      unawaited(_player.play());
    } else {
      await next();
    }
  }

  Future<void> seek(Duration d) => _player.seek(d);

  Future<void> setVolume(double v, {bool remember = true}) async {
    final value = v.clamp(0.0, 1.0);
    await _player.setVolume(value);
    if (remember) onVolumeChanged?.call(value);
    notifyListeners();
  }

  /// Перемешивание по кругу: выкл → перемешать → перемешать с
  /// рекомендациями (как «умное перемешивание» в Spotify) → выкл.
  void toggleShuffle() {
    if (!_shuffle) {
      _shuffle = true;
      _smart = false;
      _unshuffled = List.of(_queue);
      _shuffleRest();
    } else if (!_smart && recommend != null) {
      _smart = true;
      _injectRecommendations();
    } else {
      _shuffle = false;
      _smart = false;
      final cur = current;
      // Убираем подмешанные рекомендации (кроме играющей сейчас).
      _queue = _unshuffled
          .where((t) => !_recommended.contains(t.id) || t.id == cur?.id)
          .toList();
      _recommended.clear();
      if (cur != null) {
        _index = _queue.indexWhere((t) => t.id == cur.id);
        if (_index < 0) {
          _queue.insert(0, cur);
          _index = 0;
        }
      }
    }
    notifyListeners();
  }

  bool _smart = false;
  final Set<String> _recommended = {};

  /// Включено умное перемешивание (с рекомендациями).
  bool get smartShuffle => _smart;

  /// Трек подмешан рекомендациями (в очереди помечается ✨).
  bool isRecommended(Track t) => _recommended.contains(t.id);

  /// Источник рекомендаций: по трекам очереди подбирает похожие.
  Future<List<Track>> Function(List<Track> seeds, int count)? recommend;

  /// Включение умного перемешивания.
  Future<void> _injectRecommendations() => _ensureRecsAhead();

  bool _recFetching = false;

  /// Трек уже есть у тебя (тот же трек, хоть и с другой площадки).
  bool Function(Track track)? isDuplicate;

  /// Позиции, куда должна встать рекомендация: после каждой пары своих
  /// треков в ближайших 20, где её ещё нет.
  List<int> _recSpots() {
    final spots = <int>[];
    var own = 0;
    for (var i = _index + 1; i < _queue.length && i <= _index + 20; i++) {
      if (_recommended.contains(_queue[i].id)) {
        own = 0;
        continue;
      }
      own++;
      if (own == 2) {
        spots.add(i + 1);
        own = 0;
      }
    }
    return spots;
  }

  /// Как в Spotify: после каждых двух своих треков — одна рекомендация из
  /// «Моей волны». Держим их на ~20 позиций вперёд и докладываем по мере
  /// прослушивания, так что рекомендации не кончаются.
  Future<void> _ensureRecsAhead() async {
    final rec = recommend;
    if (rec == null || !_smart || _recFetching || _index < 0) return;
    final need = _recSpots().length;
    if (need == 0) return;
    _recFetching = true;
    try {
      // Похожее подбираем по своим трекам рядом с текущим.
      final near = _queue
          .skip(_index)
          .take(12)
          .where((t) => !_recommended.contains(t.id))
          .toList()
        ..shuffle(_rand);
      final found = await rec(near.take(5).toList(), need + 4);
      if (!_smart || found.isEmpty) return;
      final known = {for (final t in _queue) '${t.source.name}:${t.uri}'};
      final artists = <String>{};
      final fresh = <Track>[];
      for (final t in found) {
        if (known.contains('${t.source.name}:${t.uri}')) continue;
        if (isBlocked?.call(t) == true || isDuplicate?.call(t) == true) continue;
        // В одной пачке — не больше одного трека исполнителя.
        if (!artists.add(_artistKey(t))) continue;
        fresh.add(t);
      }
      // Позиции считаем заново: пока искали, могли переключить трек.
      for (final t in fresh) {
        final spots = _recSpots();
        if (spots.isEmpty) break;
        var pos = spots.first;
        // Не ставим рядом с треком того же исполнителя, если есть выбор.
        for (final sp in spots) {
          final prev = sp - 1 >= 0 ? _artistKey(_queue[sp - 1]) : null;
          final next = sp < _queue.length ? _artistKey(_queue[sp]) : null;
          if (prev != _artistKey(t) && next != _artistKey(t)) {
            pos = sp;
            break;
          }
        }
        _queue.insert(min(pos, _queue.length), t);
        _unshuffled.add(t);
        _recommended.add(t.id);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[Умное перемешивание] $e');
    } finally {
      _recFetching = false;
    }
  }

  final _rand = Random();

  /// Перемешивает всё после текущего трека, но «ровно», как в Spotify:
  /// треки одного исполнителя разносятся по всей очереди, а не идут подряд.
  void _shuffleRest() {
    if (_index < 0) return;
    final rest = [..._queue.sublist(_index + 1), ..._queue.sublist(0, _index)];
    _queue = [_queue[_index], ..._balancedShuffle(rest, after: _queue[_index])];
    _index = 0;
  }

  static String _artistKey(Track t) =>
      t.artist
          .toLowerCase()
          .split(RegExp(r'\s*[,&;]\s*|\s+(?:feat\.?|ft\.?|x)\s+'))
          .first
          .trim();

  /// Каждой группе (исполнителю) — позиции, равномерно разбросанные по
  /// всей длине со случайным сдвигом; потом убираем повторы подряд.
  List<Track> _balancedShuffle(List<Track> tracks, {Track? after}) {
    if (tracks.length < 3) return tracks..shuffle(_rand);
    final groups = <String, List<Track>>{};
    for (final t in tracks) {
      groups.putIfAbsent(_artistKey(t), () => []).add(t);
    }
    final placed = <({double pos, Track t})>[];
    for (final g in groups.values) {
      g.shuffle(_rand);
      final step = 1.0 / g.length;
      final offset = _rand.nextDouble() * step;
      for (var i = 0; i < g.length; i++) {
        // Небольшой разброс, чтобы порядок не был механическим.
        final jitter = (_rand.nextDouble() - 0.5) * step * 0.4;
        placed.add((pos: offset + i * step + jitter, t: g[i]));
      }
    }
    placed.sort((a, b) => a.pos.compareTo(b.pos));
    final out = placed.map((e) => e.t).toList();
    // Если два одинаковых исполнителя всё же рядом — меняем второй с дальним соседом.
    String? prev = after == null ? null : _artistKey(after);
    for (var i = 0; i < out.length; i++) {
      if (_artistKey(out[i]) == prev) {
        for (var j = i + 1; j < out.length; j++) {
          if (_artistKey(out[j]) != prev &&
              (i == 0 || _artistKey(out[j]) != _artistKey(out[i - 1]))) {
            final tmp = out[i];
            out[i] = out[j];
            out[j] = tmp;
            break;
          }
        }
      }
      prev = _artistKey(out[i]);
    }
    return out;
  }

  void cycleRepeat() {
    _repeat = RepeatSetting.values[(_repeat.index + 1) % RepeatSetting.values.length];
    notifyListeners();
  }

  // ---------- Очередь ----------

  Future<void> playNext(Track t) async {
    if (current == null) return playTracks([t]);
    _queue.insert(_index + 1, t);
    _unshuffled.add(t);
    notifyListeners();
  }

  Future<void> addToQueue(Track t) async {
    if (current == null) return playTracks([t]);
    _queue.add(t);
    _unshuffled.add(t);
    notifyListeners();
  }

  /// Добавляет треки в конец очереди (без перезапуска текущего).
  void appendAll(List<Track> tracks) {
    if (tracks.isEmpty) return;
    _queue.addAll(tracks);
    _unshuffled.addAll(tracks);
    notifyListeners();
  }

  void removeFromQueue(int i) {
    if (i < 0 || i >= _queue.length || i == _index) return;
    final removed = _queue.removeAt(i);
    _unshuffled.removeWhere((t) => t.id == removed.id);
    if (i < _index) _index--;
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final cur = current;
    _queue.insert(newIndex, _queue.removeAt(oldIndex));
    if (cur != null) _index = _queue.indexWhere((t) => t.id == cur.id);
    notifyListeners();
  }

  /// Обновляет данные трека в очереди (например, после правки названия).
  void refreshTrack(Track t) {
    var changed = false;
    for (var i = 0; i < _queue.length; i++) {
      if (_queue[i].id == t.id) {
        _queue[i] = t;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
