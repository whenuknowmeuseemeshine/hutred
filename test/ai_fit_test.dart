import 'package:flutter_test/flutter_test.dart';
import 'package:hutred/services/ai_sync_service.dart';
import 'package:hutred/services/lyrics_service.dart';

void main() {
  test('Текст с таймингами сдвигается на общий сдвиг', () {
    // Придуманный текст; в «треке» всё звучит на 4 секунды позже.
    final lyrics = Lyrics.parse(
        '[00:05.00]первая строка про утро\n'
        '[00:09.00]вторая строка про город\n'
        '[00:13.00]третья строка про дорогу\n'
        '[00:17.00]четвертая строка про вечер');
    Duration s(double x) => Duration(milliseconds: (x * 1000).round());
    final words = <HeardWord>[];
    void say(String line, double at) {
      final parts = line.split(' ');
      for (var i = 0; i < parts.length; i++) {
        words.add(HeardWord(parts[i], s(at + i * 0.4)));
      }
    }

    say('первая строка про утро', 9);
    say('вторая строка про город', 13);
    say('третья строка про дорогу', 17);
    say('четвертая строка про вечер', 21);

    final fit = AiSyncService.fitTimings(lyrics, words);
    expect(fit, isNotNull);
    expect((fit!.shift.inMilliseconds - 4000).abs() < 100, isTrue);
    final out = Lyrics.parse(fit.lrc);
    expect((out.lines.first.time.inMilliseconds - 9000).abs() < 100, isTrue);
  });
}
