import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/library_store.dart';
import '../../services/offline_service.dart';
import '../../services/player_service.dart';
import '../actions.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/controls.dart';
import '../widgets/track_tile.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final name = await AppActions.askText(context,
        title: 'Новый плейлист', hint: 'Название', action: 'Создать');
    if (name == null || !context.mounted) return;
    context.read<LibraryStore>().createPlaylist(name);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final favs = store.favorites;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Плейлисты'),
        actions: [
          IconButton(
            tooltip: 'Новый плейлист',
            onPressed: () => _create(context),
            icon: const Icon(Icons.playlist_add),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          ListTile(
            leading: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    HSLColor.fromColor(Theme.of(context).colorScheme.primary)
                        .withLightness(0.3)
                        .toColor(),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(Icons.favorite,
                  color: Theme.of(context).colorScheme.onPrimary),
            ),
            title: const Text('Избранное',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tracksWord(favs.length)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PlaylistDetailScreen(playlistId: null))),
          ),
          for (final p in store.playlists)
            ListTile(
              leading: _Collage(tracks: store.tracksOf(p)),
              title: Text(p.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tracksWord(p.trackIds.length)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(playlistId: p.id))),
            ),
          if (store.playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Text(
                    'Собирай треки из разных источников в один плейлист: '
                    'файлы, YouTube и радио вперемешку.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: HutredTheme.muted, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _create(context),
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Создать плейлист'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Обложка плейлиста из первых четырёх треков.
class _Collage extends StatelessWidget {
  const _Collage({required this.tracks});
  final List<Track> tracks;
  static const double size = 52;

  @override
  Widget build(BuildContext context) {
    if (tracks.length < 4) {
      return Artwork(
          track: tracks.isEmpty ? null : tracks.first, size: size, radius: 4);
    }
    const half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox.square(
        dimension: size,
        child: Wrap(
          children: [
            for (final t in tracks.take(4))
              Artwork(track: t, size: half, radius: 0),
          ],
        ),
      ),
    );
  }
}

/// Плейлист или «Избранное» (когда playlistId == null).
class PlaylistDetailScreen extends StatelessWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});
  final String? playlistId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final player = context.read<PlayerService>();
    final playlist = playlistId == null ? null : store.playlistById(playlistId!);
    if (playlistId != null && playlist == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Плейлист удалён')));
    }
    final tracks = playlist == null ? store.favorites : store.tracksOf(playlist);
    final name = playlist?.name ?? 'Избранное';

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          if (playlist != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'rename') {
                  final n = await AppActions.askText(context,
                      title: 'Переименовать', initial: playlist.name);
                  if (n != null) store.renamePlaylist(playlist.id, n);
                } else if (v == 'delete') {
                  final ok = await AppActions.confirm(context,
                      title: 'Удалить плейлист?',
                      body: '«${playlist.name}» будет удалён. Треки останутся в медиатеке.');
                  if (ok && context.mounted) {
                    Navigator.of(context).pop();
                    store.deletePlaylist(playlist.id);
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                PopupMenuItem(value: 'delete', child: Text('Удалить плейлист')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text(tracksWord(tracks.length),
                    style: const TextStyle(color: HutredTheme.muted)),
                const Spacer(),
                Builder(builder: (context) {
                  final off = context.watch<OfflineService>();
                  final pinned = off.isPinned(playlistId);
                  final done = tracks.where(off.isDownloaded).length;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (pinned && done < tracks.length)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text('$done/${tracks.length}',
                              style: const TextStyle(color: HutredTheme.muted, fontSize: 12)),
                        ),
                      IconButton(
                        iconSize: 28,
                        tooltip: pinned ? 'Удалить загрузки' : 'Скачать для прослушивания без интернета',
                        isSelected: pinned,
                        onPressed: tracks.isEmpty && !pinned
                            ? null
                            : () => off.pin(playlistId, !pinned),
                        icon: Icon(
                          pinned ? Icons.arrow_circle_down_rounded : Icons.arrow_circle_down_outlined,
                          color: pinned ? Theme.of(context).colorScheme.primary : Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  );
                }),
                IconButton(
                  tooltip: 'Перемешать',
                  onPressed: tracks.isEmpty ? null : () => player.shufflePlay(tracks),
                  icon: const ShuffleIcon(on: false, smart: false, size: 26),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Слушать',
                  iconSize: 30,
                  onPressed: tracks.isEmpty ? null : () => player.playTracks(tracks),
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: tracks.isEmpty
                ? Center(
                    child: Text(
                      playlist == null
                          ? 'Нажми ♥ у трека, чтобы он появился здесь'
                          : 'Добавляй треки через меню ⋮ → «Добавить в плейлист»',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: HutredTheme.muted),
                    ),
                  )
                : playlist == null
                    ? ListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: tracks.length,
                        itemBuilder: (_, i) => TrackTile(
                          track: tracks[i],
                          onTap: () => player.playTracks(tracks, start: i),
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: tracks.length,
                        onReorder: (o, n) => store.reorderPlaylist(playlist.id, o, n),
                        itemBuilder: (_, i) => TrackTile(
                          key: ValueKey(tracks[i].id),
                          track: tracks[i],
                          onTap: () => player.playTracks(tracks, start: i),
                          onRemoveFromPlaylist: () =>
                              store.removeFromPlaylist(playlist.id, tracks[i].id),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
