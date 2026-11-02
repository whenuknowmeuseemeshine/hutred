import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../services/account_service.dart';
import '../../services/library_store.dart';
import '../../services/offline_service.dart';
import '../../services/player_service.dart';
import '../actions.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/filter_field.dart';
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
            title: const Text('Любимые треки',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tracksWord(favs.length)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PlaylistDetailScreen(playlistId: null))),
          ),
          for (final p in store.playlists)
            ListTile(
              leading: _Collage(tracks: store.tracksOf(p), cover: p.cover),
              title: Text(p.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  [
                    if (p.owner != null) p.owner!,
                    tracksWord(store.tracksOf(p).length),
                    if (p.description.isNotEmpty) p.description,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
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
  const _Collage({required this.tracks, this.cover, this.size = 52});
  final List<Track> tracks;
  final String? cover;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = cover;
    if (c != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size > 100 ? 8 : 4),
        child: Image(
          image: artworkProvider(c),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Artwork(
              track: tracks.isEmpty ? null : tracks.first, size: size, radius: 4),
        ),
      );
    }
    if (tracks.length < 4) {
      return Artwork(
          track: tracks.isEmpty ? null : tracks.first, size: size, radius: 4);
    }
    final half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size > 100 ? 8 : 4),
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

/// Плейлист или «Любимые треки» (когда playlistId == null).
class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});
  final String? playlistId;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  String _q = '';
  String? get playlistId => widget.playlistId;

  @override
  void initState() {
    super.initState();
    // Чужой плейлист: сразу подтягиваем свежую версию от автора.
    final id = playlistId;
    final p = id == null ? null : context.read<LibraryStore>().playlistById(id);
    if (p != null && p.isFollowed) context.read<AccountService>().refreshFollowed();
  }

  Future<void> _edit(BuildContext context, Playlist p) async {
    final store = context.read<LibraryStore>();
    final res = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _EditPlaylistDialog(playlist: p),
    );
    if (res == null || !context.mounted) return;
    if (res.delete) {
      final ok = await AppActions.confirm(context,
          title: 'Удалить плейлист?',
          body: '«${p.name}» будет удалён. Треки останутся в медиатеке.');
      if (ok && context.mounted) {
        Navigator.of(context).pop();
        store.deletePlaylist(p.id);
      }
      return;
    }
    String? cover;
    if (res.pickedCover != null) {
      try {
        cover = await context.read<AccountService>().saveCover(res.pickedCover!, 'playlist-${p.id}');
      } catch (_) {
        cover = res.pickedCover;
      }
    }
    store.updatePlaylist(p.id,
        name: res.name,
        description: res.description,
        cover: cover,
        removeCover: res.removeCover && cover == null);
  }

  Future<void> _share(BuildContext context, Playlist p, List<Track> tracks) async {
    final acc = context.read<AccountService>();
    if (!acc.signedIn) {
      AppActions.toast(context, 'Чтобы делиться, войди в аккаунт');
      return;
    }
    try {
      final link = await acc.sharePlaylist(p, tracks);
      await Clipboard.setData(ClipboardData(text: link));
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Ссылка скопирована'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(link, style: const TextStyle(fontFamily: 'monospace')),
              const SizedBox(height: 12),
              const Text(
                'Отправь её другу. В Hutred: «Добавить музыку» → «По ссылке» — '
                'плейлист появится у него и дальше будет обновляться сам, '
                'когда ты его меняешь. Ссылка у плейлиста всегда одна.',
                style: TextStyle(color: HutredTheme.muted),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Готово')),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        AppActions.toast(context, 'Не удалось поделиться: ${'$e'.replaceFirst('Exception: ', '')}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final player = context.read<PlayerService>();
    final playlist = playlistId == null ? null : store.playlistById(playlistId!);
    if (playlistId != null && playlist == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Плейлист удалён')));
    }
    final all = playlist == null ? store.favorites : store.tracksOf(playlist);
    // Поиск внутри плейлиста. Пока ищем — перетаскивать нельзя.
    final tracks = _q.isEmpty ? all : all.where((t) => trackMatches(t, _q)).toList();
    final name = playlist?.name ?? 'Любимые треки';
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final style = HutredStyle.of(context);
    final coverSize = style.glass ? (wide ? 168.0 : 220.0) : (wide ? 196.0 : 220.0);
    final scheme = Theme.of(context).colorScheme;
    final owner = playlist?.owner ?? context.watch<AccountService>().username ?? 'Ты';
    final meta = [
      tracksWord(all.length),
      if (totalDuration(all).isNotEmpty) totalDuration(all),
    ].join(', ');

    Widget cover = playlist == null
        ? Container(
            width: coverSize,
            height: coverSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10 * style.artScale),
              gradient: LinearGradient(
                colors: [
                  scheme.primary,
                  HSLColor.fromColor(scheme.primary).withLightness(0.3).toColor(),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(Icons.favorite, size: coverSize * 0.4, color: scheme.onPrimary),
          )
        : GestureDetector(
            onTap: playlist.isFollowed ? null : () => _edit(context, playlist),
            child: _Collage(tracks: tracks, cover: playlist.cover, size: coverSize),
          );
    // Тень под обложкой: у «Стекла» — цветное свечение.
    cover = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10 * style.artScale),
        boxShadow: [
          BoxShadow(
            color: style.glass
                ? scheme.primary.withValues(alpha: 0.45)
                : Colors.black.withValues(alpha: 0.5),
            blurRadius: style.glass ? 60 : 48,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: cover,
    );

    final label = playlist?.isFollowed == true ? 'Плейлист (подписка)' : 'Плейлист';
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (style.glass)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFD8D4FE))),
          )
        else if (wide)
          Text(style.sharp ? label.toUpperCase() : label,
              style: TextStyle(
                  fontSize: style.sharp ? 11 : 13,
                  letterSpacing: style.sharp ? 1 : 0,
                  fontWeight: FontWeight.w600,
                  color: style.sharp ? scheme.primary : const Color(0xFFD4D4D4))),
        SizedBox(height: style.glass ? 10 : 8),
        Text(name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style.display(wide ? (style.glass ? 44 : 64) : 26)),
        if ((playlist?.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(playlist!.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFA3A3A3))),
        ],
        const SizedBox(height: 8),
        // Как в Spotify: автор · число треков, общая длительность.
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: owner,
                style: const TextStyle(color: HutredTheme.text, fontWeight: FontWeight.w700)),
            TextSpan(text: ' · $meta'),
          ]),
          style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 13),
        ),
      ],
    );

    final header = Padding(
      padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 8, wide ? 32 : 20, wide ? 24 : 12),
      child: wide
          ? Row(
              crossAxisAlignment:
                  style.glass ? CrossAxisAlignment.center : CrossAxisAlignment.end,
              children: [
                cover,
                const SizedBox(width: 28),
                Expanded(child: titleBlock),
              ],
            )
          // Телефон: обложка по центру, под ней название.
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: cover),
                const SizedBox(height: 20),
                titleBlock,
              ],
            ),
    );

    final canPlay = tracks.isNotEmpty;
    void play() => player.playTracks(tracks);
    void shuffle() => player.shufflePlay(tracks);

    // Большая кнопка «Слушать»: круг (Моно), капсула со словом (Стекло),
    // прямоугольник цвета акцента (Резкий).
    final playButton = style.glass
        ? FilledButton.icon(
            onPressed: canPlay ? play : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Слушать'),
          )
        : SizedBox(
            width: style.sharp ? 76 : 56,
            height: 56,
            child: FilledButton(
              onPressed: canPlay ? play : null,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: style.sharp ? const RoundedRectangleBorder() : const CircleBorder(),
                backgroundColor: style.sharp ? scheme.primary : Colors.white,
                foregroundColor:
                    style.sharp ? HutredTheme.onAccent(scheme.primary) : Colors.black,
              ),
              child: const Icon(Icons.play_arrow_rounded, size: 32),
            ),
          );

    Widget iconAction(String tip, IconData icon, VoidCallback? onTap, {Color? color}) =>
        IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, size: 24, color: color ?? const Color(0xFFA3A3A3)),
        );

    final download = Builder(builder: (context) {
      final off = context.watch<OfflineService>();
      final pinned = off.isPinned(playlistId);
      final done = tracks.where(off.isDownloaded).length;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconAction(
            pinned ? 'Удалить загрузки' : 'Скачать для прослушивания без интернета',
            pinned ? Icons.arrow_circle_down_rounded : LucideIcons.circleArrowDown,
            tracks.isEmpty && !pinned ? null : () => off.pin(playlistId, !pinned),
            color: pinned ? scheme.primary : null,
          ),
          if (pinned && done < tracks.length)
            Text('$done/${tracks.length}',
                style: const TextStyle(color: HutredTheme.muted, fontSize: 12)),
        ],
      );
    });

    final unfollow = playlist != null && playlist.isFollowed
        ? iconAction('Убрать из моих плейлистов', LucideIcons.circleMinus, () async {
            final ok = await AppActions.confirm(context,
                title: 'Убрать плейлист?',
                body: '«${playlist.name}» пропадёт из твоих плейлистов. '
                    'Вернуть можно снова по ссылке или со страницы автора.',
                action: 'Убрать');
            if (ok && context.mounted) {
              Navigator.of(context).pop();
              store.deletePlaylist(playlist.id);
            }
          })
        : null;
    final edit = playlist != null && !playlist.isFollowed
        ? iconAction('Изменить: название, описание, обложка', LucideIcons.pencil,
            () => _edit(context, playlist))
        : null;
    final share = playlist != null
        ? iconAction('Поделиться ссылкой', LucideIcons.share, () => _share(context, playlist, all))
        : null;
    final search = all.length > 8
        ? ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: FilterField(
              hint: 'Найти в плейлисте',
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          )
        : null;

    final Widget actions;
    if (style.glass) {
      actions = Padding(
        padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 0, wide ? 32 : 20, 16),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            playButton,
            OutlinedButton.icon(
              onPressed: canPlay ? shuffle : null,
              icon: const Icon(LucideIcons.shuffle, size: 16),
              label: const Text('Перемешать'),
            ),
            if (playlist != null)
              OutlinedButton.icon(
                onPressed: () => _share(context, playlist, all),
                icon: const Icon(LucideIcons.share, size: 16),
                label: const Text('Поделиться'),
              ),
            download,
            if (edit != null) edit,
            if (unfollow != null) unfollow,
            if (search != null) search,
          ],
        ),
      );
    } else if (wide) {
      actions = Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
        child: Row(
          children: [
            playButton,
            const SizedBox(width: 12),
            iconAction('Перемешать', LucideIcons.shuffle, canPlay ? shuffle : null),
            download,
            if (share != null) share,
            if (edit != null) edit,
            if (unfollow != null) unfollow,
            const Spacer(),
            if (search != null) Flexible(child: search),
          ],
        ),
      );
    } else {
      // Телефон: слева скачать/поделиться, справа перемешать и «играть».
      actions = Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 20, 8),
        child: Column(
          children: [
            Row(
              children: [
                download,
                if (share != null) share,
                if (edit != null) edit,
                if (unfollow != null) unfollow,
                const Spacer(),
                iconAction('Перемешать', LucideIcons.shuffle, canPlay ? shuffle : null),
                const SizedBox(width: 8),
                playButton,
              ],
            ),
            if (search != null)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 8),
                child: Align(alignment: Alignment.centerLeft, child: search),
              ),
          ],
        ),
      );
    }

    // Шапка таблицы (# · название · альбом · время) — на компьютере в Моно/Резком.
    final columns = wide && !style.glass && tracks.isNotEmpty
        ? Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
            child: Container(
              padding: const EdgeInsets.only(bottom: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF1F1F1F))),
              ),
              child: const DefaultTextStyle(
                style: TextStyle(
                    color: Color(0xFF737373),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4),
                child: Row(children: [
                  SizedBox(width: 40, child: Text('#')),
                  Expanded(flex: 10, child: Text('НАЗВАНИЕ')),
                  SizedBox(width: 16),
                  Expanded(flex: 8, child: Text('АЛЬБОМ')),
                  SizedBox(width: 132, child: Text('ВРЕМЯ', textAlign: TextAlign.center)),
                ]),
              ),
            ),
          )
        : const SizedBox.shrink();

    // Фон шапки: мягкий градиент сверху, как в макете.
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final headerAll = Container(
      padding: EdgeInsets.only(top: top),
      decoration: style.glass
          ? null
          : BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  style.mono
                      ? const Color(0xFF2A2A2A)
                      : scheme.primary.withValues(alpha: 0.22),
                  Colors.transparent,
                ],
              ),
            ),
      child: Column(children: [header, actions, columns]),
    );

    Widget tile(int i) => TrackTile(
          key: ValueKey(tracks[i].id),
          track: tracks[i],
          number: i + 1,
          inFavorites: playlist == null,
          onTap: () => player.playTracks(tracks, start: i),
          // В «Любимых треках» «убрать» снимает ♥ — трек остаётся в медиатеке.
          onRemoveFromPlaylist: playlist == null
              ? () => store.toggleFavorite(tracks[i].id)
              : playlist.isFollowed
                  ? null
                  : () => store.removeFromPlaylist(playlist.id, tracks[i].id),
        );

    final empty = Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        playlist == null
            ? 'Нажми ♥ у трека, чтобы он появился здесь'
            : 'Добавляй треки через меню ⋮ → «Добавить в плейлист»',
        textAlign: TextAlign.center,
        style: const TextStyle(color: HutredTheme.muted),
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: playlist == null || playlist.isFollowed || tracks.isEmpty || _q.isNotEmpty
          ? ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                headerAll,
                if (all.isEmpty) empty,
                for (var i = 0; i < tracks.length; i++) tile(i),
              ],
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              header: headerAll,
              itemCount: tracks.length,
              onReorder: (o, n) => store.reorderPlaylist(playlist.id, o, n),
              itemBuilder: (_, i) => tile(i),
            ),
    );
  }
}

class _EditResult {
  _EditResult({
    this.name,
    this.description,
    this.pickedCover,
    this.removeCover = false,
    this.delete = false,
  });
  final String? name;
  final String? description;
  final String? pickedCover;
  final bool removeCover;
  final bool delete;
}

/// Изменить плейлист: обложка, название, описание (и удалить — внизу).
class _EditPlaylistDialog extends StatefulWidget {
  const _EditPlaylistDialog({required this.playlist});
  final Playlist playlist;

  @override
  State<_EditPlaylistDialog> createState() => _EditPlaylistDialogState();
}

class _EditPlaylistDialogState extends State<_EditPlaylistDialog> {
  late final _name = TextEditingController(text: widget.playlist.name);
  late final _desc = TextEditingController(text: widget.playlist.description);
  String? _picked;
  bool _remove = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = res?.files.single.path;
    if (path != null) {
      setState(() {
        _picked = path;
        _remove = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    final current = _remove ? null : (_picked ?? widget.playlist.cover);
    return AlertDialog(
      title: const Text('Сведения о плейлисте'),
      content: SizedBox(
        width: 460,
        child: Flex(
          // На телефоне обложка над полями, на компьютере — слева.
          direction: MediaQuery.sizeOf(context).width < 560 ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _pick,
                  child: _Collage(
                    tracks: store.tracksOf(widget.playlist),
                    cover: current,
                    size: 140,
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(onPressed: _pick, child: const Text('Выбрать обложку')),
                if (current != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _picked = null;
                      _remove = true;
                    }),
                    child: const Text('Убрать'),
                  ),
              ],
            ),
            const SizedBox(width: 16, height: 8),
            Flexible(
              fit: FlexFit.loose,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Название'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _desc,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Описание'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, _EditResult(delete: true)),
          child: const Text('Удалить плейлист'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _EditResult(
                  name: _name.text,
                  description: _desc.text,
                  pickedCover: _picked,
                  removeCover: _remove,
                ),
              ),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ],
    );
  }
}
