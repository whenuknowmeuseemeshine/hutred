import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

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

  /// Включён ли YouTube как запасной источник (для текста ошибки).
  bool Function() youtubeAllowed = () => true;

  /// Скачивает копию своего файла из облака, если на устройстве его нет.
  Future<String?> Function(Track track)? cloudFile;

  PlayerService({
    required this.youtube,
    required this.soundcloud,
    this.onDurationKnown,
    this.onStarted,
    this.onVolumeChanged,
  }) {
    // Два плеера: пока один доигрывает и затихает, второй уже начинает
    // следующий трек (плавный переход). События слушаем только у текущего.
    for (final p in [_a, _b]) {
      _subs.add(p.playerStateStream.listen((s) {
        if (p != _player) return;
        if (s.processingState == ProcessingState.completed && !_completing) {
          _completing = true;
          _onCompleted().whenComplete(() => _completing = false);
        }
        notifyListeners();
      }));
      _subs.add(p.durationStream.listen((d) {
        if (p != _player) return;
        final t = current;
        if (d != null && t != null && t.durationMs == null) {
          onDurationKnown?.call(t, d);
        }
        notifyListeners();
      }));
      _subs.add(p.playbackEventStream.listen((_) {}, onError: (Object e) {
        if (p != _player) return;
        _error = 'Ошибка воспроизведения: $e';
        notifyListeners();
      }));
      _subs.add(p.positionStream.listen((d) {
        if (p == _player) _pos.add(d);
      }));
      _subs.add(p
          .createPositionStream(
            steps: 4000,
            minPeriod: const Duration(milliseconds: 16),
            maxPeriod: const Duration(milliseconds: 50),
          )
          .listen((d) {
        if (p == _player) _smoothPos.add(d);
      }));
    }
    _xfTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => _checkCrossfade());
  }

  // ---------- Где остановились ----------

  File? _stateFile;
  Timer? _stateTimer;

  /// С какого места продолжить трек, восстановленный после перезапуска.
  Duration? _resumeAt;

  /// Запомненная позиция (до нажатия «играть» после перезапуска).
  Duration? get resumePosition => _resumeAt;

  /// Восстанавливает очередь и место в треке с прошлого запуска (на паузе).
  Future<void> restoreState(File file) async {
    _stateFile = file;
    try {
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString());
        // Режимы перемешивания и повтора помним всегда, даже без очереди.
        if (j is Map) {
          _shuffle = j['shuffle'] == true;
          _smart = _shuffle && j['smart'] == true;
          recent
            ..clear()
            ..addAll([
              for (final t in (j['recent'] as List? ?? const []))
                if (t is Map) Track.fromJson(Map<String, dynamic>.from(t)),
            ]);
          final r = (j['repeat'] as num?)?.toInt() ?? 0;
          if (r >= 0 && r < RepeatSetting.values.length) _repeat = RepeatSetting.values[r];
        }
        if (j is Map && _queue.isEmpty) {
          final q = [
            for (final t in (j['queue'] as List? ?? const []))
              if (t is Map) Track.fromJson(Map<String, dynamic>.from(t)),
          ];
          final i = (j['index'] as num?)?.toInt() ?? -1;
          if (q.isNotEmpty && i >= 0 && i < q.length) {
            _queue = q;
            _unshuffled = List.of(q);
            _index = i;
            // Какие треки подмешаны рекомендациями — чтобы ✨ не пропадала после перезапуска.
            _recommended.addAll(List<String>.from(j['recommended'] as List? ?? const []));
            _shuffle = j['shuffle'] == true;
            final ms = (j['positionMs'] as num?)?.toInt() ?? 0;
            if (ms > 3000) _resumeAt = Duration(milliseconds: ms);
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('[Плеер] не удалось восстановить: $e');
    }
    // Пока играет — запоминаем раз в 5 секунд, плюс при каждой паузе.
    _stateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_player.playing) _saveState();
    });
  }

  Future<void> _saveState() async {
    final f = _stateFile;
    if (f == null) return;
    if (current == null) {
      try {
        await f.writeAsString(jsonEncode({
          'shuffle': _shuffle,
          'smart': _smart,
          'repeat': _repeat.index,
        }));
      } catch (_) {}
      return;
    }
    // Длинную очередь храним вокруг текущего трека, чтобы файл был маленьким.
    final from = max(0, _index - 50);
    final to = min(_queue.length, _index + 150);
    try {
      await f.writeAsString(jsonEncode({
        'queue': [for (final t in _queue.sublist(from, to)) t.toJson()],
        'index': _index - from,
        'positionMs': (_resumeAt ?? _player.position).inMilliseconds,
        'shuffle': _shuffle,
        'smart': _smart,
        'repeat': _repeat.index,
        'recent': [for (final t in recent.take(30)) t.toJson()],
        'recommended': [
          for (final t in _queue.sublist(from, to))
            if (_recommended.contains(t.id)) t.id,
        ],
      }));
    } catch (_) {}
  }

  // ---------- Плавность ----------

  /// Плавный переход между треками (секунды; 0 — выключен).
  int Function() crossfadeSeconds = () => 0;

  /// Пауза и продолжение плавно (затихание ~0,5 с).
  bool Function() fadeOnPause = () => true;

  // Эквалайзер: на Android — системный, на компьютере — фильтр libmpv.
  final AndroidEqualizer? _eqA = Platform.isAndroid ? AndroidEqualizer() : null;
  final AndroidEqualizer? _eqB = Platform.isAndroid ? AndroidEqualizer() : null;
  late final AudioPlayer _a = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [if (_eqA != null) _eqA!]));
  late final AudioPlayer _b = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [if (_eqB != null) _eqB!]));

  bool _eqOn = false;
  List<double> _eqGains = const [];

  static final bool _mpvEq = !kIsWeb && (Platform.isWindows || Platform.isLinux);
  static const _mpvBands = <double>[31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

  bool get eqSupported => _eqA != null || _mpvEq;

  /// Полосы эквалайзера (частоты и пределы). На Android появляются,
  /// когда что-то заиграло.
  Future<EqInfo?> eqParameters() async {
    if (_mpvEq) return const EqInfo(_mpvBands, -12, 12);
    final eq = _eqA;
    if (eq == null) return null;
    try {
      final p = await eq.parameters.timeout(const Duration(seconds: 3));
      return EqInfo([for (final b in p.bands) b.centerFrequency], p.minDecibels, p.maxDecibels);
    } catch (_) {
      return null;
    }
  }

  Future<void> setEqualizer(bool on, List<double> gains) async {
    _eqOn = on;
    _eqGains = List.of(gains);
    await _applyEq();
  }

  Future<void> _applyEq() async {
    if (_mpvEq) {
      // В сборке libmpv для Windows из фильтров есть только equalizer,
      // поэтому запас громкости делаем им же: все полосы чуть ниже.
      final on = _eqOn && _eqGains.length == _mpvBands.length && _eqGains.any((g) => g.abs() >= 0.1);
      final boost = on ? _eqGains.reduce((a, b) => a > b ? a : b).clamp(0, 12) * 0.5 : 0.0;
      final parts = <String>[
        if (on)
          for (var i = 0; i < _mpvBands.length; i++)
            if ((_eqGains[i] - boost).abs() >= 0.1)
              'equalizer=f=${_mpvBands[i].round()}:t=o:w=1:g=${(_eqGains[i] - boost).clamp(-24, 12).toStringAsFixed(1)}',
      ];
      await JustAudioMediaKit.setAudioFilter(parts.isEmpty ? '' : 'lavfi=[${parts.join(',')}]');
      return;
    }
    for (final eq in [_eqA, _eqB]) {
      if (eq == null) continue;
      try {
        await eq.setEnabled(_eqOn);
        final params = await eq.parameters.timeout(const Duration(seconds: 3));
        for (var i = 0; i < params.bands.length && i < _eqGains.length; i++) {
          await params.bands[i].setGain(_eqGains[i]
              .clamp(params.minDecibels, params.maxDecibels)
              .toDouble());
        }
      } catch (_) {}
    }
  }
  late AudioPlayer _player = _a;
  AudioPlayer get _other => identical(_player, _a) ? _b : _a;

  final _pos = StreamController<Duration>.broadcast();
  final _smoothPos = StreamController<Duration>.broadcast();
  Timer? _xfTimer;
  bool _xfRunning = false;
  int _fadeToken = 0;

  /// Громкость, которую выбрал пользователь (плавности меняют её временно).
  double _userVolume = 1;

  /// Плавно меняет громкость плеера. Прерывается, если началась другая плавность.
  Future<bool> _ramp(AudioPlayer p, double from, double to, Duration d,
      {int? token}) async {
    const steps = 30;
    final t = token ?? ++_fadeToken;
    for (var i = 1; i <= steps; i++) {
      if (t != _fadeToken) return false;
      final k = i / steps;
      // Громкость на слух логарифмическая: квадратичная кривая звучит ровно,
      // без «провала» в конце затухания.
      final v = to < from
          ? to + (from - to) * (1 - k) * (1 - k)
          : from + (to - from) * k * k;
      await p.setVolume(v.clamp(0.0, 1.0));
      await Future<void>.delayed(d ~/ steps);
    }
    return t == _fadeToken;
  }

  /// Глушит второй (затихающий) плеер — например, если переключили трек.
  Future<void> _killOther() async {
    final o = _other;
    if (o.playing || o.processingState != ProcessingState.idle) {
      try {
        await o.stop();
      } catch (_) {}
    }
  }

  /// Следующий трек, который заиграет сам (с учётом скрытых).
  int? _autoNextIndex() {
    if (_repeat == RepeatSetting.one) return null;
    var j = _index + 1;
    final blocked = isBlocked;
    while (j < _queue.length && blocked != null && blocked(_queue[j])) {
      j++;
    }
    if (j < _queue.length) return j;
    if (_repeat == RepeatSetting.all && _queue.isNotEmpty) return 0;
    return null;
  }

  Future<void> _checkCrossfade() async {
    final secs = crossfadeSeconds();
    if (secs <= 0 || _xfRunning || _loading || !_player.playing) return;
    final dur = _player.duration;
    if (dur == null || dur.inSeconds < secs * 2 + 5) return;
    final left = dur - _player.position;
    if (left > Duration(seconds: secs) || left <= const Duration(milliseconds: 600)) return;
    final j = _autoNextIndex();
    if (j == null) return;
    _xfRunning = true;
    final token = _loadToken;
    final next = _queue[j];
    try {
      // Следующий трек заранее скачан (_prefetchNext), обычно это мгновенно.
      final source = await _sourceFor(next).timeout(const Duration(seconds: 2));
      if (token != _loadToken || !_player.playing) return;
      final incoming = _other;
      await incoming.setVolume(0);
      await incoming.setAudioSource(source).timeout(const Duration(seconds: 4));
      if (token != _loadToken) {
        await incoming.stop();
        return;
      }
      final outgoing = _player;
      final fadeLen = _player.duration! - _player.position;
      // Переключаемся: теперь «текущий» — новый трек.
      _player = incoming;
      _index = j;
      ++_loadToken;
      unawaited(incoming.play());
      onStarted?.call(next);
      notifyListeners();
      if (_smart) unawaited(_ensureRecsAhead());
      _prefetchNext();
      final low = onQueueLow;
      if (low != null && _queue.length - _index <= 6) unawaited(low());
      final t = ++_fadeToken;
      await Future.wait([
        _ramp(incoming, 0, _userVolume, fadeLen, token: t),
        _ramp(outgoing, _userVolume, 0, fadeLen, token: t),
      ]);
      await outgoing.stop();
      await outgoing.setVolume(_userVolume);
      if (t == _fadeToken) await incoming.setVolume(_userVolume);
    } catch (e) {
      debugPrint('[Переход] $e');
    } finally {
      _xfRunning = false;
    }
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
  /// Кнопки сразу показывают паузу/игру, не дожидаясь конца затухания.
  bool get playing => _intent ?? _player.playing;
  bool? _intent;
  double get volume => _userVolume;
  Duration get position => _resumeAt ?? _player.position;
  Duration? get duration => _player.duration ?? current?.duration;

  Stream<Duration> get positionStream => _pos.stream;

  /// Частый поток позиции — для плавной заливки караоке.
  Stream<Duration> get smoothPositionStream => _smoothPos.stream;

  // ---------- Запуск ----------

  Future<void> playTracks(List<Track> tracks, {int start = 0}) async {
    if (tracks.isEmpty) return;
    _resumeAt = null;
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

  /// Недавно игравшие треки (новые первыми, без повторов, до 30).
  final List<Track> recent = [];

  void _noteRecent(Track t) {
    if (recent.isNotEmpty && recent.first.id == t.id) return;
    recent.removeWhere((e) => e.id == t.id || (e.source == t.source && e.uri == t.uri));
    recent.insert(0, t);
    if (recent.length > 30) recent.removeRange(30, recent.length);
  }

  /// Сейчас играет трек из этого списка (кнопка «Слушать» становится паузой).
  bool isFrom(List<Track> list) {
    final c = current;
    return c != null && list.any((t) => t.id == c.id);
  }

  /// Большая кнопка списка: если играет этот список — пауза/продолжить,
  /// иначе — включить список.
  Future<void> playOrToggle(List<Track> list, {bool all = false}) async {
    if (isFrom(list)) return togglePlay();
    return all ? playAll(list) : playTracks(list);
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

  /// Своего файла нет на месте (переместили/переименовали) — спросить, где он.
  void Function(Track track)? onMissingFile;

  /// Трек скрыт («не нравится») или исполнитель в чёрном списке.
  bool Function(Track track)? isBlocked;

  /// Исполнитель трека в чёрном списке — его не играем даже по нажатию.
  String? Function(Track track)? blockedArtist;
  String? _allowId;

  Future<void> _loadCurrent({bool autoplay = true}) async {
    var t = current;
    if (t == null) return;
    if (autoplay) _noteRecent(t);
    // Нажали на трек исполнителя из чёрного списка — не играем, объясняем.
    final banned = blockedArtist?.call(t);
    if (banned != null && t.id == _allowId) {
      _allowId = null;
      _error = '«$banned» в чёрном списке. Чтобы слушать, верни исполнителя '
          '(Настройки → Медиатека и волна → Чёрный список)';
      await _player.pause();
      notifyListeners();
      return;
    }
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
    ++_fadeToken;
    try {
      await _killOther();
      // После сбоя плеер иногда «залипает», поэтому ждём не дольше 3 секунд.
      await _player.stop().timeout(const Duration(seconds: 3));
      await _player.setVolume(_userVolume);
    } catch (_) {}
    if (token != _loadToken) return;
    try {
      final source = await _sourceFor(t)
          .timeout(const Duration(minutes: 2), onTimeout: () {
        throw Exception('источник не ответил за 2 минуты');
      });
      if (token != _loadToken) return;
      if (eqSupported && _eqOn) unawaited(_applyEq());
      await _player.setAudioSource(source).timeout(
          const Duration(seconds: 12), onTimeout: () {
        throw Exception('плеер не смог открыть поток');
      });
      if (token != _loadToken) return;
      final resume = _resumeAt;
      _resumeAt = null;
      if (resume != null) {
        try {
          await _player.seek(resume);
        } catch (_) {}
      }
      // Пока грузилось, нажали паузу — не включаем.
      if (autoplay && !_pauseRequested) unawaited(_player.play());
      _failedInRow = 0;
      onStarted?.call(t);
      // Умное перемешивание: держим рекомендации на несколько треков вперёд.
      if (_smart) unawaited(_ensureRecsAhead());
      _prefetchNext();
      final low = onQueueLow;
      if (low != null && _queue.length - _index <= 6) unawaited(low());
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
        if (t.cloudPath == null) onMissingFile?.call(t);
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
          throw Exception(youtubeAllowed()
              ? 'не нашёл этот трек на SoundCloud и YouTube'
              : 'нет на SoundCloud. Можно включить YouTube: Настройки → Сеть и YouTube');
        }
        return _sourceFor(found);
    }
  }

  // ---------- Управление ----------

  /// В джеме у гостя: кнопки управления уходят хозяину джема.
  /// Возвращает true, если команда отправлена и здесь ничего делать не нужно.
  Future<bool> Function(String cmd, {int? ms, Track? track})? remoteControl;

  Future<void> togglePlay() async {
    if (await remoteControl?.call('toggle') ?? false) return;
    if (current == null) return;
    // Трек ещё грузится: запоминаем паузу, после загрузки он не заиграет
    // и при ошибке не перескочит на следующий.
    if (_loading) {
      _pauseRequested = !_pauseRequested;
      notifyListeners();
      return;
    }
    if (playing) {
      await pause();
    } else {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      if (_player.processingState == ProcessingState.idle) {
        await _loadCurrent();
        return;
      }
      await resume();
    }
  }

  /// Пауза: как в Spotify, звук не обрывается, а быстро затихает.
  Future<void> pause() async {
    if (!_player.playing) return;
    _intent = false;
    notifyListeners();
    await _killOther();
    final p = _player;
    if (fadeOnPause()) {
      final t = ++_fadeToken;
      final done = await _ramp(p, p.volume, 0, const Duration(milliseconds: 500), token: t);
      if (!done) return; // Пока затихало, снова нажали «играть».
    }
    await p.pause();
    await p.setVolume(_userVolume);
    _intent = null;
    notifyListeners();
    unawaited(_saveState());
  }

  /// Продолжить: звук плавно нарастает.
  Future<void> resume() async {
    final p = _player;
    _intent = null;
    if (fadeOnPause()) {
      final t = ++_fadeToken;
      await p.setVolume(0);
      unawaited(p.play());
      await _ramp(p, 0, _userVolume, const Duration(milliseconds: 300), token: t);
    } else {
      ++_fadeToken;
      await p.setVolume(_userVolume);
      unawaited(p.play());
    }
  }

  Future<void> next() async {
    if (await remoteControl?.call('next') ?? false) return;
    _resumeAt = null;
    if (_queue.isEmpty) return;
    // Волна: при быстрых пропусках треки грузятся не до конца, и подкачка после
    // загрузки не успевает — подкачиваем сразу при нажатии.
    final low = onQueueLow;
    if (low != null && _queue.length - _index <= 6) {
      if (_index >= _queue.length - 1) {
        // Очередь кончилась — ждём новую порцию, а не останавливаемся.
        await low();
      } else {
        unawaited(low());
      }
    }
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
    if (await remoteControl?.call('prev') ?? false) return;
    _resumeAt = null;
    if (_queue.isEmpty) return;
    if (_player.position > const Duration(seconds: 3) || _index == 0) {
      await _player.seek(Duration.zero);
      return;
    }
    _index--;
    await _loadCurrent();
  }

  Future<void> jumpTo(int i) async {
    _resumeAt = null;
    if (i < 0 || i >= _queue.length) return;
    _index = i;
    _allowId = _queue[i].id;
    await _loadCurrent();
  }

  Future<void> _onCompleted() async {
    // Гость в джеме: следующий трек выберет хозяин.
    if (remoteControl != null) return;
    if (_repeat == RepeatSetting.one) {
      await _player.seek(Duration.zero);
      unawaited(_player.play());
    } else {
      await next();
    }
  }

  Future<void> seek(Duration d) async {
    if (await remoteControl?.call('seek', ms: d.inMilliseconds) ?? false) return;
    await syncSeek(d);
  }

  /// Перемотка без отправки хозяину джема (сама подстройка под него).
  Future<void> syncSeek(Duration d) async {
    // Трек после перезапуска ещё не загружен — просто запоминаем новое место.
    if (_resumeAt != null && _player.processingState == ProcessingState.idle) {
      _resumeAt = d;
      notifyListeners();
      return;
    }
    await _player.seek(d);
  }

  Future<void> setVolume(double v, {bool remember = true}) async {
    final value = v.clamp(0.0, 1.0);
    _userVolume = value;
    ++_fadeToken;
    await _player.setVolume(value);
    if (_other.playing) await _other.setVolume(value);
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
    unawaited(_saveState());
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
        // Место после пары, если рекомендация там ещё не стоит
        // (иначе все рекомендации вставлялись бы в одно и то же место кучкой).
        final nextIsRec = i + 1 < _queue.length && _recommended.contains(_queue[i + 1].id);
        if (!nextIsRec) spots.add(i + 1);
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
    unawaited(_saveState());
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
    _xfTimer?.cancel();
    _stateTimer?.cancel();
    _a.dispose();
    _b.dispose();
    _pos.close();
    _smoothPos.close();
    super.dispose();
  }
}


/// Полосы эквалайзера: частоты (Гц) и пределы усиления (дБ).
class EqInfo {
  const EqInfo(this.bands, this.min, this.max);
  final List<double> bands;
  final double min;
  final double max;
}
