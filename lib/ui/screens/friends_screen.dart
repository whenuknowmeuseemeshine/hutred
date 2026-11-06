import 'jam_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../services/account_service.dart';
import '../../services/settings_store.dart';
import '../../services/friends_service.dart';
import '../../services/library_store.dart';
import '../../services/player_service.dart';
import '../actions.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/net_image.dart';
import '../widgets/track_tile.dart';
import 'account_screen.dart';
import '../icons.dart';
import '../widgets/style_bits.dart';
import '../../services/jam_service.dart';

/// Друзья: добавить по логину, заявки, список друзей и их медиатеки.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _name = TextEditingController();
  final _find = TextEditingController();
  String _query = '';
  bool _sending = false;

  @override
  void dispose() {
    _name.dispose();
    _find.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final err = await context.read<FriendsService>().request(_name.text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (err == null) _name.clear();
    AppActions.toast(context, err ?? 'Заявка отправлена');
  }

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccountService>();
    final f = context.watch<FriendsService>();

    if (!acc.signedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Друзья')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Чтобы добавлять друзей, войди в аккаунт',
                  style: TextStyle(color: HutredTheme.muted)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(builder: (_) => const AccountScreen())),
                child: const Text('Войти'),
              ),
            ],
          ),
        ),
      );
    }

    final jam = context.watch<JamService>();
    final settings = context.watch<SettingsStore>();
    final st = HutredStyle.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pad = stylePagePadding(context);
    final onlineCount = f.friends.where((fr) => jam.isOnline(fr.userId)).length;
    // Сначала те, кто в сети.
    final friends = List.of(f.friends)
      ..sort((a, b) {
        final oa = jam.isOnline(a.userId) ? 0 : 1, ob = jam.isOnline(b.userId) ? 0 : 1;
        return oa != ob ? oa - ob : (a.username ?? '').compareTo(b.username ?? '');
      });
    final q = _query.trim().toLowerCase().replaceFirst('@', '');
    final shown = q.isEmpty
        ? friends
        : friends
            .where((fr) =>
                fr.name.toLowerCase().contains(q) ||
                (fr.username ?? '').toLowerCase().contains(q) ||
                (jam.listeningOf(fr.userId) ?? '').toLowerCase().contains(q))
            .toList();

    String ago(DateTime t) {
      final d = DateTime.now().difference(t);
      if (d.inMinutes < 1) return 'только что';
      if (d.inMinutes < 60) return '${d.inMinutes} мин назад';
      return '${d.inHours} ч назад';
    }

    Widget requestCard(FriendInfo r) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: st.sharp
                  ? null
                  : st.glass
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.14)
                      : const Color(0xFF1A1A1A),
              border: st.sharp ? Border.all(color: Theme.of(context).colorScheme.primary) : null,
              borderRadius: BorderRadius.circular(st.sharp ? 0 : st.glass ? 18 : 12),
            ),
            child: Row(children: [
              _Avatar(info: r, online: jam.isOnline(r.userId)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Text('хочет добавить тебя в друзья',
                      style: TextStyle(fontSize: 12, color: HutredTheme.muted)),
                ]),
              ),
              StyleButton(label: 'Принять', onPressed: () => f.accept(r)),
              IconButton(
                tooltip: 'Отклонить',
                onPressed: () => f.remove(r),
                icon: Icon(Ic.close, size: 18),
              ),
            ]),
          ),
        );

    Widget friendRow(FriendInfo fr, int i) {
      final online = jam.isOnline(fr.userId);
      final listening = jam.listeningOf(fr.userId);
      final hisJam = jam.jamOf(fr.userId);
      final seen = jam.lastSeenOf(fr.userId);
      final status = hisJam != null
          ? (hisJam == jam.hostId ? 'С тобой в джеме' : 'В джеме')
          : listening != null
              ? 'Слушает: $listening'
              : online
                  ? 'В сети'
                  : seen != null
                      ? 'Был в сети ${ago(seen)}'
                      : 'Не в сети';
      final Widget action;
      if (hisJam != null && hisJam != jam.hostId) {
        action = TextButton(onPressed: () => jam.join(hisJam), child: const Text('Присоединиться'));
      } else if (online && hisJam == null) {
        action = StyleButton(
          label: 'Позвать в джем',
          icon: Ic.graphic_eq,
          primary: false,
          onPressed: () async {
            try {
              await jam.invite(fr.userId);
              if (context.mounted) AppActions.toast(context, 'Позвали ${fr.name}');
            } catch (e) {
              if (context.mounted) {
                AppActions.toast(context, e.toString().replaceFirst('Exception: ', ''));
              }
            }
          },
        );
      } else {
        action = const SizedBox.shrink();
      }
      return InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => FriendLibraryScreen(friend: fr))),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: i == 0
              ? null
              : BoxDecoration(
                  border: Border(
                      top: BorderSide(
                          color: st.glass
                              ? Colors.white.withValues(alpha: 0.07)
                              : const Color(0xFF1F1F1F)))),
          child: Row(children: [
            _Avatar(info: fr, online: online, radius: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fr.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Row(children: [
                  if (listening != null) ...[
                    Icon(Ic.graphic_eq, size: 13, color: const Color(0xFF4ADE80)),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            color: online || hisJam != null
                                ? const Color(0xFF4ADE80)
                                : HutredTheme.muted)),
                  ),
                ]),
              ]),
            ),
            action,
            PopupMenuButton<String>(
              onSelected: (_) async {
                final ok = await AppActions.confirm(context,
                    title: 'Удалить из друзей?',
                    body: '${fr.name} больше не будет видеть твою медиатеку, а ты — его.');
                if (ok) f.remove(fr);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'remove', child: Text('Удалить из друзей')),
              ],
            ),
          ]),
        ),
      );
    }

    final addPanel = StylePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const StyleCaption('Добавить друга'),
          const SizedBox(height: 10),
          TextField(
            controller: _name,
            onSubmitted: (_) => _send(),
            decoration: const InputDecoration(prefixText: '@', hintText: 'логин друга'),
          ),
          const SizedBox(height: 10),
          StyleButton(
            label: 'Отправить заявку',
            icon: Ic.person_add_alt_1,
            onPressed: _sending ? null : _send,
          ),
          const SizedBox(height: 10),
          Text(
            acc.username == null
                ? 'Задай себе логин в Аккаунте — по нему друзья найдут тебя.'
                : 'Друг увидит заявку сразу — всплывёт сообщение.',
            style: const TextStyle(fontSize: 12, color: HutredTheme.muted, height: 1.45),
          ),
        ],
      ),
    );

    final privacy = StylePanel(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        SwitchListTile(
          title: const Text('Показывать, что я в сети'),
          subtitle: const Text('и что слушаю сейчас'),
          value: settings.shareOnline,
          onChanged: (v) {
            settings.shareOnline = v;
            jam.refreshPresence();
          },
        ),
        SwitchListTile(
          title: const Text('Показывать мою медиатеку друзьям'),
          subtitle: const Text('Отдельный трек можно скрыть в его меню'),
          value: f.libraryPublic,
          onChanged: f.setLibraryPublic,
        ),
      ]),
    );

    final main = <Widget>[
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('Друзья', style: st.display(wide ? 52 : 32)),
        const SizedBox(width: 16),
        if (onlineCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('● $onlineCount в сети',
                style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.w600)),
          ),
        const Spacer(),
        if (!settings.visibleNav.contains('jam'))
          TextButton.icon(
            onPressed: () => JamScreen.open(context),
            icon: Icon(Ic.graphic_eq, size: 18),
            label: const Text('Джем'),
          ),
        IconButton(
          tooltip: 'Обновить',
          onPressed: f.loading ? null : f.refresh,
          icon: Icon(Ic.refresh),
        ),
      ]),
      if (f.error != null)
        Text(f.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (f.incoming.isNotEmpty) ...[
        const SizedBox(height: 14),
        StyleCaption('Заявки в друзья · ${f.incoming.length}'),
        const SizedBox(height: 10),
        for (final r in f.incoming) requestCard(r),
      ],
      const SizedBox(height: 18),
      Row(children: [
        StyleCaption('Друзья${friends.isEmpty ? '' : ' · ${friends.length}'}'),
        const Spacer(),
        if (friends.length > 1)
          SizedBox(
            width: wide ? 280 : 200,
            height: 40,
            child: TextField(
              controller: _find,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Найти среди друзей',
                prefixIcon: Icon(Ic.search, size: 18),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Очистить',
                        icon: Icon(Ic.close, size: 16),
                        onPressed: () => setState(() {
                          _find.clear();
                          _query = '';
                        }),
                      ),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 6),
      if (f.loading && f.friends.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (f.friends.isEmpty)
        const Text('Пока никого. Добавь друга по логину.',
            style: TextStyle(color: HutredTheme.muted))
      else if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text('Среди друзей нет «${_query.trim()}»',
              style: const TextStyle(color: HutredTheme.muted)),
        )
      else
        for (final (i, fr) in shown.indexed) friendRow(fr, i),
      if (f.outgoing.isNotEmpty) ...[
        const SizedBox(height: 18),
        const StyleCaption('Отправленные заявки'),
        for (final r in f.outgoing)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _Avatar(info: r),
            title: Text(r.name),
            subtitle: const Text('Ждёт ответа'),
            trailing: TextButton(onPressed: () => f.remove(r), child: const Text('Отменить')),
          ),
      ],
    ];

    final top = MediaQuery.paddingOf(context).top + pad.top;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: f.refresh,
        child: wide
            ? Padding(
                padding: EdgeInsets.fromLTRB(pad.left, top, pad.right, 0),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: ListView(padding: const EdgeInsets.only(bottom: 120), children: main),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 330,
                    child: ListView(
                      padding: const EdgeInsets.only(top: 70, bottom: 120),
                      children: [addPanel, const SizedBox(height: 14), privacy],
                    ),
                  ),
                ]),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(pad.left, top, pad.right, 120),
                children: [
                  ...main,
                  const SizedBox(height: 20),
                  addPanel,
                  const SizedBox(height: 14),
                  privacy,
                ],
              ),
      ),
    );
  }
}

/// Медиатека друга: можно слушать и забирать треки к себе.
class FriendLibraryScreen extends StatefulWidget {
  const FriendLibraryScreen({super.key, required this.friend});
  final FriendInfo friend;

  @override
  State<FriendLibraryScreen> createState() => _FriendLibraryScreenState();
}

class _FriendLibraryScreenState extends State<FriendLibraryScreen> {
  late Future<List<Track>> _tracks;
  late Future<List<({String id, String name, String description, String? cover, String owner, List<Track> tracks})>> _playlists;

  @override
  void initState() {
    super.initState();
    final fs = context.read<FriendsService>();
    _tracks = fs.libraryOf(widget.friend.userId);
    _playlists = context
        .read<AccountService>()
        .playlistsOfUser(widget.friend.userId)
        .catchError((_) => <({String id, String name, String description, String? cover, String owner, List<Track> tracks})>[]);
  }

  Widget _playlistsRow() => FutureBuilder<List<({String id, String name, String description, String? cover, String owner, List<Track> tracks})>>(
        future: _playlists,
        builder: (context, snap) {
          final lists = snap.data ?? const [];
          if (lists.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Плейлисты',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              for (final l in lists)
                ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: l.cover != null && l.cover!.startsWith('http')
                        ? Image.network(l.cover!, width: 48, height: 48, fit: BoxFit.cover)
                        : Artwork(track: l.tracks.first, size: 48, radius: 4),
                  ),
                  title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(tracksWord(l.tracks.length)),
                  trailing: Icon(Ic.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FriendPlaylistScreen(
                      followId: l.id,
                      playlist: Playlist(
                        id: l.id,
                        name: l.name,
                        trackIds: const [],
                        createdAt: DateTime.now(),
                        description: l.description,
                        cover: l.cover,
                      ),
                      tracks: l.tracks,
                      owner: widget.friend.name,
                    ),
                  )),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text('Треки',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final player = context.read<PlayerService>();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _Avatar(info: widget.friend, radius: 18),
            const SizedBox(width: 12),
            Flexible(child: Text(widget.friend.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: FutureBuilder<List<Track>>(
        future: _tracks,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return const Center(child: Text('Не удалось загрузить медиатеку'));
          }
          final tracks = snap.data ?? const <Track>[];
          if (tracks.isEmpty) {
            return const Center(
              child: Text('Медиатека пустая или скрыта',
                  style: TextStyle(color: HutredTheme.muted)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: tracks.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Column(children: [
                  _playlistsRow(),
                  Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Text(tracksWord(tracks.length),
                          style: const TextStyle(color: HutredTheme.muted)),
                      const Spacer(),
                      IconButton.filled(
                        tooltip: 'Слушать всё',
                        iconSize: 30,
                        onPressed: () => player.playAll(tracks),
                        icon: Icon(Ic.play_arrow_rounded),
                      ),
                    ],
                  ),
                ),
                ]);
              }
              final t = tracks[i - 1];
              final mine = store.contains(t);
              return TrackTile(
                key: ValueKey(t.id),
                track: t,
                onTap: () => player.playTracks(tracks, start: i - 1),
                trailingAction: IconButton(
                  tooltip: mine ? 'Уже в медиатеке' : 'В медиатеку',
                  onPressed: mine
                      ? null
                      : () {
                          store.addTracks([t]);
                          AppActions.toast(context, 'Добавлено в медиатеку');
                        },
                  icon: Icon(mine ? Ic.check_circle : Ic.add_circle_outline),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.info, this.radius = 20, this.online});
  final FriendInfo info;
  final double radius;

  /// Точка «в сети» (null — без точки).
  final bool? online;

  @override
  Widget build(BuildContext context) {
    final avatar = _circle(context);
    if (online == null) return avatar;
    final sharp = HutredStyle.of(context).sharp;
    return Stack(clipBehavior: Clip.none, children: [
      avatar,
      Positioned(
        right: -1,
        bottom: -1,
        child: Container(
          width: radius * 0.6,
          height: radius * 0.6,
          decoration: BoxDecoration(
            shape: sharp ? BoxShape.rectangle : BoxShape.circle,
            color: online! ? const Color(0xFF4ADE80) : const Color(0xFF555555),
            border: Border.all(color: Theme.of(context).canvasColor, width: 2.5),
          ),
        ),
      ),
    ]);
  }

  Widget _circle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = info.avatarUrl;
    if (HutredStyle.of(context).sharp) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        color: scheme.primary,
        alignment: Alignment.center,
        child: url == null
            ? Text((info.username ?? '?')[0].toUpperCase(),
                style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onPrimary))
            : Image.network(url, fit: BoxFit.cover, width: radius * 2, height: radius * 2),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      foregroundImage: url == null ? null : NetArt(url),
      onForegroundImageError: url == null ? null : (_, __) {},
      child: Text((info.username ?? '?')[0].toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}



/// Плейлист друга: слушать или добавить себе целиком.
class FriendPlaylistScreen extends StatelessWidget {
  const FriendPlaylistScreen(
      {super.key,
      required this.followId,
      required this.playlist,
      required this.tracks,
      required this.owner});
  final String followId;
  final Playlist playlist;
  final List<Track> tracks;
  final String owner;

  void _addToMine(BuildContext context) {
    context.read<LibraryStore>().followPlaylist(
          followId: followId,
          name: playlist.name,
          description: playlist.description,
          cover: playlist.cover,
          owner: owner,
          tracks: tracks,
        );
    AppActions.toast(context,
        '«${playlist.name}» теперь в твоих плейлистах и будет обновляться вместе с оригиналом');
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerService>();
    return Scaffold(
      appBar: AppBar(title: Text(playlist.name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Плейлист · $owner · ${tracksWord(tracks.length)}'
                    '${totalDuration(tracks).isEmpty ? '' : ', ${totalDuration(tracks)}'}',
                    style: const TextStyle(color: HutredTheme.muted)),
                if (playlist.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(playlist.description, style: const TextStyle(color: HutredTheme.muted)),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  FilledButton.icon(
                    onPressed: () => _addToMine(context),
                    icon: Icon(Ic.library_add_outlined),
                    label: const Text('Добавить к себе'),
                  ),
                  const Spacer(),
                  IconButton.filled(
                    tooltip: 'Слушать',
                    iconSize: 30,
                    onPressed: () => player.playTracks(tracks),
                    icon: Icon(Ic.play_arrow_rounded),
                  ),
                ]),
              ],
            ),
          ),
          for (var i = 0; i < tracks.length; i++)
            TrackTile(
              key: ValueKey(tracks[i].id),
              track: tracks[i],
              onTap: () => player.playTracks(tracks, start: i),
            ),
        ],
      ),
    );
  }
}
