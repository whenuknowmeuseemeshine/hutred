import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/account_service.dart';
import '../services/offline_service.dart';
import '../services/update_service.dart';
import '../services/player_service.dart';
import '../services/settings_store.dart';
import 'screens/friends_screen.dart';
import 'screens/library_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/playlists_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/transfer_screen.dart';
import 'screens/wave_screen.dart';
import 'widgets/account_button.dart';
import 'widgets/blurred_background.dart';
import 'widgets/logo.dart';
import 'widgets/mini_player.dart';

/// Каркас приложения: на широком экране боковая панель, на телефоне — нижняя.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

/// Все вкладки. Порядок пользователь меняет в Настройках.
const navTabs = {
  'wave': (icon: Icons.waves_outlined, selected: Icons.waves, label: 'Волна'),
  'library': (icon: Icons.library_music_outlined, selected: Icons.library_music, label: 'Медиатека'),
  'search': (icon: Icons.search, selected: Icons.saved_search, label: 'Поиск'),
  'playlists': (icon: Icons.queue_music_outlined, selected: Icons.queue_music, label: 'Плейлисты'),
  'friends': (icon: Icons.people_outline, selected: Icons.people, label: 'Друзья'),
  'transfer': (icon: Icons.move_to_inbox_outlined, selected: Icons.move_to_inbox, label: 'Перенос'),
  'settings': (icon: Icons.settings_outlined, selected: Icons.settings, label: 'Настройки'),
};

class _HomeShellState extends State<HomeShell> {
  String? _tabId;
  final Map<String, GlobalKey<NavigatorState>> _navKeys = {
    for (final id in navTabs.keys) id: GlobalKey<NavigatorState>(),
  };

  static Widget _page(String id) => switch (id) {
        'wave' => const WaveScreen(),
        'library' => const LibraryScreen(),
        'search' => const SearchScreen(),
        'playlists' => const PlaylistsScreen(),
        'transfer' => const TransferScreen(),
        'friends' => const FriendsScreen(),
        _ => const SettingsScreen(),
      };

  List<String> get _order => context.read<SettingsStore>().navOrder;

  String get _current => _tabId ?? _order.first;

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
    final order = settings.navOrder;
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
        final banner = !context.watch<OfflineService>().online ||
            u.readyToInstall ||
            (u.available && !Platform.isWindows);
        final top = MediaQuery.paddingOf(context).top;
        final body = _KeyboardShortcuts(child: _stack(settings.waveBackground));
        return Column(
          children: [
            if (banner) SizedBox(height: top),
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

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: extended,
              selectedIndex: _tab,
              onDestinationSelected: _select,
              labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    _Logo(extended: extended),
                    const SizedBox(height: 12),
                    // Аккаунт — сразу под логотипом, чтобы не искать.
                    AccountButton(extended: extended),
                  ],
                ),
              ),
              destinations: [
                for (final id in order)
                  NavigationRailDestination(
                    icon: Icon(navTabs[id]!.icon),
                    selectedIcon: Icon(navTabs[id]!.selected),
                    label: Text(navTabs[id]!.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _select,
        height: 64,
        destinations: [
          for (final id in order)
            NavigationDestination(
              icon: Icon(navTabs[id]!.icon),
              selectedIcon: Icon(navTabs[id]!.selected),
              label: navTabs[id]!.label,
            ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.extended});
  final bool extended;

  @override
  Widget build(BuildContext context) {
    const mark = HutredLogo(size: 44);
    if (!extended) return mark;
    final name = context.watch<AccountService>().username;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 12),
        // У боковой панели нет ограничения по ширине — задаём его сами.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Hutred',
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              // Логин пользователя под названием.
              if (name != null)
                Text('@$name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
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
                      const Icon(Icons.cloud_off, size: 18),
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
                    const Icon(Icons.system_update_alt, size: 18),
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
