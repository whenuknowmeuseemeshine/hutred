import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/import_service.dart';
import '../../services/library_store.dart';
import '../../services/settings_store.dart';
import '../spotify_check.dart';
import '../../services/offline_service.dart';
import '../../services/player_service.dart';
import '../actions.dart';
import '../theme.dart';
import '../widgets/account_button.dart';
import '../widgets/controls.dart';
import '../widgets/favorites_card.dart';
import '../widgets/filter_field.dart';
import '../widgets/logo.dart';
import '../widgets/track_tile.dart';
import '../icons.dart';
import '../widgets/style_bits.dart';
import '../../models/playlist.dart';
import 'playlists_screen.dart';
import 'artist_screen.dart';
import '../widgets/artwork.dart';

enum _Sort { recent, title, artist }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

enum _Tab { tracks, playlists, artists, albums, downloaded }

class _LibraryScreenState extends State<LibraryScreen> {
  _Sort _sort = _Sort.recent;
  TrackSource? _source;
  String _q = '';
  _Tab _tab = _Tab.tracks;

  /// Режим выбора: id выбранных треков (null — режим выключен).
  Set<String>? _sel;

  /// Пробить выбранные треки по Spotify и подставить их сведения.
  Future<void> _spotifyFix(List<Track> picked) async {
    final check = context.read<SpotifyCheck>();
    final messenger = ScaffoldMessenger.of(context);
    final progress = ValueNotifier<String>('Сверяю со Spotify…');
    messenger.showSnackBar(SnackBar(
      duration: const Duration(minutes: 30),
      content: ValueListenableBuilder<String>(
        valueListenable: progress,
        builder: (_, v, __) => Text(v),
      ),
    ));
    final n = await check.applyAll(
        picked, (d, t) => progress.value = 'Сверяю со Spotify… $d из $t');
    messenger.hideCurrentSnackBar();
    if (!mounted) return;
    AppActions.toast(
        context,
        n == 0
            ? 'В Spotify ничего не нашлось'
            : 'Обновлены сведения: ${tracksWord(n)} из ${picked.length}. '
                'Тексты для них найдутся заново при включении.');
    setState(() => _sel = null);
  }

  void _toggle(String id) => setState(() {
        if (!_sel!.remove(id)) _sel!.add(id);
      });

  /// Шапка в режиме выбора: сколько выбрано и что с ними сделать.
  AppBar _selectionBar(List<Track> visible, LibraryStore store, OfflineService offline) {
    final picked = visible.where((t) => _sel!.contains(t.id)).toList();
    final all = picked.length == visible.length && visible.isNotEmpty;
    final allFav = picked.isNotEmpty && picked.every((t) => t.favorite);
    final none = picked.isEmpty;
    return AppBar(
      leading: IconButton(
        tooltip: 'Отменить выбор',
        onPressed: () => setState(() => _sel = null),
        icon: Icon(Ic.close),
      ),
      title: Text(none ? 'Выбери треки' : 'Выбрано: ${picked.length}'),
      actions: [
        IconButton(
          tooltip: all ? 'Снять выбор со всех' : 'Выбрать все',
          onPressed: () => setState(() {
            if (all) {
              _sel!.clear();
            } else {
              _sel!.addAll(visible.map((t) => t.id));
            }
          }),
          icon: Icon(all ? Ic.deselect : Ic.select_all),
        ),
        IconButton(
          tooltip: allFav ? 'Убрать из любимых' : 'В любимые',
          onPressed: none
              ? null
              : () {
                  store.setFavorite(picked.map((t) => t.id), !allFav);
                  AppActions.toast(context,
                      allFav ? 'Убрано из любимых' : 'В любимых: ${tracksWord(picked.length)}');
                },
          icon: Icon(allFav ? Ic.favorite : Ic.favorite_border),
        ),
        if (context.read<SettingsStore>().hasSpotifyKeys)
          IconButton(
            tooltip: 'Сведения из Spotify: точные название, исполнитель, альбом и обложка',
            onPressed: none ? null : () => _spotifyFix(picked),
            icon: Icon(Ic.graphic_eq),
          ),
        IconButton(
          tooltip: 'Добавить в плейлист',
          onPressed: none ? null : () => AppActions.addManyToPlaylistDialog(context, picked),
          icon: Icon(Ic.playlist_add),
        ),
        IconButton(
          tooltip: 'Скачать',
          onPressed: none
              ? null
              : () {
                  offline.downloadAll(picked);
                  AppActions.toast(context, 'Скачиваю: ${tracksWord(picked.length)}');
                },
          icon: Icon(Ic.download_outlined),
        ),
        IconButton(
          tooltip: 'Удалить из медиатеки',
          onPressed: none
              ? null
              : () async {
                  final ok = await AppActions.confirm(context,
                      title: 'Удалить ${tracksWord(picked.length)}?',
                      body: 'Они пропадут из медиатеки и всех плейлистов. '
                          'Файлы на диске останутся.');
                  if (!ok) return;
                  store.removeTracks(picked.map((t) => t.id));
                  setState(() => _sel = null);
                },
          icon: Icon(Ic.delete_outline),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  static final _sortLabels = {
    _Sort.recent: ('Недавно добавленные', Ic.schedule),
    _Sort.title: ('По названию', Ic.sort_by_alpha),
    _Sort.artist: ('По исполнителю', Ic.person_outline),
  };

  /// Пункт меню в том же стиле, что и меню трека: значок + текст + галочка.
  PopupMenuItem<T> _item<T>(T value, IconData icon, String text, bool selected) =>
      PopupMenuItem<T>(
        value: value,
        height: 40,
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white70),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            if (selected)
              Icon(Ic.check, size: 18, color: Theme.of(context).colorScheme.primary),
          ],
        ),
      );

  /// Кнопка-«выпадашка»: подпись текущего выбора и стрелка вниз.
  Widget _dropdown<T>({
    required IconData icon,
    required String label,
    required List<PopupMenuEntry<T>> Function() items,
    required ValueChanged<T> onSelected,
    required String tooltip,
  }) {
    return PopupMenuButton<T>(
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: (_) => items(),
      // Меню открывается под кнопкой и такое же скруглённое.
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(minWidth: 220),
      // Подсветка при наведении — по форме кнопки, а не квадратом.
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Ic.expand_more, size: 18),
          ],
        ),
      ),
    );
  }

  /// Медиатека = любимые треки (как в Spotify).
  List<Track> _visible(LibraryStore store, OfflineService offline) {
    var list = store.favorites.where((t) {
      if (_tab == _Tab.downloaded && !offline.isDownloaded(t)) return false;
      if (_source != null && t.source != _source) return false;
      if (_q.isNotEmpty && !trackMatches(t, _q)) return false;
      return true;
    }).toList();
    switch (_sort) {
      case _Sort.recent:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case _Sort.title:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case _Sort.artist:
        list.sort((a, b) {
          final c = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          return c != 0 ? c : a.album.compareTo(b.album);
        });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final player = context.watch<PlayerService>();
    final offline = context.watch<OfflineService>();
    final favs = store.favorites;
    final tracks = _visible(store, offline);
    final st = HutredStyle.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final pad = stylePagePadding(context);
    final downloaded = favs.where(offline.isDownloaded).length;
    final dur = totalDuration(favs);
    final sources = TrackSource.values.where((src) => favs.any((t) => t.source == src)).toList();
    final artists = _groupArtists(favs);
    final albums = _groupAlbums(favs);

    // ---------- Шапка ----------
    final header = Padding(
      padding: EdgeInsets.fromLTRB(
          pad.left, MediaQuery.paddingOf(context).top + pad.top, pad.right, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!wide) ...[
            const HutredLogo(size: 34),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(st.sharp ? 'МЕДИАТЕКА' : 'Медиатека', style: st.display(wide ? 46 : 28)),
              if (wide) ...[
                const SizedBox(height: 4),
                Text(
                  [tracksWord(favs.length), if (dur.isNotEmpty) dur, if (downloaded > 0) '$downloaded скачано']
                      .join(' · '),
                  style: st.sharp
                      ? st.caption(color: HutredTheme.muted)
                      : const TextStyle(color: HutredTheme.muted, fontSize: 13),
                ),
              ],
            ]),
          ),
          if (!wide) const AccountButton(),
          if (wide && (_tab == _Tab.tracks || _tab == _Tab.downloaded))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterField(
                width: 260,
                hint: 'Найти в медиатеке',
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
          if (favs.isNotEmpty && (_tab == _Tab.tracks || _tab == _Tab.downloaded))
            IconButton(
              tooltip: 'Выбрать несколько',
              onPressed: () => setState(() => _sel = {}),
              icon: Icon(Ic.checklist_rtl, size: 20),
            ),
          const SizedBox(width: 4),
          StyleButton(
            label: _tab == _Tab.playlists ? 'Новый плейлист' : 'Добавить',
            icon: Ic.add,
            primary: _tab == _Tab.playlists,
            onPressed: () => _tab == _Tab.playlists
                ? _newPlaylist(context, store)
                : AppActions.showAddSheet(context),
          ),
        ],
      ),
    );

    // ---------- Вкладки ----------
    final tabs = Padding(
      padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, 18),
      child: _LibTabs(
        selected: _tab,
        onSelect: (t) => setState(() {
          _tab = t;
          _sel = null;
        }),
        counts: {
          _Tab.tracks: favs.length,
          _Tab.playlists: store.playlists.length,
          _Tab.artists: artists.length,
          _Tab.albums: albums.length,
          _Tab.downloaded: downloaded,
        },
      ),
    );

    final listTab = _tab == _Tab.tracks || _tab == _Tab.downloaded;

    // ---------- Верх вкладки «Треки»: любимые и «часто слушаешь» ----------
    Widget? hero;
    if (_tab == _Tab.tracks && _q.isEmpty && _source == null && _sel == null) {
      final top = List.of(favs)..sort((a, b) => b.plays.compareTo(a.plays));
      final often = top.where((t) => t.plays > 0).take(6).toList();
      final card = FavoritesCard(
        favorites: favs,
        subtitle: '${tracksWord(favs.length)}${dur.isEmpty ? '' : ' · $dur'}',
        height: wide ? 220 : 196,
        onOpen: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const PlaylistDetailScreen(playlistId: null))),
      );
      hero = Padding(
        padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, 22),
        child: wide && often.isNotEmpty
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 520, child: card),
                const SizedBox(width: 20),
                Expanded(child: _Often(tracks: often, all: favs)),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                card,
                if (often.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _Often(tracks: often, all: favs, strip: true),
                ],
              ]),
      );
    }

    // ---------- Заголовок списка ----------
    final listHead = Padding(
      padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right - 8, 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          Text(
            _tab == _Tab.downloaded
                ? (st.sharp ? 'СКАЧАННЫЕ' : 'Скачанные')
                : (st.sharp ? 'ВСЕ ТРЕКИ' : 'Все треки'),
            style: st.display(20),
          ),
          Text(tracksWord(tracks.length),
              style: const TextStyle(color: HutredTheme.muted, fontSize: 13)),
          const SizedBox(width: 8),
          _dropdown<_Sort>(
            tooltip: 'Сортировка',
            icon: _sortLabels[_sort]!.$2,
            label: _sortLabels[_sort]!.$1,
            onSelected: (v) => setState(() => _sort = v),
            items: () => [
              for (final e in _sortLabels.entries)
                _item(e.key, e.value.$2, e.value.$1, _sort == e.key),
            ],
          ),
          if (sources.length > 1)
            _dropdown<int>(
              tooltip: 'Откуда трек',
              icon: Ic.library_music_outlined,
              label: _source == null ? 'Все источники' : sourceLabel(_source!),
              onSelected: (v) => setState(() => _source = v < 0 ? null : TrackSource.values[v]),
              items: () => [
                _item(-1, Ic.library_music_outlined, 'Все источники', _source == null),
                for (final src in sources)
                  _item(src.index, Ic.library_music_outlined, sourceLabel(src), _source == src),
              ],
            ),
          if (!wide)
            SizedBox(
              width: 200,
              child: FilterField(hint: 'Найти', onChanged: (v) => setState(() => _q = v.trim())),
            ),
        ],
      ),
    );
    final listActions = Padding(
      padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right - 8, 6),
      child: Row(children: [
        const Spacer(),
        Builder(builder: (context) {
          final pinned = offline.isPinned(null);
          return IconButton(
            tooltip: pinned
                ? 'Медиатека скачана — нажми, чтобы удалить загрузки'
                : 'Скачать всю медиатеку (новые лайки тоже скачаются)',
            onPressed: favs.isEmpty && !pinned
                ? null
                : () {
                    offline.pin(null, !pinned);
                    AppActions.toast(context,
                        pinned ? 'Загрузки удалены' : 'Скачиваю: ${tracksWord(favs.length)}');
                  },
            icon: Icon(
              pinned ? Ic.arrow_circle_down_rounded : Ic.arrow_circle_down_outlined,
              color: pinned ? Theme.of(context).colorScheme.primary : Colors.white70,
            ),
          );
        }),
        IconButton(
          tooltip: !player.shuffle
              ? 'Перемешивание выключено'
              : (player.smartShuffle ? 'Перемешивание с рекомендациями' : 'Перемешивание включено'),
          onPressed: player.toggleShuffle,
          icon: ShuffleIcon(on: player.shuffle, smart: player.smartShuffle, size: 24),
        ),
        const SizedBox(width: 6),
        _PlayButton(
          playing: player.playing && player.isFrom(tracks),
          onPressed: tracks.isEmpty ? null : () => player.playOrToggle(tracks, all: true),
        ),
      ]),
    );

    Widget gridOf(List<Widget> items, double maxW) => Padding(
          padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, 120),
          child: LayoutBuilder(builder: (context, box) {
            const gap = 18.0;
            final cols = max(2, ((box.maxWidth + gap) / (maxW + gap)).floor());
            final w = (box.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(spacing: gap, runSpacing: 22, children: [
              for (final it in items) SizedBox(width: w, child: it),
            ]);
          }),
        );

    final List<Widget> slivers;
    if (favs.isEmpty && store.playlists.isEmpty) {
      slivers = [
        SliverToBoxAdapter(child: header),
        const SliverFillRemaining(hasScrollBody: false, child: _EmptyLibrary()),
      ];
    } else if (listTab) {
      slivers = [
        if (_sel == null) SliverToBoxAdapter(child: header),
        if (_sel == null) SliverToBoxAdapter(child: tabs),
        if (hero != null) SliverToBoxAdapter(child: hero),
        SliverToBoxAdapter(child: listHead),
        SliverToBoxAdapter(child: listActions),
        if (tracks.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(_tab == _Tab.downloaded ? 'Скачанных треков пока нет' : 'Ничего не нашлось',
                  style: const TextStyle(color: HutredTheme.muted)),
            ),
          )
        else
          SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (context, i) => _sel == null
                ? TrackTile(
                    key: ValueKey(tracks[i].id),
                    track: tracks[i],
                    number: i + 1,
                    onTap: () => player.playTracks(tracks, start: i),
                  )
                : Row(
                    key: ValueKey('sel${tracks[i].id}'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Checkbox(
                          value: _sel!.contains(tracks[i].id),
                          onChanged: (_) => _toggle(tracks[i].id),
                        ),
                      ),
                      Expanded(
                        child: TrackTile(track: tracks[i], onTap: () => _toggle(tracks[i].id)),
                      ),
                    ],
                  ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ];
    } else if (_tab == _Tab.playlists) {
      slivers = [
        SliverToBoxAdapter(child: header),
        SliverToBoxAdapter(child: tabs),
        SliverToBoxAdapter(
          child: gridOf([
            _NewPlaylistTile(onTap: () => _newPlaylist(context, store)),
            for (final p in store.playlists) _PlaylistTile(playlist: p),
          ], 220),
        ),
      ];
    } else if (_tab == _Tab.artists) {
      slivers = [
        SliverToBoxAdapter(child: header),
        SliverToBoxAdapter(child: tabs),
        SliverToBoxAdapter(
          child: gridOf([
            for (final a in artists)
              _CircleTile(
                track: a.cover,
                title: a.name,
                subtitle: tracksWord(a.count),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => ArtistScreen(name: a.name))),
              ),
          ], 170),
        ),
      ];
    } else {
      slivers = [
        SliverToBoxAdapter(child: header),
        SliverToBoxAdapter(child: tabs),
        SliverToBoxAdapter(
          child: gridOf([
            for (final al in albums)
              _AlbumTile(
                title: al.title,
                artist: al.artist,
                tracks: al.tracks,
              ),
          ], 200),
        ),
      ];
    }

    return Scaffold(
      appBar: _sel != null ? _selectionBar(tracks, store, offline) : null,
      body: CustomScrollView(slivers: slivers),
    );
  }

  Future<void> _newPlaylist(BuildContext context, LibraryStore store) async {
    final name = await AppActions.askText(context,
        title: 'Новый плейлист', hint: 'Название', action: 'Создать');
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final p = store.createPlaylist(name.trim());
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlistId: p.id)));
  }

  static List<({String name, int count, Track cover})> _groupArtists(List<Track> list) {
    final by = <String, List<Track>>{};
    for (final t in list) {
      final a = t.artist.split(RegExp(r'\s*(?:,|&|\bfeat\.?|\bft\.?)\s*')).first.trim();
      if (a.isEmpty || a == Track.unknownArtist) continue;
      by.putIfAbsent(a, () => []).add(t);
    }
    final out = [
      for (final e in by.entries)
        (name: e.key, count: e.value.length, cover: e.value.firstWhere((t) => t.artworkUrl != null, orElse: () => e.value.first)),
    ]..sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  static List<({String title, String artist, List<Track> tracks})> _groupAlbums(List<Track> list) {
    final by = <String, List<Track>>{};
    for (final t in list) {
      final al = t.shownAlbum;
      if (al.isEmpty) continue;
      by.putIfAbsent('${al.toLowerCase()}|${t.artist.toLowerCase()}', () => []).add(t);
    }
    final out = [
      for (final e in by.values) (title: e.first.shownAlbum, artist: e.first.artist, tracks: e),
    ]..sort((a, b) => b.tracks.length.compareTo(a.tracks.length));
    return out;
  }
}

/// Вкладки медиатеки: подчёркивание (Моно), «таблетка» (Стекло), ячейка акцента (Резкий).
class _LibTabs extends StatelessWidget {
  const _LibTabs({required this.selected, required this.onSelect, required this.counts});
  final _Tab selected;
  final ValueChanged<_Tab> onSelect;
  final Map<_Tab, int> counts;

  static const _labels = {
    _Tab.tracks: 'Треки',
    _Tab.playlists: 'Плейлисты',
    _Tab.artists: 'Исполнители',
    _Tab.albums: 'Альбомы',
    _Tab.downloaded: 'Скачанные',
  };

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final line = st.glass ? Colors.white.withValues(alpha: 0.08) : const Color(0xFF1F1F1F);
    return Container(
      decoration: st.glass ? null : BoxDecoration(border: Border(bottom: BorderSide(color: line))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final t in _Tab.values)
            Builder(builder: (context) {
              final on = t == selected;
              final fg = on
                  ? (st.sharp ? HutredTheme.onAccent(accent) : HutredTheme.text)
                  : HutredTheme.muted;
              final label = st.sharp ? _labels[t]!.toUpperCase() : _labels[t]!;
              return Padding(
                padding: EdgeInsets.only(right: st.sharp ? 0 : 4),
                child: Material(
                  color: on
                      ? (st.sharp
                          ? accent
                          : st.glass
                              ? accent.withValues(alpha: 0.22)
                              : Colors.transparent)
                      : Colors.transparent,
                  shape: st.glass ? const StadiumBorder() : const RoundedRectangleBorder(),
                  child: InkWell(
                    customBorder: st.glass ? const StadiumBorder() : const RoundedRectangleBorder(),
                    onTap: () => onSelect(t),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: st.sharp ? 18 : 14, vertical: 10),
                      decoration: st.mono
                          ? BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: on ? HutredTheme.text : Colors.transparent, width: 2)))
                          : null,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(label,
                            style: st.sharp
                                ? st.caption(size: 13, color: fg)
                                : TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: fg)),
                        const SizedBox(width: 6),
                        Text('${counts[t] ?? 0}',
                            style: TextStyle(
                                fontSize: 12,
                                color: on && st.sharp ? fg : HutredTheme.muted)),
                      ]),
                    ),
                  ),
                ),
              );
            }),
        ]),
      ),
    );
  }
}

/// «Часто слушаешь»: плитки (на компьютере — сетка 2×3, на телефоне — лента).
class _Often extends StatelessWidget {
  const _Often({required this.tracks, required this.all, this.strip = false});
  final List<Track> tracks;
  final List<Track> all;
  final bool strip;

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    final player = context.read<PlayerService>();
    final caption = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: StyleCaption('Часто слушаешь'),
    );
    if (strip) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        caption,
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tracks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => InkWell(
              onTap: () => player.playTracks(tracks, start: i),
              child: SizedBox(
                width: 104,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Artwork(track: tracks[i], size: 104, radius: st.sharp ? 0 : st.glass ? 14 : 8),
                  const SizedBox(height: 6),
                  Text(tracks[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      caption,
      LayoutBuilder(builder: (context, box) {
        const gap = 8.0;
        final w = (box.maxWidth - gap) / 2;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final (i, t) in tracks.indexed)
            SizedBox(
              width: w,
              child: Material(
                color: st.sharp
                    ? Colors.transparent
                    : st.glass
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFF161616),
                shape: st.sharp
                    ? const RoundedRectangleBorder(side: BorderSide(color: Color(0xFF2A2A2A)))
                    : RoundedRectangleBorder(borderRadius: BorderRadius.circular(st.glass ? 14 : 8)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => player.playTracks(tracks, start: i),
                  child: Row(children: [
                    Artwork(track: t, size: 56, radius: 0),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        Text(t.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: HutredTheme.muted)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                  ]),
                ),
              ),
            ),
        ]);
      }),
    ]);
  }
}

class _NewPlaylistTile extends StatelessWidget {
  const _NewPlaylistTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    final r = BorderRadius.circular(st.sharp ? 0 : st.glass ? 18 : 10);
    return InkWell(
      onTap: onTap,
      borderRadius: r,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: r,
              border: Border.all(color: const Color(0xFF3A3A3A), width: 1.5),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Ic.add, size: 30, color: HutredTheme.muted),
              const SizedBox(height: 8),
              const Text('Новый плейлист',
                  style: TextStyle(color: HutredTheme.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Создать', style: TextStyle(fontWeight: FontWeight.w700)),
        const Text('или перенести из Spotify',
            style: TextStyle(fontSize: 12, color: HutredTheme.muted)),
      ]),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist});
  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    final tracks = store.tracksOf(playlist);
    return InkWell(
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlistId: playlist.id))),
      child: LayoutBuilder(builder: (context, box) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PlaylistCollage(tracks: tracks, cover: playlist.cover, size: box.maxWidth),
          const SizedBox(height: 8),
          Text(playlist.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(tracksWord(tracks.length), style: const TextStyle(fontSize: 12, color: HutredTheme.muted)),
        ]);
      }),
    );
  }
}

class _CircleTile extends StatelessWidget {
  const _CircleTile({required this.track, required this.title, required this.subtitle, required this.onTap});
  final Track track;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    return InkWell(
      onTap: onTap,
      child: LayoutBuilder(builder: (context, box) {
        return Column(children: [
          Artwork(track: track, size: box.maxWidth, radius: st.sharp ? 0 : box.maxWidth / 2),
          const SizedBox(height: 8),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: HutredTheme.muted)),
        ]);
      }),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({required this.title, required this.artist, required this.tracks});
  final String title;
  final String artist;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _TrackListScreen(title: title, subtitle: artist, tracks: tracks))),
      child: LayoutBuilder(builder: (context, box) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Artwork(track: tracks.first, size: box.maxWidth, radius: st.sharp ? 0 : st.glass ? 18 : 8),
          const SizedBox(height: 8),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('$artist · ${tracksWord(tracks.length)}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: HutredTheme.muted)),
        ]);
      }),
    );
  }
}

/// Простой список треков (альбом из медиатеки).
class _TrackListScreen extends StatelessWidget {
  const _TrackListScreen({required this.title, required this.subtitle, required this.tracks});
  final String title;
  final String subtitle;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final st = HutredStyle.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        children: [
          Row(children: [
            Artwork(track: tracks.first, size: 140, radius: st.sharp ? 0 : 10),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: st.display(28)),
                const SizedBox(height: 4),
                Text('$subtitle · ${tracksWord(tracks.length)}',
                    style: const TextStyle(color: HutredTheme.muted)),
                const SizedBox(height: 12),
                _PlayButton(
                  playing: player.playing && player.isFrom(tracks),
                  onPressed: () => player.playOrToggle(tracks),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          for (final (i, t) in tracks.indexed)
            TrackTile(track: t, number: i + 1, onTap: () => player.playTracks(tracks, start: i)),
        ],
      ),
    );
  }
}

/// Кнопка «Слушать всё» в стиле: белый круг / круг акцента / салатовый прямоугольник.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onPressed, this.playing = false});
  final VoidCallback? onPressed;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final bg = st.mono ? Colors.white : accent;
    return SizedBox(
      width: st.sharp ? 64 : 48,
      height: 48,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: st.sharp ? const RoundedRectangleBorder() : const CircleBorder(),
          backgroundColor: bg,
          foregroundColor: st.mono ? Colors.black : HutredTheme.onAccent(accent),
        ),
        child: Icon(playing ? Ic.pause_rounded : Ic.play_arrow_rounded, size: 28),
      ),
    );
  }
}

/// «Любимые треки» крупной карточкой и плитки плейлистов рядом.
class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Ic.library_music_outlined,
                  size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              const Text('Медиатека пока пустая',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                'Добавь треки с компьютера или телефона, вставь ссылку '
                '(Spotify, SoundCloud, YouTube, mp3, радио) или найди трек во вкладке «Поиск».',
                textAlign: TextAlign.center,
                style: TextStyle(color: HutredTheme.muted, height: 1.4),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  // Обе кнопки в одном стиле: «с устройства» и «по ссылке».
                  FilledButton.tonalIcon(
                    onPressed: () => AppActions.addFromDevice(context),
                    icon: Icon(Ic.audio_file_outlined),
                    label: Text(ImportService.isDesktop ? 'Файлы или папка' : 'Файлы'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => AppActions.addUrlDialog(context),
                    icon: Icon(Ic.link),
                    label: const Text('Ссылка'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
