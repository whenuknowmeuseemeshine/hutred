import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hutred/models/track.dart';
import 'package:hutred/services/player_service.dart';
import 'package:hutred/services/soundcloud_source.dart';
import 'package:hutred/services/youtube_source.dart';
import 'package:hutred/ui/widgets/controls.dart';
import 'package:provider/provider.dart';

Track _track(String id) => Track(
      id: id,
      title: id,
      artist: 'Artist',
      source: TrackSource.spotify,
      uri: id,
      addedAt: DateTime(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PlayerService player;
  final first = _track('first');
  final second = _track('second');

  setUp(() {
    player = PlayerService(youtube: YoutubeSource(), soundcloud: SoundcloudSource());
  });

  tearDown(() => player.dispose());

  test('a second tap on the same row does not restart a pending load', () async {
    final pending = Completer<Track?>();
    final resolving = Completer<void>();
    var calls = 0;
    player.resolveSpotify = (_) {
      calls++;
      if (!resolving.isCompleted) resolving.complete();
      return pending.future;
    };

    final load = player.playTrackFromList([first]);
    await resolving.future;
    await player.playTrackFromList([first]);
    await player.playCurrent();
    expect(calls, 1);
    expect(player.pausePending, isFalse);
    pending.complete(null);
    await load;
  });

  test('a superseded load cannot overwrite the selected track error', () async {
    final pending = Completer<Track?>();
    final resolving = Completer<void>();
    player.resolveSpotify = (track) async {
      if (track.id == second.id) return null;
      resolving.complete();
      return pending.future;
    };

    final oldLoad = player.playTrackFromList([first, second]);
    await resolving.future;
    await player.playTrackFromList([first, second], start: 1);
    expect(player.error, contains('second'));
    pending.completeError(StateError('old failure'));
    await oldLoad;

    expect(player.current?.id, second.id);
    expect(player.error, contains('second'));
    expect(player.canRetry, isTrue);
    expect(player.playing, isFalse);
    expect(player.position, Duration.zero);
  });

  test('retry stays on the selected track and keeps its chosen position', () async {
    final attempts = <Track>[];
    player.resolveSpotify = (track) async {
      attempts.add(track);
      return null;
    };
    await player.playTrackFromList([first, second]);
    expect(player.canRetry, isTrue);

    const retryFrom = Duration(seconds: 22);
    await player.syncSeek(retryFrom);
    await player.retry();

    expect(attempts, [first, first]);
    expect(player.current?.id, first.id);
    expect(player.position, retryFrom);
    expect(player.playing, isFalse);
    expect(player.canRetry, isTrue);
  });

  test('background audio keeps publishing position while the window is inactive', () async {
    player.resolveSpotify = (_) async => null;
    await player.playTrackFromList([first]);

    final servicePositions = <Duration>[];
    final visualPositions = <Duration>[];
    final karaokePositions = <Duration>[];
    addTearDown(player.positionStream.listen(servicePositions.add).cancel);
    addTearDown(player.visualPositionStream.listen(visualPositions.add).cancel);
    addTearDown(player.smoothPositionStream.listen(karaokePositions.add).cancel);

    player.setVisualsActive(false);
    const backgroundPosition = Duration(seconds: 22);
    await player.syncSeek(backgroundPosition);
    expect(servicePositions, [backgroundPosition]);
    expect(visualPositions, isEmpty);
    expect(karaokePositions, isEmpty);

    player.setVisualsActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(servicePositions, [backgroundPosition]);
    expect(visualPositions, [backgroundPosition]);
    expect(karaokePositions, [backgroundPosition]);
  });

  testWidgets('speaker button mutes and restores the previous slider value', (tester) async {
    await tester.runAsync(() => player.setVolume(0.32));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: player,
      child: const MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: 220, child: VolumeSlider()))),
      ),
    ));

    await tester.tap(find.byTooltip('Выключить звук'));
    await tester.pump();
    expect(player.volume, 0);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);

    await tester.tap(find.byTooltip('Включить звук'));
    await tester.pump();
    expect(player.volume, 0.32);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0.32);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
