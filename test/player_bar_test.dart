import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hutred/models/track.dart';
import 'package:hutred/services/account_service.dart';
import 'package:hutred/services/device_sync.dart';
import 'package:hutred/services/library_store.dart';
import 'package:hutred/services/player_service.dart';
import 'package:hutred/services/settings_store.dart';
import 'package:hutred/services/soundcloud_source.dart';
import 'package:hutred/services/wave_service.dart';
import 'package:hutred/services/youtube_source.dart';
import 'package:hutred/ui/theme.dart';
import 'package:hutred/ui/widgets/controls.dart';
import 'package:hutred/ui/widgets/mini_player.dart';
import 'package:provider/provider.dart';

class _ConnectedDevices extends DeviceSync {
  _ConnectedDevices({required super.account, required super.player});

  @override
  bool get online => true;
}

void main() {
  testWidgets('desktop player fits all controls from the minimum width', (tester) async {
    final settings = SettingsStore();
    final store = LibraryStore();
    final account = AccountService(store: store);
    final soundcloud = SoundcloudSource();
    final player = PlayerService(youtube: YoutubeSource(), soundcloud: soundcloud);
    final devices = _ConnectedDevices(account: account, player: player);
    final wave = WaveService(store: store, player: player, soundcloud: soundcloud);
    addTearDown(() {
      devices.dispose();
      player.dispose();
      wave.dispose();
      account.dispose();
      store.dispose();
      settings.dispose();
    });
    final track = Track(
      id: 'fixture',
      title: 'Hate everything about you',
      artist: 'AQUAKEY',
      source: TrackSource.local,
      uri: 'fixture',
      addedAt: DateTime(2026),
    );

    for (final style in ['mono', 'glass', 'sharp']) {
      // At an 800 px window the glass rail and its margins leave 688 px.
      for (final width in [688.0, 800.0, 1020.0, 1440.0, 1920.0]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 600);
        final bar = PlayerBar(track: track);
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: store),
            ChangeNotifierProvider.value(value: player),
            ChangeNotifierProvider<DeviceSync>.value(value: devices),
            ChangeNotifierProvider.value(value: wave),
          ],
          child: MaterialApp(
            theme: HutredTheme.build(settings.accent, settings.background, style),
            themeAnimationDuration: Duration.zero,
            home: Scaffold(body: Center(child: bar)),
          ),
        ));
        expect(tester.takeException(), isNull, reason: '$style at $width');
        final mute = tester.getRect(find.byTooltip('Выключить звук'));
        expect(mute.right, lessThan(width));
        final volumeSlider = find.descendant(
          of: find.byType(VolumeSlider), matching: find.byType(Slider),
        );
        final volume = tester.getRect(volumeSlider);
        expect(volume.right, lessThanOrEqualTo(width));
        expect(volume.width, greaterThanOrEqualTo(52), reason: '$style at $width');
        final seek = tester.getRect(find.byType(SeekBar));
        expect(seek.center.dx, closeTo(width / 2, 1));
        expect(seek.width, lessThanOrEqualTo(560));
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
