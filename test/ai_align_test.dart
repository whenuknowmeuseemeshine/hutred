import 'package:flutter_test/flutter_test.dart';
import 'package:hutred/services/ai_sync_service.dart';
import 'package:hutred/services/lyrics_service.dart';

void main() {
  test('Строки получают время по распознанным словам', () {
    final lyrics = Lyrics.parse('[Куплет]\nсолнце встаёт над рекой\nветер поёт за окном\nэто придуманный текст');
    Duration s(double x) => Duration(milliseconds: (x * 1000).round());
    final words = [
      HeardWord('солнце', s(10)), HeardWord('встает', s(10.5)),
      HeardWord('над', s(11)), HeardWord('рекой', s(11.4)),
      HeardWord('ветер', s(15)), HeardWord('поет', s(15.6)),
      HeardWord('за', s(16)), HeardWord('окном', s(16.3)),
      HeardWord('это', s(20)), HeardWord('придуманый', s(20.4)),
      HeardWord('текст', s(21)),
    ];
    final out = Lyrics.parse(AiSyncService.align(lyrics, words));
    expect(out.synced, isTrue);
    final byText = {for (final l in out.lines) l.text: l.time};
    expect(byText['солнце встаёт над рекой'], s(10));
    expect(byText['ветер поёт за окном'], s(15));
    expect(byText['это придуманный текст'], s(20));
  });
}
