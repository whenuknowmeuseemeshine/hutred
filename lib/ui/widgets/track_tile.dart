
import '../../services/jam_service.dart';
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
import '../../services/wave_service.dart';
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
    this.inFavorites = false,
  });

  final Track track;
  final VoidCallback onTap;

  /// Строка в «Любимых треках»: «убрать» снимает ♥, а не удаляет трек.
  final bool inFavorites;

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

    // Скрытые треки и чёрный список — полупрозрачные (играть не будут).
    final hidden = context.watch<WaveService>().isBlocked(track);
    // На компьютере «в любимые» — кнопкой в строке (видна при наведении),
    // поэтому из меню её убираем.
    final desktop = HutredTheme.desktop;
    final store = context.read<LibraryStore>();
    final saved = store.byId(track.id) ?? store.findBySource(track.source, track.uri);
    return TrackContextMenu(
      track: track,
      compact: desktop,
      inFavorites: inFavorites,
      onRemoveFromPlaylist: onRemoveFromPlaylist,
      child: _Hover(builder: (hovered) => Opacity(
        opacity: hidden ? 0.4 : 1,
        child: ListTile(
      // Как в Spotify: нажал на играющий трек ещё раз — пауза/продолжить.
      onTap: isCurrent ? player.togglePlay : onTap,
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
          if (track.favorite && !desktop) ...[
            Icon(Icons.favorite, size: 13, color: scheme.primary),
            const SizedBox(width: 4),
          ],
          _DownloadMark(track: track),
          Icon(sourceIcon(track.source), size: 13, color: HutredTheme.muted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              track.shownAlbum.isEmpty
                  ? track.artist
                  : '${track.artist} · ${track.shownAlbum}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (desktop) ...[
            if (saved != null)
              _RowAction(
                visible: hovered || saved.favorite,
                tooltip: saved.favorite ? 'Убрать из любимых' : 'В любимые',
                icon: saved.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: saved.favorite ? scheme.primary : null,
                onTap: () => store.toggleFavorite(saved.id),
              ),
            const SizedBox(width: 8),
          ],
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
              track: track,
              compact: desktop,
              inFavorites: inFavorites,
              onRemoveFromPlaylist: onRemoveFromPlaylist),
        ],
      ),
    ),
      )),
    );
  }
}

/// Пункты меню трека — одинаковые для «⋮» и для правого клика.
List<PopupMenuEntry<String>> trackMenuItems(BuildContext context, Track track,
    {bool canRemoveFromPlaylist = false, bool compact = false, bool inFavorites = false}) {
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
    item('radio', Icons.graphic_eq_rounded, 'Джем по треку'),
    if (context.read<JamService>().active) item('jamAdd', Icons.group_add_outlined, 'Добавить в джем'),
    item('next', Icons.playlist_play, 'Играть следующим'),
    item('queue', Icons.queue_music, 'Добавить в очередь'),
    if (hasArtist) item('artist', Icons.person_outline, 'К исполнителю'),
    if (context.read<WaveService>().isDisliked(track))
      item('undislike', Icons.thumb_down, 'Вернуть трек (снова играть)')
    else
      item('dislike', Icons.thumb_down_outlined, 'Не нравится — скрыть'),
    if (hasArtist) item('block', Icons.block, 'Не показывать исполнителя…'),
    if (context.read<OfflineService>().isDownloaded(track))
      item('undownload', Icons.download_done, 'Удалить загрузку')
    else
      item('download', Icons.download_outlined, 'Скачать'),
    const PopupMenuDivider(),
    item('playlist', Icons.add_circle_outline, 'Добавить в плейлист…'),
    if (!inLibrary) item('library', Icons.library_add_outlined, 'Добавить в медиатеку'),
    if (inLibrary && !compact && !inFavorites)
      item('fav', saved.favorite ? Icons.favorite : Icons.favorite_border,
          saved.favorite ? 'Убрать из любимых' : 'В любимые'),
    if (inLibrary) ...[
      const PopupMenuDivider(),
      item('edit', Icons.edit_outlined, 'Изменить сведения…'),
      item('refresh', Icons.refresh_rounded, 'Обновить трек'),
      if (acc.signedIn)
        item('hide', saved.hiddenFromFriends ? Icons.visibility : Icons.visibility_off_outlined,
            saved.hiddenFromFriends ? 'Показать друзьям' : 'Скрыть от друзей'),
      if (acc.signedIn && acc.isAdmin)
        item('fix', Icons.public, 'Применить правки для всех'),
    ],
    if (canRemoveFromPlaylist)
      inFavorites
          ? item('unlist', Icons.heart_broken_outlined, 'Убрать из любимых')
          : item('unlist', Icons.playlist_remove, 'Убрать из плейлиста'),
    if (inLibrary && !inFavorites) item('delete', Icons.delete_outline, 'Удалить из медиатеки'),
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
    case 'radio':
      final wave = context.read<WaveService>();
      AppActions.toast(context, 'Подбираю похожее на «${t.title}»…');
      await wave.startFromTrack(t);
      if (context.mounted) {
        AppActions.toast(context, wave.error ?? 'Играет джем по треку «${t.title}»');
      }
    case 'jamAdd':
      await context.read<JamService>().addTrack(t);
      if (context.mounted) AppActions.toast(context, 'Добавлено в джем');
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
    case 'dislike':
    case 'undislike':
      await context.read<WaveService>().toggleDislike(t);
      if (context.mounted) {
        AppActions.toast(context,
            action == 'dislike' ? 'Трек скрыт и больше не попадётся' : 'Трек снова будет играть');
      }
    case 'block':
      final names = WaveService.artistsOf(t);
      var name = names.isEmpty ? t.artist : names.first;
      if (names.length > 1) {
        final picked = await showDialog<String>(
          context: context,
          builder: (d) => SimpleDialog(
            title: const Text('Кого не показывать?'),
            children: [
              for (final n in names)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(d, n),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(n, style: const TextStyle(fontSize: 16)),
                  ),
                ),
            ],
          ),
        );
        if (picked == null) return;
        name = picked;
      }
      if (!context.mounted) return;
      await context.read<WaveService>().blockArtist(name);
      if (context.mounted) {
        AppActions.toast(context, '«$name» в чёрном списке — его треки больше не будут играть');
      }
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
    case 'refresh':
      // Сначала Spotify (точные название, альбом, обложка), если есть ключи;
      // не нашёлся — обычный поиск обложки и сведений.
      AppActions.toast(context, 'Обновляю «${t.title}»…');
      if (context.read<SettingsStore>().hasSpotifyKeys && t.source != TrackSource.spotify) {
        final n = await context.read<SpotifyCheck>().applyAll([t], (_, __) {});
        if (n > 0) {
          if (context.mounted) AppActions.toast(context, 'Сведения и обложка из Spotify');
          return;
        }
      }
      if (!context.mounted) return;
      final found = await context.read<CoverService>().fetchFor(t, manual: true);
      if (context.mounted) {
        AppActions.toast(
            context, found != null ? 'Обложка и сведения из $found' : 'Ничего нового не нашлось');
      }
    case 'cover':
      AppActions.toast(context, 'Ищу обложку…');
      final from = await context.read<CoverService>().fetchFor(t, manual: true);
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
    {VoidCallback? onRemoveFromPlaylist, bool compact = false, bool inFavorites = false}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(globalPosition);
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(local & const Size(1, 1), Offset.zero & overlay.size),
    items: trackMenuItems(context, track,
        canRemoveFromPlaylist: onRemoveFromPlaylist != null,
        compact: compact,
        inFavorites: inFavorites),
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
    this.compact = false,
    this.inFavorites = false,
  });

  final Track track;
  final Widget child;
  final VoidCallback? onRemoveFromPlaylist;
  final bool compact;
  final bool inFavorites;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (d) => showTrackMenuAt(context, track, d.globalPosition,
            onRemoveFromPlaylist: onRemoveFromPlaylist,
            compact: compact,
            inFavorites: inFavorites),
        onLongPressStart: (d) => showTrackMenuAt(context, track, d.globalPosition,
            onRemoveFromPlaylist: onRemoveFromPlaylist,
            compact: compact,
            inFavorites: inFavorites),
        child: child,
      );
}

class TrackMenuButton extends StatelessWidget {
  const TrackMenuButton(
      {super.key,
      required this.track,
      this.onRemoveFromPlaylist,
      this.compact = false,
      this.inFavorites = false});

  final Track track;
  final VoidCallback? onRemoveFromPlaylist;
  final bool compact;
  final bool inFavorites;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Действия',
      icon: const Icon(Icons.more_vert),
      onSelected: (v) =>
          runTrackAction(context, track, v, onRemoveFromPlaylist: onRemoveFromPlaylist),
      itemBuilder: (_) => trackMenuItems(context, track,
          canRemoveFromPlaylist: onRemoveFromPlaylist != null,
          compact: compact,
          inFavorites: inFavorites),
    );
  }
}


/// Отдаёт в [builder], наведена ли мышь на строку.
class _Hover extends StatefulWidget {
  const _Hover({required this.builder});
  final Widget Function(bool hovered) builder;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: widget.builder(_h),
      );
}

/// Маленькая кнопка в строке трека; скрытая всё равно занимает место,
/// чтобы время не прыгало.
class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.visible,
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.color,
  });

  final bool visible;
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Visibility(
        visible: visible,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: IconButton(
          tooltip: tooltip,
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
          icon: Icon(icon, color: color ?? Colors.white70),
        ),
      );
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
