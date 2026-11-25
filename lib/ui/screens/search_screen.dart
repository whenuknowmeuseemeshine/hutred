import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/remote.dart';
import '../../models/track.dart';
import '../../services/library_store.dart';
import '../../services/player_service.dart';
import '../../services/settings_store.dart';
import '../../services/soundcloud_source.dart';
import '../../services/spotify_service.dart';
import '../../services/transfer_service.dart';
import '../../services/youtube_source.dart';
import '../actions.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/track_tile.dart';
import '../icons.dart';
import '../widgets/style_bits.dart';
import '../../services/wave_service.dart';
import 'artist_screen.dart';

enum _Mode { tracks, playlists }

/// Результаты одного источника.
class _Results {
  List<Track> tracks = [];
  List<RemotePlaylist> playlists = [];
  Future<Paged<Track>?> Function()? more;
  bool loading = false;
  bool loadingMore = false;
  String? error;
  bool collapsed = false;
}

/// Поиск по медиатеке, SoundCloud и YouTube. Источники можно включать и
/// выключать, разделы — сворачивать.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';
  _Mode _mode = _Mode.tracks;
  int _token = 0;
  final Map<String, _Results> _results = {};

  /// Онлайн-источники: Spotify — только если есть ключи (свои или от админа).
  List<String> _online(SettingsStore s) =>
      [if (s.hasSpotifyKeys) 'spotify', 'soundcloud', 'audius', if (s.youtubeAuto) 'youtube'];

  static const _labels = {
    'library': 'Медиатека',
    'spotify': 'Spotify',
    'soundcloud': 'SoundCloud',
    'audius': 'Audius',
    'youtube': 'YouTube',
  };
  static final _icons = {
    'library': Ic.library_music_outlined,
    'spotify': Ic.graphic_eq,
    'soundcloud': Ic.cloud_outlined,
    'audius': Ic.graphic_eq,
    'youtube': Ic.smart_display_outlined,
  };

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _isUrl {
    final u = Uri.tryParse(_query.trim());
    return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _token++;
    setState(() {
      _query = v;
      _results.clear();
    });
    if (v.trim().length < 2 || _isUrl) return;
    _debounce = Timer(const Duration(milliseconds: 600), _searchOnline);
  }

  void _submit(String v) {
    if (_isUrl) {
      AppActions.addUrl(context, v.trim());
      return;
    }
    context.read<SettingsStore>().rememberQuery(v);
    _debounce?.cancel();
    _searchOnline();
  }

  void _useQuery(String q) {
    _ctrl.text = q;
    _ctrl.selection = TextSelection.collapsed(offset: q.length);
    _onChanged(q);
    _submit(q);
  }

  Future<void> _searchOnline() async {
    final q = _query.trim();
    if (q.length < 2 || _isUrl) return;
    final token = ++_token;
    final mode = _mode;
    final settings = context.read<SettingsStore>();
    final enabled = settings.searchSources;
    final spotify = context.read<SpotifyService>();
    final sc = context.read<SoundcloudSource>();
    final yt = context.read<YoutubeSource>();
    final au = context.read<TransferService>().audius;

    Future<void> run(String key) async {
      final r = _results.putIfAbsent(key, _Results.new);
      setState(() {
        r.loading = true;
        r.loadingMore = false;
        r.error = null;
      });
      try {
        if (mode == _Mode.tracks) {
          final page = switch (key) {
            'spotify' => await spotify.searchTracks(
                id: settings.spotifyId, secret: settings.spotifySecret, query: q),
            'soundcloud' => await sc.searchPaged(q),
            'audius' => await au.searchPaged(q),
            _ => await yt.searchPaged(q),
          };
          if (!mounted || token != _token) return;
          setState(() {
            r.tracks = page.items;
            r.more = page.next;
            r.playlists = [];
          });
        } else if (key == 'spotify' || key == 'audius') {
          // Плейлисты Spotify добавляются ссылкой (вкладка «Перенос»).
          setState(() {
            r.playlists = [];
            r.tracks = [];
            r.more = null;
          });
        } else {
          final lists = key == 'soundcloud'
              ? await sc.searchPlaylists(q)
              : await yt.searchPlaylists(q);
          if (!mounted || token != _token) return;
          setState(() {
            r.playlists = lists;
            r.tracks = [];
            r.more = null;
          });
        }
      } catch (e) {
        if (!mounted || token != _token) return;
        // Для Spotify показываем настоящую причину (например, «просит подождать»).
        final msg = '$e'.replaceFirst('Exception: ', '');
        setState(() => r.error = msg.startsWith('Spotify')
            ? msg
            : 'Поиск не удался. Проверь подключение.');
      } finally {
        if (mounted && token == _token) setState(() => r.loading = false);
      }
    }

    await Future.wait([
      for (final key in _online(settings))
        if (enabled.contains(key)) run(key),
    ]);
  }

  Future<void> _loadMore(String key) async {
    final r = _results.putIfAbsent(key, _Results.new);
    final more = r.more;
    if (more == null || r.loadingMore) return;
    final token = _token;
    setState(() => r.loadingMore = true);
    try {
      final page = await more();
      if (!mounted || token != _token) return;
      setState(() {
        if (page != null) r.tracks = [...r.tracks, ...page.items];
        r.more = page?.next;
      });
    } catch (_) {
      if (mounted && token == _token) {
        AppActions.toast(context, 'Не удалось загрузить ещё');
      }
    } finally {
      if (mounted && token == _token) setState(() => r.loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final store = context.watch<LibraryStore>();
    final player = context.read<PlayerService>();
    final enabled = settings.searchSources;
    final q = _query.trim();
    final local = q.isEmpty || _isUrl || !enabled.contains('library') || _mode != _Mode.tracks
        ? const <Track>[]
        : store.search(q);

    final st = HutredStyle.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final pad = stylePagePadding(context);

    // Поле поиска по макету: большая капсула (Моно, Стекло) или рамка (Резкий).
    final field = TextField(
      controller: _ctrl,
      focusNode: _focus,
      onChanged: _onChanged,
      onSubmitted: _submit,
      textInputAction: TextInputAction.search,
      style: TextStyle(fontSize: st.sharp ? 20 : 16, fontWeight: st.sharp ? FontWeight.w600 : FontWeight.w500),
      decoration: InputDecoration(
        hintText: 'Песня, исполнитель, альбом или ссылка',
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Icon(Ic.search),
        ),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Очистить',
                icon: Icon(Ic.close),
                onPressed: () {
                  _ctrl.clear();
                  _onChanged('');
                  _focus.requestFocus();
                },
              ),
        filled: !st.sharp,
        fillColor: st.glass ? Colors.white.withValues(alpha: 0.08) : const Color(0xFF1F1F1F),
        contentPadding: const EdgeInsets.symmetric(vertical: 17, horizontal: 16),
        border: st.sharp
            ? const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Color(0xFF333333)))
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(99), borderSide: BorderSide.none),
        enabledBorder: st.sharp
            ? const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Color(0xFF333333)))
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(99), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(st.sharp ? 0 : 99),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)),
      ),
    );

    final onlineKeys = _online(settings).where(enabled.contains).toList();
    final groups = _mode == _Mode.tracks
        ? _groupTracks([
            for (final t in local) ('library', t),
            if (q.length >= 2 && !_isUrl)
              for (final key in onlineKeys)
                for (final t in _results[key]?.tracks ?? const <Track>[])
                  (key, t),
          ], q)
        : <List<(String, Track)>>[];
    final showHero = q.length >= 2 && !_isUrl && groups.isNotEmpty;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  pad.left, MediaQuery.paddingOf(context).top + pad.top, pad.right, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (Navigator.of(context).canPop())
                    IconButton(
                      tooltip: 'Назад',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const BackButtonIcon(),
                    ),
                  if (!wide) ...[
                    Text('Поиск', style: st.display(30)),
                    const SizedBox(height: 12),
                  ],
                  ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: st.sharp ? 900 : 560), child: field),
                  const SizedBox(height: 14),
                  // Где искать и что искать.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final key in ['library', ..._online(settings)])
                        StyleChip(
                          label: _labels[key]!,
                          selected: enabled.contains(key),
                          onTap: () {
                            settings.toggleSearchSource(key);
                            if (settings.searchSources.contains(key)) _searchOnline();
                          },
                        ),
                      const SizedBox(width: 10),
                      StyleChip(
                        label: 'Треки',
                        selected: _mode == _Mode.tracks,
                        onTap: () {
                          if (_mode == _Mode.tracks) return;
                          setState(() {
                            _mode = _Mode.tracks;
                            _results.clear();
                          });
                          _searchOnline();
                        },
                      ),
                      StyleChip(
                        label: 'Плейлисты',
                        selected: _mode == _Mode.playlists,
                        onTap: () {
                          if (_mode == _Mode.playlists) return;
                          setState(() {
                            _mode = _Mode.playlists;
                            _results.clear();
                          });
                          _searchOnline();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (q.isEmpty) ..._history(settings),
          if (_isUrl)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad.left, 8, pad.right, 8),
                child: StylePanel(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(Ic.link),
                    title: const Text('Добавить по ссылке'),
                    subtitle: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Icon(Ic.add),
                    onTap: () => AppActions.addUrl(context, q),
                  ),
                ),
              ),
            ),
          if (showHero)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad.left, 8, pad.right, 8),
                child: _SearchHero(
                  results: groups.map((group) => group.first).toList(),
                  labels: _labels,
                ),
              ),
            ),
          if (_mode == _Mode.tracks && q.isNotEmpty && !_isUrl)
            ..._unifiedTracks(groups, q.length >= 2 ? onlineKeys : [], store, player)
          else if (q.length >= 2 && !_isUrl)
            for (final key in onlineKeys)
              if (key == 'soundcloud' || key == 'youtube') ..._playlistSection(key),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }

  List<Widget> _history(SettingsStore settings) {
    final h = settings.searchHistory;
    if (h.isEmpty) {
      return const [
        SliverFillRemaining(hasScrollBody: false, child: _SearchHint()),
      ];
    }
    final pad = stylePagePadding(context);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad.left, 12, pad.right, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const StyleCaption('Недавно искал'),
                const Spacer(),
                TextButton(onPressed: settings.clearHistory, child: const Text('Очистить')),
              ]),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final q in h)
                    GestureDetector(
                      onSecondaryTap: () => settings.forgetQuery(q),
                      onLongPress: () => settings.forgetQuery(q),
                      child: StyleChip(label: q, icon: Ic.history, onTap: () => _useQuery(q)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Text('Долгое нажатие или правый клик — убрать из истории',
                  style: TextStyle(fontSize: 12, color: HutredTheme.muted)),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _playlistSection(String key) {
    final r = _results[key];
    if (r == null) return [];
    final count = r.playlists.length;
    return [
      _header(key, count,
          busy: r.loading,
          collapsed: r.collapsed,
          onToggle: () => setState(() => r.collapsed = !r.collapsed)),
      if (!r.collapsed) ...[
        if (r.loading && count == 0)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        if (r.error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(r.error!, style: const TextStyle(color: HutredTheme.muted)),
            ),
          ),
        if (!r.loading && r.error == null && count == 0)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('Ничего не нашлось', style: TextStyle(color: HutredTheme.muted)),
            ),
          ),
        SliverList.builder(
          itemCount: r.playlists.length,
          itemBuilder: (_, i) => _PlaylistTile(playlist: r.playlists[i]),
        ),
      ],
    ];
  }

  static String _normalize(String text) => text
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r"['’]"), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  List<List<(String, Track)>> _groupTracks(
      List<(String, Track)> results, String query) {
    final buckets = <(String, String), List<List<(String, Track)>>>{};
    final identities = <(TrackSource, String)>{};
    final unknownArtist = _normalize(Track.unknownArtist);
    for (final result in results) {
      final track = result.$2;
      if (!identities.add((track.source, track.uri))) continue;
      final artist = _normalize(track.artist);
      final title = _normalize(track.title);
      final duration = track.durationMs;
      final matches = buckets.putIfAbsent((artist, title), () => []);
      List<(String, Track)>? same;
      for (final group in matches) {
        final first = group.first.$2;
        if (first.source == track.source && first.uri == track.uri ||
            artist.isNotEmpty && artist != unknownArtist &&
                title.isNotEmpty && duration != null &&
                first.durationMs != null &&
                (duration - first.durationMs!).abs() <= 3000) {
          same = group;
          break;
        }
      }
      if (same == null) {
        matches.add([result]);
      } else {
        same.add(result);
      }
    }

    final words = _normalize(query);
    int rank(Track track) {
      final title = _normalize(track.title);
      final artist = _normalize(track.artist);
      if (words.isEmpty) return 0;
      if (words == title || words == '$artist $title' || words == '$title $artist') return 0;
      if (title.startsWith(words) || '$artist $title'.startsWith(words)) return 1;
      if ('$title $artist'.contains(words)) return 2;
      return 3;
    }

    final groups = buckets.values.expand((groups) => groups).toList();
    final sorted = groups.indexed.toList()
      ..sort((a, b) {
        final byMatch = rank(a.$2.first.$2).compareTo(rank(b.$2.first.$2));
        return byMatch != 0 ? byMatch : a.$1.compareTo(b.$1);
      });
    return sorted.map((entry) => entry.$2).toList();
  }

  List<Widget> _unifiedTracks(
    List<List<(String, Track)>> groups,
    List<String> keys,
    LibraryStore store,
    PlayerService player,
  ) {
    final results = [
      for (final key in keys)
        if (_results[key] case final _Results result) (key, result),
    ];
    final busy = results.any((entry) => entry.$2.loading);
    final loadingMore = results.any((entry) => entry.$2.loadingMore);
    final more = results.where((entry) => entry.$2.more != null);
    final rows = groups.map((group) {
      Track? saved;
      Track? playable;
      for (final (key, track) in group) {
        final inLibrary = key == 'library'
            ? track
            : store.findBySource(track.source, track.uri);
        saved ??= inLibrary;
        if (track.source != TrackSource.spotify) playable ??= inLibrary ?? track;
      }
      final display = saved ?? playable ?? group.first.$2;
      return (group: group, display: display, saved: saved != null);
    }).toList();
    final queue = rows.map((row) => row.display).toList();

    Widget status(Widget child) => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: child,
          ),
        );

    return [
      if (rows.isNotEmpty)
        status(Row(children: [
          StyleCaption('Треки · ${rows.length}'),
          if (busy) ...[
            const SizedBox(width: 10),
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ])),
      if (rows.isEmpty && busy)
        status(const Center(child: CircularProgressIndicator())),
      if (rows.isEmpty && !busy && results.isNotEmpty)
        status(const Text('Ничего не нашлось')),
      for (final (key, result) in results)
        if (result.error case final String error)
          status(Text('${_labels[key]} · $error',
              style: const TextStyle(color: HutredTheme.muted))),
      SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (_, i) {
          final row = rows[i];
          return TrackTile(
            track: row.display,
            onTap: () => player.playTracks(queue, start: i),
            trailingAction: Row(mainAxisSize: MainAxisSize.min, children: [
              if (row.group.length > 1)
                PopupMenuButton<Track>(
                  tooltip: 'Версии трека',
                  icon: Icon(Ic.expand_more),
                  onSelected: (track) => player.playTracks(
                    [...queue.take(i), track, ...queue.skip(i + 1)],
                    start: i,
                  ),
                  itemBuilder: (_) => [
                    for (final (key, track) in row.group)
                      PopupMenuItem(
                        value: track,
                        child: Text(
                          [_labels[key]!, if (track.album.isNotEmpty) track.album]
                              .join(' · '),
                        ),
                      ),
                  ],
                ),
              IconButton(
                tooltip: row.saved ? 'Уже в медиатеке' : 'В медиатеку',
                onPressed: row.saved
                    ? null
                    : () {
                        AppActions.ensureInLibrary(context, row.display);
                        AppActions.toast(context, 'Добавлено: «${row.display.title}»');
                      },
                icon: Icon(row.saved ? Ic.check_circle : Ic.add_circle_outline,
                    color: row.saved ? Theme.of(context).colorScheme.primary : null),
              ),
            ]),
          );
        },
      ),
      if (more.isNotEmpty || loadingMore)
        status(Center(
          child: loadingMore
              ? const SizedBox.square(
                  dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton.icon(
                  onPressed: () => Future.wait([
                    for (final (key, _) in more) _loadMore(key),
                  ]),
                  icon: Icon(Ic.expand_more),
                  label: const Text('Показать ещё'),
                ),
        )),
    ];
  }

  Widget _header(String key, int count,
          {bool busy = false, required bool collapsed, required VoidCallback onToggle}) =>
      SliverToBoxAdapter(
        child: InkWell(
          onTap: onToggle,
          child: Padding(
            padding: EdgeInsets.fromLTRB(stylePagePadding(context).left, 22, 16, 6),
            child: Row(
              children: [
                Icon(_icons[key], size: 18, color: HutredTheme.muted),
                const SizedBox(width: 8),
                StyleCaption(_labels[key]!),
                const SizedBox(width: 8),
                if (count > 0)
                  Text('$count', style: const TextStyle(color: HutredTheme.muted)),
                if (busy && count > 0) ...[
                  const SizedBox(width: 12),
                  const SizedBox.square(
                      dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
                const Spacer(),
                Icon(collapsed ? Ic.expand_more : Ic.expand_less,
                    color: HutredTheme.muted),
              ],
            ),
          ),
        ),
      );
}

/// Плейлист из поиска: можно сразу слушать или добавить целиком.
class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist});
  final RemotePlaylist playlist;

  Future<List<Track>> _load(BuildContext context) async {
    if (playlist.source == TrackSource.soundcloud) {
      return context.read<SoundcloudSource>().fromUrl(playlist.url);
    }
    return context.read<YoutubeSource>().fromPlaylistUrl(playlist.url);
  }

  @override
  Widget build(BuildContext context) {
    final p = playlist;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox.square(
          dimension: 48,
          child: p.artworkUrl == null
              ? const Artwork(track: null, size: 48, radius: 4)
              : Image.network(p.artworkUrl!, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Artwork(track: null, size: 48, radius: 4)),
        ),
      ),
      title: Text(p.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [p.owner, if (p.count != null) tracksWord(p.count!)].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Слушать',
            icon: Icon(Ic.play_circle_outline),
            onPressed: () async {
              AppActions.toast(context, 'Загружаю плейлист…');
              try {
                final tracks = await _load(context);
                if (!context.mounted) return;
                if (tracks.isEmpty) {
                  AppActions.toast(context, 'В плейлисте нет доступных треков');
                  return;
                }
                await context.read<PlayerService>().playTracks(tracks);
              } catch (e) {
                if (context.mounted) AppActions.toast(context, 'Не удалось загрузить плейлист');
              }
            },
          ),
          IconButton(
            tooltip: 'Добавить в медиатеку',
            icon: Icon(Ic.library_add_outlined),
            onPressed: () => AppActions.addUrl(context, p.url),
          ),
        ],
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Ic.manage_search, size: 56, color: HutredTheme.muted),
            SizedBox(height: 12),
            Text(
              'Выбери выше, где искать: в медиатеке, на SoundCloud или YouTube.\n'
              'Можно искать треки или целые плейлисты и альбомы.\n'
              'Вставь ссылку — добавлю трек или плейлист.',
              textAlign: TextAlign.center,
              style: TextStyle(color: HutredTheme.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}


/// Верх результатов по макету: «Лучший результат» (исполнитель первого
/// трека, с джемом по нему), рядом — первые треки, ниже — исполнители.
class _SearchHero extends StatelessWidget {
  const _SearchHero({required this.results, required this.labels});
  final List<(String, Track)> results;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    final store = context.read<LibraryStore>();
    final player = context.read<PlayerService>();
    final first = results.first.$2;
    final names = splitArtists(first.artist);
    final artist = names.isEmpty ? first.artist : names.first;
    final mine = store.tracks
        .where((t) => t.artist.toLowerCase().contains(artist.toLowerCase()))
        .toList();
    final top = results.take(4).toList();
    final artists = <String, Track>{};
    for (final (_, t) in results) {
      for (final a in splitArtists(t.artist)) {
        artists.putIfAbsent(a, () => t);
      }
      if (artists.length >= 6) break;
    }

    final best = StylePanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(st.sharp ? 0 : 48),
            child: Artwork(track: first, size: 96, radius: 0),
          ),
          const SizedBox(height: 14),
          Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: st.display(36)),
          const SizedBox(height: 6),
          Text(
              mine.isEmpty
                  ? 'Исполнитель'
                  : 'Исполнитель · в медиатеке ${tracksWord(mine.length)}',
              style: const TextStyle(color: HutredTheme.muted)),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            StyleButton(
              label: 'Джем по исполнителю',
              icon: Ic.graphic_eq,
              onPressed: () async {
                final wave = context.read<WaveService>();
                final seeds = [
                  for (final t in mine.take(20)) (track: t, weight: 4),
                  for (final (_, t) in results.where((r) => r.$2.artist.contains(artist)).take(10))
                    (track: t, weight: 3),
                ];
                await wave.startCustom(seeds,
                    label: 'Джем по исполнителю «$artist»', first: first);
                if (context.mounted) {
                  AppActions.toast(context, wave.error ?? 'Играет джем по исполнителю «$artist»');
                }
              },
            ),
            StyleButton(
              label: 'Открыть',
              primary: false,
              onPressed: () => openArtist(context, artist),
            ),
          ]),
        ],
      ),
    );

    Widget badge(String key) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: st.sharp ? null : Colors.white.withValues(alpha: 0.07),
            border: st.sharp ? Border.all(color: const Color(0xFF333333)) : null,
            borderRadius: BorderRadius.circular(st.sharp ? 0 : 99),
          ),
          child: Text(st.sharp ? labels[key]!.toUpperCase() : labels[key]!,
              style: st.sharp
                  ? st.caption(color: HutredTheme.muted, size: 11)
                  : const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: HutredTheme.muted)),
        );

    final tracks = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StyleCaption('Треки'),
        const SizedBox(height: 8),
        for (final (i, (key, t)) in top.indexed)
          Builder(builder: (context) {
            final saved = store.findBySource(t.source, t.uri);
            return InkWell(
              borderRadius: BorderRadius.circular(st.radius),
              onTap: () => player.playTracks(
                  top.map((r) => store.findBySource(r.$2.source, r.$2.uri) ?? r.$2).toList(),
                  start: i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
                child: Row(children: [
                  Artwork(track: t, size: 44, radius: 4),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: HutredTheme.muted)),
                    ]),
                  ),
                  badge(key),
                  IconButton(
                    tooltip: saved == null ? 'В медиатеку' : 'Уже в медиатеке',
                    onPressed: saved == null
                        ? () {
                            AppActions.ensureInLibrary(context, t);
                            AppActions.toast(context, 'Добавлено: «${t.title}»');
                          }
                        : null,
                    icon: Icon(saved == null ? Ic.add_circle_outline : Ic.check_circle,
                        color: saved == null ? null : Theme.of(context).colorScheme.primary),
                  ),
                  Text(formatDuration(t.duration),
                      style: const TextStyle(color: HutredTheme.muted, fontSize: 13)),
                ]),
              ),
            );
          }),
      ],
    );

    final artistRow = artists.length < 2
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 22),
              const StyleCaption('Исполнители'),
              const SizedBox(height: 12),
              SizedBox(
                height: 156,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: artists.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 18),
                  itemBuilder: (_, i) {
                    final e = artists.entries.elementAt(i);
                    return InkWell(
                      onTap: () => openArtist(context, e.key),
                      child: SizedBox(
                        width: 110,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(st.sharp ? 0 : 55),
                            child: Artwork(track: e.value, size: 110, radius: 0),
                          ),
                          const SizedBox(height: 8),
                          Text(e.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ],
          );

    return LayoutBuilder(builder: (context, box) {
      final row = box.maxWidth >= 760
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 85,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const StyleCaption('Лучший результат'),
                  const SizedBox(height: 8),
                  best,
                ]),
              ),
              const SizedBox(width: 24),
              Expanded(flex: 115, child: tracks),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const StyleCaption('Лучший результат'),
              const SizedBox(height: 8),
              best,
              const SizedBox(height: 18),
              tracks,
            ]);
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [row, artistRow]);
    });
  }
}
