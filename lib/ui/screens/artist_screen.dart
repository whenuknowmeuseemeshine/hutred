import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/deezer_catalog.dart';
import '../../services/library_store.dart';
import '../../services/player_service.dart';
import '../../services/soundcloud_source.dart';
import '../../services/wave_service.dart';
import '../actions.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/track_tile.dart';
import '../icons.dart';
import '../widgets/settings_kit.dart';

final _artistSplit = RegExp(
  r'\s*(?:,|;|&|\s+x\s+|\s+feat\.?\s+|\s+ft\.?\s+|\s+featuring\s+|\s+и\s+)\s*',
  caseSensitive: false,
);

/// «A, B feat. C» → [A, B, C].
List<String> splitArtists(String artist) => artist
    .split(_artistSplit)
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty && e != Track.unknownArtist)
    .toSet()
    .toList();

String _norm(String s) => s
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

/// Открывает карточку исполнителя; если их несколько — спрашивает, какого.
Future<void> openArtist(BuildContext context, String artistField) async {
  final names = splitArtists(artistField);
  if (names.isEmpty) {
    AppActions.toast(context, 'У трека не указан исполнитель');
    return;
  }
  var name = names.first;
  if (names.length > 1) {
    final picked = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('Какой исполнитель?'),
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
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ArtistScreen(name: name)),
  );
}

/// Карточка исполнителя: фото, популярное, последний релиз, альбомы и
/// похожие — с Deezer; его треки из моей медиатеки; ещё — с SoundCloud.
class ArtistScreen extends StatefulWidget {
  const ArtistScreen({super.key, required this.name});
  final String name;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  ScArtist? _sc;
  DzArtist? _dz;
  List<Track> _top = const [];
  List<DzAlbum> _albums = const [];
  List<DzArtist> _related = const [];
  bool _loading = true;
  bool _allTop = false;
  String _kind = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sc = context.read<SoundcloudSource>();
    await Future.wait([
      () async {
        try {
          final a = await sc.artist(widget.name);
          if (mounted) setState(() => _sc = a);
        } catch (_) {}
      }(),
      () async {
        try {
          final a = await DeezerCatalog.findArtist(widget.name);
          if (a == null || !mounted) return;
          setState(() => _dz = a);
          final r = await Future.wait([
            DeezerCatalog.top(a.id).catchError((_) => <Track>[]),
            DeezerCatalog.albums(a.id).catchError((_) => <DzAlbum>[]),
            DeezerCatalog.related(a.id).catchError((_) => <DzArtist>[]),
          ]);
          if (!mounted) return;
          setState(() {
            _top = r[0] as List<Track>;
            _albums = r[1] as List<DzAlbum>;
            _related = r[2] as List<DzArtist>;
          });
        } catch (_) {}
      }(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  List<Track> _mine(LibraryStore store) {
    final key = _norm(widget.name);
    return store.tracks.where((t) {
      if (splitArtists(t.artist).any((a) => _norm(a) == key)) return true;
      final feat = RegExp(r'(?:feat\.?|ft\.?|при участии)\s+([^\)\]]+)', caseSensitive: false)
          .firstMatch(t.title);
      return feat != null && splitArtists(feat.group(1)!).any((a) => _norm(a) == key);
    }).toList()
      ..sort((a, b) => b.plays.compareTo(a.plays));
  }

  static String _count(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')} млн';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1).replaceAll('.', ',')} тыс.';
    return '$n';
  }

  static const _months = [
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];
  static String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final player = context.read<PlayerService>();
    final st = HutredStyle.of(context);
    final k = Sk.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pad = wide ? 40.0 : 16.0;
    final mine = _mine(store);
    final topKeys = {for (final t in _top) _norm(t.title)};
    final scMore = (_sc?.tracks ?? const <Track>[])
        .where((t) => !store.contains(t) && !topKeys.contains(_norm(t.title)))
        .toList();
    final photo = _dz?.picture ?? _sc?.avatarUrl ?? mine.map((t) => t.artworkUrl).whereType<String>().firstOrNull;
    final name = _dz?.name ?? widget.name;
    final playList = _top.isNotEmpty ? _top : (mine.isNotEmpty ? mine : scMore);

    final stats = [
      if (_dz != null && _dz!.fans > 0) '${_count(_dz!.fans)} поклонников на Deezer'
      else if (_sc != null && _sc!.followers > 0) '${_count(_sc!.followers)} подписчиков на SoundCloud',
      if (mine.isNotEmpty) '${tracksWord(mine.length)} в медиатеке',
    ].join(' · ');

    Widget photoImg(double size, {bool circle = true}) => ClipRRect(
          borderRadius: BorderRadius.circular(circle && !st.sharp ? size / 2 : 0),
          child: SizedBox.square(
            dimension: size,
            child: photo == null
                ? Container(
                    color: k.inner,
                    alignment: Alignment.center,
                    child: Text(name.characters.first.toUpperCase(),
                        style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w900)),
                  )
                : Image(image: artworkProvider(photo), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: k.inner)),
          ),
        );

    final bg = Theme.of(context).scaffoldBackgroundColor;
    final Widget header;
    if (wide) {
      header = SizedBox(
        height: 340,
        child: Stack(fit: StackFit.expand, children: [
          if (photo != null)
            Opacity(
              opacity: 0.55,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Image(image: artworkProvider(photo), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bg.withValues(alpha: 0.1), bg],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 70, pad, 28),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              photoImg(200),
              const SizedBox(width: 28),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Исполнитель', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: k.text)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(st.sharp ? name.toUpperCase() : name, maxLines: 1, style: st.display(80)),
                  ),
                  if (stats.isNotEmpty) Text(stats, style: const TextStyle(color: Color(0xFFCFCFCF))),
                ]),
              ),
            ]),
          ),
        ]),
      );
    } else {
      header = SizedBox(
        height: 300,
        child: Stack(fit: StackFit.expand, children: [
          if (photo != null)
            Image(image: artworkProvider(photo), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: k.inner))
          else
            Container(color: k.inner),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.35, 1],
                colors: [Colors.transparent, bg],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(st.sharp ? name.toUpperCase() : name,
                    maxLines: 1, style: st.display(st.glass ? 34 : 44)),
              ),
              if (stats.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(stats, style: const TextStyle(fontSize: 12, color: Color(0xFFDCDCDC))),
              ],
            ]),
          ),
        ]),
      );
    }

    final wave = context.watch<WaveService>();
    final blocked = wave.isArtistBlocked(widget.name);
    void addPopular() {
      final n = store.addTracks([..._top, ...scMore]);
      AppActions.toast(context, n == 0 ? 'Всё уже в медиатеке' : 'Добавлено: ${tracksWord(n)}');
    }

    void toggleBlock() => blocked ? wave.unblockArtist(widget.name) : wave.blockArtist(widget.name);

    final playBtn = Material(
      color: k.btn,
      shape: k.sharp ? const RoundedRectangleBorder() : const CircleBorder(),
      child: InkWell(
        customBorder: k.sharp ? const RoundedRectangleBorder() : const CircleBorder(),
        onTap: playList.isEmpty ? null : () => player.playAll(playList),
        child: SizedBox.square(
          dimension: wide ? 56 : 52,
          child: Icon(Ic.play_arrow_rounded, size: 30, color: k.btnFg),
        ),
      ),
    );
    final actions = Padding(
      padding: EdgeInsets.fromLTRB(pad, wide ? 8 : 4, pad, 0),
      child: wide
          ? Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              playBtn,
              SkButton('Перемешать', height: 40, onTap: playList.isEmpty ? null : () => player.shufflePlay(playList)),
              if (_top.isNotEmpty || scMore.isNotEmpty)
                SkButton('Добавить популярное в медиатеку', height: 40, onTap: addPopular),
              SkButton(blocked ? 'Вернуть исполнителя' : 'В чёрный список', height: 40, onTap: toggleBlock),
            ])
          : Row(children: [
              if (_top.isNotEmpty || scMore.isNotEmpty) SkButton('В медиатеку', height: 36, onTap: addPopular),
              PopupMenuButton<String>(
                tooltip: 'Ещё',
                icon: Icon(Icons.more_horiz_rounded, color: k.muted),
                onSelected: (_) => toggleBlock(),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'b', child: Text(blocked ? 'Вернуть исполнителя' : 'В чёрный список')),
                ],
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Перемешать',
                onPressed: playList.isEmpty ? null : () => player.shufflePlay(playList),
                icon: Icon(Icons.shuffle_rounded, color: k.muted),
              ),
              playBtn,
            ]),
    );

    Widget h2(String t, {Widget? trailing}) => Padding(
          padding: EdgeInsets.fromLTRB(pad, wide ? 34 : 26, pad, 10),
          child: Row(children: [
            Expanded(child: Text(st.sharp ? t.toUpperCase() : t, style: st.display(wide ? 24 : 18))),
            if (trailing != null) trailing,
          ]),
        );

    // ---------- Популярное ----------
    final shownTop = _allTop ? _top : _top.take(5).toList();
    final popular = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < shownTop.length; i++)
        TrackTile(
          key: ValueKey('dz${shownTop[i].uri}'),
          track: shownTop[i],
          number: i + 1,
          onTap: () => player.playTracks(_top, start: i),
          trailingAction: store.contains(shownTop[i])
              ? null
              : IconButton(
                  tooltip: 'В медиатеку',
                  onPressed: () {
                    store.addTracks([shownTop[i]]);
                    AppActions.toast(context, 'Добавлено в медиатеку');
                  },
                  icon: Icon(Ic.add_circle_outline),
                ),
        ),
      if (_top.length > 5)
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pad - 8),
            child: TextButton(
              onPressed: () => setState(() => _allTop = !_allTop),
              child: Text(_allTop ? 'Свернуть' : 'Ещё ${_top.length - 5}', style: TextStyle(color: k.text)),
            ),
          ),
        ),
    ]);

    // ---------- Последний релиз ----------
    final latest = _albums.firstOrNull;
    Widget? latestCard;
    if (latest != null) {
      final fresh = latest.released != null && DateTime.now().difference(latest.released!).inDays <= 60;
      final when = latest.released == null ? '' : _date(latest.released!);
      latestCard = Material(
        color: wide ? k.card : Colors.transparent,
        borderRadius: BorderRadius.circular(k.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(k.r),
          onTap: () => _openAlbum(latest, name),
          child: Padding(
            padding: EdgeInsets.all(wide ? 16 : 0),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(k.sharp ? 0 : 8),
                child: SizedBox.square(
                  dimension: wide ? 120 : 64,
                  child: latest.cover == null
                      ? Container(color: k.inner)
                      : Image(image: artworkProvider(latest.cover!), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      fresh
                          ? 'НОВОЕ${when.isEmpty ? '' : ' · ${when.toUpperCase()}'}'
                          : 'ПОСЛЕДНИЙ РЕЛИЗ${when.isEmpty ? '' : ' · ${when.toUpperCase()}'}',
                      style: st.caption(color: fresh ? k.ok : k.muted, size: 11).copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(latest.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: wide ? 20 : 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(latest.typeLabel, style: k.small),
                ]),
              ),
            ]),
          ),
        ),
      );
    }

    // ---------- Альбомы ----------
    final albums = _albums.where((a) => switch (_kind) {
          'album' => a.type == 'album' || a.type == 'compile',
          'single' => a.type == 'single' || a.type == 'ep',
          _ => true,
        }).toList();
    Widget albumTile(DzAlbum a, double w) => SizedBox(
          width: w,
          child: InkWell(
            onTap: () => _openAlbum(a, name),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(k.sharp ? 0 : 8),
                child: SizedBox.square(
                  dimension: w,
                  child: a.cover == null
                      ? Container(color: k.inner)
                      : Image(image: artworkProvider(a.cover!), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 8),
              Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${a.released?.year ?? ''}${a.released == null ? '' : ' · '}${a.typeLabel}', style: k.small),
            ]),
          ),
        );
    final kindChips = Wrap(spacing: 8, children: [
      for (final (v, l) in const [('all', 'Все'), ('album', 'Альбомы'), ('single', 'Синглы')])
        SkChip(l, selected: _kind == v, onTap: () => setState(() => _kind = v)),
    ]);
    final albumsView = wide
        ? Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: LayoutBuilder(builder: (context, box) {
              const gap = 20.0;
              final cols = ((box.maxWidth + gap) / (190 + gap)).floor().clamp(2, 8);
              final w = (box.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(spacing: gap, runSpacing: 22, children: [for (final a in albums.take(cols * 2)) albumTile(a, w)]);
            }),
          )
        : SizedBox(
            height: 186,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: pad),
              itemCount: albums.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => albumTile(albums[i], 128),
            ),
          );

    // ---------- Похожие ----------
    Widget relatedTile(DzArtist a, double size) => SizedBox(
          width: size,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtistScreen(name: a.name))),
            child: Column(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(k.sharp ? 0 : size / 2),
                child: SizedBox.square(
                  dimension: size,
                  child: a.picture == null
                      ? Container(color: k.inner)
                      : Image(image: artworkProvider(a.picture!), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 8),
              Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        );
    final relatedView = SizedBox(
      height: wide ? 180 : 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: pad),
        itemCount: _related.length,
        separatorBuilder: (_, __) => SizedBox(width: wide ? 20 : 14),
        itemBuilder: (_, i) => relatedTile(_related[i], wide ? 140 : 104),
      ),
    );

    final children = <Widget>[
      header,
      actions,
      if (_loading && _dz == null && _sc == null)
        const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
      if (_top.isNotEmpty || latestCard != null)
        if (wide && latestCard != null && _top.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(right: pad),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 16, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [h2('Популярное'), popular])),
              const SizedBox(width: 24),
              Expanded(
                flex: 10,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 34, 0, 10),
                    child: Text(st.sharp ? 'ПОСЛЕДНИЙ РЕЛИЗ' : 'Последний релиз', style: st.display(24)),
                  ),
                  latestCard,
                ]),
              ),
            ]),
          )
        else ...[
          if (latestCard != null)
            Padding(padding: EdgeInsets.fromLTRB(pad, 18, pad, 0), child: latestCard),
          if (_top.isNotEmpty) ...[h2('Популярное'), popular],
        ],
      if (_albums.isNotEmpty) ...[
        h2('Альбомы и синглы', trailing: wide ? kindChips : null),
        if (!wide) Padding(padding: EdgeInsets.fromLTRB(pad, 0, pad, 12), child: kindChips),
        albumsView,
      ],
      if (_related.isNotEmpty) ...[h2('Похожие исполнители'), relatedView],
      if (mine.isNotEmpty) ...[
        h2('В твоей медиатеке · ${mine.length}'),
        for (var i = 0; i < mine.length; i++)
          TrackTile(key: ValueKey(mine[i].id), track: mine[i], onTap: () => player.playTracks(mine, start: i)),
      ],
      if (scMore.isNotEmpty) ...[
        h2(_dz == null ? 'Популярное на SoundCloud' : 'Ещё на SoundCloud'),
        for (var i = 0; i < scMore.length; i++)
          TrackTile(
            key: ValueKey('sc${scMore[i].uri}'),
            track: scMore[i],
            onTap: () => player.playTracks(scMore, start: i),
            trailingAction: IconButton(
              tooltip: 'В медиатеку',
              onPressed: () {
                store.addTracks([scMore[i]]);
                AppActions.toast(context, 'Добавлено в медиатеку');
              },
              icon: Icon(Ic.add_circle_outline),
            ),
          ),
      ],
      if (!_loading && _dz == null && _sc == null && mine.isEmpty)
        Padding(
          padding: EdgeInsets.all(pad),
          child: Text('Не нашёл «${widget.name}» ни на Deezer, ни на SoundCloud.', style: k.sub),
        ),
    ];

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0),
      extendBodyBehindAppBar: true,
      body: ListView(padding: const EdgeInsets.only(bottom: 120), children: children),
    );
  }

  void _openAlbum(DzAlbum a, String artist) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => _AlbumScreen(album: a, artist: artist)));
}

/// Альбом с Deezer: обложка и треки.
class _AlbumScreen extends StatefulWidget {
  const _AlbumScreen({required this.album, required this.artist});
  final DzAlbum album;
  final String artist;

  @override
  State<_AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<_AlbumScreen> {
  List<Track>? _tracks;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    DeezerCatalog.albumTracks(widget.album.id).then((t) {
      if (mounted) setState(() => _tracks = t);
    }, onError: (_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerService>();
    final store = context.watch<LibraryStore>();
    final st = HutredStyle.of(context);
    final k = Sk.of(context);
    final a = widget.album;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final tracks = _tracks ?? const <Track>[];
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(k.sharp ? 0 : 10),
      child: SizedBox.square(
        dimension: wide ? 200 : 160,
        child: a.cover == null ? Container(color: k.inner) : Image(image: artworkProvider(a.cover!), fit: BoxFit.cover),
      ),
    );
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(a.typeLabel, style: k.small),
      Text(a.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: st.display(wide ? 36 : 26)),
      const SizedBox(height: 4),
      Text(
          [widget.artist, if (a.released != null) '${a.released!.year}', if (tracks.isNotEmpty) tracksWord(tracks.length)]
              .join(' · '),
          style: k.sub),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SkButton('Играть', primary: true, height: 40, onTap: tracks.isEmpty ? null : () => player.playAll(tracks)),
        SkButton('Добавить в медиатеку', height: 40, onTap: tracks.isEmpty
            ? null
            : () {
                final n = store.addTracks(tracks);
                AppActions.toast(context, n == 0 ? 'Всё уже в медиатеке' : 'Добавлено: ${tracksWord(n)}');
              }),
      ]),
    ]);
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        children: [
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [cover, const SizedBox(width: 24), Expanded(child: info)])
          else ...[
            Center(child: cover),
            const SizedBox(height: 16),
            info,
          ],
          const SizedBox(height: 16),
          if (_tracks == null && !_failed)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (_failed) Text('Deezer не ответил. Проверь интернет.', style: k.sub),
          for (var i = 0; i < tracks.length; i++)
            TrackTile(
              key: ValueKey('al${tracks[i].uri}'),
              track: tracks[i],
              number: i + 1,
              onTap: () => player.playTracks(tracks, start: i),
            ),
        ],
      ),
    );
  }
}
