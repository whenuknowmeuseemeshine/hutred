import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/library_store.dart';
import '../../services/player_service.dart';
import '../../services/settings_store.dart';
import '../../services/wave_service.dart';
import 'artist_screen.dart';
import '../widgets/artwork.dart';
import '../widgets/controls.dart';
import '../widgets/cover_color.dart';
import '../widgets/like_buttons.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';

/// Полноэкранный плеер: обложка, текст-караоке и очередь.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, __, ___) => const NowPlayingScreen(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final store = context.watch<LibraryStore>();
    final current = player.current;
    if (current == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Ничего не играет')),
      );
    }
    final track = store.byId(current.id) ?? current;
    final settings = context.watch<SettingsStore>();
    final ink = Theme.of(context).scaffoldBackgroundColor;

    Widget page(Color tint) => Scaffold(
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(tint.withValues(alpha: 0.85), ink),
                  Color.alphaBlend(tint.withValues(alpha: 0.35), ink),
                  ink,
                ],
                stops: const [0, 0.5, 1],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, box) => box.maxWidth >= 900
                    ? const _WideLayout()
                    : _NarrowLayout(tint: tint),
              ),
            ),
          ),
        );

    // Фон — из цвета обложки, как в больших стриминговых плеерах.
    if (!settings.tintFromCover) return page(Theme.of(context).colorScheme.primary);
    return CoverColorBuilder(track: track, builder: (context, c) => page(c));
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final track = player.current!;
    return Row(
      children: [
        IconButton(
          tooltip: 'Свернуть',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
        ),
        Expanded(
          child: Text(
            'ИСТОЧНИК: ${sourceLabel(track.source).toUpperCase()}',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 11, letterSpacing: 1.2, color: Colors.white70),
          ),
        ),
        if (context.watch<WaveService>().isWaveTrack(track))
          IconButton(
            tooltip: 'Не нравится',
            onPressed: () => context.read<WaveService>().dislike(track),
            icon: const Icon(Icons.thumb_down_alt_outlined),
          ),
        TrackMenuButton(track: track),
      ],
    );
  }
}

/// Название, исполнитель и сердечко.
class _TitleRow extends StatelessWidget {
  const _TitleRow();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final store = context.watch<LibraryStore>();
    final track = store.byId(player.current!.id) ?? player.current!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4)),
                const SizedBox(height: 4),
                _ArtistLink(artist: track.artist),
              ],
            ),
          ),
          LikeButtons(track: track, size: 28),
        ],
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine();

  @override
  Widget build(BuildContext context) {
    final error = context.select<PlayerService, String?>((p) => p.error);
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Text(error,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Theme.of(context).colorScheme.error)),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final store = context.watch<LibraryStore>();
    final track = store.byId(player.current!.id) ?? player.current!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 440),
          child: AnimatedScale(
            scale: player.playing ? 1 : 0.9,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black54,
                      blurRadius: 40,
                      offset: Offset(0, 16)),
                ],
              ),
              child: Hero(
                tag: 'artwork',
                child: Artwork(track: track, radius: 10),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Телефон: всё на одной прокручиваемой странице — обложка, управление,
/// ниже карточка с текстом и «Далее в очереди».
class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({required this.tint});
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final track = player.current!;
    final card = HSLColor.fromColor(tint)
        .withLightness((HSLColor.fromColor(tint).lightness * 0.85).clamp(0.2, 0.4))
        .toColor();
    return Column(
      children: [
        const _TopBar(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const _Cover(),
              const _TitleRow(),
              const _ErrorLine(),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SeekBar(),
              ),
              const TransportControls(),
              const SizedBox(height: 24),
              _LyricsCard(track: track, color: card),
              const SizedBox(height: 16),
              _UpNextCard(color: card),
            ],
          ),
        ),
      ],
    );
  }
}

/// Карточка с текстом под управлением; «Развернуть» — текст на весь экран.
class _LyricsCard extends StatelessWidget {
  const _LyricsCard({required this.track, required this.color});
  final Track track;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
              child: Row(
                children: [
                  const Text('Текст',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => LyricsPage.open(context, color),
                    icon: const Icon(Icons.open_in_full, size: 16),
                    label: const Text('Развернуть'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                  ),
                ],
              ),
            ),
            SizedBox(height: 360, child: LyricsPanel(track: track)),
          ],
        ),
      ),
    );
  }
}

/// Следующие треки очереди.
class _UpNextCard extends StatelessWidget {
  const _UpNextCard({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final next = player.queue.skip(player.index + 1).take(3).toList();
    if (next.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: color.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
              child: Row(
                children: [
                  const Text('Далее в очереди',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Очередь')),
                        body: const QueueList(),
                      ),
                    )),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Вся очередь'),
                  ),
                ],
              ),
            ),
            for (var k = 0; k < next.length; k++)
              ListTile(
                dense: true,
                onTap: () => player.jumpTo(player.index + 1 + k),
                leading: Artwork(track: next[k], size: 40, radius: 4),
                title: Text(next[k].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(next[k].artist,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Текст песни на весь экран, на цвете обложки, с управлением внизу.
class LyricsPage extends StatelessWidget {
  const LyricsPage({super.key, required this.color});
  final Color color;

  static Future<void> open(BuildContext context, Color color) =>
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        builder: (_) => LyricsPage(color: color),
      ));

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final track = player.current;
    if (track == null) return const Scaffold();
    return Scaffold(
      backgroundColor: color,
      appBar: AppBar(
        backgroundColor: color,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(track.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(track.artist,
                style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: LyricsPanel(track: track)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SeekBar(),
            ),
            const TransportControls(big: false),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Компьютер: на весь экран только текст (или очередь), всё управление
/// и действия с треком — в нижней панели.
/// Компьютер: слева большая обложка (её можно скрыть), справа текст
/// или очередь, всё управление — в нижней панели.
/// Компьютер, как в Spotify: слева обложка (можно скрыть), по центру
/// текст, справа панель очереди (включается кнопкой в нижней панели).
/// Компьютер: текст всегда по центру. Кнопками в нижней панели:
/// «Обложка» — большая обложка слева, «Очередь» — панель справа.
class _WideLayout extends StatelessWidget {
  const _WideLayout();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final store = context.watch<LibraryStore>();
    final settings = context.watch<SettingsStore>();
    final track = store.byId(player.current!.id) ?? player.current!;
    final showLyrics = settings.fullscreenLyrics;
    // Без текста обложка встаёт в центр, слева её не дублируем.
    final showCover = settings.fullscreenCover && showLyrics;
    final showQueue = settings.queuePanel;

    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            tooltip: 'Свернуть',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: showCover
                    ? _BigCover(track: track, width: showQueue ? 340 : 420)
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: showLyrics
                      ? Center(
                          key: const ValueKey('lyrics'),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 900),
                            child: LyricsPanel(track: track),
                          ),
                        )
                      : Center(
                          key: const ValueKey('cover'),
                          child: _BigCover(track: track, width: showQueue ? 460 : 560),
                        ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: showQueue
                    ? _QueuePanel(onClose: () => settings.queuePanel = false)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        PlayerBar(track: track, inFullScreen: true),
      ],
    );
  }
}

class _BigCover extends StatelessWidget {
  const _BigCover({required this.track, this.width = 420});
  final Track track;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 16, 24, 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 40, offset: Offset(0, 16)),
                  ],
                ),
                child: Hero(tag: 'artwork', child: Artwork(track: track, radius: 10)),
              ),
            ),
            const SizedBox(height: 20),
            Text(track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
            const SizedBox(height: 4),
            _ArtistLink(artist: track.artist),
          ],
        ),
      ),
    );
  }
}

/// Панель очереди справа: «Сейчас играет» и «Далее».
class _QueuePanel extends StatelessWidget {
  const _QueuePanel({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final current = player.current;
    return Container(
      width: 360,
      margin: const EdgeInsets.fromLTRB(0, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(
              children: [
                const Text('Очередь',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          if (current != null) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text('Сейчас играет',
                  style: TextStyle(fontSize: 13, color: Colors.white60)),
            ),
            ListTile(
              dense: true,
              leading: Artwork(track: current, size: 44, radius: 4),
              title: Text(current.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary)),
              subtitle: Text(current.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Далее', style: TextStyle(fontSize: 13, color: Colors.white60)),
          ),
          const Expanded(child: QueueList(upcomingOnly: true)),
        ],
      ),
    );
  }
}

/// Очередь: можно перетаскивать, смахивать, нажать для перехода.
class QueueList extends StatelessWidget {
  const QueueList({super.key, this.upcomingOnly = false});

  /// Только треки после текущего (для панели «Далее»).
  final bool upcomingOnly;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final queue = player.queue;
    // Сдвиг: в режиме «Далее» список начинается со следующего трека.
    final base = upcomingOnly ? player.index + 1 : 0;
    final count = (queue.length - base).clamp(0, queue.length);
    if (count == 0) {
      return Center(
          child: Text(upcomingOnly ? 'Дальше ничего нет' : 'Очередь пуста',
              style: const TextStyle(color: Colors.white60)));
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: count,
      onReorder: (o, n) => player.reorderQueue(o + base, n + base),
      buildDefaultDragHandles: false,
      itemBuilder: (context, k) {
        final i = k + base;
        final t = queue[i];
        final isCurrent = i == player.index;
        final tile = ListTile(
          onTap: () => player.jumpTo(i),
          leading: Artwork(track: t, size: 40, radius: 4),
          title: Text(t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isCurrent
                    ? Theme.of(context).colorScheme.primary
                    : (i < player.index ? Colors.white54 : null),
              )),
          subtitle: Row(
            children: [
              if (player.isRecommended(t)) ...[
                Icon(Icons.auto_awesome,
                    size: 13, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          trailing: ReorderableDragStartListener(
            index: k,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.drag_handle),
            ),
          ),
        );
        // Ключ должен быть уникален, даже если трек стоит в очереди дважды.
        final key = ValueKey('${t.id}#$i');
        final withMenu = TrackContextMenu(track: t, child: tile);
        if (isCurrent) return KeyedSubtree(key: key, child: withMenu);
        return Dismissible(
          key: key,
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: Colors.red.withValues(alpha: 0.3),
            child: const Icon(Icons.remove_circle_outline),
          ),
          onDismissed: (_) => player.removeFromQueue(i),
          child: withMenu,
        );
      },
    );
  }
}


/// Имя исполнителя — нажатие открывает его карточку.
class _ArtistLink extends StatelessWidget {
  const _ArtistLink({required this.artist});
  final String artist;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => openArtist(context, artist),
          child: Text(artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, color: Colors.white70)),
        ),
      );
}
