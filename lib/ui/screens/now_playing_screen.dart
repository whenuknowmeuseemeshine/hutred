import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
import '../theme.dart';

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
    final ink = Theme.of(context).canvasColor;

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
                builder: (context, box) {
                  final style = HutredStyle.of(context);
                  if (box.maxWidth >= 900) {
                    return style.sharp ? const _SharpWide() : const _WideLayout();
                  }
                  return style.glass ? const _GlassNarrow() : _NarrowLayout(tint: tint);
                },
              ),
            ),
          ),
        );

    // «Резкий»: ровный тёмный фон без подкраски.
    if (HutredStyle.of(context).sharp) return page(ink);
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
            context.watch<WaveService>().radioLabel?.toUpperCase() ??
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
                child: TrackContextMenu(
                    track: track, child: Artwork(track: track, radius: 10)),
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
                child: TrackContextMenu(
                  track: track,
                  child: Hero(tag: 'artwork', child: Artwork(track: track, radius: 10)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: HutredStyle.of(context).display(26)),
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

// ======================================================================
// Плеер по макетам стилей.
// ======================================================================

/// «Стекло», телефон: большая скруглённая обложка со свечением, круглые
/// кнопки, переключатель «Текст / Очередь» внизу.
class _GlassNarrow extends StatefulWidget {
  const _GlassNarrow();

  @override
  State<_GlassNarrow> createState() => _GlassNarrowState();
}

class _GlassNarrowState extends State<_GlassNarrow> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final store = context.watch<LibraryStore>();
    final wave = context.watch<WaveService>();
    final track = store.byId(player.current!.id) ?? player.current!;
    final accent = Theme.of(context).colorScheme.primary;
    final from = wave.radioLabel ??
        (wave.isWaveTrack(track) ? 'Моя волна' : sourceLabel(track.source));

    Widget round(IconData icon, String tip, VoidCallback onTap, {Color? bg, Color? fg}) =>
        Material(
          color: bg ?? Colors.white.withValues(alpha: 0.1),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Tooltip(
              message: tip,
              child: SizedBox.square(
                  dimension: 44, child: Icon(icon, size: 20, color: fg ?? Colors.white)),
            ),
          ),
        );

    final saved = store.byId(track.id) ?? store.findBySource(track.source, track.uri);
    final liked = saved?.favorite ?? false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
      children: [
        Row(
          children: [
            round(Icons.keyboard_arrow_down_rounded, 'Свернуть',
                () => Navigator.of(context).pop()),
            Expanded(
              child: Column(children: [
                const Text('ИГРАЕТ ИЗ',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFC9C5E0))),
                Text(from,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ),
            TrackMenuButton(track: track),
          ],
        ),
        const SizedBox(height: 18),
        AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                    color: accent.withValues(alpha: 0.5), blurRadius: 70, offset: const Offset(0, 30)),
              ],
            ),
            child: Hero(
              tag: 'artwork',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Artwork(track: track, radius: 0),
              ),
            ),
          ),
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: HutredStyle.of(context).display(26)),
                  _ArtistLink(artist: track.artist),
                ],
              ),
            ),
            round(LucideIcons.x, 'Не моё — больше не играть', () async {
              await context.read<WaveService>().toggleDislike(track);
              if (player.current?.id == track.id) await player.next();
            }),
            const SizedBox(width: 10),
            round(
              liked ? Icons.favorite_rounded : LucideIcons.heart,
              liked ? 'Убрать из любимых' : 'В любимые',
              () {
                if (saved == null) {
                  store.addTracks([track.copyWith(favorite: true)]);
                } else {
                  store.toggleFavorite(saved.id);
                }
              },
              bg: accent.withValues(alpha: 0.25),
              fg: liked ? accent : Colors.white,
            ),
          ],
        ),
        const _ErrorLine(),
        const SizedBox(height: 14),
        const SeekBar(),
        const SizedBox(height: 6),
        const TransportControls(),
        const SizedBox(height: 26),
        // Переключатель «Текст / Очередь».
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(children: [
            for (final (i, label) in const [(0, 'Текст'), (1, 'Очередь')])
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tab = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _tab == i ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    alignment: Alignment.center,
                    child: Text(label,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _tab == i ? Colors.white : const Color(0xFFC9C5E0))),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        if (_tab == 0)
          SizedBox(height: 380, child: LyricsPanel(track: track))
        else
          for (final (k, t) in player.queue.skip(player.index + 1).take(10).indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => player.jumpTo(player.index + 1 + k),
              leading: Artwork(track: t, size: 44, radius: 6),
              title: Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
      ],
    );
  }
}

/// «Резкий», компьютер: слева трек крупно и кнопки, справа текст и очередь.
class _SharpWide extends StatelessWidget {
  const _SharpWide();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final store = context.watch<LibraryStore>();
    final wave = context.watch<WaveService>();
    final track = store.byId(player.current!.id) ?? player.current!;
    final accent = Theme.of(context).colorScheme.primary;
    final style = HutredStyle.of(context);
    const mono = TextStyle(fontSize: 12, color: Color(0xFF8A8A8A), letterSpacing: 1);
    final from = wave.radioLabel?.toUpperCase() ??
        (wave.isWaveTrack(track) ? 'ИЗ ВОЛНЫ' : sourceLabel(track.source).toUpperCase());
    final saved = store.byId(track.id) ?? store.findBySource(track.source, track.uri);
    final liked = saved?.favorite ?? false;
    final next = player.queue.skip(player.index + 1).take(6).toList();

    Widget box(Widget child, VoidCallback onTap, {bool filled = false, double? width}) =>
        Material(
          color: filled ? accent : Colors.transparent,
          shape: filled
              ? const RoundedRectangleBorder()
              : const RoundedRectangleBorder(side: BorderSide(color: Color(0xFF333333))),
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 52,
              width: width,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: width == null ? 18 : 0),
                child: Center(child: child),
              ),
            ),
          ),
        );

    final left = ListView(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380, maxHeight: 380),
            child: Hero(tag: 'artwork', child: Artwork(track: track, radius: 0)),
          ),
        ),
        const SizedBox(height: 22),
        Text('СЕЙЧАС ИГРАЕТ · $from', style: mono.copyWith(color: accent)),
        const SizedBox(height: 8),
        Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: style.display(72)),
        const SizedBox(height: 6),
        DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 22, color: Color(0xFF8A8A8A)),
          child: _ArtistLink(artist: track.artist),
        ),
        const _ErrorLine(),
        const SizedBox(height: 18),
        const ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 560),
          child: SeekBar(compact: true),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            box(
              const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.x, size: 18),
                SizedBox(width: 8),
                Text('Не моё', style: TextStyle(fontWeight: FontWeight.w600)),
              ]),
              () async {
                await context.read<WaveService>().toggleDislike(track);
                if (player.current?.id == track.id) await player.next();
              },
            ),
            box(const Icon(Icons.skip_previous_rounded), player.previous, width: 52),
            box(
              Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: HutredTheme.onAccent(accent), size: 26),
              player.togglePlay,
              filled: true,
              width: 72,
            ),
            box(const Icon(Icons.skip_next_rounded), player.next, width: 52),
            box(
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(liked ? Icons.favorite_rounded : LucideIcons.heart,
                    size: 18, color: liked ? accent : null),
                const SizedBox(width: 8),
                Text(liked ? 'В любимых' : 'В любимые',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
              () {
                if (saved == null) {
                  store.addTracks([track.copyWith(favorite: true)]);
                } else {
                  store.toggleFavorite(saved.id);
                }
              },
            ),
            const SizedBox(width: 220, child: VolumeSlider()),
          ],
        ),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(32, 8, 32, 8),
          child: Text('ТЕКСТ', style: mono),
        ),
        Expanded(child: LyricsPanel(track: track)),
        const Divider(height: 1),
        if (next.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 6),
            child: Text(wave.isWaveTrack(track) ? 'ДАЛЬШЕ В ВОЛНЕ' : 'ДАЛЬШЕ', style: mono),
          ),
          for (final (k, t) in next.take(5).indexed)
            InkWell(
              onTap: () => player.jumpTo(player.index + 1 + k),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                child: Row(children: [
                  SizedBox(
                      width: 28,
                      child: Text((k + 1).toString().padLeft(2, '0'),
                          style: mono.copyWith(color: const Color(0xFF555555)))),
                  Artwork(track: t, size: 40, radius: 0),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF8A8A8A))),
                    ]),
                  ),
                  Text(formatDuration(t.duration), style: mono.copyWith(letterSpacing: 0)),
                ]),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ],
    );

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
              Expanded(flex: 11, child: left),
              const VerticalDivider(width: 1, color: Color(0xFF222222)),
              Expanded(flex: 9, child: right),
            ],
          ),
        ),
      ],
    );
  }
}
