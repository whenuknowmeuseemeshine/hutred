/// Чистка «грязных» названий треков и нечёткое сравнение слов.
///
/// «Автостопом по фазе сн Я умру в Североморске audiovk com»
///   → «Автостопом по фазе сн Я умру в Североморске»,
/// а слово «сн» считается совпадением со «сна».
class MetaClean {
  static final _junk = RegExp(
    // Адреса сайтов: «audiovk.com», «www.site.ru».
    r'\b(?:www\.)?[a-z0-9-]+\.(?:com|net|ru|org|su|fm|cc|io|biz|info)\b'
    // Известные сайты-качалки, в том числе без точки: «audiovk com».
    r'|\b(?:audiovk|vkmusic|vk|muzofond|zaycev|hitmo|mp3party|musify|rocknation|'
    r'lightaudio|drivemusic|mp3xa|muzmo)\s*(?:com|net|ru|su|me|fm|org)?\b'
    r'|\b(?:mp3|320\s?kbps|skachat|скачать|бесплатно)\b'
    r'|[\(\[][^\)\]]*(?:official|video|audio|lyric|lyrics|mv|hd|4k|visuali[sz]er|клип|'
    r'премьера|текст|prod\.?|prod by|bass boost|slowed|reverb|speed up|sped up)[^\)\]]*[\)\]]',
    caseSensitive: false,
  );

  /// Убирает адреса сайтов, «mp3», «(Official Video)» и прочий мусор.
  static String clean(String s) => s
      .replaceAll(_junk, ' ')
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+[-–—|]\s*$'), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  static String norm(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  static List<String> words(String s) =>
      norm(s).split(' ').where((w) => w.isNotEmpty).toList();

  /// Слова похожи: совпадают, одно — начало другого («сн» → «сна»),
  /// или отличаются одной буквой (опечатка) у длинных слов.
  static bool wordLike(String a, String b) {
    if (a == b) return true;
    final short = a.length <= b.length ? a : b;
    final long = a.length <= b.length ? b : a;
    if (short.length >= 2 && long.startsWith(short)) return true;
    if (short.length >= 4 && (long.length - short.length) <= 1) {
      return _oneEdit(short, long);
    }
    return false;
  }

  static bool _oneEdit(String a, String b) {
    var i = 0, j = 0, edits = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      if (a.length == b.length) {
        i++;
        j++;
      } else {
        j++;
      }
    }
    return edits + (b.length - j) + (a.length - i) <= 1;
  }

  /// Какая доля слов [a] нашлась (нечётко) в [b], 0..1.
  static double fuzzy(String a, String b) {
    final wa = words(a), wb = words(b);
    if (wa.isEmpty || wb.isEmpty) return 0;
    var hit = 0;
    for (final w in wa) {
      if (wb.any((x) => wordLike(w, x))) hit++;
    }
    return hit / wa.length;
  }

  /// Варианты запроса от точного к общему: целиком, первые слова, только исполнитель.
  static List<({String artist, String title})> variants(String artist, String title) {
    final a = clean(artist);
    var t = clean(title);
    final unknown = a.isEmpty || a.toLowerCase().contains('неизвестн');
    final out = <({String artist, String title})>[];
    void add(String ar, String ti) {
      if (ti.trim().isEmpty && ar.trim().isEmpty) return;
      final v = (artist: ar.trim(), title: ti.trim());
      if (!out.contains(v)) out.add(v);
    }

    add(unknown ? '' : a, t);
    final tw = t.split(' ');
    if (tw.length > 3) add(unknown ? '' : a, tw.take(3).join(' '));
    // Название целиком вида «Исполнитель Название» без разделителя:
    // пробуем первые 2–4 слова как исполнителя.
    if (unknown && tw.length >= 3) {
      for (var n = 2; n <= 4 && n < tw.length; n++) {
        add(tw.take(n).join(' '), tw.skip(n).join(' '));
      }
    }
    return out;
  }
}
