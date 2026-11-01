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
import '../../services/youtube_source.dart';
import '../actions.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/track_tile.dart';

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
  final Map<String, _Results> _results = {
    'spotify': _Results(),
    'soundcloud': _Results(),
    'youtube': _Results(),
  };

  /// Онлайн-источники: Spotify — только если есть ключи (свои или от админа).
  List<String> _online(SettingsStore s) =>
      [if (s.hasSpotifyKeys) 'spotify', 'soundcloud', 'youtube'];
  bool _libraryCollapsed = false;

  static const _labels = {
    'library': 'Медиатека',
    'spotify': 'Spotify',
    'soundcloud': 'SoundCloud',
    'youtube': 'YouTube',
  };
  static const _icons = {
    'library': Icons.library_music_outlined,
    'spotify': Icons.graphic_eq,
    'soundcloud': Icons.cloud_outlined,
    'youtube': Icons.smart_display_outlined,
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
    setState(() => _query = v);
    _debounce?.cancel();
    if (v.trim().length < 2 || _isUrl) {
      _token++;
      setState(() {
        for (final r in _results.values) {
          r
            ..tracks = []
            ..playlists = []
            ..more = null
            ..loading = false
            ..error = null;
        }
      });
      return;
    }
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
    final settings = context.read<SettingsStore>();
    final enabled = settings.searchSources;
    final spotify = context.read<SpotifyService>();
    final sc = context.read<SoundcloudSource>();
    final yt = context.read<YoutubeSource>();

    Future<void> run(String key) async {
      final r = _results.putIfAbsent(key, _Results.new);
      setState(() {
        r.loading = true;
        r.error = null;
      });
      try {
        if (_mode == _Mode.tracks) {
          final page = switch (key) {
            'spotify' => await spotify.searchTracks(
                id: settings.spotifyId, secret: settings.spotifySecret, query: q),
            'soundcloud' => await sc.searchPaged(q),
            _ => await yt.searchPaged(q),
          };
          if (!mounted || token != _token) return;
          setState(() {
            r.tracks = page.items;
            r.more = page.next;
            r.playlists = [];
          });
        } else if (key == 'spotify') {
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
      if (mounted) AppActions.toast(context, 'Не удалось загрузить ещё');
    } finally {
      if (mounted) setState(() => r.loadingMore = false);
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

    return Scaffold(
      appBar: AppBar(title: const Text('Поиск')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                onChanged: _onChanged,
                onSubmitted: _submit,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Песня, исполнитель, альбом или ссылка',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Очистить',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _ctrl.clear();
                            _onChanged('');
                            _focus.requestFocus();
                          },
                        ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          // Где искать и что искать.
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  for (final key in ['library', ..._online(settings)]) ...[
                    FilterChip(
                      showCheckmark: false,
                      avatar: Icon(_icons[key], size: 16),
                      label: Text(_labels[key]!),
                      selected: enabled.contains(key),
                      onSelected: (_) {
                        settings.toggleSearchSource(key);
                        if (settings.searchSources.contains(key)) _searchOnline();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                  const SizedBox(width: 8),
                  SegmentedButton<_Mode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: _Mode.tracks, label: Text('Треки')),
                      ButtonSegment(value: _Mode.playlists, label: Text('Плейлисты')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) {
                      setState(() => _mode = s.first);
                      _searchOnline();
                    },
                  ),
                ],
              ),
            ),
          ),
          if (q.isEmpty) ..._history(settings),
          if (_isUrl)
            SliverToBoxAdapter(
              child: Card(
                margin: const EdgeInsets.all(16),
                child: ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Добавить по ссылке'),
                  subtitle: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.add),
                  onTap: () => AppActions.addUrl(context, q),
                ),
              ),
            ),
          if (local.isNotEmpty) ...[
            _header('library', local.length,
                collapsed: _libraryCollapsed,
                onToggle: () => setState(() => _libraryCollapsed = !_libraryCollapsed)),
            if (!_libraryCollapsed)
              SliverList.builder(
                itemCount: local.length,
                itemBuilder: (_, i) => TrackTile(
                  track: local[i],
                  onTap: () => player.playTracks(local, start: i),
                ),
              ),
          ],
          if (q.length >= 2 && !_isUrl)
            for (final key in _online(settings))
              if (enabled.contains(key) && !(key == 'spotify' && _mode != _Mode.tracks))
                ..._section(key, store, player),
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
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
          child: Row(
            children: [
              const Text('Недавние запросы',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton(onPressed: settings.clearHistory, child: const Text('Очистить')),
            ],
          ),
        ),
      ),
      SliverList.builder(
        itemCount: h.length,
        itemBuilder: (_, i) => ListTile(
          leading: const Icon(Icons.history, color: HutredTheme.muted),
          title: Text(h[i]),
          onTap: () => _useQuery(h[i]),
          trailing: IconButton(
            tooltip: 'Убрать из истории',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => settings.forgetQuery(h[i]),
          ),
        ),
      ),
    ];
  }

  List<Widget> _section(String key, LibraryStore store, PlayerService player) {
    final r = _results.putIfAbsent(key, _Results.new);
    final count = _mode == _Mode.tracks ? r.tracks.length : r.playlists.length;
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
        if (_mode == _Mode.tracks)
          _trackList(r.tracks, store, player)
        else
          SliverList.builder(
            itemCount: r.playlists.length,
            itemBuilder: (_, i) => _PlaylistTile(playlist: r.playlists[i]),
          ),
        if (_mode == _Mode.tracks && r.more != null && count > 0)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: r.loadingMore
                    ? const SizedBox.square(
                        dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton.icon(
                        onPressed: () => _loadMore(key),
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Показать ещё'),
                      ),
              ),
            ),
          ),
      ],
    ];
  }

  Widget _trackList(List<Track> list, LibraryStore store, PlayerService player) {
    return SliverList.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final t = list[i];
        final saved = store.findBySource(t.source, t.uri);
        return TrackTile(
          track: saved ?? t,
          onTap: () => player.playTracks(
            list.map((o) => store.findBySource(o.source, o.uri) ?? o).toList(),
            start: i,
          ),
          trailingAction: IconButton(
            tooltip: saved == null ? 'В медиатеку' : 'Уже в медиатеке',
            onPressed: saved == null
                ? () {
                    AppActions.ensureInLibrary(context, t);
                    AppActions.toast(context, 'Добавлено: «${t.title}»');
                  }
                : null,
            icon: Icon(saved == null ? Icons.add_circle_outline : Icons.check_circle,
                color: saved == null ? null : Theme.of(context).colorScheme.primary),
          ),
        );
      },
    );
  }

  Widget _header(String key, int count,
          {bool busy = false, required bool collapsed, required VoidCallback onToggle}) =>
      SliverToBoxAdapter(
        child: InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
            child: Row(
              children: [
                Icon(_icons[key], size: 20, color: HutredTheme.muted),
                const SizedBox(width: 8),
                Text(_labels[key]!,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                if (count > 0)
                  Text('$count', style: const TextStyle(color: HutredTheme.muted)),
                if (busy && count > 0) ...[
                  const SizedBox(width: 12),
                  const SizedBox.square(
                      dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
                const Spacer(),
                Icon(collapsed ? Icons.expand_more : Icons.expand_less,
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
            icon: const Icon(Icons.play_circle_outline),
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
            icon: const Icon(Icons.library_add_outlined),
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
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.manage_search, size: 56, color: HutredTheme.muted),
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
