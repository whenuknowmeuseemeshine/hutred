import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'genius_service.dart';
import 'youtube_source.dart';

/// Слово с точным временем (пословный текст, как в караоке).
class LyricWord {
  const LyricWord(this.time, this.text);
  final Duration time;
  final String text;
}

class LyricLine {
  const LyricLine(this.time, this.text, [this.words = const []]);
  final Duration time;
  final String text;

  /// Пословные тайминги, если источник их дал (NetEase, ИИ).
  final List<LyricWord> words;

  bool get hasWordTimes => words.length >= 2;
}

/// Разобранный текст песни. synced = есть тайминги (формат LRC).
class Lyrics {
  const Lyrics(this.lines, {required this.synced});

  final List<LyricLine> lines;
  final bool synced;

  bool get isEmpty => lines.every((l) => l.text.trim().isEmpty);

  static final _stamp = RegExp(r'^\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final _offsetTag =
      RegExp(r'^\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);

  static final _header = RegExp(r'^\[[^\]]*\]$');

  static final _wordStamp =
      RegExp(r'<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>([^<]*)');

  static Duration _toDuration(String m, String s, String? frac) {
    frac ??= '0';
    final ms = switch (frac.length) {
      1 => int.parse(frac) * 100,
      2 => int.parse(frac) * 10,
      _ => int.parse(frac),
    };
    return Duration(minutes: int.parse(m), seconds: int.parse(s), milliseconds: ms);
  }

  /// Время в формате LRC: [мм:сс.сс] или <мм:сс.сс>.
  static String stamp(Duration d, {bool word = false}) {
    final ms = d.inMilliseconds;
    final m = (ms ~/ 60000).toString().padLeft(2, '0');
    final sec = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
    final cs = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
    return word ? '<$m:$sec.$cs>' : '[$m:$sec.$cs]';
  }

  static Lyrics parse(String raw) {
    final timed = <LyricLine>[];
    final plain = <String>[];
    var offsetMs = 0;

    for (var line in const LineSplitter().convert(raw)) {
      line = line.trim();
      final off = _offsetTag.firstMatch(line);
      if (off != null) {
        offsetMs = int.parse(off.group(1)!);
        continue;
      }
      final stamps = <Duration>[];
      var m = _stamp.firstMatch(line);
      while (m != null) {
        final frac = m.group(3) ?? '0';
        final ms = switch (frac.length) {
          1 => int.parse(frac) * 100,
          2 => int.parse(frac) * 10,
          _ => int.parse(frac),
        };
        stamps.add(Duration(
          minutes: int.parse(m.group(1)!),
          seconds: int.parse(m.group(2)!),
          milliseconds: ms,
        ));
        line = line.substring(m.end).trim();
        m = _stamp.firstMatch(line);
      }
      if (stamps.isNotEmpty) {
        // Расширенный LRC: <мм:сс.сс>слово — время каждого слова.
        final words = <LyricWord>[];
        if (line.contains('<')) {
          for (final w in _wordStamp.allMatches(line)) {
            final text = w.group(4)!.trim();
            if (text.isEmpty) continue;
            words.add(LyricWord(_toDuration(w.group(1)!, w.group(2)!, w.group(3)), text));
          }
          line = line.replaceAll(RegExp(r'<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>'), '').trim();
          line = line.replaceAll(RegExp(r'\s+'), ' ');
        }
        // Заголовки куплетов не поются: в тексте с таймингами они только
        // сбивают подсветку, поэтому пропускаем их.
        if (_header.hasMatch(line)) continue;
        for (final s in stamps) {
          timed.add(LyricLine(s, line, words));
        }
      } else {
        // Теги вида [ar:...] нужны только LRC; в обычном тексте
        // строки в скобках — это заголовки куплетов, их оставляем.
        plain.add(line);
      }
    }

    if (timed.isNotEmpty) {
      // В LRC положительный offset означает «показывать раньше».
      final shifted = timed
          .map((l) {
            Duration shift(Duration t) {
              final v = t - Duration(milliseconds: offsetMs);
              return v < Duration.zero ? Duration.zero : v;
            }

            return LyricLine(shift(l.time), l.text,
                [for (final w in l.words) LyricWord(shift(w.time), w.text)]);
          })
          .toList()
        ..sort((a, b) => a.time.compareTo(b.time));
      return Lyrics(shifted, synced: true);
    }
    while (plain.isNotEmpty && plain.first.isEmpty) {
      plain.removeAt(0);
    }
    return Lyrics(plain.map((t) => LyricLine(Duration.zero, t)).toList(),
        synced: false);
  }

  /// Индекс строки, которая звучит в момент [pos]; -1 до первой строки.
  int indexAt(Duration pos) {
    if (!synced || lines.isEmpty) return -1;
    var lo = 0, hi = lines.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time <= pos) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  /// Когда заканчивается строка [i] (начало следующей, не дольше 8 секунд).
  Duration endOf(int i) {
    final start = lines[i].time;
    final cap = start + const Duration(seconds: 8);
    if (i + 1 >= lines.length) return cap;
    final next = lines[i + 1].time;
    return next < cap ? next : cap;
  }
}

/// Источник текста.
enum LyricsOrigin {
  lrclib('LRCLIB'),
  netease('NetEase Music'),
  youtube('Субтитры YouTube'),
  genius('Genius'),
  ai('Синхронизировано ИИ'),
  custom('Свой текст');

  const LyricsOrigin(this.label);
  final String label;

  static LyricsOrigin? byName(String? name) {
    for (final o in values) {
      if (o.name == name) return o;
    }
    return null;
  }
}

class LyricsResult {
  const LyricsResult(this.text, this.origin);
  final String text;
  final LyricsOrigin origin;
}

/// Ищет текст по очереди: синхронный в LRCLIB, синхронный в субтитрах
/// YouTube, обычный на Genius, обычный в LRCLIB.
class LyricsService {
  LyricsService({required this.youtube, required this.genius});

  final YoutubeSource youtube;
  final GeniusService genius;
  final http.Client _client = http.Client();
  static const _headers = {'User-Agent': 'Hutred music player 1.0'};

  /// Порядок источников (из настроек): lrclib, youtube, genius.
  static List<String> order = const ['lrclib', 'youtube', 'genius'];

  Future<LyricsResult?> find(
    Track t, {
    bool useYoutube = true,
    bool useGenius = true,
    LyricsOrigin? only,
  }) async {
    final split = YoutubeSource.splitTitle(t.title, t.artist);
    final title = YoutubeSource.searchTitle(split.title);
    final artist = split.artist;

    // Порядок источников задаётся в настройках (по умолчанию LRCLIB →
    // YouTube → Genius). NetEase — запасной к LRCLIB.
    ({String? synced, String? plain})? lrclib;
    for (final src in order) {
      switch (src) {
        case 'lrclib':
          if (only == null || only == LyricsOrigin.lrclib) {
            lrclib = await _tryOrNull(() => _lrclib(t, artist, title));
            if (lrclib?.synced != null) {
              return LyricsResult(lrclib!.synced!, LyricsOrigin.lrclib);
            }
          }
          if (only == null || only == LyricsOrigin.netease) {
            final lrc = await _tryOrNull(() => _netease(t, artist, title));
            if (lrc != null) return LyricsResult(lrc, LyricsOrigin.netease);
          }
        case 'youtube':
          if ((only == null && useYoutube) || only == LyricsOrigin.youtube) {
            final lrc = await _tryOrNull(() => youtube.findCaptionLyrics(
                  videoId: t.source == TrackSource.youtube ? t.uri : null,
                  artist: artist,
                  title: title,
                  duration: t.duration,
                ));
            if (lrc != null) return LyricsResult(lrc, LyricsOrigin.youtube);
          }
        case 'genius':
          if ((only == null && useGenius) || only == LyricsOrigin.genius) {
            final text = await _tryOrNull<String>(() async {
              final song = await genius.findSong(artist, title);
              if (song == null) return null;
              return await genius.fetchLyrics(song);
            });
            if (text != null) return LyricsResult(text, LyricsOrigin.genius);
          }
      }
    }

    // 4. Обычный текст из LRCLIB.
    if (lrclib?.plain != null) {
      return LyricsResult(lrclib!.plain!, LyricsOrigin.lrclib);
    }
    return null;
  }

  static Future<T?> _tryOrNull<T>(Future<T?> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  Future<({String? synced, String? plain})?> _lrclib(
      Track t, String artist, String title) async {
    final hasArtist = artist != Track.unknownArtist && artist.isNotEmpty;

    // Несколько вариантов запроса: точный, по полям, общий.
    final results = <Map<String, dynamic>>[];
    final seen = <Object?>{};
    void addAll(Iterable<Map<String, dynamic>> items) {
      for (final r in items) {
        if (seen.add(r['id'])) results.add(r);
      }
    }

    if (hasArtist) {
      final exact = await _get(artist, title, t.duration);
      if (exact != null) addAll([exact]);
      addAll(await _search({'track_name': title, 'artist_name': artist}));
    }
    if (!results.any((r) => (r['syncedLyrics'] as String?)?.isNotEmpty ?? false)) {
      addAll(await _search({'q': hasArtist ? '$artist $title' : title}));
    }
    if (results.isEmpty && hasArtist) {
      addAll(await _search({'track_name': title}));
    }
    // Отбрасываем явно чужие песни.
    results.removeWhere((r) =>
        GeniusService.similar(title, r['trackName'] as String? ?? '') < 0.5 ||
        (hasArtist &&
            GeniusService.similar(artist, r['artistName'] as String? ?? '') == 0));
    if (results.isEmpty) return null;

    final dur = t.duration?.inSeconds;
    Map<String, dynamic>? best;
    var bestScore = -1;
    for (final r in results.take(15)) {
      if (r['instrumental'] == true) continue;
      final synced = (r['syncedLyrics'] as String?)?.isNotEmpty ?? false;
      final plain = (r['plainLyrics'] as String?)?.isNotEmpty ?? false;
      if (!synced && !plain) continue;
      var score = synced ? 4 : 1;
      final rd = (r['duration'] as num?)?.round();
      if (dur != null && rd != null) {
        final diff = (rd - dur).abs();
        if (diff <= 2) {
          score += 5;
        } else if (diff <= 8) {
          score += 2;
        } else if (diff > 30) {
          score -= 4;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        best = r;
      }
    }
    if (best == null) return null;
    String? nonEmpty(Object? v) =>
        (v is String && v.trim().isNotEmpty) ? v : null;
    return (
      synced: nonEmpty(best['syncedLyrics']),
      plain: nonEmpty(best['plainLyrics']),
    );
  }

  Future<Map<String, dynamic>?> _get(
      String artist, String title, Duration? duration) async {
    final params = {'artist_name': artist, 'track_name': title};
    if (duration != null) params['duration'] = '${duration.inSeconds}';
    final res = await _lrclibGet(Uri.https('lrclib.net', '/api/get', params));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  /// Если LRCLIB лежит (502 и т.п.), 10 минут его не трогаем,
  /// чтобы не ждать таймаутов на каждом треке.
  DateTime _lrclibDownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  Future<http.Response> _lrclibGet(Uri uri) async {
    if (DateTime.now().isBefore(_lrclibDownUntil)) {
      throw Exception('LRCLIB недоступен');
    }
    try {
      final res = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode >= 500) throw Exception('LRCLIB: ${res.statusCode}');
      return res;
    } catch (_) {
      _lrclibDownUntil = DateTime.now().add(const Duration(minutes: 10));
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _search(Map<String, String> params) async {
    final uri = Uri.https('lrclib.net', '/api/search', params);
    final res = await _lrclibGet(uri);
    if (res.statusCode != 200) return const [];
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! List) return const [];
    return data.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  // ---------- NetEase Music ----------

  static const _neteaseHeaders = {
    'Referer': 'https://music.163.com/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/126.0 Safari/537.36',
  };

  Future<String?> _netease(Track t, String artist, String title) async {
    final hasArtist = artist != Track.unknownArtist && artist.isNotEmpty;
    final res = await _client
        .get(
            Uri.https('music.163.com', '/api/search/get', {
              's': hasArtist ? '$artist $title' : title,
              'type': '1',
              'limit': '10',
            }),
            headers: _neteaseHeaders)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final result = data is Map ? data['result'] : null;
    final songs = (result is Map ? result['songs'] as List? : null) ?? const [];

    final dur = t.duration?.inSeconds;
    final candidates = <({int id, double score})>[];
    for (final song in songs.whereType<Map>()) {
      final id = (song['id'] as num?)?.toInt();
      if (id == null) continue;
      final name = song['name'] as String? ?? '';
      final artists = (song['artists'] as List? ?? const [])
          .whereType<Map>()
          .map((a) => a['name'] as String? ?? '')
          .join(' ');
      final titleScore = GeniusService.similar(title, name);
      if (titleScore < 0.5) continue;
      final artistScore = hasArtist ? GeniusService.similar(artist, artists) : 1.0;
      if (hasArtist && artistScore == 0) continue;
      var score = titleScore * 2 + artistScore;
      final ms = (song['duration'] as num?)?.toInt();
      if (dur != null && ms != null) {
        final diff = (ms ~/ 1000 - dur).abs();
        if (diff <= 3) {
          score += 1;
        } else if (diff > 20) {
          score -= 1.5;
        }
      }
      candidates.add((id: id, score: score));
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));

    for (final c in candidates.take(3)) {
      final lr = await _client
          .get(
              Uri.https('music.163.com', '/api/song/lyric',
                  {'id': '${c.id}', 'lv': '1', 'kv': '1', 'tv': '-1', 'yv': '1'}),
              headers: _neteaseHeaders)
          .timeout(const Duration(seconds: 10));
      if (lr.statusCode != 200) continue;
      final j = jsonDecode(utf8.decode(lr.bodyBytes));
      // Пословный вариант (yrc) — у многих песен NetEase он есть.
      final yrcObj = j is Map ? j['yrc'] : null;
      final yrc = yrcObj is Map ? yrcObj['lyric'] as String? : null;
      if (yrc != null && yrc.trim().isNotEmpty) {
        final enhanced = _yrcToLrc(yrc);
        if (enhanced != null) return enhanced;
      }
      final lrcObj = j is Map ? j['lrc'] : null;
      final lrc = lrcObj is Map ? lrcObj['lyric'] as String? : null;
      if (lrc == null || lrc.trim().isEmpty) continue;
      final cleaned = _cleanNetease(lrc);
      final parsed = Lyrics.parse(cleaned);
      // Нужны именно тайминги и хоть сколько-то строк.
      if (parsed.synced && parsed.lines.where((l) => l.text.isNotEmpty).length >= 4) {
        return cleaned;
      }
    }
    return null;
  }

  /// Формат NetEase yrc: [начало,длительность](слово_начало,длит,0)слово…
  /// Переводим в расширенный LRC: [мм:сс.сс]<мм:сс.сс>слово <мм:сс.сс>слово
  static String? _yrcToLrc(String yrc) {
    final lineRe = RegExp(r'^\[(\d+),(\d+)\](.*)$');
    final wordRe = RegExp(r'\((\d+),(\d+),\d+\)([^(]*)');
    final out = <String>[];
    for (final raw in const LineSplitter().convert(yrc)) {
      final l = raw.trim();
      if (l.isEmpty || l.startsWith('{')) continue; // строки с авторами
      final m = lineRe.firstMatch(l);
      if (m == null) continue;
      final start = Duration(milliseconds: int.parse(m.group(1)!));
      final buf = StringBuffer(Lyrics.stamp(start));
      var words = 0;
      for (final w in wordRe.allMatches(m.group(3)!)) {
        final text = w.group(3)!;
        if (text.trim().isEmpty) continue;
        buf.write(Lyrics.stamp(Duration(milliseconds: int.parse(w.group(1)!)), word: true));
        buf.write(text.trim());
        buf.write(' ');
        words++;
      }
      if (words == 0) continue;
      out.add(buf.toString().trimRight());
    }
    if (out.length < 4) return null;
    final text = out.join('\n');
    return _cleanNetease(text);
  }

  /// NetEase вставляет в начало строки с авторами («作词 : …», «作曲 : …»).
  static String _cleanNetease(String lrc) {
    final credit = RegExp(
        r'^\[[\d:.]+\]\s*(作词|作曲|编曲|制作人|混音|母带|和声|吉他|贝斯|鼓|录音|监制|出品|发行|OP|SP|Lyricist|Composer|Arranger|Producer|Mixing|Mastering)\s*[:：]',
        caseSensitive: false);
    return lrc
        .split('\n')
        .where((l) => !credit.hasMatch(l.trim()))
        .join('\n');
  }
}
