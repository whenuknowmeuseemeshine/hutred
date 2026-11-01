import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/library_store.dart';
import '../../services/player_service.dart';
import '../../services/soundcloud_source.dart';
import '../../services/wave_service.dart';
import '../actions.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/track_tile.dart';

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

/// Карточка исполнителя: его треки из моей медиатеки и популярное
/// с SoundCloud, которое можно добавить одним нажатием.
class ArtistScreen extends StatefulWidget {
  const ArtistScreen({super.key, required this.name});
  final String name;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  ScArtist? _sc;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await context.read<SoundcloudSource>().artist(widget.name);
      if (!mounted) return;
      setState(() {
        _sc = a;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  List<Track> _mine(LibraryStore store) {
    final key = _norm(widget.name);
    return store.tracks.where((t) {
      if (splitArtists(t.artist).any((a) => _norm(a) == key)) return true;
      // «Название (feat. Исполнитель)»
      final feat = RegExp(r'(?:feat\.?|ft\.?|при участии)\s+([^\)\]]+)', caseSensitive: false)
          .firstMatch(t.title);
      return feat != null && splitArtists(feat.group(1)!).any((a) => _norm(a) == key);
    }).toList()
      ..sort((a, b) => b.plays.compareTo(a.plays));
  }

  static String _followers(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)} млн';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)} тыс.';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final player = context.read<PlayerService>();
    final mine = _mine(store);
    final suggested = (_sc?.tracks ?? const <Track>[])
        .where((t) => !store.contains(t))
        .toList();
    final scheme = Theme.of(context).colorScheme;
    final cover = _sc?.avatarUrl ??
        mine.map((t) => t.artworkUrl).whereType<String>().firstOrNull;

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // Шапка: аватар, имя, цифры.
          Container(
            padding: const EdgeInsets.fromLTRB(24, 88, 24, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [scheme.primary.withValues(alpha: 0.35), Colors.transparent],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                CircleAvatar(
                  radius: 72,
                  backgroundColor: scheme.surfaceContainerHighest,
                  foregroundImage: cover == null ? null : artworkProvider(cover),
                  onForegroundImageError: cover == null ? null : (_, __) {},
                  child: Text(
                    widget.name.characters.first.toUpperCase(),
                    style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Исполнитель',
                          style: TextStyle(color: HutredTheme.muted, fontSize: 13)),
                      Text(widget.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 40, fontWeight: FontWeight.w900, height: 1.1)),
                      const SizedBox(height: 6),
                      Text(
                        [
                          'в медиатеке: ${tracksWord(mine.length)}',
                          if (_sc != null && _sc!.followers > 0)
                            '${_followers(_sc!.followers)} подписчиков на SoundCloud',
                        ].join(' · '),
                        style: const TextStyle(color: HutredTheme.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton.filled(
                  tooltip: 'Слушать',
                  iconSize: 30,
                  onPressed: mine.isEmpty && suggested.isEmpty
                      ? null
                      : () => player.playAll(mine.isNotEmpty ? mine : suggested),
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
                const SizedBox(width: 12),
                Builder(builder: (context) {
                  final wave = context.watch<WaveService>();
                  final blocked = wave.isArtistBlocked(widget.name);
                  return OutlinedButton.icon(
                    onPressed: () => blocked
                        ? wave.unblockArtist(widget.name)
                        : wave.blockArtist(widget.name),
                    icon: Icon(blocked ? Icons.check_circle_outline : Icons.block),
                    label: Text(blocked ? 'Вернуть исполнителя' : 'В чёрный список'),
                  );
                }),
                const SizedBox(width: 12),
                if (suggested.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () {
                      final n = store.addTracks(suggested);
                      AppActions.toast(context, 'Добавлено: ${tracksWord(n)}');
                    },
                    icon: const Icon(Icons.library_add_outlined),
                    label: const Text('Добавить всё с SoundCloud'),
                  ),
              ],
            ),
          ),
          if (mine.isNotEmpty) ...[
            const _Header('В твоей медиатеке'),
            for (var i = 0; i < mine.length; i++)
              TrackTile(
                key: ValueKey(mine[i].id),
                track: mine[i],
                onTap: () => player.playTracks(mine, start: i),
              ),
          ],
          const _Header('Популярное на SoundCloud'),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_failed || _sc == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _failed
                    ? 'SoundCloud не ответил. Проверь интернет.'
                    : 'Не нашёл «${widget.name}» на SoundCloud.',
                style: const TextStyle(color: HutredTheme.muted),
              ),
            )
          else if (suggested.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Все его треки с SoundCloud уже у тебя в медиатеке 👌',
                  style: TextStyle(color: HutredTheme.muted)),
            )
          else
            for (var i = 0; i < suggested.length; i++)
              TrackTile(
                key: ValueKey('sc${suggested[i].uri}'),
                track: suggested[i],
                onTap: () => player.playTracks(suggested, start: i),
                trailingAction: IconButton(
                  tooltip: 'В медиатеку',
                  onPressed: () {
                    store.addTracks([suggested[i]]);
                    AppActions.toast(context, 'Добавлено в медиатеку');
                  },
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
        child: Text(text,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      );
}
