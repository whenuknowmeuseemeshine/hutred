import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/account_service.dart';
import '../services/friends_service.dart';
import '../services/jam_service.dart';
import '../services/offline_service.dart';
import '../services/update_service.dart';
import '../services/player_service.dart';
import '../services/settings_store.dart';
import 'screens/friends_screen.dart';
import 'screens/jam_screen.dart';
import 'screens/library_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/playlists_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/transfer_screen.dart';
import 'screens/wave_screen.dart';
import 'widgets/blurred_background.dart';
import 'widgets/mini_player.dart';
import 'shell_nav.dart';
import 'theme.dart';
import 'icons.dart';

/// Каркас приложения: на широком экране боковая панель, на телефоне — нижняя.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

/// Все вкладки. Порядок пользователь меняет в Настройках.
final navTabs = {
  'wave': (icon: Ic.waves, selected: Ic.waves, label: 'Волна'),
  'library': (icon: Ic.library_music_outlined, selected: Ic.library_music_outlined, label: 'Медиатека'),
  'search': (icon: Ic.search, selected: Ic.search, label: 'Поиск'),
  'playlists': (icon: Ic.queue_music, selected: Ic.queue_music, label: 'Плейлисты'),
  'jam': (icon: Ic.graphic_eq, selected: Ic.graphic_eq, label: 'Джем'),
  'friends': (icon: Ic.people_outline, selected: Ic.people_outline, label: 'Друзья'),
  'transfer': (icon: Ic.move_to_inbox_outlined, selected: Ic.move_to_inbox_outlined, label: 'Перенос'),
  'settings': (icon: Ic.settings_outlined, selected: Ic.settings_outlined, label: 'Настройки'),
};

class _HomeShellState extends State<HomeShell> {
  String? _tabId;
  final Map<String, GlobalKey<NavigatorState>> _navKeys = {
    for (final id in navTabs.keys) id: GlobalKey<NavigatorState>(),
  };

  static Widget _page(String id) => navPage(id);

  StreamSubscription<JamInvite>? _inviteSub;
  StreamSubscription<FriendInfo>? _requestSub;

  @override
  void initState() {
    super.initState();
    // Новая заявка в друзья — всплывающим сообщением с кнопкой «Принять».
    _requestSub = context.read<FriendsService>().newRequests.listen((f) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 15),
        content: Text('${f.name} хочет добавить тебя в друзья'),
        action: SnackBarAction(
          label: 'Принять',
          onPressed: () => context.read<FriendsService>().accept(f),
        ),
      ));
    });
    // Приглашения в джем — всплывающим сообщением с кнопкой «Войти».
    _inviteSub = context.read<JamService>().invites.listen((inv) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 20),
        content: Text('${inv.fromName} зовёт тебя в джем'),
        action: SnackBarAction(
          label: 'Войти',
          onPressed: () async {
            try {
              await context.read<JamService>().join(inv.host);
              if (mounted) _openJam();
            } catch (_) {}
          },
        ),
      ));
    });
  }

  @override
  void dispose() {
    _requestSub?.cancel();
    _inviteSub?.cancel();
    super.dispose();
  }

  /// Джем: своя вкладка, а если её скрыли — открываем поверх текущей.
  void _openJam() {
    if (_order.contains('jam')) {
      setState(() => _tabId = 'jam');
    } else {
      _navKeys[_current]!.currentState?.push(MaterialPageRoute(builder: (_) => const JamScreen()));
    }
  }

  List<String> get _order => context.read<SettingsStore>().visibleNav;

  String get _current {
    final id = _tabId;
    // Вкладку скрыли, пока она была открыта, — возвращаемся на первую.
    return id != null && _order.contains(id) ? id : _order.first;
  }

  int get _tab {
    final i = _order.indexOf(_current);
    return i < 0 ? 0 : i;
  }

  void _select(int i) {
    final id = _order[i];
    if (id == _current) {
      // Повторное нажатие на вкладку возвращает к её началу.
      _navKeys[id]!.currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _tabId = id);
    }
  }

  Widget _stack(String? bg) {
    final order = _order;
    return IndexedStack(
      index: _tab,
      children: [
        for (final id in order)
          _TabBackground(
            // На «Волне» свой, чёткий фон; на остальных — размытый.
            imagePath: id == 'wave' ? null : bg,
            child: Navigator(
              key: _navKeys[id],
              onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _page(id)),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final order = settings.visibleNav;
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final extended = MediaQuery.sizeOf(context).width >= 1150;

    final body = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _navKeys[_current]!.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (_tab != 0) {
          setState(() => _tabId = order.first);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Builder(builder: (context) {
        // Полоски сверху не должны залезать под кнопки окна: если хоть одна
        // показана, отступ сверху берут они, а содержимое под ними — без отступа.
        final u = context.watch<UpdateService>();
        final inJam = context.watch<JamService>().active;
        final banner = inJam ||
            !context.watch<OfflineService>().online ||
            u.readyToInstall ||
            (u.available && !Platform.isWindows);
        final top = MediaQuery.paddingOf(context).top;
        final body = _KeyboardShortcuts(child: _stack(settings.waveBackground));
        return Column(
          children: [
            if (banner) SizedBox(height: top),
            if (inJam) _JamBanner(onTap: _openJam),
            const _OfflineBanner(),
            const _UpdateBanner(),
            Expanded(
              child: banner
                  ? MediaQuery.removePadding(context: context, removeTop: true, child: body)
                  : body,
            ),
          ],
        );
      }),
    );

    final style = HutredStyle.of(context);
    final items = <NavItem>[
      for (final id in order)
        (
          id: id,
          icon: navTabs[id]!.icon,
          label: navTabs[id]!.label,
          badge: id == 'friends' ? context.watch<FriendsService>().incoming.length : 0,
        ),
    ];
    void onSelect(String id) => _select(order.indexOf(id));

    if (wide) {
      // Три раскладки по макетам: A — боковая панель, B — стеклянные панели,
      // C — меню сверху.
      if (style.glass) {
        return Scaffold(
          body: Padding(
            padding: EdgeInsets.fromLTRB(12, MediaQuery.paddingOf(context).top + 4, 12, 12),
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: Row(
                children: [
                  GlassRail(items: items, selected: _current, onSelect: onSelect),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: GlassPanel(child: body)),
                        const MiniPlayer(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (style.sharp) {
        return Scaffold(
          body: Column(
            children: [
              SharpTopNav(items: items, selected: _current, onSelect: onSelect),
              Expanded(
                child: MediaQuery.removePadding(
                    context: context, removeTop: true, child: body),
              ),
              const MiniPlayer(),
            ],
          ),
        );
      }
      return Scaffold(
        body: Row(
          children: [
            MonoSidebar(
              items: items,
              selected: _current,
              onSelect: onSelect,
              compact: !extended,
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: body),
                  const MiniPlayer(),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          Expanded(child: body),
          const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: PhoneNav(items: items, selected: _current, onSelect: onSelect),
    );
  }
}

/// Горячие клавиши на десктопе: Ctrl+Пробел — пауза, Ctrl+→/← — треки,
/// Ctrl+L — открыть плеер с текстом.
class _KeyboardShortcuts extends StatelessWidget {
  const _KeyboardShortcuts({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerService>();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space, control: true): player.togglePlay,
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): player.togglePlay,
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): player.next,
        const SingleActivator(LogicalKeyboardKey.mediaTrackNext): player.next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): player.previous,
        const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): player.previous,
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () {
          if (player.current != null) NowPlayingScreen.open(context);
        },
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

/// Размытый свой фон под вкладкой: страницы и шапки становятся прозрачными.
class _TabBackground extends StatelessWidget {
  const _TabBackground({required this.imagePath, required this.child});
  final String? imagePath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (imagePath == null) return child;
    final theme = Theme.of(context);
    return BlurredBackground(
      imagePath: imagePath,
      child: Theme(
        data: theme.copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          appBarTheme: theme.appBarTheme.copyWith(backgroundColor: Colors.transparent),
        ),
        child: child,
      ),
    );
  }
}


/// Полоска «Джем»: с кем слушаешь, нажатие открывает экран джема.
class _JamBanner extends StatelessWidget {
  const _JamBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final jam = context.watch<JamService>();
    final others = jam.members.where((m) => m.uid != context.read<AccountService>().user?.id);
    final who = others.isEmpty
        ? 'пока никого — позови друзей'
        : others.map((m) => m.name).take(3).join(', ');
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Color.alphaBlend(scheme.primary.withValues(alpha: 0.18), scheme.surface),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Icon(Ic.graphic_eq_rounded, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Джем: $who',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            Icon(Ic.chevron_right, size: 18),
          ]),
        ),
      ),
    );
  }
}

/// Полоска «Нет интернета», пока связи нет.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final off = context.watch<OfflineService>();
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: off.online
          ? const SizedBox(width: double.infinity)
          : Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: InkWell(
                onTap: off.checkOnline,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Ic.cloud_off, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Нет интернета — играют скачанные треки (${off.count}). '
                          'Нажми, чтобы проверить снова.',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// Полоска «Вышла новая версия» (Android) или «Новая версия скачана» (Windows).
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner();

  @override
  Widget build(BuildContext context) {
    final u = context.watch<UpdateService>();
    final show = u.readyToInstall || (u.available && !Platform.isWindows);
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: !show
          ? const SizedBox(width: double.infinity)
          : Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    Icon(Ic.system_update_alt, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        u.readyToInstall
                            ? 'Новая версия Hutred скачана'
                            : Platform.isIOS
                                ? 'Вышла новая версия Hutred — обнови в SideStore'
                                : 'Вышла новая версия Hutred',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: u.updateNow,
                      child: Text(u.readyToInstall
                          ? 'Перезапустить'
                          : Platform.isIOS
                              ? 'Открыть'
                              : 'Скачать'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Экран вкладки (его можно открыть и из Настроек, если вкладка скрыта).
Widget navPage(String id) => switch (id) {
      'wave' => const WaveScreen(),
      'library' => const LibraryScreen(),
      'search' => const SearchScreen(),
      'playlists' => const PlaylistsScreen(),
      'transfer' => const TransferScreen(),
      'friends' => const FriendsScreen(),
      'jam' => const JamScreen(),
      _ => const SettingsScreen(),
    };
