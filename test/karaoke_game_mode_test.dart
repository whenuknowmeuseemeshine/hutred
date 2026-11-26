import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hutred/services/lyrics_service.dart';
import 'package:hutred/ui/widgets/lyrics_view.dart';

void main() {
  testWidgets('game mode keeps lyrics visible without subscribing to karaoke ticks',
      (tester) async {
    final position = StreamController<Duration>.broadcast();
    addTearDown(position.close);

    Widget view({required bool gameMode}) => MaterialApp(
          home: Scaffold(
            body: KaraokeView(
              lyrics: const Lyrics([
                LyricLine(Duration(seconds: 2), 'Первая строка'),
                LyricLine(Duration(seconds: 5), 'Вторая строка'),
              ], synced: true),
              gameMode: gameMode,
              position: position.stream,
              initialPosition: const Duration(seconds: 2),
              onSeek: (_) {},
            ),
          ),
        );

    await tester.pumpWidget(view(gameMode: false));
    expect(position.hasListener, isTrue);

    await tester.pumpWidget(view(gameMode: true));
    expect(find.text('Первая строка'), findsOneWidget);
    expect(find.text('Вторая строка'), findsOneWidget);
    expect(position.hasListener, isFalse);

    await tester.pumpWidget(view(gameMode: false));
    expect(position.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
