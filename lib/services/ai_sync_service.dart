import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'cloud_relay.dart';

import 'lyrics_service.dart';

/// Слово, распознанное в треке, со временем звучания.
class HeardWord {
  const HeardWord(this.text, this.start);
  final String text;
  final Duration start;
}

/// ИИ-распознавание речи (Whisper) через любой OpenAI-совместимый сервис:
/// Groq (есть бесплатный тариф), OpenAI или свой сервер.
/// По распознанным словам расставляет тайминги строкам текста.
class AiSyncService {
  final http.Client _client = http.Client();

  Future<List<HeardWord>> transcribe({
    required File audio,
    required String baseUrl,
    required String apiKey,
    required String model,
    String? prompt,
    String? language,
  }) async {
    final size = await audio.length();
    if (size > 25 * 1024 * 1024) {
      throw Exception('Файл больше 25 МБ — сервис ИИ его не примет');
    }
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    // Запрос собираем функцией: если сервис не пустит напрямую (403 — например,
    // из России), отправим его ещё раз через облако Hutred.
    Future<http.MultipartRequest> build(bool viaRelay) async {
    final target = Uri.parse('$base/audio/transcriptions');
    final req = http.MultipartRequest('POST', viaRelay ? CloudRelay.wrap(target) : target)
      ..headers.addAll(viaRelay
          ? CloudRelay.headers({'Authorization': 'Bearer $apiKey'})
          : {'Authorization': 'Bearer $apiKey'})
      ..fields['model'] = model
      ..fields['response_format'] = 'verbose_json'
      ..fields['timestamp_granularities[]'] = 'word'
      // Подсказка с ожидаемым текстом: Whisper лучше слышит слова песни.
      ..fields.addAll({
        if (prompt != null && prompt.isNotEmpty) 'prompt': prompt,
        if (language != null) 'language': language,
      })
      ..files.add(await http.MultipartFile.fromPath('file', audio.path,
          filename: 'track${_ext(audio.path)}'));
    // Второе значение того же поля MultipartRequest не умеет — сегменты
    // приходят в verbose_json и так.
    return req;
    }

    var streamed = await _client.send(await build(false)).timeout(const Duration(minutes: 3));
    var body = await streamed.stream.bytesToString();
    if (streamed.statusCode == 403 && CloudRelay.available) {
      streamed = await _client.send(await build(true)).timeout(const Duration(minutes: 3));
      body = await streamed.stream.bytesToString();
    }
    if (streamed.statusCode == 403) {
      throw Exception('Сервис ИИ (Groq) отказал в доступе (403). Так бывает из стран, '
          'где он не работает, или через VPN такой страны');
    }
    if (streamed.statusCode == 401) {
      throw Exception('Сервис ИИ не принял ключ. Проверь его в Настройках');
    }
    if (streamed.statusCode != 200) {
      throw Exception('Сервис ИИ ответил ${streamed.statusCode}: '
          '${body.length > 200 ? body.substring(0, 200) : body}');
    }
    final j = jsonDecode(body);
    if (j is! Map) throw Exception('Непонятный ответ сервиса ИИ');

    final words = <HeardWord>[];
    for (final w in (j['words'] as List? ?? const []).whereType<Map>()) {
      final text = '${w['word'] ?? ''}'.trim();
      final start = (w['start'] as num?)?.toDouble();
      if (text.isEmpty || start == null) continue;
      words.add(HeardWord(text, _dur(start)));
    }
    if (words.isEmpty) {
      // Без пословных меток: раскладываем слова сегмента равномерно.
      for (final seg in (j['segments'] as List? ?? const []).whereType<Map>()) {
        final text = '${seg['text'] ?? ''}'.trim();
        final s = (seg['start'] as num?)?.toDouble();
        final e = (seg['end'] as num?)?.toDouble();
        if (text.isEmpty || s == null || e == null) continue;
        final parts = text.split(RegExp(r'\s+'));
        for (var i = 0; i < parts.length; i++) {
          words.add(HeardWord(parts[i], _dur(s + (e - s) * i / parts.length)));
        }
      }
    }
    if (words.isEmpty) throw Exception('ИИ не расслышал слов в этом треке');
    return words;
  }

  /// Строки из распознанного текста, когда своего текста нет совсем.
  static String transcriptToLrc(List<HeardWord> words) {
    final lines = <String>[];
    var buf = <String>[];
    Duration? lineStart;
    Duration? prev;
    void flush() {
      if (buf.isEmpty || lineStart == null) return;
      lines.add('${_stamp(lineStart!)}${buf.join(' ')}');
      buf = [];
      lineStart = null;
    }

    for (final w in words) {
      // Новая строка после паузы или каждые 8 слов.
      if (prev != null &&
          (w.start - prev > const Duration(milliseconds: 1200) || buf.length >= 8)) {
        flush();
      }
      lineStart ??= w.start;
      // Тайминг — на всю строку, а не на каждое слово: так читать удобнее.
      buf.add(w.text);
      prev = w.start;
      // Конец предложения — новая строка.
      if (RegExp(r'[.!?…]$').hasMatch(w.text)) {
        flush();
        prev = null;
      }
    }
    flush();
    return lines.join('\n');
  }

  /// Подсказка для Whisper и язык — из текста песни.
  static String promptFrom(Lyrics lyrics) {
    final text = lyrics.lines
        .map((l) => l.text.trim())
        .where((t) => t.isNotEmpty && !t.startsWith('['))
        .join(' ');
    // Сервис ограничивает подсказку 896 байтами (кириллица — 2 байта
    // на букву), поэтому режем по байтам и по границе слова.
    const maxBytes = 850;
    if (utf8.encode(text).length <= maxBytes) return text;
    final words = text.split(' ');
    final buf = StringBuffer();
    var bytes = 0;
    for (final w in words) {
      final add = utf8.encode(buf.isEmpty ? w : ' $w').length;
      if (bytes + add > maxBytes) break;
      buf.write(buf.isEmpty ? w : ' $w');
      bytes += add;
    }
    return buf.toString();
  }

  static String? languageOf(Lyrics lyrics) {
    final text = lyrics.lines.map((l) => l.text).join(' ');
    final cyr = RegExp(r'[а-яА-ЯёЁ]').allMatches(text).length;
    final lat = RegExp(r'[a-zA-Z]').allMatches(text).length;
    if (cyr + lat < 20) return null;
    if (cyr > lat * 2) return 'ru';
    if (lat > cyr * 2) return 'en';
    return null;
  }

  /// Места, где в распознанном тексте может звучать строка [i]:
  /// (номер слова, насколько уверенно совпало 0..1).
  static List<({int j, double score})> _candidates(
      String line, List<String> heard) {
    final tokens = _norm(line).split(' ').where((t) => t.isNotEmpty).take(6).toList();
    // Обычный (изменяемый) список: дальше его сортируют.
    if (tokens.length < 2) return <({int j, double score})>[];
    final out = <({int j, double score})>[];
    for (var j = 0; j < heard.length; j++) {
      if (!_close(tokens.first, heard[j]) &&
          (tokens.length < 2 || j + 1 >= heard.length || !_close(tokens[1], heard[j + 1]))) {
        continue;
      }
      var k = j;
      var hits = 0;
      for (final tok in tokens) {
        for (var look = 0; look < 3; look++) {
          final idx = k + look;
          if (idx >= heard.length) break;
          if (_close(tok, heard[idx])) {
            hits++;
            k = idx + 1;
            break;
          }
        }
      }
      final score = hits / tokens.length;
      if (score >= 0.5) out.add((j: j, score: score));
    }
    return out;
  }

  /// Текст УЖЕ с таймингами (NetEase, LRCLIB, субтитры): ищем один общий
  /// сдвиг (и небольшое растяжение темпа), при котором больше всего строк
  /// совпадает с тем, что услышал ИИ. Так строки не разъезжаются.
  /// Возвращает null, если надёжных совпадений мало.
  static ({String lrc, Duration shift})? fitTimings(
      Lyrics lyrics, List<HeardWord> words) {
    if (!lyrics.synced) return null;
    final heard = words.map((w) => _norm(w.text)).toList();
    final pairs = <({double t, double h, double score})>[];
    for (final l in lyrics.lines) {
      if (l.text.trim().isEmpty || l.text.trim().startsWith('[')) continue;
      for (final c in _candidates(l.text, heard)) {
        pairs.add((
          t: l.time.inMilliseconds / 1000,
          h: words[c.j].start.inMilliseconds / 1000,
          score: c.score,
        ));
      }
    }
    if (pairs.isEmpty) return null;

    // Голосование: какой сдвиг поддерживает больше всего строк (окно ±0,6 с).
    var bestShift = 0.0;
    var bestSupport = 0.0;
    for (final p in pairs) {
      final d = p.h - p.t;
      var support = 0.0;
      final seen = <double>{};
      for (final q in pairs) {
        if ((q.h - q.t - d).abs() <= 0.6 && seen.add(q.t)) support += q.score;
      }
      if (support > bestSupport) {
        bestSupport = support;
        bestShift = d;
      }
    }
    final lineCount = lyrics.lines.where((l) => l.text.trim().isNotEmpty).length;
    if (bestSupport < 3 || bestSupport < lineCount * 0.2) return null;

    // Уточняем по совпавшим строкам: сдвиг + растяжение (метод наименьших квадратов).
    final inl = pairs.where((p) => (p.h - p.t - bestShift).abs() <= 0.6).toList();
    final n = inl.length.toDouble();
    final mt = inl.fold<double>(0, (s, p) => s + p.t) / n;
    final mh = inl.fold<double>(0, (s, p) => s + p.h) / n;
    var cov = 0.0, vt = 0.0;
    for (final p in inl) {
      cov += (p.t - mt) * (p.h - mh);
      vt += (p.t - mt) * (p.t - mt);
    }
    var a = vt > 0 ? cov / vt : 1.0;
    // Темп песни один и тот же: допускаем только небольшое растяжение.
    if (a < 0.97 || a > 1.03 || inl.length < 6) a = 1.0;
    final b = mh - a * mt;

    final newTimes = [
      for (final l in lyrics.lines)
        _dur(((a * (l.time.inMilliseconds / 1000) + b).clamp(0, 1e9)).toDouble())
    ];
    final out = <String>[];
    for (var i = 0; i < lyrics.lines.length; i++) {
      if (_isHeader(lyrics.lines[i].text)) continue;
      final end = i + 1 < newTimes.length
          ? newTimes[i + 1]
          : newTimes[i] + const Duration(seconds: 6);
      final l = lyrics.lines[i];
      if (l.hasWordTimes) {
        // У текста уже есть пословные тайминги (NetEase) — сдвигаем их тем же сдвигом.
        Duration move(Duration t) =>
            _dur(((a * (t.inMilliseconds / 1000) + b).clamp(0, 1e9)).toDouble());
        final buf = StringBuffer(_stamp(newTimes[i]));
        for (var w = 0; w < l.words.length; w++) {
          buf.write(Lyrics.stamp(move(l.words[w].time), word: true));
          buf.write(l.words[w].text);
          if (w + 1 < l.words.length) buf.write(' ');
        }
        out.add(buf.toString());
      } else {
        out.add(_lineWithWords(l.text, newTimes[i], end, words));
      }
    }
    return (lrc: out.join('\n'), shift: _dur(b + (a - 1) * mt));
  }

  /// Текст БЕЗ таймингов: для каждой строки ищем все места, где она могла
  /// звучать, и выбираем последовательность мест по порядку песни с
  /// наибольшим числом совпадений (динамическое программирование).
  /// Строки без совпадений получают время между соседями.
  static String align(Lyrics lyrics, List<HeardWord> words) {
    final heard = words.map((w) => _norm(w.text)).toList();
    final lines = lyrics.lines.map((l) => l.text).toList();
    final times = List<Duration?>.filled(lines.length, null);

    // Кандидаты по строкам (не больше 8 лучших на строку).
    final cands = <int, List<({int j, double score})>>{};
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].trim();
      if (t.isEmpty || t.startsWith('[')) continue;
      final c = List.of(_candidates(t, heard))
        ..sort((x, y) => y.score.compareTo(x.score));
      if (c.isNotEmpty) cands[i] = c.take(8).toList();
    }
    // DP: лучшая сумма для «строка i стоит на слове j», с порядком j.
    final states = <({int i, int j, double score})>[];
    for (final e in cands.entries) {
      for (final c in e.value) {
        states.add((i: e.key, j: c.j, score: c.score));
      }
    }
    states.sort((x, y) => x.i != y.i ? x.i.compareTo(y.i) : x.j.compareTo(y.j));
    final best = List<double>.filled(states.length, 0);
    final prev = List<int>.filled(states.length, -1);
    for (var s1 = 0; s1 < states.length; s1++) {
      best[s1] = states[s1].score;
      for (var s0 = 0; s0 < s1; s0++) {
        if (states[s0].i < states[s1].i &&
            states[s0].j < states[s1].j &&
            best[s0] + states[s1].score > best[s1]) {
          best[s1] = best[s0] + states[s1].score;
          prev[s1] = s0;
        }
      }
    }
    if (states.isNotEmpty) {
      var end = 0;
      for (var k = 1; k < states.length; k++) {
        if (best[k] > best[end]) end = k;
      }
      for (var k = end; k >= 0; k = prev[k]) {
        times[states[k].i] = words[states[k].j].start;
      }
    }

    // Расставляем время только поющимся строкам, заголовки убираем.
    final sung = <int>[for (var i = 0; i < lines.length; i++) if (!_isHeader(lines[i])) i];
    final sungTimes = [for (final i in sung) times[i]];
    _interpolate(sungTimes, [for (final i in sung) lines[i]]);
    for (var k = 0; k < sung.length; k++) {
      times[sung[k]] = sungTimes[k];
    }
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final t = times[i];
      if (t == null || _isHeader(lines[i])) continue;
      final end = i + 1 < times.length && times[i + 1] != null
          ? times[i + 1]!
          : t + const Duration(seconds: 6);
      out.add(_lineWithWords(lines[i], t, end, words));
    }
    return out.join('\n');
  }

  /// Строка с пословными таймингами: слова строки сопоставляются с тем,
  /// что ИИ услышал между началом этой строки и началом следующей.
  /// Если совпало меньше половины слов — оставляем обычную строку.
  static String _lineWithWords(
      String text, Duration start, Duration end, List<HeardWord> words) {
    // ИИ ставит время целой строке (предложению): пословная подсветка по
    // распознанным словам выходила рваной и неточной.
    return '${_stamp(start)}$text';
  }

  // Прежний пословный вариант — оставлен на случай, если захочется вернуть.
  // ignore: unused_element
  static String _lineWithWordsOld(
      String text, Duration start, Duration end, List<HeardWord> words) {
    final line = '${_stamp(start)}$text';
    final tokens = text.trim().split(RegExp(r'\s+'));
    if (text.trim().isEmpty || text.trim().startsWith('[') || tokens.length < 2) {
      return line;
    }
    final from = start - const Duration(milliseconds: 400);
    final window = words.where((w) => w.start >= from && w.start < end).toList();
    if (window.isEmpty) return line;

    final times = List<Duration?>.filled(tokens.length, null);
    var k = 0;
    for (var t = 0; t < tokens.length; t++) {
      final want = _norm(tokens[t]);
      if (want.isEmpty) continue;
      for (var look = 0; look < 3 && k + look < window.length; look++) {
        if (_close(want, _norm(window[k + look].text))) {
          times[t] = window[k + look].start;
          k = k + look + 1;
          break;
        }
      }
    }
    final matched = times.whereType<Duration>().length;
    if (matched < tokens.length / 2) return line;

    // Несовпавшие слова — равномерно между соседними известными.
    times[0] ??= start;
    for (var t = 1; t < tokens.length; t++) {
      if (times[t] != null) continue;
      var n = t + 1;
      while (n < tokens.length && times[n] == null) {
        n++;
      }
      final left = times[t - 1]!;
      final right = n < tokens.length ? times[n]! : end;
      final step = (right - left) * (1 / (n - t + 1));
      for (var q = t; q < n; q++) {
        times[q] = left + step * (q - t + 1);
      }
      t = n - 1;
    }
    // Время слов не должно идти назад.
    for (var t = 1; t < tokens.length; t++) {
      if (times[t]! < times[t - 1]!) times[t] = times[t - 1];
    }
    final buf = StringBuffer(_stamp(start));
    for (var t = 0; t < tokens.length; t++) {
      buf.write(Lyrics.stamp(times[t]!, word: true));
      buf.write(tokens[t]);
      if (t + 1 < tokens.length) buf.write(' ');
    }
    return buf.toString();
  }

  /// «[Куплет 2]», «[Припев]» и пустые строки — их не поют.
  static bool _isHeader(String text) {
    final t = text.trim();
    return t.isEmpty || (t.startsWith('[') && t.endsWith(']'));
  }

  static void _interpolate(List<Duration?> times, List<String> lines) {
    final anchors = <int>[for (var i = 0; i < times.length; i++) if (times[i] != null) i];
    if (anchors.isEmpty) {
      throw Exception('ИИ не нашёл строки текста в треке. Возможно, это другая версия песни');
    }
    // До первой найденной строки — по 3 секунды назад.
    for (var i = anchors.first - 1; i >= 0; i--) {
      final next = times[i + 1]!;
      final t = next - const Duration(seconds: 3);
      times[i] = t.isNegative ? Duration.zero : t;
    }
    // Между найденными строками — равномерно.
    for (var a = 0; a < anchors.length - 1; a++) {
      final i0 = anchors[a], i1 = anchors[a + 1];
      final t0 = times[i0]!, t1 = times[i1]!;
      for (var i = i0 + 1; i < i1; i++) {
        times[i] = t0 + (t1 - t0) * ((i - i0) / (i1 - i0));
      }
    }
    // После последней — по 3 секунды вперёд.
    for (var i = anchors.last + 1; i < times.length; i++) {
      times[i] = times[i - 1]! + const Duration(seconds: 3);
    }
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Слова «похожи»: совпадают или отличаются на 1–2 буквы.
  static bool _close(String a, String b) {
    if (a == b) return true;
    if (a.length < 3 || b.length < 3) return false;
    if (a.length > 4 && b.length > 4 && a.substring(0, 4) == b.substring(0, 4)) {
      return true;
    }
    return _levenshtein(a, b) <= (a.length > 6 ? 2 : 1);
  }

  static int _levenshtein(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
            .reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  static Duration _dur(double seconds) =>
      Duration(milliseconds: (seconds * 1000).round());

  static String _stamp(Duration d) {
    final ms = d.inMilliseconds;
    final m = (ms ~/ 60000).toString().padLeft(2, '0');
    final s = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
    final cs = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
    return '[$m:$s.$cs]';
  }

  static String _ext(String path) {
    final i = path.lastIndexOf('.');
    return i < 0 ? '.m4a' : path.substring(i);
  }
}
