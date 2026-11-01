import 'package:flutter_test/flutter_test.dart';
import 'package:hutred/services/genius_service.dart';
import 'package:hutred/services/lyrics_service.dart';
import 'package:hutred/services/youtube_source.dart';

void main() {
  test('LRC разбирается и сортируется по времени', () {
    final l = Lyrics.parse('[ar:Кто-то]\n[00:05.50]Вторая\n[00:01.2][00:10.123]Повтор\n');
    expect(l.synced, isTrue);
    expect(l.lines.map((e) => e.text), ['Повтор', 'Вторая', 'Повтор']);
    expect(l.lines.first.time, const Duration(seconds: 1, milliseconds: 200));
    expect(l.lines.last.time, const Duration(seconds: 10, milliseconds: 123));
    expect(l.indexAt(const Duration(seconds: 6)), 1);
    expect(l.indexAt(Duration.zero), -1);
  });

  test('Обычный текст без таймингов', () {
    final l = Lyrics.parse('Строка один\nСтрока два');
    expect(l.synced, isFalse);
    expect(l.lines.length, 2);
  });

  test('Название с YouTube разделяется на исполнителя и трек', () {
    final r = YoutubeSource.splitTitle('Артист - Песня (Official Video)', 'ArtistVEVO');
    expect(r.artist, 'Артист');
    expect(r.title, 'Песня');
    final r2 = YoutubeSource.splitTitle('Blinding Lights', 'The Weeknd - Topic');
    expect(r2.artist, 'The Weeknd');
    final r3 = YoutubeSource.splitTitle('Артист -- Песня', 'Артист');
    expect(r3.title, 'Песня');
    expect(YoutubeSource.searchTitle('Песня (prod. Кто-то) feat. Другой'), 'Песня');
  });

  test('Текст со страницы Genius', () {
    const html = '<div class="x"><div data-lyrics-container="true" class="L">'
        '<div data-exclude-from-selection="true"><span>12 Contributors</span></div>'
        '[Куплет 1]<br/>Первая строка куплета<br><a href="#"><span>Вторая строка</span></a>'
        '</div></div><div data-lyrics-container="true">[Припев]<br/>Строка припева &amp; ещё</div>';
    final text = GeniusService.parseLyricsHtml(html);
    expect(text, '[Куплет 1]\nПервая строка куплета\nВторая строка\n[Припев]\nСтрока припева & ещё');
    final l = Lyrics.parse(text!);
    expect(l.synced, isFalse);
    expect(l.lines.first.text, '[Куплет 1]');
  });
}
