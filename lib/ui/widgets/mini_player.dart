import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/library_store.dart';
import '../../services/player_service.dart';
import '../../services/settings_store.dart';
import '../screens/now_playing_screen.dart';
import '../theme.dart';
import '../../models/track.dart';
import 'artwork.dart';
import 'track_tile.dart';
import 'controls.dart';
import 'like_buttons.dart';

/// Мини-плеер внизу экрана. Нажатие открывает полноэкранный плеер.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final store = context.watch<LibraryStore>();
    final current = player.current;
    if (current == null) return const SizedBox.shrink();
    final track = store.byId(current.id) ?? current;
    final tint = context.watch<SettingsStore>().tintFromCover
        ? Artwork.tint(track)
        : Theme.of(context).colorScheme.primary;
    final wide = MediaQuery.sizeOf(context).width >= 800;
    // На компьютере — широкая панель в три части, как в настольных плеерах.
    if (wide) return PlayerBar(track: track);

    return Material(
      color: Color.alphaBlend(tint.withValues(alpha: 0.22), Theme.of(context).colorScheme.surface),
      child: InkWell(
        onTap: () => NowPlayingScreen.open(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<Duration>(
              stream: player.positionStream,
              builder: (context, snap) {
                final dur = player.duration?.inMilliseconds ?? 0;
                final pos = snap.data?.inMilliseconds ?? 0;
                return LinearProgressIndicator(
                  value: dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0,
                  minHeight: 2,
                  backgroundColor: Colors.white12,
                  color: Colors.white,
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Row(
                children: [
                  Hero(
                    tag: 'artwork',
                    child: TrackContextMenu(
                        track: track, child: Artwork(track: track, size: 46, radius: 4)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          player.error ?? track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: player.error != null
                                ? Theme.of(context).colorScheme.error
                                : HutredTheme.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (wide)
                    IconButton(
                      tooltip: 'Предыдущий',
                      onPressed: player.previous,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                  LikeButtons(track: track),
                  player.loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(
                              dimension: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          tooltip: player.playing ? 'Пауза' : 'Играть',
                          iconSize: 32,
                          onPressed: player.togglePlay,
                          icon: Icon(player.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                        ),
                  IconButton(
                    tooltip: 'Следующий',
                    onPressed: player.next,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Нижняя панель на компьютере: слева трек, в центре управление и
/// перемотка, справа текст, очередь и громкость.
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key, required this.track, this.inFullScreen = false});
  final Track track;

  /// Внутри полноэкранного плеера: прозрачный фон, кнопка «свернуть».
  final bool inFullScreen;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final store = context.watch<LibraryStore>();
    final scheme = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsStore>();

    return Material(
      color: inFullScreen ? Colors.black.withValues(alpha: 0.25) : scheme.surface,
      child: Container(
        height: 100,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
        ),
        child: Row(
          children: [
            // Слева: обложка, название, сердечко.
            Expanded(
              flex: 3,
              child: InkWell(
                onTap: inFullScreen ? null : () => NowPlayingScreen.open(context),
                borderRadius: BorderRadius.circular(6),
                child: Row(
                  children: [
                    TrackContextMenu(
                      track: track,
                      child: Hero(
                          tag: 'artwork', child: Artwork(track: track, size: 60, radius: 6)),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(player.error ?? track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: player.error != null
                                      ? scheme.error
                                      : HutredTheme.muted)),
                        ],
                      ),
                    ),
                    LikeButtons(track: track, size: 20),
                  ],
                ),
              ),
            ),
            // Центр: кнопки и перемотка.
            Expanded(
              flex: 4,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: 48, child: TransportControls(big: false, compact: true)),
                    SeekBar(compact: true),
                  ],
                ),
              ),
            ),
            // Справа: текст, очередь, громкость.
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Текст: открыть/закрыть полноэкранный плеер.
                  // Текст: в полноэкранном плеере прячет/показывает только текст,
                  // закрыть плеер целиком — кнопкой «Свернуть».
                  IconButton(
                    tooltip: settings.fullscreenLyrics && inFullScreen
                        ? 'Скрыть текст'
                        : 'Текст',
                    isSelected: settings.fullscreenLyrics && inFullScreen,
                    onPressed: () {
                      if (inFullScreen) {
                        settings.fullscreenLyrics = !settings.fullscreenLyrics;
                      } else {
                        settings.fullscreenLyrics = true;
                        NowPlayingScreen.open(context);
                      }
                    },
                    icon: const Icon(Icons.lyrics_outlined, size: 20),
                    selectedIcon: Icon(Icons.lyrics, size: 20, color: scheme.primary),
                  ),
                  // Обложка: большая обложка слева от текста.
                  IconButton(
                    tooltip: settings.fullscreenCover && inFullScreen
                        ? 'Скрыть обложку'
                        : 'Обложка',
                    isSelected: settings.fullscreenCover && inFullScreen,
                    onPressed: () {
                      if (inFullScreen) {
                        settings.fullscreenCover = !settings.fullscreenCover;
                      } else {
                        settings.fullscreenCover = true;
                        NowPlayingScreen.open(context);
                      }
                    },
                    icon: const Icon(Icons.album_outlined, size: 20),
                    selectedIcon: Icon(Icons.album, size: 20, color: scheme.primary),
                  ),
                  // Очередь: панель справа от текста.
                  IconButton(
                    tooltip: settings.queuePanel && inFullScreen
                        ? 'Скрыть очередь'
                        : 'Очередь',
                    isSelected: settings.queuePanel && inFullScreen,
                    onPressed: () {
                      if (inFullScreen) {
                        settings.queuePanel = !settings.queuePanel;
                      } else {
                        settings.queuePanel = true;
                        NowPlayingScreen.open(context);
                      }
                    },
                    icon: const Icon(Icons.queue_music_outlined, size: 20),
                    selectedIcon:
                        Icon(Icons.queue_music, size: 20, color: scheme.primary),
                  ),
                  const SizedBox(width: 4),
                  const SizedBox(width: 150, child: VolumeSlider()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
