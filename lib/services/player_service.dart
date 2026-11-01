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
    // Режим перемешивания действует при любом запуске, в том числе по нажатию на трек.
    if (_shuffle) _shuffleRest();
    final load = _loadCurrent();
    if (_smart) unawaited(_injectRecommendations());
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

  Future<void> _loadCurrent({bool autoplay = true}) async {
    final t = current;
    if (t == null) return;
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
        if (found == null) {
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

  /// Каждый третий трек после текущего — рекомендация.
  Future<void> _injectRecommendations() async {
    final rec = recommend;
    if (rec == null || _index < 0) return;
    final seeds = (_queue.where((t) => !_recommended.contains(t.id)).toList()..shuffle())
        .take(5)
        .toList();
    List<Track> found;
    try {
      found = await rec(seeds, 8);
    } catch (_) {
      return;
    }
    if (!_smart || found.isEmpty) return;
    var pos = _index + 3;
    for (final t in found) {
      if (pos > _queue.length) break;
      _queue.insert(pos, t);
      _unshuffled.add(t);
      _recommended.add(t.id);
      pos += 3;
    }
    notifyListeners();
  }

  /// Перемешивает всё, что идёт после текущего трека (как в Spotify).
  void _shuffleRest() {
    if (_index < 0) return;
    final rest = _queue.sublist(_index + 1)..shuffle();
    final before = _queue.sublist(0, _index)..shuffle();
    _queue = [_queue[_index], ...rest, ...before];
    _index = 0;
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
