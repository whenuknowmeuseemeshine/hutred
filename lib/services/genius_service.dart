import 'dart:convert';

import 'package:http/http.dart' as http;

/// Найденная на Genius песня.
class GeniusSong {
  const GeniusSong({
    required this.title,
    required this.artist,
    required this.url,
    this.artUrl,
  });

  final String title;
  final String artist;
  final String url;

  /// Обложка (null, если у песни заглушка Genius).
  final String? artUrl;
}

/// Поиск песен, текстов и обложек на genius.com.
class GeniusService {
  final http.Client _client = http.Client();
  final Map<String, GeniusSong?> _cache = {};

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/126.0 Safari/537.36',
    'Accept-Language': 'ru,en;q=0.8',
  };

  /// Ищет песню и проверяет, что найденное действительно похоже на запрос.
  Future<GeniusSong?> findSong(String artist, String title) async {
    final key = '${_norm(artist)}|${_norm(title)}';
    if (_cache.containsKey(key)) return _cache[key];

    final hasArtist = artist.isNotEmpty && artist != 'Неизвестный исполнитель';
    final q = hasArtist ? '$artist $title' : title;
    final uri = Uri.https(
        'genius.com', '/api/search/multi', {'per_page': '5', 'q': q});
    final res = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;

    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final response = data is Map ? data['response'] : null;
    final sections =
        (response is Map ? response['sections'] : null) as List? ?? const [];

    GeniusSong? best;
    var bestScore = 0.0;
    final seen = <String>{};
    for (final s in sections) {
      for (final h in (s as Map)['hits'] as List? ?? const []) {
        if (h is! Map || h['type'] != 'song') continue;
        final r = h['result'];
        if (r is! Map) continue;
        final url = r['url'] as String?;
        if (url == null || !seen.add(url)) continue;
        if (r['instrumental'] == true) continue;

        final rTitle = (r['title'] as String?) ?? '';
        final primary = r['primary_artist'];
        final rArtist = (primary is Map ? primary['name'] as String? : null) ??
            (r['artist_names'] as String?) ??
            '';
        var score = similar(title, rTitle) * 2;
        if (hasArtist) {
          score += similar(artist, rArtist) +
              similar(artist, (r['artist_names'] as String?) ?? '');
        } else {
          score += 1;
        }
        if (score > bestScore) {
          bestScore = score;
          final art = (r['song_art_image_url'] as String?) ??
              (r['header_image_url'] as String?);
          best = GeniusSong(
            title: rTitle,
            artist: rArtist,
            url: url,
            artUrl: (art == null || art.contains('default_cover')) ? null : art,
          );
        }
      }
    }
    // Порог: совпадение названия обязательно, исполнителя — желательно.
    final result = bestScore >= 2.6 ? best : null;
    _cache[key] = result;
    return result;
  }

  /// Текст песни со страницы Genius (без таймингов).
  Future<String?> fetchLyrics(GeniusSong song) async {
    final res = await _client
        .get(Uri.parse(song.url), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    return parseLyricsHtml(utf8.decode(res.bodyBytes, allowMalformed: true));
  }

  /// Достаёт текст из всех блоков data-lyrics-container на странице.
  static String? parseLyricsHtml(String html) {
    const marker = 'data-lyrics-container="true"';
    final parts = <String>[];
    var from = 0;
    while (true) {
      final m = html.indexOf(marker, from);
      if (m < 0) break;
      final open = html.indexOf('>', m);
      if (open < 0) break;
      final close = _matchingDivEnd(html, open + 1);
      if (close < 0) break;
      parts.add(html.substring(open + 1, close));
      from = close;
    }
    if (parts.isEmpty) return null;

    var text = parts.join('<br/>');
    // Служебные блоки внутри текста («N Contributors», «Read more»).
    text = _removeDivs(text, 'data-exclude-from-selection="true"');
    text = text
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    text = _decodeEntities(text);
    final lines = text.split('\n').map((l) => l.trimRight()).toList();
    // Сжимаем подряд идущие пустые строки.
    final out = <String>[];
    for (final l in lines) {
      if (l.trim().isEmpty && (out.isEmpty || out.last.trim().isEmpty)) continue;
      out.add(l.trim());
    }
    final result = out.join('\n').trim();
    return result.isEmpty ? null : result;
  }

  static int _matchingDivEnd(String html, int from) {
    var depth = 1;
    var i = from;
    final re = RegExp(r'<(/?)div\b', caseSensitive: false);
    while (depth > 0) {
      final m = re.firstMatch(html.substring(i));
      if (m == null) return -1;
      final pos = i + m.start;
      if (m.group(1) == '/') {
        depth--;
        if (depth == 0) return pos;
      } else {
        depth++;
      }
      i = pos + m.group(0)!.length;
    }
    return -1;
  }

  static String _removeDivs(String html, String attr) {
    while (true) {
      final a = html.indexOf(attr);
      if (a < 0) return html;
      final start = html.lastIndexOf('<div', a);
      final open = html.indexOf('>', a);
      if (start < 0 || open < 0) return html;
      final end = _matchingDivEnd(html, open + 1);
      if (end < 0) return html;
      final after = html.indexOf('>', end);
      html = html.substring(0, start) + html.substring(after + 1);
    }
  }

  static String _decodeEntities(String s) {
    s = s.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
    s = s.replaceAllMapped(RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!)));
    return s
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }

  // ---------- Сравнение строк ----------

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ')
      .replaceAll(RegExp(r'\b(feat|ft|featuring)\b.*'), ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  /// Похожесть 0..1: доля общих слов.
  static double similar(String a, String b) {
    final wa = _norm(a).split(' ').where((w) => w.isNotEmpty).toSet();
    final wb = _norm(b).split(' ').where((w) => w.isNotEmpty).toSet();
    if (wa.isEmpty || wb.isEmpty) return 0;
    final common = wa.intersection(wb).length;
    return common / (wa.length > wb.length ? wa.length : wb.length);
  }
}
