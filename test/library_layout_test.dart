import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hutred/models/track.dart';
import 'package:hutred/services/account_service.dart';
import 'package:hutred/services/library_store.dart';
import 'package:hutred/services/offline_service.dart';
import 'package:hutred/services/player_service.dart';
import 'package:hutred/services/releases_service.dart';
import 'package:hutred/services/settings_store.dart';
import 'package:hutred/services/soundcloud_source.dart';
import 'package:hutred/services/wave_service.dart';
import 'package:hutred/services/youtube_source.dart';
import 'package:hutred/ui/screens/library_screen.dart';
import 'package:hutred/ui/theme.dart';
import 'package:hutred/ui/widgets/style_bits.dart';
import 'package:provider/provider.dart';

class _SpotifySettings extends SettingsStore {
  @override
  bool get hasSpotifyKeys => true;
}

void main() {
  testWidgets('library actions remain available in a narrow window and on a phone', (tester) async {
    final settings = _SpotifySettings();
    final store = LibraryStore();
    final account = AccountService(store: store);
    final soundcloud = SoundcloudSource();
    final youtube = YoutubeSource();
    final player = PlayerService(youtube: youtube, soundcloud: soundcloud);
    final wave = WaveService(store: store, player: player, soundcloud: soundcloud);
    final offline = OfflineService(store: store, youtube: youtube, soundcloud: soundcloud);
    final releases = ReleasesService(wave: wave);
    addTearDown(() {
      releases.dispose();
      offline.dispose();
      wave.dispose();
      player.dispose();
      account.dispose();
      store.dispose();
      settings.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    store.addTracks([
      for (final source in [TrackSource.local, TrackSource.youtube])
        Track(id: source.name, title: source.name, artist: 'Artist', source: source,
            uri: source.name, addedAt: DateTime(2026), favorite: true, plays: 2),
    ]);
    tester.view.devicePixelRatio = 1;

    Future<void> show(double windowWidth, double panelWidth, String style) async {
      tester.view.physicalSize = Size(windowWidth, 720);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsStore>.value(value: settings),
          ChangeNotifierProvider.value(value: store),
          ChangeNotifierProvider.value(value: account),
          ChangeNotifierProvider.value(value: player),
          ChangeNotifierProvider.value(value: wave),
          ChangeNotifierProvider.value(value: offline),
          ChangeNotifierProvider.value(value: releases),
        ],
        child: MaterialApp(
          theme: HutredTheme.build(settings.accent, settings.background, style),
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.35)),
            child: child!,
          ),
          home: Center(child: SizedBox(width: panelWidth, child: LibraryScreen(key: ValueKey(style)))),
        ),
      ));
      await tester.pump();
    }

    await show(800, 688, 'mono');
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(TextField).first).width, greaterThan(100));
    expect(find.text('Добавить').hitTestable(), findsOneWidget);

    await show(1440, 1328, 'mono');
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.widgetWithText(StyleButton, 'Добавить')).right,
        greaterThan(1320));

    await show(320, 320, 'sharp');
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Откуда трек').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Выбрать несколько'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Выбрать все'));
    await tester.pump();
    expect(find.text('Выбрано: 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Действия с выбранными треками'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Добавить в плейлист').hitTestable(), findsOneWidget);
    expect(find.text('Удалить из медиатеки').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a labeled action fits in a narrow card', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 140,
            child: StyleButton(label: 'Джем по исполнителю', icon: Icons.music_note, onPressed: () {}),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Джем по исполнителю').hitTestable(), findsOneWidget);
  });
}
