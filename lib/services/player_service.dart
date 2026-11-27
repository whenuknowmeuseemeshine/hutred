import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import '../models/track.dart';
import 'playback_sources.dart';
import 'soundcloud_source.dart';
import 'youtube_source.dart';

enum RepeatSetting { off, all, one }

typedef _PlaybackSource = ({AudioSource audio, Track? online});

/// Очередь воспроизведения и управление плеером.
class PlayerService extends ChangeNotifier {
  /// Скачанный файл трека (раздел «Загрузки») или null.
  String? Function(Track track)? offlineAudio;

  /// true — интернета нет: играем только скачанное.
  bool Function()? isOffline;

  /// Находит, где играть трек из Spotify (SoundCloud или YouTube).
  Future<Track?> Function(Track track)? resolveSpotify;
  PlaybackSources? playbackSources;

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
        if (s.processingState == ProcessingState.completed &&
            !_loading && !_needsPlaybackRetry && !_completing) {
          _completing = true;
          _onCompleted().whenComplete(() => _completing = false);
        }
        _updateKaraokeTimer();
        notifyListeners();
      }));
      _subs.add(p.durationStream.listen((d) {
        if (p != _player || _loading || _needsPlaybackRetry) return;
        final t = current;
        if (d != null && t != null && t.durationMs == null) {
          onDurationKnown?.call(t, d);
        }
        notifyListeners();
      }));
      _subs.add(p.playbackEventStream.listen((_) {},
          onError: (Object e) => _handlePlaybackError(p, e)));
      _subs.add(p.positionStream.listen((d) {
        if (p == _player && !_loading && !_needsPlaybackRetry) {
          _publishPosition(d, updateKaraoke: _karaokeTimer == null);
        }
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
    // Очередь храним целиком (раньше — только 150 треков вперёд, и после
    // перезапуска часть медиатеки пропадала из перемешивания).
    final from = max(0, _index - 200);
    final to = min(_queue.length, _index + 3000);
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
  final _visualPos = StreamController<Duration>.broadcast();
  late final _smoothPos = StreamController<Duration>.broadcast(
    onListen: _updateKaraokeTimer,
    onCancel: _updateKaraokeTimer,
  );
  Timer? _karaokeTimer;
  bool _visualsActive = true;
  Timer? _xfTimer;
  bool _xfRunning = false;
  int _fadeToken = 0;

  /// Громкость, которую выбрал пользователь (плавности меняют её временно).
  double _userVolume = 1;
  double _lastAudibleVolume = 0.5;

  /// Плавно меняет громкость плеера. Прерывается, если началась другая плавность.
  Future<bool> _ramp(AudioPlayer p, Duration d,
      {required int token, double? fadeOutFrom}) async {
    const steps = 30;
    for (var i = 1; i <= steps; i++) {
      if (token != _fadeToken) return false;
      final k = i / steps;
      // Громкость на слух логарифмическая: квадратичная кривая звучит ровно,
      // без «провала» в конце затухания.
      final v = fadeOutFrom == null
          ? _userVolume * k * k
          : min(_userVolume, fadeOutFrom) * (1 - k) * (1 - k);
      await p.setVolume(v);
      await Future<void>.delayed(d ~/ steps);
    }
    return token == _fadeToken;
  }

  /// Новый трек при переходе: громкость растёт по синусу — быстро
  /// становится слышно начало песни, а к концу перехода выходит ровно.
  Future<bool> _fadeIn(AudioPlayer p, Duration d, int token) async {
    const steps = 30;
    for (var i = 1; i <= steps; i++) {
      if (token != _fadeToken) return false;
      await p.setVolume(_userVolume * sin(i / steps * pi / 2));
      await Future<void>.delayed(d ~/ steps);
    }
    return token == _fadeToken;
  }

  /// Глушит второй (затихающий) плеер — например, если переключили трек.
  Future<void> _killOther() async {
    final o = _other;
    if (o.playing || o.processingState != ProcessingState.idle) {
      try {
        await _silence(o);
      } catch (_) {}
    }
  }

  // На Windows переиспользуем libmpv: stop() уничтожает нативный плеер.
  Future<void> _silence(AudioPlayer p) =>
      (Platform.isWindows ? p.pause() : p.stop()).timeout(const Duration(seconds: 3));

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
    if (_shuffle && _repeat == RepeatSetting.all && _index == _queue.length - 1) return;
    final secs = crossfadeSeconds();
    if (secs <= 0 || _xfRunning || _loading || !playing) return;
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
      final candidate = _candidates(next).first;
      final resolved = await _sourceFor(next, candidate: candidate)
          .timeout(const Duration(seconds: 2));
      if (token != _loadToken || !playing) return;
      final incoming = _other;
      await incoming.setVolume(0);
      if (token != _loadToken || !playing) return;
      await incoming.setAudioSource(resolved.audio)
          .timeout(const Duration(seconds: 4));
      if (token != _loadToken || !playing) {
        return;
      }
      final outgoing = _player;
      final fadeLen = _player.duration! - _player.position;
      // Переключаемся: теперь «текущий» — новый трек.
      _player = incoming;
      _index = j;
      ++_loadToken;
      _streamRecoveryUsed = false;
      _exactSourcePlayback = false;
      _rememberOpened(next, resolved);
      _startPlayer(incoming, _loadToken);
      onStarted?.call(next);
      notifyListeners();
      if (_smart) unawaited(_ensureRecsAhead());
      if (_queue.length - _index <= 3) unawaited(_autoplayFill());
      _prefetchNext();
      final low = onQueueLow;
      if (low != null && _queue.length - _index <= 6) unawaited(low());
      // Старый трек не трогаем: он доигрывает до самого конца на своей
      // громкости, а новый мягко вступает поверх него. Раньше конец
      // старого трека заглушался, и казалось, что у песни отрезали кусок.
      final t = ++_fadeToken;
      await Future.wait([
        _fadeIn(incoming, fadeLen, t),
        outgoing.processingStateStream
            .firstWhere((s) => s == ProcessingState.completed || s == ProcessingState.idle)
            .timeout(fadeLen + const Duration(seconds: 3), onTimeout: () => ProcessingState.idle),
      ]);
      if (t != _fadeToken) return;
      await _silence(outgoing);
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
  bool _needsPlaybackRetry = false;
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
  bool get canRetry => _needsPlaybackRetry && !_loading;
  /// Кнопки сразу показывают паузу/игру, не дожидаясь конца затухания.
  bool get playing => !_needsPlaybackRetry && (_intent ?? _player.playing);
  bool? _intent;
  double get volume => _userVolume;
  Duration get position => _resumeAt ?? (_loading ? Duration.zero : _player.position);
  Duration? get duration => _loading || _needsPlaybackRetry
      ? current?.duration
      : _player.duration ?? current?.duration;

  Stream<Duration> get positionStream => _pos.stream;
  Stream<Duration> get visualPositionStream => _visualPos.stream;

  /// Частый поток позиции — для плавной заливки караоке.
  Stream<Duration> get smoothPositionStream => _smoothPos.stream;

  void setVisualsActive(bool active) {
    if (_disposed || _visualsActive == active) return;
    _visualsActive = active;
    _updateKaraokeTimer();
    if (active) _publishVisualPosition(position);
  }

  void _updateKaraokeTimer() {
    if (_disposed || !_visualsActive || !_smoothPos.hasListener || _loading ||
        !playing || _player.processingState != ProcessingState.ready) {
      _karaokeTimer?.cancel();
      _karaokeTimer = null;
      return;
    }
    final interval = Duration(
      microseconds: ((duration?.inMicroseconds ?? 0) ~/ 4000).clamp(16000, 50000),
    );
    _karaokeTimer ??= Timer.periodic(interval, (_) {
      _smoothPos.add(position);
    });
  }

  void _publishVisualPosition(Duration value, {bool updateKaraoke = true}) {
    if (!_visualsActive) return;
    _visualPos.add(value);
    if (updateKaraoke && _smoothPos.hasListener) _smoothPos.add(value);
  }

  void _publishPosition(Duration value, {bool updateKaraoke = true}) {
    _pos.add(value);
    _publishVisualPosition(value, updateKaraoke: updateKaraoke);
  }

  // ---------- Запуск ----------

  Future<void> playTrackFromList(List<Track> tracks, {
    int start = 0,
    bool exactSource = false,
  }) async {
    if (tracks.isEmpty) return;
    final target = tracks[start.clamp(0, tracks.length - 1)];
    final active = current;
    if (active?.id == target.id && active?.source == target.source &&
        active?.uri == target.uri && _exactSourcePlayback == exactSource) {
      return playCurrent();
    }
    await playTracks(tracks, start: start, exactSource: exactSource);
  }

  Future<void> playTracks(List<Track> tracks, {
    int start = 0,
    bool exactSource = false,
  }) async {
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
    final load = _loadCurrent(exactSource: exactSource);
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
    return all || _shuffle ? playAll(list) : playTracks(list);
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

  Future<void> _loadCurrent({
    bool autoplay = true,
    bool exactSource = false,
    Track? resumeWith,
    bool skipOffline = false,
    bool autoSkipOnFailure = true,
  }) async {
    var t = current;
    if (t == null) return;
    if (autoplay && resumeWith == null) _noteRecent(t);
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
    if (resumeWith == null && blocked != null &&
        t.id != _allowId && blocked(t)) {
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
    final explicitlySelected = _allowId == t.id;
    _allowId = null;
    if (resumeWith == null) {
      _streamRecoveryUsed = false;
      _exactSourcePlayback = exactSource;
    }
    final token = ++_loadToken;
    _loading = true;
    _needsPlaybackRetry = false;
    _intent = null;
    _playedFromFile = false;
    _playingSource = null;
    _pauseRequested = false;
    _error = null;
    _updateKaraokeTimer();
    _publishPosition(position);
    notifyListeners();
    // Сразу глушим прошлый трек: если новый не загрузится,
    // старый не должен продолжать играть.
    ++_fadeToken;
    final p = _player;
    try {
      await _killOther();
      if (token != _loadToken) return;
      await _silence(p);
      if (token != _loadToken) return;
      await p.setVolume(_userVolume);
    } catch (_) {}
    if (token != _loadToken) return;
    final elapsed = Stopwatch()..start();
    var stage = 'source';
    final selected = t;
    final candidates = resumeWith != null
        ? [resumeWith]
        : exactSource ? [selected] : _candidates(selected);
    final hasFallback = candidates.length > 1;
    final retryOnline = resumeWith != null || skipOffline;

    Future<bool> open(Track candidate, {required bool first}) async {
      stage = 'source';
      elapsed.reset();
      final budget = resumeWith != null
          ? const Duration(seconds: 30)
          : hasFallback
              ? Duration(seconds: first ? 8 : 12)
              : const Duration(minutes: 2);
      var resolved = await _sourceFor(
        selected,
        candidate: candidate,
        skipOffline: retryOnline || !first,
        completeYoutube: resumeWith != null,
      ).timeout(budget, onTimeout: () {
        throw Exception('источник не ответил за ${budget.inSeconds} с');
      });
      if (token != _loadToken) return false;
      try {
        debugPrint('[Playback] ${(resolved.online ?? candidate).source.name} '
            'source ready in ${elapsed.elapsedMilliseconds} ms (${resolved.audio.runtimeType})');
        stage = 'open';
        elapsed.reset();
        if (eqSupported && _eqOn) unawaited(_applyEq());
        await p.setAudioSource(resolved.audio).timeout(
          hasFallback && first
              ? const Duration(seconds: 5)
              : const Duration(seconds: 12),
          onTimeout: () => throw Exception('плеер не смог открыть поток'),
        );
      } catch (_) {
        final source = resolved.online;
        if (token != _loadToken) return false;
        if (source?.source == TrackSource.youtube && resolved.audio is GrowingFileAudioSource &&
            !(hasFallback && first)) {
          final file = await youtube.cachedAudio(source!.uri).timeout(const Duration(minutes: 2));
          if (token != _loadToken) return false;
          resolved = (audio: AudioSource.file(file.path), online: source);
          await p.setAudioSource(resolved.audio).timeout(const Duration(seconds: 12));
        } else {
          if (source != null) playbackSources?.failed(selected, source);
          rethrow;
        }
      }
      if (token != _loadToken) return false;
      _rememberOpened(selected, resolved);
      debugPrint('[Playback] player opened source in ${elapsed.elapsedMilliseconds} ms');
      return true;
    }

    try {
      try {
        if (!await open(candidates.first, first: true)) return;
      } on PlayerInterruptedException {
        rethrow;
      } catch (_) {
        if (token != _loadToken || !hasFallback) rethrow;
        playbackSources?.failed(selected, candidates.first);
        debugPrint('[Playback] trying another source after $stage failed');
        if (stage == 'open') {
          try {
            await p.stop().timeout(const Duration(seconds: 3));
          } catch (_) {}
        }
        if (token != _loadToken || !await open(candidates[1], first: false)) return;
      }
      stage = 'resume';
      final resume = _resumeAt;
      if (resume != null) {
        await p.seek(resume);
      }
      // Пока грузилось, нажали паузу — не включаем.
      if (token != _loadToken) return;
      _resumeAt = null;
      _publishPosition(p.position);
      final knownDuration = p.duration;
      if (knownDuration != null && t.durationMs == null) {
        onDurationKnown?.call(t, knownDuration);
      }
      if (autoplay && !_pauseRequested) _startPlayer(p, token);
      _failedInRow = 0;
      if (resumeWith == null) onStarted?.call(t);
      // Умное перемешивание: держим рекомендации на несколько треков вперёд.
      if (_smart) unawaited(_ensureRecsAhead());
      // Подходит конец очереди — заранее подбираем похожее.
      if (_queue.length - _index <= 3) unawaited(_autoplayFill());
      _prefetchNext();
      final low = onQueueLow;
      if (low != null && _queue.length - _index <= 6) unawaited(low());
    } on PlayerInterruptedException {
      // Загрузку прервал следующий трек — это нормально.
    } catch (e) {
      if (token == _loadToken) {
        debugPrint('[Playback] ${t.source.name} $stage failed after '
            '${elapsed.elapsedMilliseconds} ms (${e.runtimeType})');
        _stopWithError(p, _resumeAt ?? Duration.zero,
            'Не удалось включить «${t.title}»: ${_shortError(e)}');
        _failedInRow++;
        // Как в Spotify: недоступный трек пропускаем и играем следующий.
        // Если поставили на паузу — остаёмся на этом треке.
        if (autoplay &&
            autoSkipOnFailure &&
            !explicitlySelected &&
            resumeWith == null &&
            !_pauseRequested &&
            _index + 1 < _queue.length &&
            _failedInRow < _queue.length) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (token == _loadToken && canRetry && !_pauseRequested) next(userSkip: false);
          });
        }
      }
    } finally {
      if (token == _loadToken) {
        _loading = false;
        _updateKaraokeTimer();
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
    final firstLine = text.split('\n').first.replaceFirst('Exception: ', '');
    return firstLine.length > 160 ? '${firstLine.substring(0, 160)}…' : firstLine;
  }

  List<Track> _candidates(Track track) {
    final candidates = playbackSources?.candidates(
      track,
      youtubeAllowed: youtubeAllowed(),
    ) ?? [track];
    final available = candidates.where((source) =>
        source.source != TrackSource.youtube || !youtube.isUnavailable(source.uri));
    return available.isEmpty ? [track] : available.toList();
  }

  bool _streamRecoveryUsed = false;
  bool _exactSourcePlayback = false;

  void _startPlayer(AudioPlayer p, int token) {
    unawaited(p.play().catchError((Object e) {
      if (token == _loadToken) _handlePlaybackError(p, e);
    }));
  }

  void _handlePlaybackError(AudioPlayer p, Object e) {
    if (_disposed || p != _player || _loading || _needsPlaybackRetry) return;
    final track = current;
    if (track == null) return;
    final source = _playingSource;
    final at = p.position;
    if (source != null) {
      playbackSources?.failed(track, source);
      if (_recoverStream(track, source, at, playing: playing)) return;
    }
    if (_playedFromFile && _fileRetryFor != track.id) {
      _fileRetryFor = track.id;
      final token = _loadToken;
      unawaited(() async {
        try {
          await forgetFile?.call(track);
        } catch (e) {
          debugPrint('[Playback] could not remove invalid copy (${e.runtimeType})');
        }
        if (token != _loadToken || _needsPlaybackRetry) return;
        _resumeAt = at;
        await _loadCurrent(exactSource: _exactSourcePlayback, skipOffline: true);
      }());
      return;
    }
    _stopWithError(p, at, 'Ошибка воспроизведения: ${_shortError(e)}');
  }

  void _stopWithError(AudioPlayer p, Duration at, String message) {
    ++_fadeToken;
    _needsPlaybackRetry = true;
    _resumeAt = at;
    _error = message;
    _updateKaraokeTimer();
    _publishPosition(at);
    unawaited(p.pause().catchError((Object e) {
      debugPrint('[Playback] could not pause after failure (${e.runtimeType})');
    }));
    notifyListeners();
    unawaited(_saveState());
  }

  bool _recoverStream(Track track, Track source, Duration position,
      {required bool playing}) {
    if (_streamRecoveryUsed || !playing || isOffline?.call() == true) {
      return false;
    }
    final alternatives = _exactSourcePlayback ? <Track>[] : _candidates(track);
    final alternate = alternatives.where((candidate) =>
        candidate.source != TrackSource.spotify &&
        candidate.source != TrackSource.local &&
        (candidate.source != source.source || candidate.uri != source.uri)).firstOrNull;
    final retrySource = source.source == TrackSource.youtube &&
            _playingGrowingYoutube
        ? source : alternate;
    if (retrySource == null) return false;
    _streamRecoveryUsed = true;
    _resumeAt = position;
    debugPrint('[Playback] resuming after ${source.source.name} stopped '
        'at ${position.inMilliseconds} ms using ${retrySource.source.name}');
    unawaited(_loadCurrent(resumeWith: retrySource));
    return true;
  }

  bool _prefetching = false;
  bool _disposed = false;

  /// Готовим только один следующий трек из очереди.
  void _prefetchNext() {
    if (_prefetching || _disposed || isOffline?.call() == true) return;
    final index = _autoNextIndex();
    if (index == null || index == _index) return;
    final next = _queue[index];
    if (offlineAudio?.call(next) != null) return;

    _prefetching = true;
    final token = _loadToken;
    unawaited(() async {
      try {
        final candidate = _candidates(next).first;
        final track = candidate.source == TrackSource.spotify
            ? await resolveSpotify?.call(candidate)
            : candidate;
        if (_disposed || token != _loadToken || track == null) return;
        if (track.source == TrackSource.youtube) {
          await youtube.cachedAudio(track.uri);
        } else if (track.source == TrackSource.soundcloud) {
          await soundcloud.cachedAudio(track.uri);
        }
      } catch (_) {
        // Ошибка предзагрузки не прерывает текущий трек.
      } finally {
        _prefetching = false;
        if (token != _loadToken && !_loading) _prefetchNext();
      }
    }());
  }

  /// Трек сейчас играет из файла (скачанный, свой, из облака).
  bool _playedFromFile = false;
  bool _playingGrowingYoutube = false;
  Track? _playingSource;

  /// Для этого трека файл уже пересоздавали — второй раз не пробуем.
  String? _fileRetryFor;

  /// Убрать скачанную/облачную копию трека (она не играет).
  Future<void> Function(Track t)? forgetFile;

  /// Такой же трек на SoundCloud/YouTube — для своих файлов, которые не играют.
  Future<Track?> Function(Track t)? findOnline;

  static const _iosUnplayable = {'ogg', 'opus', 'oga', 'webm', 'weba', 'wma', 'ape', 'mka'};

  void _rememberOpened(Track track, _PlaybackSource resolved) {
    final audio = resolved.audio;
    final source = resolved.online;
    _playingSource = source;
    _playingGrowingYoutube = audio is GrowingFileAudioSource;
    _playedFromFile = source == null && audio is UriAudioSource &&
        audio.uri.scheme == 'file';
    if (source != null) playbackSources?.opened(track, source);
  }

  Future<_PlaybackSource> _sourceFor(
    Track track, {
    required Track candidate,
    bool skipOffline = false,
    bool completeYoutube = false,
  }) async {
    Track? online;
    final audio = await _sourceForInner(
      track,
      candidate: candidate,
      skipOffline: skipOffline,
      completeYoutube: completeYoutube,
      onOnline: (source) => online = source,
      token: _loadToken,
    );
    return (audio: audio, online: online);
  }

  Future<AudioSource> _sourceForInner(
    Track t, {
    required Track candidate,
    required bool skipOffline,
    required bool completeYoutube,
    required void Function(Track) onOnline,
    required int token,
  }) async {
    if (token != _loadToken) throw PlayerInterruptedException('Трек переключён');
    Future<AudioSource> follow(Track found) => _sourceForInner(
          found,
          candidate: found,
          skipOffline: true,
          completeYoutube: completeYoutube,
          onOnline: onOnline,
          token: token,
        );
    final online = skipOffline;
    if (online && t.source == TrackSource.local) {
      final found = await findOnline?.call(t).catchError((_) => null);
      if (found != null && found.source != TrackSource.local) return follow(found);
    }
    final downloaded = online ? null : offlineAudio?.call(t);
    if (downloaded != null && !_unplayableHere(downloaded)) return AudioSource.file(downloaded);
    if (isOffline?.call() == true &&
        !(t.source == TrackSource.local && File(t.uri).existsSync())) {
      throw Exception('нет интернета, а трек не скачан');
    }
    if (candidate.source != t.source || candidate.uri != t.uri) {
      return follow(candidate);
    }
    switch (t.source) {
      case TrackSource.local:
        if (File(t.uri).existsSync()) return AudioSource.file(t.uri);
        // Файла на этом устройстве нет — берём копию из облака.
        final fromCloud = await cloudFile?.call(t);
        if (token != _loadToken) throw PlayerInterruptedException('Трек переключён');
        if (fromCloud != null && !_unplayableHere(fromCloud)) return AudioSource.file(fromCloud);
        if (fromCloud != null) {
          // Формат, который iPhone не играет — ищем такой же трек онлайн.
          final found = await findOnline?.call(t).catchError((_) => null);
          if (found != null && found.source != TrackSource.local) return follow(found);
          throw Exception('iPhone не играет файлы .${fromCloud.split('.').last}, '
              'а онлайн этот трек не нашёлся');
        }
        if (t.cloudPath == null) onMissingFile?.call(t);
        throw Exception(t.cloudPath == null
            ? 'файл не найден: ${t.uri}'
            : 'не удалось скачать файл из облака');
      case TrackSource.url:
        onOnline(t);
        return AudioSource.uri(Uri.parse(t.uri));
      case TrackSource.youtube:
        onOnline(t);
        // При восстановлении оборванного потока дожидаемся готового файла.
        if (completeYoutube) {
          return AudioSource.file((await youtube.cachedAudio(t.uri)).path);
        }
        return await youtube.playableSource(t.uri);
      case TrackSource.soundcloud:
        onOnline(t);
        return AudioSource.file((await soundcloud.cachedAudio(t.uri)).path);
      case TrackSource.spotify:
        // Spotify звук не отдаёт: играем тот же трек с SoundCloud/YouTube.
        final elapsed = Stopwatch()..start();
        final found = await resolveSpotify?.call(t);
        debugPrint('[Playback] spotify matched ${found?.source.name ?? 'nothing'} '
            'after ${elapsed.elapsedMilliseconds} ms');
        if (found == null || found.source == TrackSource.spotify) {
          throw Exception(youtubeAllowed()
              ? 'не нашёл этот трек на SoundCloud и YouTube'
              : 'нет на SoundCloud. Можно включить YouTube: Настройки → Сеть и YouTube');
        }
        try {
          return await follow(found);
        } catch (_) {
          if (token != _loadToken ||
              found.source != TrackSource.youtube ||
              !youtube.isUnavailable(found.uri)) {
            rethrow;
          }
          final alternate = await resolveSpotify?.call(t);
          if (token != _loadToken ||
              alternate == null ||
              alternate.source == TrackSource.spotify ||
              (alternate.source == found.source && alternate.uri == found.uri)) {
            rethrow;
          }
          return follow(alternate);
        }
    }
  }

  static bool _unplayableHere(String path) {
    if (!Platform.isIOS && !Platform.isMacOS) return false;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot < path.lastIndexOf(Platform.pathSeparator)) return false;
    return _iosUnplayable.contains(path.substring(dot + 1).toLowerCase());
  }

  // ---------- Управление ----------

  /// В джеме у гостя: кнопки управления уходят хозяину джема.
  /// Возвращает true, если команда отправлена и здесь ничего делать не нужно.
  Future<bool> Function(String cmd, {int? ms, Track? track})? remoteControl;

  Future<void> playCurrent() async {
    if (current == null || _loading || playing) return;
    final remote = remoteControl;
    if (remote != null && await remote('toggle')) return;
    if (current == null || _loading || playing) return;
    await _resumeCurrent();
  }

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
      await _resumeCurrent();
    }
  }

  Future<void> _resumeCurrent() async {
    if (canRetry) return retry();
    final p = _player;
    final token = _loadToken;
    if (p.processingState == ProcessingState.completed) {
      await p.seek(Duration.zero);
    }
    if (token != _loadToken) return;
    if (p.processingState == ProcessingState.idle) {
      await _loadCurrent(exactSource: _exactSourcePlayback);
    } else {
      await resume();
    }
  }

  Future<void> retry() async {
    final track = current;
    if (!canRetry || track == null) return;
    _allowId = track.id;
    await _loadCurrent(exactSource: _exactSourcePlayback, autoSkipOnFailure: false);
  }

  /// Пауза: как в Spotify, звук не обрывается, а быстро затихает.
  Future<void> pause() async {
    if (!playing) return;
    final loadToken = _loadToken;
    final t = ++_fadeToken;
    _intent = false;
    notifyListeners();
    await _killOther();
    if (loadToken != _loadToken || t != _fadeToken) return;
    final p = _player;
    if (fadeOnPause()) {
      final done = await _ramp(p, const Duration(milliseconds: 500),
          token: t, fadeOutFrom: p.volume);
      if (!done) return; // Пока затихало, снова нажали «играть».
    }
    await p.pause();
    if (loadToken != _loadToken || t != _fadeToken) return;
    await p.setVolume(_userVolume);
    if (loadToken != _loadToken || t != _fadeToken) return;
    _intent = null;
    notifyListeners();
    unawaited(_saveState());
  }

  /// Продолжить: звук плавно нарастает.
  Future<void> resume() async {
    if (canRetry) return retry();
    final p = _player;
    final loadToken = _loadToken;
    final t = ++_fadeToken;
    _intent = true;
    notifyListeners();
    if (fadeOnPause()) {
      await p.setVolume(0);
      if (loadToken != _loadToken || t != _fadeToken) return;
      _startPlayer(p, loadToken);
      await _ramp(p, const Duration(milliseconds: 300), token: t);
    } else {
      await p.setVolume(_userVolume);
      if (loadToken != _loadToken || t != _fadeToken) return;
      _startPlayer(p, loadToken);
    }
    if (loadToken != _loadToken || t != _fadeToken) return;
    _intent = null;
    notifyListeners();
  }

  void Function(Track)? onEarlySkip;

  Future<void> next({bool userSkip = true}) async {
    if (await remoteControl?.call('next') ?? false) return;
    final skipped = current;
    if (userSkip && skipped != null && !canRetry && position < const Duration(seconds: 30)) {
      onEarlySkip?.call(skipped);
    }
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
      if (_shuffle && _queue.length > 1) {
        _shuffleRest();
        final previous = _queue.removeAt(0);
        _queue.insert(1 + _rand.nextInt(_queue.length), previous);
      }
      _index = 0;
    } else if (await _autoplayFill()) {
      // Как в Spotify: плейлист кончился — играем похожее.
      _index++;
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
      _startPlayer(_player, _loadToken);
    } else {
      await next(userSkip: false);
    }
  }

  Future<void> seek(Duration d) async {
    if (await remoteControl?.call('seek', ms: d.inMilliseconds) ?? false) return;
    await syncSeek(d);
  }

  /// Перемотка без отправки хозяину джема (сама подстройка под него).
  Future<void> syncSeek(Duration d) async {
    // Трек после перезапуска ещё не загружен — просто запоминаем новое место.
    if (_loading || _needsPlaybackRetry ||
        (_resumeAt != null && _player.processingState == ProcessingState.idle)) {
      _resumeAt = d;
      _publishPosition(d);
      notifyListeners();
      return;
    }
    await _player.seek(d);
  }

  Future<void> toggleMute() => volume == 0
      ? setVolume(_lastAudibleVolume)
      : setVolume(0, remember: false);

  Future<void> setVolume(double v, {bool remember = true}) async {
    final value = v.clamp(0.0, 1.0);
    _userVolume = value;
    if (value > 0) _lastAudibleVolume = value;
    final volumeUpdates = [
      _player.setVolume(value),
      if (_other.playing) _other.setVolume(value),
    ];
    if (remember) onVolumeChanged?.call(value);
    notifyListeners();
    await Future.wait(volumeUpdates);
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

  /// Можно ли после конца плейлиста включать похожие треки (настройка).
  bool Function() autoplayAllowed = () => true;

  /// Сейчас играет «Моя волна» — она докладывает треки сама.
  bool Function()? isWaveQueue;

  Future<bool>? _autoplayRun;

  /// Очередь кончается — добавляем в конец похожие треки (рекомендации).
  /// true — что-то добавили.
  Future<bool> _autoplayFill() => _autoplayRun ??= () async {
        try {
          return await _autoplayFillNow();
        } finally {
          _autoplayRun = null;
        }
      }();

  Future<bool> _autoplayFillNow() async {
    final rec = recommend;
    if (rec == null || _queue.isEmpty || !autoplayAllowed()) return false;
    if (_repeat != RepeatSetting.off) return false;
    if (isWaveQueue?.call() == true) return false;
    if (_queue.length - _index > 3) return false;
    try {
      // Похожее — по последним своим трекам очереди.
      final own = _queue.reversed.where((t) => !_recommended.contains(t.id)).take(12).toList()
        ..shuffle(_rand);
      final seeds = own.isEmpty ? _queue.reversed.take(5).toList() : own.take(5).toList();
      final found = await rec(seeds, 20).timeout(const Duration(seconds: 20));
      final known = {for (final t in _queue) '${t.source.name}:${t.uri}'};
      final artists = <String, int>{};
      final fresh = <Track>[];
      for (final t in found) {
        if (!known.add('${t.source.name}:${t.uri}')) continue;
        if (isBlocked?.call(t) == true || isDuplicate?.call(t) == true) continue;
        // Не больше двух треков одного исполнителя в пачке.
        final k = _artistKey(t);
        if ((artists[k] = (artists[k] ?? 0) + 1) > 2) continue;
        fresh.add(t);
      }
      if (fresh.isEmpty) return false;
      _queue.addAll(fresh);
      _unshuffled.addAll(fresh);
      _recommended.addAll(fresh.map((t) => t.id));
      notifyListeners();
      unawaited(_saveState());
      return true;
    } catch (e) {
      debugPrint('[Похожее после плейлиста] $e');
      return false;
    }
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
    if (tracks.length < 2) return tracks;
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

  /// Убрать из очереди всё, что после текущего трека.
  void clearUpcoming() {
    if (_index + 1 >= _queue.length) return;
    final gone = _queue.sublist(_index + 1).map((t) => t.id).toSet();
    _queue.removeRange(_index + 1, _queue.length);
    _unshuffled.removeWhere((t) => gone.contains(t.id));
    notifyListeners();
    unawaited(_saveState());
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
    _disposed = true;
    ++_loadToken;
    ++_fadeToken;
    for (final s in _subs) {
      s.cancel();
    }
    _xfTimer?.cancel();
    _stateTimer?.cancel();
    _karaokeTimer?.cancel();
    _a.dispose();
    _b.dispose();
    _pos.close();
    _visualPos.close();
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
