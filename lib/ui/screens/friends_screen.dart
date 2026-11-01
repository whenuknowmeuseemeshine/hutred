import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/account_service.dart';
import '../../services/friends_service.dart';
import '../../services/library_store.dart';
import '../../services/player_service.dart';
import '../actions.dart';
import '../theme.dart';
import '../widgets/track_tile.dart';
import 'account_screen.dart';

/// Друзья: добавить по логину, заявки, список друзей и их медиатеки.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _name = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _name.dispose();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Друзья'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: f.loading ? null : f.refresh,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: f.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixText: '@',
                      hintText: 'логин друга',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Добавить'),
                ),
              ],
            ),
            if (acc.username == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Задай себе логин в Аккаунте — по нему друзья найдут тебя.',
                  style: TextStyle(color: HutredTheme.muted),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Показывать мою медиатеку друзьям'),
              subtitle: const Text(
                  'Отдельный трек можно скрыть в его меню: «Скрыть от друзей»'),
              value: f.libraryPublic,
              onChanged: f.setLibraryPublic,
            ),
            if (f.error != null)
              Text(f.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (f.incoming.isNotEmpty) ...[
              const _Section('Заявки в друзья'),
              for (final r in f.incoming)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _Avatar(info: r),
                  title: Text(r.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Отклонить',
                        onPressed: () => f.remove(r),
                        icon: const Icon(Icons.close),
                      ),
                      FilledButton(
                        onPressed: () => f.accept(r),
                        child: const Text('Принять'),
                      ),
                    ],
                  ),
                ),
            ],
            const _Section('Друзья'),
            if (f.loading && f.friends.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (f.friends.isEmpty)
              const Text('Пока никого. Добавь друга по логину.',
                  style: TextStyle(color: HutredTheme.muted))
            else
              for (final fr in f.friends)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _Avatar(info: fr),
                  title: Text(fr.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Открыть медиатеку'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => FriendLibraryScreen(friend: fr))),
                  trailing: PopupMenuButton<String>(
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
                ),
            if (f.outgoing.isNotEmpty) ...[
              const _Section('Отправленные заявки'),
              for (final r in f.outgoing)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _Avatar(info: r),
                  title: Text(r.name),
                  subtitle: const Text('Ждёт ответа'),
                  trailing: TextButton(
                    onPressed: () => f.remove(r),
                    child: const Text('Отменить'),
                  ),
                ),
            ],
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

  @override
  void initState() {
    super.initState();
    _tracks = context.read<FriendsService>().libraryOf(widget.friend.userId);
  }

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
                return Padding(
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
                        icon: const Icon(Icons.play_arrow_rounded),
                      ),
                    ],
                  ),
                );
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
                  icon: Icon(mine ? Icons.check_circle : Icons.add_circle_outline),
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
  const _Avatar({required this.info, this.radius = 20});
  final FriendInfo info;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = info.avatarUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      foregroundImage: url == null ? null : NetworkImage(url),
      onForegroundImageError: url == null ? null : (_, __) {},
      child: Text((info.username ?? '?')[0].toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
        child: Text(text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      );
}
