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
import '../icons.dart';

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

    final style = HutredStyle.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Мини-плеер — отдельная плашка над нижним меню (у «Резкого» — без скруглений).
    final radius = BorderRadius.circular(style.sharp ? 0 : style.glass ? 18 : 10);
    final progress = StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snap) {
        final dur = player.duration?.inMilliseconds ?? 0;
        final pos = snap.data?.inMilliseconds ?? 0;
        return LinearProgressIndicator(
          value: dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0,
          minHeight: 2,
          backgroundColor: Colors.white12,
          color: style.sharp ? scheme.primary : Colors.white,
        );
      },
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Material(
      color: style.glass
          ? Colors.black.withValues(alpha: 0.45)
          : style.sharp
              ? scheme.surface
              : Color.alphaBlend(tint.withValues(alpha: 0.18), scheme.surfaceContainerHighest),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: style.mono
            ? BorderSide.none
            : BorderSide(color: Colors.white.withValues(alpha: style.sharp ? 0.16 : 0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => NowPlayingScreen.open(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                      icon: Icon(Ic.skip_previous_rounded),
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
                          icon: SwapIcon(player.playing
                              ? Ic.pause_rounded
                              : Ic.play_arrow_rounded),
                        ),
                  IconButton(
                    tooltip: 'Следующий',
                    onPressed: player.next,
                    icon: Icon(Ic.skip_next_rounded),
                  ),
                ],
              ),
            ),
            progress,
          ],
        ),
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

    final style = HutredStyle.of(context);
    // «Стекло»: панель парит над страницей; остальные — во всю ширину с линией сверху.
    final floating = style.glass && !inFullScreen;
    final bar = Material(
      color: inFullScreen
          ? Colors.black.withValues(alpha: 0.25)
          : floating
              ? const Color(0xFF14121F).withValues(alpha: 0.72)
              : Theme.of(context).canvasColor,
      shape: floating
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.1)))
          : null,
      clipBehavior: floating ? Clip.antiAlias : Clip.none,
      child: Container(
        height: floating ? 80 : (style.sharp ? 92 : 84),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: floating
            ? null
            : BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: Colors.white.withValues(alpha: style.sharp ? 0.14 : 0.07))),
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
                          tag: 'artwork', child: Artwork(track: track, size: 52, radius: 6)),
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
                  // Текст, обложка, очередь: в полноэкранном плеере прячут/показывают
                  // свою часть, снаружи — открывают плеер с ней.
                  _PanelToggle(
                    label: 'Текст',
                    icon: Ic.lyrics_outlined,
                    on: settings.fullscreenLyrics && inFullScreen,
                    onTap: () {
                      if (inFullScreen) {
                        settings.fullscreenLyrics = !settings.fullscreenLyrics;
                      } else {
                        settings.fullscreenLyrics = true;
                        NowPlayingScreen.open(context);
                      }
                    },
                  ),
                  _PanelToggle(
                    label: 'Обложка',
                    icon: Ic.album_outlined,
                    on: settings.fullscreenCover && inFullScreen,
                    onTap: () {
                      if (inFullScreen) {
                        settings.fullscreenCover = !settings.fullscreenCover;
                      } else {
                        settings.fullscreenCover = true;
                        NowPlayingScreen.open(context);
                      }
                    },
                  ),
                  _PanelToggle(
                    label: 'Очередь',
                    icon: Ic.queue_music,
                    on: settings.queuePanel && inFullScreen,
                    onTap: () {
                      if (inFullScreen) {
                        settings.queuePanel = !settings.queuePanel;
                      } else {
                        settings.queuePanel = true;
                        NowPlayingScreen.open(context);
                      }
                    },
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
    return floating ? Padding(padding: const EdgeInsets.only(top: 12), child: bar) : bar;
  }
}

/// Кнопка панели плеера: у «Стекла» — капсула со словом, у остальных — значок.
class _PanelToggle extends StatelessWidget {
  const _PanelToggle({
    required this.label,
    required this.icon,
    required this.on,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = HutredStyle.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    if (style.glass) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: on ? accent.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.07),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: on ? Colors.white : const Color(0xFFD6D6E2))),
            ),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: on ? 'Скрыть: ${label.toLowerCase()}' : label,
      isSelected: on,
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      selectedIcon: Icon(icon, size: 20, color: accent),
    );
  }
}
