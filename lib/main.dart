import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';

import 'services/account_service.dart';
import 'services/ai_sync_service.dart';
import 'services/cover_service.dart';
import 'services/friends_service.dart';
import 'services/genius_service.dart';
import 'services/library_store.dart';
import 'services/offline_service.dart';
import 'services/lyrics_service.dart';
import 'services/player_service.dart';
import 'services/settings_store.dart';
import 'services/soundcloud_source.dart';
import 'services/spotify_service.dart';
import 'services/track_fixes.dart';
import 'services/transfer_service.dart';
import 'services/wave_service.dart';
import 'services/youtube_source.dart';
import 'ui/home_shell.dart';
import 'ui/spotify_check.dart';
import 'ui/theme.dart';

/// Навигатор приложения — чтобы показывать диалоги из сервисов.
final hutredNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // На Windows и Linux звук идёт через media_kit (libmpv);
  // на Android, iOS и macOS just_audio использует системный плеер.
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true);

  final settings = SettingsStore();
  final store = LibraryStore();
  final account = AccountService(store: store, settings: settings);
  // Аккаунт решает, чью медиатеку открыть (без входа — локальную).
  await Future.wait([settings.load(), account.init()]);
  // Добавленные треки сразу в любимые (можно выключить в настройках).
  store.autoFavorite = settings.autoFavorite;
  settings.addListener(() => store.autoFavorite = settings.autoFavorite);
  // Исправления треков от админа (текст, тайминги, сведения).
  final fixes = TrackFixes(account: account, store: store);
  await fixes.load();
  final friends = FriendsService(account: account);
  if (account.signedIn) friends.refresh();

  final youtube =
      YoutubeSource(cookiesBrowser: () => settings.youtubeCookiesBrowser);
  final genius = GeniusService();
  final spotify = SpotifyService();
  final soundcloud = SoundcloudSource();
  // late: колбэки ниже ссылаются на сам плеер.
  late final PlayerService player;
  player = PlayerService(
    youtube: youtube,
    soundcloud: soundcloud,
    onVolumeChanged: (v) => settings.volume = v,
    // Счётчик прослушиваний — по нему подстраивается «Моя волна».
    onStarted: (track) {
      final stored = store.byId(track.id);
      if (stored != null) store.updateTrack(stored.copyWith(plays: stored.plays + 1));
      // Если админ исправил этот трек — подтягиваем правку.
      fixes.check(track).then((fixed) {
        if (fixed != null) player.refreshTrack(fixed);
      });
    },
    // Длительность локальных файлов узнаём при первом проигрывании.
    onDurationKnown: (track, d) {
      final stored = store.byId(track.id);
      if (stored != null && stored.durationMs == null) {
        store.updateTrack(stored.copyWith(durationMs: d.inMilliseconds));
      }
    },
  );
  // Громкость с прошлого запуска.
  await player.setVolume(settings.volume, remember: false);

  final covers = CoverService(
    genius: genius,
    spotify: spotify,
    itunes: ItunesService(),
    store: store,
    settings: settings,
    player: player,
  );

  final wave = WaveService(store: store, player: player, soundcloud: soundcloud);
  await wave.load();
  // Умное перемешивание берёт похожие треки из «Моей волны».
  player.recommend = (seeds, count) => wave.recommendFrom(seeds, size: count);
  final transfer = TransferService(
    store: store,
    settings: settings,
    youtube: youtube,
    soundcloud: soundcloud,
    spotify: spotify,
  );
  // Треки из Spotify играют с SoundCloud/YouTube.
  player.resolveSpotify = transfer.resolveSpotify;
  // Загрузки: скачанное играет без интернета.
  final offline = OfflineService(store: store, youtube: youtube, soundcloud: soundcloud)
    ..resolveSpotify = transfer.resolveSpotify
    ..cloudFile = account.cloudFileFor;
  await offline.load();
  player.offlineAudio = offline.audioFor;
  player.isOffline = () => !offline.online;
  // Новые треки с YouTube/SoundCloud сверяем со Spotify (с вопросом).
  SpotifyCheck(
    navigatorKey: hutredNavigatorKey,
    store: store,
    settings: settings,
    spotify: spotify,
    player: player,
  );
  // Свои файлы: если на устройстве нет — качаем копию из облака.
  player.cloudFile = account.cloudFileFor;

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: store),
      ChangeNotifierProvider.value(value: account),
      ChangeNotifierProvider.value(value: friends),
      Provider.value(value: fixes),
      ChangeNotifierProvider.value(value: player),
      Provider.value(value: youtube),
      Provider.value(value: genius),
      Provider.value(value: spotify),
      Provider.value(value: soundcloud),
      ChangeNotifierProvider.value(value: wave),
      Provider.value(value: covers),
      ChangeNotifierProvider.value(value: transfer),
      ChangeNotifierProvider.value(value: offline),
      Provider(create: (_) => AiSyncService()),
      Provider(create: (_) => LyricsService(youtube: youtube, genius: genius)),
    ],
    child: const HutredApp(),
  ));
}

class HutredApp extends StatelessWidget {
  const HutredApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    return MaterialApp(
      title: 'Hutred',
      navigatorKey: hutredNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: HutredTheme.build(settings.accent, settings.background),
      themeAnimationDuration: const Duration(milliseconds: 250),
      home: const HomeShell(),
    );
  }
}
