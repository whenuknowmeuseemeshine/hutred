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

enum _Sort { recent, title, artist }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  _Sort _sort = _Sort.recent;
  TrackSource? _source;
  bool _favOnly = false;
  String _q = '';
  bool _downloadedOnly = false;

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

  String get _filterLabel => _downloadedOnly
      ? 'Скачанные'
      : _favOnly
          ? 'Любимые треки'
          : (_source == null ? 'Все треки' : sourceLabel(_source!));

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

  List<Track> _visible(LibraryStore store, OfflineService offline) {
    var list = store.tracks.where((t) {
      if (_downloadedOnly && !offline.isDownloaded(t)) return false;
      if (_favOnly && !t.favorite) return false;
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
    final tracks = _visible(store, offline);
    final st = HutredStyle.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final pad = stylePagePadding(context);
    final filtered = _favOnly || _downloadedOnly || _source != null || _q.isNotEmpty;
    // Источники, которые реально есть в медиатеке, — фишками.
    final sources = TrackSource.values.where((src) => store.tracks.any((t) => t.source == src));

    Widget chip(String label, bool on, VoidCallback onTap) =>
        StyleChip(label: label, selected: on, onTap: onTap);

    final header = Padding(
      padding: EdgeInsets.fromLTRB(
          pad.left, MediaQuery.paddingOf(context).top + pad.top, pad.right, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!wide) ...[
            const HutredLogo(size: 34),
            const SizedBox(width: 12),
          ],
          Expanded(child: Text('Медиатека', style: st.display(wide ? 48 : 30))),
          if (!wide) const AccountButton(),
          if (store.tracks.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _sel = {}),
              icon: Icon(Ic.checklist_rtl, size: 20),
              label: const Text('Выбрать'),
            ),
          const SizedBox(width: 8),
          StyleButton(
            label: 'Добавить',
            icon: Ic.add,
            primary: false,
            onPressed: () => AppActions.showAddSheet(context),
          ),
        ],
      ),
    );

    final filters = Padding(
      padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, 18),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          chip('Все', !filtered || (_q.isNotEmpty && !_favOnly && !_downloadedOnly && _source == null),
              () => setState(() {
                    _favOnly = false;
                    _downloadedOnly = false;
                    _source = null;
                  })),
          chip('Любимые', _favOnly, () => setState(() {
                _favOnly = !_favOnly;
                _downloadedOnly = false;
                _source = null;
              })),
          chip('Скачанные', _downloadedOnly, () => setState(() {
                _downloadedOnly = !_downloadedOnly;
                _favOnly = false;
                _source = null;
              })),
          for (final src in sources)
            chip(sourceLabel(src), _source == src, () => setState(() {
                  _source = _source == src ? null : src;
                  _favOnly = false;
                  _downloadedOnly = false;
                })),
          FilterField(
            width: 220,
            hint: 'Найти в медиатеке',
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
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
        ],
      ),
    );

    // Верх как в макете: большая карточка «Любимые треки» и плитки плейлистов.
    final hero = filtered || _sel != null
        ? null
        : Padding(
            padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, 24),
            child: _LibraryHero(favorites: store.favorites, playlists: store.playlists),
          );

    final listHead = Padding(
      padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right - 8, 8),
      child: Row(
        children: [
          StyleCaption(filtered ? _filterLabel : _sortLabels[_sort]!.$1),
          const SizedBox(width: 10),
          Text(tracksWord(tracks.length),
              style: const TextStyle(color: HutredTheme.muted, fontSize: 13)),
          const Spacer(),
          // Скачать все любимые (и докачивать новые лайки).
          Builder(builder: (context) {
            final pinned = offline.isPinned(null);
            final favs = store.favorites;
            final done = favs.where(offline.isDownloaded).length;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pinned && done < favs.length)
                  Text('$done/${favs.length}',
                      style: const TextStyle(color: HutredTheme.muted, fontSize: 12)),
                IconButton(
                  tooltip: pinned
                      ? 'Любимые скачаны — нажми, чтобы удалить загрузки'
                      : 'Скачать все любимые треки (новые лайки тоже скачаются)',
                  onPressed: favs.isEmpty && !pinned
                      ? null
                      : () {
                          offline.pin(null, !pinned);
                          AppActions.toast(
                              context,
                              pinned
                                  ? 'Загрузки любимых удалены'
                                  : 'Скачиваю любимые: ${tracksWord(favs.length)}');
                        },
                  icon: Icon(
                    pinned ? Ic.arrow_circle_down_rounded : Ic.arrow_circle_down_outlined,
                    color: pinned ? Theme.of(context).colorScheme.primary : Colors.white70,
                  ),
                ),
              ],
            );
          }),
          IconButton(
            tooltip: !player.shuffle
                ? 'Перемешивание выключено'
                : (player.smartShuffle
                    ? 'Перемешивание с рекомендациями'
                    : 'Перемешивание включено'),
            onPressed: player.toggleShuffle,
            icon: ShuffleIcon(on: player.shuffle, smart: player.smartShuffle, size: 24),
          ),
          const SizedBox(width: 6),
          _PlayButton(
            playing: player.playing && player.isFrom(tracks),
            onPressed: tracks.isEmpty ? null : () => player.playOrToggle(tracks, all: true),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: _sel != null ? _selectionBar(tracks, store, offline) : null,
      body: store.tracks.isEmpty
          ? Column(children: [header, const Expanded(child: _EmptyLibrary())])
          : CustomScrollView(
              slivers: [
                if (_sel == null) SliverToBoxAdapter(child: header),
                SliverToBoxAdapter(child: filters),
                if (hero != null) SliverToBoxAdapter(child: hero),
                SliverToBoxAdapter(child: listHead),
                if (tracks.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('Под фильтр ничего не попало')),
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
                                child: TrackTile(
                                  track: tracks[i],
                                  onTap: () => _toggle(tracks[i].id),
                                ),
                              ),
                            ],
                          ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
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
class _LibraryHero extends StatelessWidget {
  const _LibraryHero({required this.favorites, required this.playlists});
  final List<Track> favorites;
  final List<Playlist> playlists;

  void _open(BuildContext context, String? id) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlistId: id)));

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    final store = context.read<LibraryStore>();
    final dur = totalDuration(favorites);
    final sub = [tracksWord(favorites.length), if (dur.isNotEmpty) dur].join(' · ');

    Widget favCard(double h) => FavoritesCard(
          favorites: favorites,
          subtitle: sub,
          height: h,
          onOpen: () => _open(context, null),
        );

    Widget tile(Playlist p, double size) {
      final tracks = store.tracksOf(p);
      return InkWell(
        onTap: () => _open(context, p.id),
        borderRadius: BorderRadius.circular(st.radius),
        child: SizedBox(
          width: size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PlaylistCollage(tracks: tracks, cover: p.cover, size: size),
              const SizedBox(height: 8),
              Text(p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: st.glass ? FontWeight.w700 : FontWeight.w600)),
              Text('Плейлист · ${tracks.length}',
                  maxLines: 1,
                  style: const TextStyle(fontSize: 12, color: HutredTheme.muted)),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      if (w < 700) {
        // Телефон: карточка во всю ширину, плейлисты — лентой.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            favCard(196),
            if (playlists.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 186,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: playlists.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (_, i) => tile(playlists[i], 140),
                ),
              ),
            ],
          ],
        );
      }
      const gap = 18.0;
      // Карточка любимых крупно слева, справа — сколько влезет плейлистов.
      final favW = min(max(w * 0.48, 520.0), 680.0);
      const size = 250.0;
      final left = w - favW;
      final count = max(0, ((left + gap) / (size + gap)).floor());
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: favW, child: favCard(300)),
          for (final p in playlists.take(count)) ...[
            const SizedBox(width: gap),
            tile(p, size),
          ],
        ],
      );
    });
  }
}

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
