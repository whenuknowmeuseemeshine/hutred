import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'services/account_service.dart';
import 'services/ai_sync_service.dart';
import 'services/cover_service.dart';
import 'services/desktop_tray.dart';
import 'services/dpi_bypass.dart';
import 'services/discord_presence.dart';
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
import 'services/update_service.dart';
import 'services/transfer_service.dart';
import 'services/wave_service.dart';
import 'services/youtube_source.dart';
import 'services/yt_dlp.dart';
import 'ui/home_shell.dart';
import 'ui/missing_file.dart';
import 'ui/spotify_check.dart';
import 'ui/theme.dart';
import 'ui/widgets/title_bar.dart';

/// Навигатор приложения — чтобы показывать диалоги из сервисов.
final hutredNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // На Windows и Linux звук идёт через media_kit (libmpv);
  // на Android, iOS и macOS just_audio использует системный плеер.
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true);

  // Обход блокировок: ставится до создания любых сетевых клиентов.
  await DpiBypass.install();
  final settings = SettingsStore();
  final store = LibraryStore();
  final account = AccountService(store: store, settings: settings);
  // Аккаунт решает, чью медиатеку открыть (без входа — локальную).
  await settings.load();
  DpiBypass.watchZapret(() => settings.dpiBypass);
  settings.addListener(() => DpiBypass.refresh(settings.dpiBypass));
  await account.init();
  // Админ поменял ключи Spotify/ИИ/Discord — они сразу уходят всем.
  Timer? keysDebounce;
  settings.addListener(() {
    keysDebounce?.cancel();
    keysDebounce = Timer(const Duration(seconds: 2), account.shareAdminKeys);
  });
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
  player.crossfadeSeconds = () => settings.crossfade ? settings.crossfadeSec : 0;
  player.fadeOnPause = () => settings.fadePause;

  final covers = CoverService(
    genius: genius,
    spotify: spotify,
    itunes: ItunesService(),
    soundcloud: soundcloud,
    store: store,
    settings: settings,
    player: player,
  );

  final wave = WaveService(store: store, player: player, soundcloud: soundcloud);
  await wave.load();
  // Умное перемешивание берёт похожие треки из «Моей волны».
  player.recommend = (seeds, count) => wave.recommendFrom(seeds, size: count);
  // Скрытые треки и исполнители из чёрного списка не играют.
  player.isBlocked = wave.isBlocked;
  // Не советовать то, что уже есть в медиатеке (в том числе с другой площадки).
  player.isDuplicate = wave.isOwnedLike;
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
  // Трей: крестик прячет окно, при автозапуске окно вообще не показываем.
  // Свой yt-dlp (Windows) раз в сутки обновляется в фоне.
  unawaited(getApplicationSupportDirectory().then(YtDlp.selfUpdate));
  await DesktopTray.init(
    player: player,
    settings: settings,
    startHidden: args.contains('--minimized'),
  );
  // Медиаклавиши Windows (Fn+F9 и т.п.) работают и при свёрнутом окне.
  if (!kIsWeb && Platform.isWindows) {
    const MethodChannel('hutred/media_keys').setMethodCallHandler((call) async {
      switch (call.method) {
        case 'playPause':
          await player.togglePlay();
        case 'next':
          await player.next();
        case 'previous':
          await player.previous();
        case 'stop':
          if (player.playing) await player.togglePlay();
      }
    });
  }
  // Автообновление (сборки из облака).
  final updates = UpdateService(settings: settings, player: player);
  await updates.start();
  // Файл трека переместили — спросим, где он теперь.
  MissingFiles(navigatorKey: hutredNavigatorKey, store: store, player: player);
  // Статус «Слушает Hutred» в Discord (на компьютере).
  DiscordPresence(player: player, settings: settings);
  final spotifyCheck = SpotifyCheck(
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
      Provider.value(value: spotifyCheck),
      ChangeNotifierProvider.value(value: updates),
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
      builder: (context, child) {
        if (!HutredTheme.desktop || !Platform.isWindows) return child!;
        // Приложение занимает всё окно, полоса лежит поверх него, а
        // содержимому сообщаем «отступ сверху», как для строки состояния.
        final mq = MediaQuery.of(context);
        const h = HutredTitleBar.height;
        return Stack(children: [
          MediaQuery(
            data: mq.copyWith(
              padding: mq.padding.copyWith(top: mq.padding.top + h),
              viewPadding: mq.viewPadding.copyWith(top: mq.viewPadding.top + h),
            ),
            child: child!,
          ),
          const Positioned(top: 0, left: 0, right: 0, child: HutredTitleBar()),
        ]);
      },
    );
  }
}
