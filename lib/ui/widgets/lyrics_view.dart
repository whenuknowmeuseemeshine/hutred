import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/account_service.dart';
import '../../services/ai_sync_service.dart';
import '../../services/library_store.dart';
import '../../services/lyrics_service.dart';
import '../../services/player_service.dart';
import '../../services/settings_store.dart';
import '../../services/soundcloud_source.dart';
import '../../services/youtube_source.dart';
import '../actions.dart';

/// Панель текста: находит текст для трека и показывает его в режиме караоке.
class LyricsPanel extends StatefulWidget {
  const LyricsPanel({super.key, required this.track});
  final Track track;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

/// Тексты, найденные для треков вне медиатеки (например, из поиска YouTube).
final Map<String, LyricsResult?> _sessionLyrics = {};
final Set<String> _upgradeTried = {};
final Map<String, int> _sessionOffsets = {};

class _LyricsPanelState extends State<LyricsPanel> {
  bool _loading = false;
  String _loadingText = 'Ищу текст…';
  String? _error;
  String? _lastTrackId;

  String? _parsedRaw;
  Lyrics? _parsed;

  @override
  void initState() {
    super.initState();
    _maybeFetch();
  }

  Lyrics? _lyricsFor(String? raw) {
    if (raw == null) return null;
    if (raw != _parsedRaw) {
      _parsedRaw = raw;
      _parsed = Lyrics.parse(raw);
    }
    return _parsed;
  }

  @override
  void didUpdateWidget(LyricsPanel old) {
    super.didUpdateWidget(old);
    if (old.track.id != widget.track.id) _maybeFetch();
  }

  String? _rawLyrics() {
    final stored = context.read<LibraryStore>().byId(widget.track.id);
    return stored?.lyrics ??
        widget.track.lyrics ??
        _sessionLyrics[widget.track.id]?.text;
  }

  LyricsOrigin? _origin() {
    final stored = context.read<LibraryStore>().byId(widget.track.id);
    return LyricsOrigin.byName(stored?.lyricsSource ?? widget.track.lyricsSource) ??
        _sessionLyrics[widget.track.id]?.origin;
  }

  void _maybeFetch({bool force = false, LyricsOrigin? only}) {
    final id = widget.track.id;
    if (!force && _lastTrackId == id) return;
    _lastTrackId = id;
    _error = null;
    if (!force &&
        (_rawLyrics() != null || _sessionLyrics.containsKey(id))) {
      _maybeUpgrade(id);
      return;
    }
    // Запуск после кадра: из initState/didUpdateWidget нельзя вызывать setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.track.id == id) _fetch(only: only);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Если сохранён текст без таймингов, один раз за запуск тихо
  /// пробуем найти версию с таймингами.
  void _maybeUpgrade(String id) {
    final raw = _rawLyrics();
    if (raw == null || _origin() == LyricsOrigin.custom) return;
    if (Lyrics.parse(raw).synced || !_upgradeTried.add(id)) return;
    final track = widget.track;
    final settings = context.read<SettingsStore>();
    final service = context.read<LyricsService>();
    () async {
      try {
        final found = await service.find(track,
            useYoutube: settings.youtubeLyrics, useGenius: false);
        if (!mounted || widget.track.id != id || found == null) return;
        if (Lyrics.parse(found.text).synced) _save(found);
      } catch (_) {}
    }();
  }

  Future<void> _fetch({LyricsOrigin? only}) async {
    final track = widget.track;
    final settings = context.read<SettingsStore>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final found = await context.read<LyricsService>().find(
            track,
            useYoutube: settings.youtubeLyrics,
            useGenius: settings.geniusLyrics,
            only: only,
          );
      if (!mounted || widget.track.id != track.id) return;
      if (found == null && only != null && _rawLyrics() != null) {
        // Поиск в конкретном источнике не удался — старый текст не трогаем.
        AppActions.toast(context, '${only.label}: текст не найден');
        return;
      }
      _save(found);
      if (found != null && only != null) {
        AppActions.toast(context, 'Текст взят из: ${found.origin.label}');
      }
    } catch (e) {
      if (mounted && widget.track.id == track.id) {
        _error = 'Не получилось загрузить текст. Проверь интернет.';
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _save(LyricsResult? lyrics, {bool manual = false}) {
    _sessionLyrics[widget.track.id] = lyrics;
    final store = context.read<LibraryStore>();
    final stored = store.byId(widget.track.id);
    if (stored != null) {
      final updated = stored.copyWith(
          lyrics: lyrics?.text, lyricsSource: lyrics?.origin.name);
      // Ручные правки админа уходят всем (см. TrackFixes).
      store.updateTrack(updated, manual: manual);
      context.read<PlayerService>().refreshTrack(updated);
    }
    setState(() {});
  }

  Future<void> _editLyrics() async {
    final ctrl = TextEditingController(text: _rawLyrics() ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Свой текст'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: ctrl,
            maxLines: 14,
            minLines: 8,
            decoration: const InputDecoration(
              hintText: '[00:12.30] Первая строка\n[00:15.80] Вторая строка\n\n'
                  'Можно вставить и обычный текст без таймингов.',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(d, ctrl.text),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (result == null || !mounted) return;
    _save(
        result.trim().isEmpty ? null : LyricsResult(result, LyricsOrigin.custom),
        manual: true);
  }

  // ---------- Сдвиг текста ----------

  int _offsetMs() {
    final stored = context.read<LibraryStore>().byId(widget.track.id);
    return stored?.lyricsOffsetMs ?? _sessionOffsets[widget.track.id] ?? 0;
  }

  void _setOffset(int ms) {
    _sessionOffsets[widget.track.id] = ms;
    final store = context.read<LibraryStore>();
    final stored = store.byId(widget.track.id);
    if (stored != null) {
      store.updateTrack(stored.copyWith(lyricsOffsetMs: ms), manual: true);
    }
    setState(() {});
  }

  Future<void> _shiftSheet() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) {
          final ms = _offsetMs();
          void change(int delta) {
            _setOffset(ms + delta);
            setSheet(() {});
          }

          final label = ms == 0
              ? 'Без сдвига'
              : '${ms > 0 ? 'Текст раньше' : 'Текст позже'} на ${(ms.abs() / 1000).toStringAsFixed(1)} с';
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text(
                    'Если строки загораются позже, чем поют, жми «Раньше».',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton(
                          onPressed: () => change(-1000),
                          child: const Text('Позже 1 с')),
                      OutlinedButton(
                          onPressed: () => change(-200),
                          child: const Text('Позже 0,2 с')),
                      FilledButton.tonal(
                          onPressed: () => change(-ms),
                          child: const Text('Сброс')),
                      OutlinedButton(
                          onPressed: () => change(200),
                          child: const Text('Раньше 0,2 с')),
                      OutlinedButton(
                          onPressed: () => change(1000),
                          child: const Text('Раньше 1 с')),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------- ИИ ----------

  Future<File?> _audioFile(Track t) async {
    switch (t.source) {
      case TrackSource.local:
        return File(t.uri);
      case TrackSource.youtube:
        return context.read<YoutubeSource>().cachedAudio(t.uri);
      case TrackSource.soundcloud:
        return context.read<SoundcloudSource>().cachedAudio(t.uri);
      case TrackSource.url:
      case TrackSource.spotify:
        return null;
    }
  }

  /// ИИ слушает трек и расставляет строкам тайминги.
  /// Если текста нет совсем — делает его из распознанных слов.
  Future<void> _aiSync() async {
    final settings = context.read<SettingsStore>();
    if (!settings.hasAi) {
      AppActions.toast(
          context,
          context.read<AccountService>().isAdmin
              ? 'Сначала добавь ключ ИИ: Настройки → ИИ для текстов'
              : 'ИИ пока не настроен админом');
      return;
    }
    final track = widget.track;
    final ai = context.read<AiSyncService>();
    final raw = _rawLyrics();
    setState(() {
      _loading = true;
      _loadingText = 'ИИ слушает трек… Это займёт до минуты';
      _error = null;
    });
    try {
      final file = await _audioFile(track);
      if (file == null) {
        throw Exception('ИИ работает только с файлами, YouTube и SoundCloud');
      }

      // 1. Опорный текст с таймингами (NetEase, LRCLIB, субтитры YouTube).
      //    С ним ИИ нужно найти только общий сдвиг — это намного точнее.
      var reference = raw == null ? null : Lyrics.parse(raw);
      if (reference == null || !reference.synced) {
        setState(() => _loadingText = 'Ищу текст с таймингами…');
        final synced = await context.read<LyricsService>().find(track,
            useYoutube: settings.youtubeLyrics, useGenius: false);
        if (synced != null && Lyrics.parse(synced.text).synced) {
          reference = Lyrics.parse(synced.text);
        }
      }
      if (!mounted) return;
      setState(() => _loadingText = 'ИИ слушает трек… Это займёт до минуты');

      // 2. Распознавание с подсказкой: ИИ знает, какие слова ждать.
      final words = await ai.transcribe(
        audio: file,
        baseUrl: settings.aiBaseUrl,
        apiKey: settings.aiKey,
        model: settings.aiModel,
        prompt: reference == null || reference.isEmpty
            ? null
            : AiSyncService.promptFrom(reference),
        language: reference == null ? null : AiSyncService.languageOf(reference),
      );

      // 3. Подгонка.
      String lrc;
      String message;
      final fit = reference == null ? null : AiSyncService.fitTimings(reference, words);
      if (fit != null) {
        lrc = fit.lrc;
        final ms = fit.shift.inMilliseconds;
        message = ms.abs() < 150
            ? 'Тайминги совпадают с треком, сдвиг не нужен'
            : 'Текст сдвинут ${ms > 0 ? 'позже' : 'раньше'} на ${(ms.abs() / 1000).toStringAsFixed(1)} с';
      } else if (reference != null && !reference.isEmpty) {
        lrc = AiSyncService.align(reference, words);
        message = 'Строки расставлены по распознанным словам';
      } else {
        lrc = AiSyncService.transcriptToLrc(words);
        message = 'Текста не было — сделал его из распознанных слов';
      }
      if (!mounted || widget.track.id != track.id) return;
      _save(LyricsResult(lrc, LyricsOrigin.ai), manual: true);
      _setOffset(0);
      AppActions.toast(context, message);
    } catch (e) {
      if (mounted) {
        AppActions.toast(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingText = 'Ищу текст…';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LibraryStore>();
    final raw = _rawLyrics();
    final lyrics = _lyricsFor(raw);
    final player = context.read<PlayerService>();

    Widget body;
    if (_loading) {
      body = _Message(
        icon: Icons.lyrics_outlined,
        text: _loadingText,
        child: const SizedBox(
            width: 120, child: LinearProgressIndicator(minHeight: 2)),
      );
    } else if (lyrics == null || lyrics.isEmpty) {
      body = _Message(
        icon: Icons.lyrics_outlined,
        text: _error ?? 'Текст для этого трека не нашёлся',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => _maybeFetch(force: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Искать текст'),
            ),
            FilledButton.tonalIcon(
              onPressed: _editLyrics,
              icon: const Icon(Icons.edit_note),
              label: const Text('Вставить свой'),
            ),
            if (context.watch<AccountService>().aiAllowed)
              FilledButton.tonalIcon(
                onPressed: _aiSync,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Распознать ИИ'),
              ),
          ],
        ),
      );
    } else {
      body = KaraokeView(
        key: ValueKey(widget.track.id),
        lyrics: lyrics,
        sourceLabel: _origin()?.label,
        offset: Duration(milliseconds: _offsetMs()),
        position: player.smoothPositionStream,
        initialPosition: player.position,
        onSeek: (d) {
          player.seek(d);
          if (!player.playing) player.togglePlay();
        },
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: body),
        if (lyrics != null && lyrics.synced && !_loading && _origin() != null)
          Positioned(
            top: 14,
            left: 24,
            child: Text(
              'Текст: ${_origin()!.label}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        if (lyrics != null && !_loading)
          Positioned(
            top: 4,
            right: 4,
            // Четыре понятные кнопки вместо длинного меню.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (context.watch<AccountService>().aiAllowed)
                  _ToolButton(
                    icon: Icons.auto_awesome,
                    tooltip: 'Подогнать под трек с помощью ИИ',
                    onPressed: _aiSync,
                  ),
                _ToolButton(
                  icon: Icons.swap_vert,
                  tooltip: 'Сдвинуть текст раньше или позже',
                  onPressed: _shiftSheet,
                ),
                _ToolButton(
                  icon: Icons.refresh,
                  tooltip: 'Найти текст заново (везде)',
                  onPressed: () => _maybeFetch(force: true),
                ),
                _ToolButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Редактировать или вставить свой текст',
                  onPressed: _editLyrics,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Отсчёт «3 2 1» строкой текста над следующей строкой: текущая цифра
/// крупная и белая, следующие — тусклые, прошедшие гаснут.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.value, required this.frac, required this.fontSize});
  final int value;
  final double frac;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          for (final n in const [3, 2, 1])
            Padding(
              padding: EdgeInsets.only(right: fontSize * 0.6),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: n == value ? 1 : (n < value ? 0.3 : 0.12),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  alignment: Alignment.bottomLeft,
                  scale: n == value ? 1.0 : 0.72,
                  child: Text(
                    '$n',
                    style: TextStyle(
                      fontSize: fontSize * 1.4,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          foregroundColor: Colors.white70,
          backgroundColor: Colors.black.withValues(alpha: 0.18),
        ),
        icon: Icon(icon),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.child});
  final IconData icon;
  final String text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Colors.white38),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16)),
            if (child != null) ...[const SizedBox(height: 16), child!],
          ],
        ),
      ),
    );
  }
}

/// Караоке: текущая строка заливается по словам в такт музыке,
/// список сам прокручивается, по строке можно нажать и перемотать.
class KaraokeView extends StatefulWidget {
  const KaraokeView({
    super.key,
    required this.lyrics,
    this.sourceLabel,
    this.offset = Duration.zero,
    required this.position,
    required this.initialPosition,
    required this.onSeek,
  });

  final Lyrics lyrics;
  final String? sourceLabel;

  /// Сдвиг текста: + — строки загораются раньше.
  final Duration offset;
  final Stream<Duration> position;
  final Duration initialPosition;
  final ValueChanged<Duration> onSeek;

  @override
  State<KaraokeView> createState() => _KaraokeViewState();
}

const _lead = Duration(milliseconds: 250);

class _KaraokeViewState extends State<KaraokeView> {
  final _scroll = ScrollController();
  late List<GlobalKey> _keys;
  int _current = -2;
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
  }

  @override
  void didUpdateWidget(KaraokeView old) {
    super.didUpdateWidget(old);
    if (old.lyrics != widget.lyrics) {
      _keys = List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
      _current = -2;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _follow(int index, {bool animate = true}) {
    if (index < 0 || index >= _keys.length) return;
    // Если пользователь сам листал текст — не дёргаем его 4 секунды.
    if (DateTime.now().difference(_userScrolledAt) <
        const Duration(seconds: 4)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[index].currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: animate ? const Duration(milliseconds: 450) : Duration.zero,
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.lyrics;
    final width = MediaQuery.sizeOf(context).width;
    final fontSize = width > 900 ? 30.0 : (width > 500 ? 26.0 : 22.0);
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      height: 1.25,
      letterSpacing: -0.3,
      color: Colors.white,
    );

    if (!lyrics.synced) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
        children: [
          Text(
              widget.sourceLabel == null
                  ? 'Текст без таймингов'
                  : 'Текст без таймингов · ${widget.sourceLabel}',
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 16),
          for (final l in lyrics.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: l.text.startsWith('[')
                  // Заголовки куплетов с Genius: [Припев], [Куплет 1]
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(l.text,
                          style: TextStyle(
                              fontSize: 13,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary)),
                    )
                  : Text(l.text.isEmpty ? ' ' : l.text,
                      style: style.copyWith(
                          fontSize: fontSize * 0.8, color: Colors.white70)),
            ),
        ],
      );
    }

    return NotificationListener<UserScrollNotification>(
      onNotification: (_) {
        _userScrolledAt = DateTime.now();
        return false;
      },
      child: StreamBuilder<Duration>(
        stream: widget.position,
        initialData: widget.initialPosition,
        builder: (context, snap) {
          // Небольшое опережение: глаз должен успеть за голосом, плюс
          // компенсация задержки вывода звука.
          final pos = (snap.data ?? Duration.zero) + widget.offset + _lead;
          final idx = lyrics.indexAt(pos);
          if (idx != _current) {
            final first = _current == -2;
            _current = idx;
            _follow(idx < 0 ? 0 : idx, animate: !first);
          }
          // Отсчёт 3-2-1 только перед первой строкой (вступление).
          // В середине трека конец строки нам точно не известен: длинную
          // строку в быстром куплете легко принять за проигрыш.
          int? gapBefore; // индекс строки, над которой показываем отсчёт
          var count = 0;
          var secondFrac = 0.0;
          Duration? nextStart;
          Duration? gapFrom;
          if (idx < 0 && lyrics.lines.isNotEmpty) {
            nextStart = lyrics.lines.first.time;
            gapFrom = Duration.zero;
          }
          if (nextStart != null && gapFrom != null) {
            final gap = nextStart - gapFrom;
            final left = nextStart - pos;
            if (gap >= const Duration(seconds: 4) &&
                left > Duration.zero &&
                left <= const Duration(seconds: 3)) {
              gapBefore = idx < 0 ? 0 : idx + 1;
              count = (left.inMilliseconds / 1000).ceil();
              // Сколько прошло от текущей секунды (для кольца).
              secondFrac = 1 - (left.inMilliseconds - (count - 1) * 1000) / 1000;
            }
          }
          return Stack(
            children: [
              Positioned.fill(child: ShaderMask(
            // Мягкое затухание текста сверху и снизу.
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent
              ],
              stops: [0, 0.08, 0.88, 1],
            ).createShader(r),
            blendMode: BlendMode.dstIn,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(
                  24, MediaQuery.sizeOf(context).height * 0.2, 24,
                  MediaQuery.sizeOf(context).height * 0.4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lyrics.lines.length; i++) ...[
                    if (gapBefore == i)
                      _Countdown(value: count, frac: secondFrac, fontSize: fontSize),
                    _LineWidget(
                      key: _keys[i],
                      line: lyrics.lines[i],
                      state: i < idx
                          ? _LineState.past
                          : (i == idx ? _LineState.current : _LineState.future),
                      progress: i == idx
                          ? _progress(pos, lyrics.lines[i].time, lyrics.endOf(i))
                          : 0,
                      position: pos,
                      lineEnd: lyrics.endOf(i),
                      style: style,
                      onTap: () {
                        final t = lyrics.lines[i].time - widget.offset;
                        widget.onSeek(t.isNegative ? Duration.zero : t);
                      },
                    ),
                  ],
                ],
              ),
            ),
          )),
            ],
          );
        },
      ),
    );
  }

  static double _progress(Duration pos, Duration start, Duration end) {
    final total = (end - start).inMilliseconds;
    if (total <= 0) return 1;
    return ((pos - start).inMilliseconds / total).clamp(0.0, 1.0);
  }
}

enum _LineState { past, current, future }

class _LineWidget extends StatelessWidget {
  const _LineWidget({
    super.key,
    required this.line,
    required this.state,
    required this.progress,
    required this.style,
    required this.onTap,
    this.position = Duration.zero,
    this.lineEnd = Duration.zero,
  });

  final LyricLine line;
  final _LineState state;
  final double progress;
  final Duration position;
  final Duration lineEnd;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final text = line.text.trim().isEmpty ? '♪' : line.text.trim();

    // Как в Spotify: строка целиком загорается, когда начинает звучать.
    // Пословная заливка — только если у слов есть настоящие тайминги.
    Widget content;
    if (state == _LineState.current && line.hasWordTimes) {
      content = _FilledWords(
        text: text,
        progress: progress,
        words: line.words,
        position: position,
        lineEnd: lineEnd,
        style: style,
        filled: Colors.white,
        empty: Colors.white.withValues(alpha: 0.35),
        glow: accent,
      );
    } else {
      final color = switch (state) {
        _LineState.current => Colors.white,
        _LineState.past => Colors.white.withValues(alpha: 0.55),
        _LineState.future => Colors.white.withValues(alpha: 0.3),
      };
      content = AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        style: style.copyWith(
          color: color,
          shadows: const [],
        ),
        child: Text(text),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedScale(
        scale: state == _LineState.current ? 1.0 : 0.96,
        alignment: Alignment.centerLeft,
        duration: const Duration(milliseconds: 250),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: content,
        ),
      ),
    );
  }
}

/// Заливка по словам: каждое слово закрашивается слева направо по мере пения.
/// Работает и когда строка переносится на несколько рядов.
class _FilledWords extends StatelessWidget {
  const _FilledWords({
    required this.text,
    required this.progress,
    required this.style,
    required this.filled,
    required this.empty,
    required this.glow,
    this.words,
    this.position = Duration.zero,
    this.lineEnd = Duration.zero,
  });

  final String text;
  final double progress;

  /// Точные тайминги слов: тогда каждое слово загорается ровно когда поётся.
  final List<LyricWord>? words;
  final Duration position;
  final Duration lineEnd;
  final TextStyle style;
  final Color filled;
  final Color empty;
  final Color glow;

  /// Доля «спетости» каждого слова 0..1.
  List<({String text, double p})> _progressByWord() {
    final timed = words;
    if (timed != null && timed.isNotEmpty) {
      final out = <({String text, double p})>[];
      for (var i = 0; i < timed.length; i++) {
        final start = timed[i].time;
        var end = i + 1 < timed.length ? timed[i + 1].time : lineEnd;
        // Последнее слово и слова перед паузой не тянем дольше 1,2 с.
        final cap = start + const Duration(milliseconds: 1200);
        if (end > cap) end = cap;
        final total = (end - start).inMilliseconds;
        final done = (position - start).inMilliseconds;
        final p = total <= 0 ? (done >= 0 ? 1.0 : 0.0) : (done / total).clamp(0.0, 1.0);
        out.add((text: timed[i].text, p: p));
      }
      return out;
    }
    // Без таймингов слов: равномерно по длине строки.
    final parts = text.split(RegExp(r'\s+'));
    final total = parts.fold<int>(0, (s, w) => s + w.length + 1);
    final reached = progress * total;
    var offset = 0;
    final out = <({String text, double p})>[];
    for (final w in parts) {
      final start = offset;
      final len = w.length + 1;
      offset += len;
      out.add((text: w, p: ((reached - start) / len).clamp(0.0, 1.0)));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final item in _progressByWord()) {
      final w = item.text;
      final p = item.p;
      final edge = (p + 0.08).clamp(0.0, 1.0);
      // Ещё не спетое слово — целиком тусклое, уже спетое — целиком яркое.
      // Градиент только у слова, которое поётся сейчас.
      if (p <= 0 || p >= 1) {
        children.add(Text(w, style: style.copyWith(color: p >= 1 ? filled : empty)));
        continue;
      }
      // Слово, которое поётся прямо сейчас, чуть приподнимается.
      final lift = (p > 0 && p < 1) ? -2.0 : 0.0;
      children.add(
        AnimatedSlide(
          offset: Offset(0, lift / (style.fontSize ?? 24)),
          duration: const Duration(milliseconds: 120),
          child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => LinearGradient(
            colors: [filled, filled, empty, empty],
            stops: [0, p, edge, 1],
          ).createShader(r),
          child: Text(
            w,
            style: style.copyWith(
              shadows: null,
            ),
          ),
        ),
        ),
      );
    }
    return Wrap(
      spacing: style.fontSize! * 0.28,
      runSpacing: 2,
      children: children,
    );
  }
}
