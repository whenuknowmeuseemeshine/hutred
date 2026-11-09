import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/deezer_catalog.dart';
import '../../services/library_store.dart';
import '../../services/player_service.dart';
import '../../services/releases_service.dart';
import '../../services/wave_service.dart';
import '../actions.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/settings_kit.dart';
import 'artist_screen.dart';

/// Колокольчик с числом новых релизов.
class ReleasesBell extends StatelessWidget {
  const ReleasesBell({super.key});

  @override
  Widget build(BuildContext context) {
    final r = context.watch<ReleasesService>();
    final k = Sk.of(context);
    final n = r.unread;
    return IconButton(
      tooltip: 'Что нового',
      onPressed: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ReleasesScreen())),
      icon: Badge(
        isLabelVisible: n > 0,
        label: Text(n > 9 ? '9+' : '$n'),
        backgroundColor: k.ok,
        textColor: Colors.black,
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}

String _ago(DateTime d) {
  final days = DateTime.now().difference(d).inDays;
  if (days <= 0) return 'сегодня';
  if (days == 1) return 'вчера';
  if (days < 7) return '$days ${_plural(days, 'день', 'дня', 'дней')} назад';
  final w = days ~/ 7;
  if (days < 30) return '$w ${_plural(w, 'неделю', 'недели', 'недель')} назад';
  final m = days ~/ 30;
  return '$m ${_plural(m, 'месяц', 'месяца', 'месяцев')} назад';
}

String _plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 10 || m100 >= 20)) return few;
  return many;
}

/// «Что нового»: последние релизы исполнителей, на которых подписан.
class ReleasesScreen extends StatefulWidget {
  const ReleasesScreen({super.key});

  @override
  State<ReleasesScreen> createState() => _ReleasesScreenState();
}

class _ReleasesScreenState extends State<ReleasesScreen> {
  ReleasesService? _r;
  bool _subscribing = false;

  @override
  void initState() {
    super.initState();
    _r = context.read<ReleasesService>();
  }

  @override
  void dispose() {
    // Ушли со страницы — всё увиденное прочитано.
    _r?.markSeen();
    super.dispose();
  }

  /// Подписаться разом на исполнителей, которых больше всего в медиатеке.
  Future<void> _followTop() async {
    final store = context.read<LibraryStore>();
    final wave = context.read<WaveService>();
    setState(() => _subscribing = true);
    final count = <String, int>{};
    for (final t in store.favorites) {
      for (final a in splitArtists(t.artist).take(1)) {
        count[a] = (count[a] ?? 0) + 1 + t.plays;
      }
    }
    final top = count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!));
    var n = 0;
    for (final name in top.take(25)) {
      if (n >= 15) break;
      try {
        final a = await DeezerCatalog.findArtist(name);
        if (a == null || wave.isFollowing('${a.id}')) continue;
        await wave.follow('${a.id}', a.name, a.picture);
        n++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _subscribing = false);
    AppActions.toast(context, n == 0 ? 'Не нашёл новых исполнителей на Deezer' : 'Подписался: $n');
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<ReleasesService>();
    final wave = context.watch<WaveService>();
    final st = HutredStyle.of(context);
    final k = Sk.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final follows = wave.follows;

    Widget row(DzAlbum a) {
      final fresh = r.isNew(a);
      final size = wide ? 96.0 : 64.0;
      return InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => DzAlbumScreen(album: a, artist: a.artist))),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: wide ? 14 : 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: k.line))),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(k.sharp ? 0 : 8),
              child: SizedBox.square(
                dimension: size,
                child: a.cover == null
                    ? Container(color: k.inner)
                    : Image(image: artworkProvider(a.cover!), fit: BoxFit.cover),
              ),
            ),
            SizedBox(width: wide ? 20 : 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: wide ? 17 : 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(a.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                Row(children: [
                  if (fresh) ...[
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: k.ok, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                  ],
                  Text('${a.typeLabel} · ${_ago(a.released!)}',
                      style: TextStyle(fontSize: 12, color: fresh ? k.ok : k.muted, fontWeight: FontWeight.w600)),
                ]),
              ]),
            ),
            IconButton(
              tooltip: 'Добавить в медиатеку',
              onPressed: () async {
                final store = context.read<LibraryStore>();
                final tracks = await DeezerCatalog.tracksOf(a).catchError((_) => <Track>[]);
                if (!context.mounted) return;
                final n = store.addTracks(tracks);
                AppActions.toast(context, n == 0 ? 'Уже в медиатеке' : 'Добавлено: ${tracksWord(n)}');
              },
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
            IconButton(
              tooltip: 'Слушать',
              onPressed: () async {
                final player = context.read<PlayerService>();
                final tracks = await DeezerCatalog.tracksOf(a).catchError((_) => <Track>[]);
                if (tracks.isNotEmpty) await player.playAll(tracks);
              },
              icon: Icon(Icons.play_circle_fill_rounded, size: 34, color: k.text),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Проверить сейчас',
            onPressed: r.loading ? null : () => r.refresh(force: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => r.refresh(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(wide ? 40 : 16, 0, wide ? 40 : 16, 120),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(st.sharp ? 'ЧТО НОВОГО' : 'Что нового', style: st.display(wide ? 40 : 30)),
                  const SizedBox(height: 6),
                  Text('Последние релизы исполнителей, на которых ты подписан', style: k.sub),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    SkChip('Подписки: ${follows.length}', onTap: follows.isEmpty ? null : () => _showFollows(context)),
                    SkChip(_subscribing ? 'Подписываюсь…' : 'Подписаться на любимых',
                        onTap: _subscribing ? null : _followTop),
                  ]),
                  const SizedBox(height: 18),
                  if (r.loading && r.items.isEmpty)
                    const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                  else if (follows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                          'Пока ни на кого не подписан. Открой карточку исполнителя и нажми «Подписаться» — '
                          'или подпишись разом на любимых кнопкой выше.',
                          style: k.sub),
                    )
                  else if (r.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text('За последние 4 месяца новых релизов нет', style: k.sub),
                    )
                  else ...[
                    if (r.unread > 0) ...[
                      Text(st.sharp ? 'НОВОЕ' : 'Новое', style: st.display(20)),
                      const SizedBox(height: 8),
                      for (final a in r.items.where(r.isNew)) row(a),
                      const SizedBox(height: 24),
                    ],
                    Text(st.sharp ? 'РАНЕЕ' : 'Ранее', style: st.display(20)),
                    const SizedBox(height: 8),
                    for (final a in r.items.where((a) => !r.isNew(a))) row(a),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFollows(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Consumer<WaveService>(
        builder: (ctx, wave, _) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final f in wave.follows)
                  ListTile(
                    leading: CircleAvatar(
                      foregroundImage: f.picture == null ? null : artworkProvider(f.picture!),
                      child: Text(f.name.isEmpty ? '?' : f.name.characters.first),
                    ),
                    title: Text(f.name),
                    onTap: () => Navigator.of(ctx).push(
                        MaterialPageRoute(builder: (_) => ArtistScreen(name: f.name))),
                    trailing: TextButton(
                      onPressed: () => wave.unfollow(f.id),
                      child: const Text('Отписаться'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
