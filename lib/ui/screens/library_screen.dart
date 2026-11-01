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
import '../widgets/logo.dart';
import '../widgets/track_tile.dart';

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
        icon: const Icon(Icons.close),
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
          icon: Icon(all ? Icons.deselect : Icons.select_all),
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
          icon: Icon(allFav ? Icons.favorite : Icons.favorite_border),
        ),
        if (context.read<SettingsStore>().hasSpotifyKeys)
          IconButton(
            tooltip: 'Сведения из Spotify: точные название, исполнитель, альбом и обложка',
            onPressed: none ? null : () => _spotifyFix(picked),
            icon: const Icon(Icons.graphic_eq),
          ),
        IconButton(
          tooltip: 'Добавить в плейлист',
          onPressed: none ? null : () => AppActions.addManyToPlaylistDialog(context, picked),
          icon: const Icon(Icons.playlist_add),
        ),
        IconButton(
          tooltip: 'Скачать',
          onPressed: none
              ? null
              : () {
                  offline.downloadAll(picked);
                  AppActions.toast(context, 'Скачиваю: ${tracksWord(picked.length)}');
                },
          icon: const Icon(Icons.download_outlined),
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
          icon: const Icon(Icons.delete_outline),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  static const _sortLabels = {
    _Sort.recent: ('Недавно добавленные', Icons.schedule),
    _Sort.title: ('По названию', Icons.sort_by_alpha),
    _Sort.artist: ('По исполнителю', Icons.person_outline),
  };

  String get _filterLabel => _downloadedOnly
      ? 'Скачанные'
      : _favOnly
          ? 'Избранное'
          : (_source == null ? 'Все треки' : sourceLabel(_source!));

  IconData get _filterIcon => _downloadedOnly
      ? Icons.arrow_circle_down
      : _favOnly
          ? Icons.favorite
          : (_source == null ? Icons.library_music_outlined : sourceIcon(_source!));

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
              Icon(Icons.check, size: 18, color: Theme.of(context).colorScheme.primary),
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
            const Icon(Icons.expand_more, size: 18),
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

    return Scaffold(
      appBar: _sel != null ? _selectionBar(tracks, store, offline) : AppBar(
        title: Row(
          children: [
            if (MediaQuery.sizeOf(context).width < 800) ...[
              const HutredLogo(size: 34),
              const SizedBox(width: 12),
            ],
            const Text('Медиатека'),
          ],
        ),
        actions: [
          if (MediaQuery.sizeOf(context).width < 800) const AccountButton(),
          if (store.tracks.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _sel = {}),
              icon: const Icon(Icons.checklist_rtl, size: 20),
              label: const Text('Выбрать'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: store.tracks.isEmpty
          ? const _EmptyLibrary()
          : CustomScrollView(
              slivers: [
                // Два меню: что показывать и как сортировать.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _dropdown<String>(
                          tooltip: 'Что показывать',
                          icon: _filterIcon,
                          label: _filterLabel,
                          onSelected: (v) => setState(() {
                            _favOnly = v == 'fav';
                            _downloadedOnly = v == 'downloaded';
                            _source = (v == 'all' || v == 'fav' || v == 'downloaded')
                                ? null
                                : TrackSource.values.byName(v);
                          }),
                          items: () => [
                            _item('all', Icons.library_music_outlined, 'Все треки',
                                !_favOnly && !_downloadedOnly && _source == null),
                            _item('fav', Icons.favorite_border, 'Избранное', _favOnly),
                            _item('downloaded', Icons.arrow_circle_down, 'Скачанные',
                                _downloadedOnly),
                            const PopupMenuDivider(),
                            for (final src in TrackSource.values)
                              _item(src.name, sourceIcon(src), sourceLabel(src),
                                  !_favOnly && !_downloadedOnly && _source == src),
                          ],
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
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Text(tracksWord(tracks.length),
                            style: const TextStyle(color: HutredTheme.muted)),
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
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Text('$done/${favs.length}',
                                      style: const TextStyle(
                                          color: HutredTheme.muted, fontSize: 12)),
                                ),
                              IconButton.filledTonal(
                                tooltip: pinned
                                    ? 'Любимые скачаны — нажми, чтобы удалить загрузки'
                                    : 'Скачать все любимые треки (новые лайки тоже скачаются)',
                                isSelected: pinned,
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
                                  pinned ? Icons.arrow_circle_down : Icons.download_outlined,
                                  color: pinned ? Theme.of(context).colorScheme.primary : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          );
                        }),
                        IconButton.filledTonal(
                          tooltip: 'Добавить музыку: YouTube, файлы, папка, ссылка',
                          onPressed: () => AppActions.showAddSheet(context),
                          icon: const Icon(Icons.add),
                        ),
                        const SizedBox(width: 8),
                        // Как в Spotify: выкл → перемешать → перемешать с рекомендациями.
                        IconButton.filledTonal(
                          tooltip: !player.shuffle
                              ? 'Перемешивание выключено'
                              : (player.smartShuffle
                                  ? 'Перемешивание с рекомендациями'
                                  : 'Перемешивание включено'),
                          onPressed: player.toggleShuffle,
                          isSelected: player.shuffle,
                          icon: Icon(
                            player.smartShuffle ? Icons.auto_awesome : Icons.shuffle,
                            color: player.shuffle
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white60,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: 'Слушать всё',
                          iconSize: 30,
                          onPressed: tracks.isEmpty ? null : () => player.playAll(tracks),
                          icon: const Icon(Icons.play_arrow_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
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
              Icon(Icons.library_music_outlined,
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
                    icon: const Icon(Icons.audio_file_outlined),
                    label: Text(ImportService.isDesktop ? 'Файлы или папка' : 'Файлы'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => AppActions.addUrlDialog(context),
                    icon: const Icon(Icons.link),
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
