
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/account_service.dart';
import '../../services/cover_service.dart';
import '../../services/offline_service.dart';
import '../../services/library_store.dart';
import '../../services/player_service.dart';
import '../../services/track_fixes.dart';
import '../../services/settings_store.dart';
import '../actions.dart';
import '../spotify_check.dart';
import '../screens/artist_screen.dart';
import '../theme.dart';
import 'artwork.dart';

IconData sourceIcon(TrackSource s) => switch (s) {
      TrackSource.local => Icons.insert_drive_file_outlined,
      TrackSource.url => Icons.public,
      TrackSource.youtube => Icons.smart_display_outlined,
      TrackSource.soundcloud => Icons.cloud_outlined,
      TrackSource.spotify => Icons.graphic_eq,
    };

String sourceLabel(TrackSource s) => switch (s) {
      TrackSource.local => 'Файл',
      TrackSource.url => 'Ссылка',
      TrackSource.youtube => 'YouTube',
      TrackSource.soundcloud => 'SoundCloud',
      TrackSource.spotify => 'Spotify',
    };

/// Строка трека с обложкой, источником и меню действий.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.onRemoveFromPlaylist,
    this.trailingAction,
  });

  final Track track;
  final VoidCallback onTap;

  /// Если задано — в меню появится «Убрать из плейлиста».
  final VoidCallback? onRemoveFromPlaylist;

  /// Дополнительная кнопка справа (например, «добавить» в поиске).
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final isCurrent = player.current?.id == track.id ||
        (player.current != null &&
            player.current!.source == track.source &&
            player.current!.uri == track.uri);
    final scheme = Theme.of(context).colorScheme;

    return TrackContextMenu(
      track: track,
      onRemoveFromPlaylist: onRemoveFromPlaylist,
      child: ListTile(
      onTap: onTap,
      leading: Stack(
        children: [
          Artwork(track: track, size: 48, radius: 4),
          if (isCurrent)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: EqualizerBars(
                    playing: player.playing && !player.loading,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isCurrent ? scheme.primary : null,
        ),
      ),
      subtitle: Row(
        children: [
          if (track.favorite) ...[
            Icon(Icons.favorite, size: 13, color: scheme.primary),
            const SizedBox(width: 4),
          ],
          _DownloadMark(track: track),
          Icon(sourceIcon(track.source), size: 13, color: HutredTheme.muted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              track.album.isEmpty
                  ? track.artist
                  : '${track.artist} · ${track.album}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (track.duration != null)
            Text(
              formatDuration(track.duration),
              style: const TextStyle(
                color: HutredTheme.muted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          if (trailingAction != null) trailingAction!,
          TrackMenuButton(
              track: track, onRemoveFromPlaylist: onRemoveFromPlaylist),
        ],
      ),
    ),
    );
  }
}

/// Пункты меню трека — одинаковые для «⋮» и для правого клика.
List<PopupMenuEntry<String>> trackMenuItems(
    BuildContext context, Track track, {bool canRemoveFromPlaylist = false}) {
  final store = context.read<LibraryStore>();
  final saved = store.byId(track.id) ?? store.findBySource(track.source, track.uri);
  final inLibrary = saved != null;
  final acc = context.read<AccountService>();
  final hasArtist = splitArtists(track.artist).isNotEmpty;
  PopupMenuItem<String> item(String value, IconData icon, String text) => PopupMenuItem(
        value: value,
        height: 40,
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white70),
            const SizedBox(width: 12),
            Text(text),
          ],
        ),
      );
  return [
    item('next', Icons.playlist_play, 'Играть следующим'),
    item('queue', Icons.queue_music, 'Добавить в очередь'),
    if (hasArtist) item('artist', Icons.person_outline, 'К исполнителю'),
    if (context.read<OfflineService>().isDownloaded(track))
      item('undownload', Icons.download_done, 'Удалить загрузку')
    else
      item('download', Icons.download_outlined, 'Скачать'),
    const PopupMenuDivider(),
    item('playlist', Icons.add_circle_outline, 'Добавить в плейлист…'),
    if (!inLibrary) item('library', Icons.library_add_outlined, 'Добавить в медиатеку'),
    if (inLibrary)
      item('fav', saved.favorite ? Icons.favorite : Icons.favorite_border,
          saved.favorite ? 'Убрать из любимых' : 'В любимые'),
    if (inLibrary) ...[
      const PopupMenuDivider(),
      item('edit', Icons.edit_outlined, 'Изменить сведения…'),
      item('cover', Icons.image_search, 'Найти обложку и сведения'),
      if (context.read<SettingsStore>().hasSpotifyKeys && track.source != TrackSource.spotify)
        item('spotifyMeta', Icons.graphic_eq, 'Сведения из Spotify'),
      if (acc.signedIn)
        item('hide', saved.hiddenFromFriends ? Icons.visibility : Icons.visibility_off_outlined,
            saved.hiddenFromFriends ? 'Показать друзьям' : 'Скрыть от друзей'),
      if (acc.signedIn && acc.isAdmin)
        item('fix', Icons.public, 'Применить правки для всех'),
    ],
    if (canRemoveFromPlaylist) item('unlist', Icons.playlist_remove, 'Убрать из плейлиста'),
    if (inLibrary) item('delete', Icons.delete_outline, 'Удалить из медиатеки'),
  ];
}

/// Выполняет выбранный пункт меню трека.
Future<void> runTrackAction(BuildContext context, Track track, String action,
    {VoidCallback? onRemoveFromPlaylist}) async {
  final store = context.read<LibraryStore>();
  final player = context.read<PlayerService>();
  final saved = store.byId(track.id) ?? store.findBySource(track.source, track.uri);
  final t = saved ?? track;
  switch (action) {
    case 'next':
      await player.playNext(t);
      if (context.mounted) AppActions.toast(context, 'Сыграет следующим');
    case 'queue':
      await player.addToQueue(t);
      if (context.mounted) AppActions.toast(context, 'Добавлено в очередь');
    case 'library':
      AppActions.ensureInLibrary(context, t);
      AppActions.toast(context, 'Добавлено в медиатеку');
    case 'playlist':
      await AppActions.addToPlaylistDialog(context, t);
    case 'fav':
      store.toggleFavorite(t.id);
    case 'artist':
      await openArtist(context, t.artist);
    case 'spotifyMeta':
      AppActions.toast(context, 'Ищу в Spotify…');
      final n = await context.read<SpotifyCheck>().applyAll([t], (_, __) {});
      if (context.mounted) {
        AppActions.toast(context, n == 0 ? 'В Spotify не нашёлся' : 'Сведения обновлены из Spotify');
      }
    case 'download':
      context.read<OfflineService>().downloadTrack(t);
      AppActions.toast(context, 'Скачиваю «${t.title}»');
    case 'undownload':
      await context.read<OfflineService>().remove(t);
    case 'hide':
      store.updateTrack(t.copyWith(hiddenFromFriends: !t.hiddenFromFriends));
      AppActions.toast(context,
          t.hiddenFromFriends ? 'Друзья снова видят этот трек' : 'Трек скрыт от друзей');
    case 'fix':
      final err = await context.read<TrackFixes>().publish(t);
      if (context.mounted) {
        AppActions.toast(context, err ?? 'Правки трека применены у всех');
      }
    case 'edit':
      await AppActions.editTrackDialog(context, t);
    case 'cover':
      AppActions.toast(context, 'Ищу обложку…');
      final from = await context.read<CoverService>().fetchFor(t);
      if (context.mounted) {
        AppActions.toast(context, from != null ? 'Обложка и сведения из $from' : 'Ничего не нашлось');
      }
    case 'unlist':
      onRemoveFromPlaylist?.call();
    case 'delete':
      final ok = await AppActions.confirm(context,
          title: 'Удалить из медиатеки?',
          body: '«${t.title}» пропадёт из медиатеки и всех плейлистов. '
              'Сам файл на диске останется.');
      if (ok) store.removeTrack(t.id);
  }
}

/// Меню трека в точке клика (правая кнопка мыши или долгое нажатие).
Future<void> showTrackMenuAt(BuildContext context, Track track, Offset globalPosition,
    {VoidCallback? onRemoveFromPlaylist}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(globalPosition);
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(local & const Size(1, 1), Offset.zero & overlay.size),
    items: trackMenuItems(context, track,
        canRemoveFromPlaylist: onRemoveFromPlaylist != null),
  );
  if (action != null && context.mounted) {
    await runTrackAction(context, track, action, onRemoveFromPlaylist: onRemoveFromPlaylist);
  }
}

/// Правый клик (и долгое нажатие на телефоне) по любому месту строки
/// открывает меню трека — как в Spotify.
class TrackContextMenu extends StatelessWidget {
  const TrackContextMenu({
    super.key,
    required this.track,
    required this.child,
    this.onRemoveFromPlaylist,
  });

  final Track track;
  final Widget child;
  final VoidCallback? onRemoveFromPlaylist;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (d) => showTrackMenuAt(context, track, d.globalPosition,
            onRemoveFromPlaylist: onRemoveFromPlaylist),
        onLongPressStart: (d) => showTrackMenuAt(context, track, d.globalPosition,
            onRemoveFromPlaylist: onRemoveFromPlaylist),
        child: child,
      );
}

class TrackMenuButton extends StatelessWidget {
  const TrackMenuButton(
      {super.key, required this.track, this.onRemoveFromPlaylist});

  final Track track;
  final VoidCallback? onRemoveFromPlaylist;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Действия',
      icon: const Icon(Icons.more_vert),
      onSelected: (v) =>
          runTrackAction(context, track, v, onRemoveFromPlaylist: onRemoveFromPlaylist),
      itemBuilder: (_) => trackMenuItems(context, track,
          canRemoveFromPlaylist: onRemoveFromPlaylist != null),
    );
  }
}


/// Прыгающие полоски на обложке играющего трека (как в Spotify).
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({super.key, required this.playing, required this.color, this.size = 20});
  final bool playing;
  final Color color;
  final double size;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  // У каждой полоски свой ритм и сдвиг, чтобы не прыгали одинаково.
  static const _speeds = [2.0, 3.0, 4.0, 3.0];
  static const _phases = [0.0, 1.3, 2.6, 0.7];

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) _c.repeat();
    if (!widget.playing && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final barW = s / 7;
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                width: barW,
                height: widget.playing
                    ? s * (0.25 + 0.75 * (0.5 + 0.5 * math.sin(_c.value * math.pi * 2 * _speeds[i] + _phases[i])))
                    : s * 0.25,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(barW / 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}


/// Зелёная стрелка у скачанного трека, крутилка — пока качается.
class _DownloadMark extends StatelessWidget {
  const _DownloadMark({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final off = context.watch<OfflineService>();
    final accent = Theme.of(context).colorScheme.primary;
    if (off.isDownloaded(track)) {
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Icon(Icons.arrow_circle_down, size: 14, color: accent),
      );
    }
    if (off.isDownloading(track)) {
      return Padding(
        padding: const EdgeInsets.only(right: 5),
        child: SizedBox.square(
          dimension: 11,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: accent),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
