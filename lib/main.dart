import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/xray_vpn.dart';
import 'services/jam_service.dart';
import 'services/relay.dart';
import 'services/account_service.dart';
import 'services/ai_sync_service.dart';
import 'services/cover_service.dart';
import 'services/desktop_tray.dart';
import 'services/dpi_bypass.dart';
import 'services/discord_presence.dart';
import 'services/friends_service.dart';
import 'services/genius_service.dart';
import 'services/duration_probe.dart';
import 'services/library_store.dart';
import 'services/media_session.dart';
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
import 'ui/widgets/glass_backdrop.dart';
import 'ui/home_shell.dart';
import 'ui/icons.dart';
import 'ui/missing_file.dart';
import 'ui/spotify_check.dart';
import 'ui/theme.dart';
import 'ui/welcome.dart';
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
  // Набор значков — по стилю, выбранному при запуске.
  Ic.style = settings.style;
  DpiBypass.splitHello = !settings.dnsOnly;
  DpiBypass.strategy = settings.dpiStrategy ?? 'split';
  if (settings.dpiStrategy != null) {
    DpiBypass.status.value = 'Способ: ${DpiBypass.strategyLabel(settings.dpiStrategy!)}';
  }
  DpiBypass.watchZapret(() => settings.dpiBypass);
  // Способ обхода подбирается сам: при первом включении и раз в неделю
  // (провайдеры меняют настройки блокировок).
  final tuned = settings.dpiTunedAt;
  // Свой VPN-ключ: поднимаем ядро Xray в фоне, музыка пока идёт напрямую.
  XrayVpn.hwid = settings.vpnHwid;
  if (settings.vpnOn && settings.vpnServers.isNotEmpty && XrayVpn.supported) {
    final i = settings.vpnIndex.clamp(0, settings.vpnServers.length - 1);
    final s = XrayVpn.parse(settings.vpnServers[i]);
    if (s != null) unawaited(XrayVpn.start(s));
  }
  if (settings.dpiBypass &&
      !settings.vpnOn &&
      !settings.dnsOnly &&
      (tuned == null || DateTime.now().difference(tuned) > const Duration(days: 7))) {
    unawaited(Future<void>.delayed(const Duration(seconds: 8), () async {
      if (!DpiBypass.enabled) return;
      settings.setDpiStrategy(await DpiBypass.autotune());
    }));
  }
  settings.addListener(() {
    DpiBypass.splitHello = !settings.dnsOnly;
    DpiBypass.refresh(settings.dpiBypass);
  });
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
  // Эквалайзер (Android).
  unawaited(player.setEqualizer(settings.eqOn, settings.eqGains));
  // Трек в шторке Android и в «Исполняется» на iPhone.
  await MediaSession.init(player);
  // Последний трек и место в нём — с прошлого запуска (на паузе).
  unawaited(getApplicationSupportDirectory().then((d) => player
      .restoreState(File('${d.path}${Platform.pathSeparator}player_state.json'))));

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
  player.blockedArtist = wave.blockedArtistOf;
  // Сервер-посредник: для тех, у кого музыкальные сервисы заблокированы.
  HutredRelay.mode = () => settings.relayMode;
  HutredRelay.token = () {
    try {
      return account.user == null
          ? null
          : Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  };
  // Джем: слушать вместе с друзьями.
  final jam = JamService(account: account, player: player, store: store, wave: wave)
    ..shareOnline = (() => settings.shareOnline);
  // Заявка в друзья: друг узнаёт сразу, а не через минуту.
  friends.onRequestSent = jam.pingFriendRequest;
  jam.friendRequests.listen((_) => friends.refresh(quiet: true));
  // Длительность своих файлов, у которых её нет.
  DurationProbe(store);
  // Любимые = вся медиатека (как в Spotify): один раз ставим ♥ всем трекам.
  if (!settings.likesMigrated) {
    store.likeEverything();
    settings.likesMigrated = true;
  }
  // Сняли ♥ — трек уходит из медиатеки, но его можно вернуть.
  store.onUnliked = (t, undo) {
    hutredMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('«${t.title}» убран из медиатеки'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: 'Вернуть', onPressed: undo),
      ));
  };
  // Ошибки плеера (не играет трек, исполнитель в чёрном списке) — внизу экрана.
  String? lastPlayerError;
  player.addListener(() {
    final e = player.error;
    if (e != null && e != lastPlayerError) {
      hutredMessengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e), duration: const Duration(seconds: 5)));
    }
    lastPlayerError = e;
  });
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
  // В джеме трек из файла хозяина гости слушают онлайн-копию.
  jam.findOnline = transfer.findPlayable;
  // Загрузки: скачанное играет без интернета.
  final offline = OfflineService(store: store, youtube: youtube, soundcloud: soundcloud)
    ..resolveSpotify = transfer.resolveSpotify
    ..cloudFile = account.cloudFileFor;
  offline.wifiOnly = () => settings.wifiOnly;
  await offline.load();
  // Качество звука и лимит кэша — из настроек, меняются на лету.
  void applyAudioPrefs() {
    LyricsService.order = settings.lyricsOrder;
    YoutubeSource.quality = settings.audioQuality;
    YoutubeSource.cacheLimitBytes = settings.cacheLimitMb * 1024 * 1024;
  }
  applyAudioPrefs();
  settings.addListener(applyAudioPrefs);
  // После каждого нового трека подрезаем кэш до лимита.
  String? lastTrimmed;
  player.addListener(() {
    final id = player.current?.id;
    if (id == null || id == lastTrimmed || YoutubeSource.cacheLimitBytes <= 0) return;
    lastTrimmed = id;
    unawaited(() async {
      await YoutubeSource.trimCaches(
          [await YoutubeSource.cacheDir(), await SoundcloudSource.cacheDir()]);
    }());
  });
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
      ChangeNotifierProvider.value(value: jam),
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

/// Для сообщений внизу экрана из любого места (например, из плеера).
final hutredMessengerKey = GlobalKey<ScaffoldMessengerState>();

class HutredApp extends StatelessWidget {
  const HutredApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    return MaterialApp(
      title: 'Hutred',
      navigatorKey: hutredNavigatorKey,
      scaffoldMessengerKey: hutredMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: HutredTheme.build(settings.accent, settings.background, settings.style),
      themeAnimationDuration: const Duration(milliseconds: 250),
      home: const _Gate(),
      builder: (context, child) {
        if (settings.style == 'glass') {
          child = GlassBackdrop(
              accent: settings.accent, ink: settings.background.ink, child: child!);
        }
        if (HutredTheme.desktop) child = _UiScale(scale: settings.uiScale, child: child!);
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


/// На большом окне (во весь экран на широком мониторе) всё становится
/// крупнее, чтобы не оставалось пустых полей. [scale] 0 — по ширине окна.
class _UiScale extends StatelessWidget {
  const _UiScale({required this.scale, required this.child});
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final mq = MediaQuery.of(context);
      // Авто: по ширине и высоте окна, чтобы во весь экран на большом
      // мониторе интерфейс заполнял его, а не терялся посередине.
      final auto = [box.maxWidth / 1440, box.maxHeight / 840].reduce((a, b) => a < b ? a : b);
      final s = scale > 0 ? scale : auto.clamp(1.0, 1.6).toDouble();
      if ((s - 1).abs() < 0.01 || !box.hasBoundedWidth || !box.hasBoundedHeight) return child;
      final size = Size(box.maxWidth / s, box.maxHeight / s);
      return MediaQuery(
        data: mq.copyWith(
          size: size,
          devicePixelRatio: mq.devicePixelRatio * s,
          padding: mq.padding / s,
          viewPadding: mq.viewPadding / s,
          viewInsets: mq.viewInsets / s,
        ),
        // Рамка ровно во всё окно: иначе при свободных ограничениях
        // FittedBox сжимается до размера содержимого и справа/снизу
        // остаётся чёрная полоса.
        child: SizedBox(
          width: box.maxWidth,
          height: box.maxHeight,
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(size: size, child: child),
          ),
        ),
      );
    });
  }
}

/// Что показать при запуске: вход → «кого слушаешь» → само приложение.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccountService>();
    final settings = context.watch<SettingsStore>();
    if (acc.enabled && !acc.signedIn && !settings.guest) return const WelcomeScreen();
    if (acc.signedIn && settings.pickTheme) return const ThemePickerScreen();
    if (acc.signedIn && settings.pickArtists) return const ArtistPickerScreen();
    return const HomeShell();
  }
}
