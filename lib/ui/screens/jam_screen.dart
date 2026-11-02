import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/account_service.dart';
import '../../services/friends_service.dart';
import '../../services/jam_service.dart';
import '../actions.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import 'account_screen.dart';

/// Джем: слушать вместе с друзьями, позвать друга, микс по вкусам всех.
class JamScreen extends StatelessWidget {
  const JamScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const JamScreen()));

  Future<void> _run(BuildContext context, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (context.mounted) {
        AppActions.toast(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final jam = context.watch<JamService>();
    final acc = context.watch<AccountService>();
    final style = HutredStyle.of(context);

    if (!acc.signedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Джем')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Чтобы слушать вместе, войди в аккаунт',
                style: TextStyle(color: HutredTheme.muted)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context, rootNavigator: true)
                  .push(MaterialPageRoute(builder: (_) => const AccountScreen())),
              child: const Text('Войти'),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Джем')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        children: [
          if (!jam.active) ...[
            Text('Слушайте вместе', style: style.display(32)),
            const SizedBox(height: 8),
            const Text(
              'Начни джем и позови друзей: у всех играет одно и то же, '
              'в одно и то же время. Каждый может ставить на паузу, '
              'переключать и добавлять треки. А «Микс джема» соберёт '
              'музыку под вкусы всех сразу.',
              style: TextStyle(color: HutredTheme.muted, height: 1.4),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _run(context, jam.start),
                icon: const Icon(LucideIcons.radioTower, size: 18),
                label: const Text('Начать джем'),
              ),
            ),
          ] else ...[
            Text(jam.isHost ? 'Твой джем' : 'Джем ${jam.hostName}', style: style.display(32)),
            const SizedBox(height: 6),
            Text(
              jam.isHost
                  ? 'Твоя музыка играет у всех, кто в джеме'
                  : 'Музыка идёт от ${jam.hostName}. Твои кнопки управляют джемом',
              style: const TextStyle(color: HutredTheme.muted),
            ),
            const SizedBox(height: 16),
            _Members(members: jam.members, host: jam.hostId),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, children: [
              if (jam.isHost)
                FilledButton.icon(
                  onPressed: () => _run(context, () async {
                    await jam.startMix();
                    if (context.mounted) AppActions.toast(context, 'Играет микс джема');
                  }),
                  icon: const Icon(LucideIcons.sparkles, size: 18),
                  label: const Text('Микс джема'),
                ),
              OutlinedButton.icon(
                onPressed: () => _run(context, jam.leave),
                icon: const Icon(LucideIcons.logOut, size: 18),
                label: Text(jam.isHost ? 'Завершить джем' : 'Выйти из джема'),
              ),
            ]),
            if (jam.problem != null) ...[
              const SizedBox(height: 12),
              Text(jam.problem!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const _Head('Сейчас играет'),
            if (jam.hostTrack == null)
              const Text('Пока тишина. Включи что-нибудь — заиграет у всех.',
                  style: TextStyle(color: HutredTheme.muted))
            else
              _TrackRow(track: jam.hostTrack!, playing: jam.hostPlaying),
            if (jam.upNext.isNotEmpty) ...[
              const _Head('Дальше'),
              for (final t in jam.upNext) _TrackRow(track: t),
            ],
          ],
          const _Head('Позвать друзей'),
          const _InviteList(),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 28, 0, 10),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary)),
      );
}

class _Members extends StatelessWidget {
  const _Members({required this.members, required this.host});
  final List<JamMember> members;
  final String? host;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const Text('Подключаемся…', style: TextStyle(color: HutredTheme.muted));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in members)
          Chip(
            avatar: CircleAvatar(
              backgroundImage: m.avatar == null ? null : NetworkImage(m.avatar!),
              child: m.avatar == null ? Text(m.name.replaceFirst('@', '').characters.first) : null,
            ),
            label: Text(m.uid == host ? '${m.name} · ведущий' : m.name),
          ),
      ],
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, this.playing});
  final Track track;
  final bool? playing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Artwork(track: track, size: 48, radius: 6),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: HutredTheme.muted, fontSize: 13)),
          ]),
        ),
        if (playing != null)
          Icon(playing! ? LucideIcons.audioLines : LucideIcons.pause,
              size: 18, color: HutredTheme.muted),
      ]),
    );
  }
}

/// Друзья: позвать в свой джем или присоединиться к их джему.
class _InviteList extends StatelessWidget {
  const _InviteList();

  @override
  Widget build(BuildContext context) {
    final f = context.watch<FriendsService>();
    final jam = context.watch<JamService>();
    if (f.friends.isEmpty) {
      return const Text('Добавь друзей во вкладке «Друзья» — и зови их сюда.',
          style: TextStyle(color: HutredTheme.muted));
    }
    return Column(children: [
      for (final fr in f.friends)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundImage: fr.avatarUrl == null ? null : NetworkImage(fr.avatarUrl!),
            child: fr.avatarUrl == null ? const Icon(LucideIcons.user, size: 18) : null,
          ),
          title: Text(fr.name),
          subtitle: () {
            final h = jam.jamOf(fr.userId);
            if (h == null) return null;
            if (h == jam.hostId) return const Text('С тобой в джеме');
            return const Text('Сейчас в джеме');
          }(),
          trailing: () {
            final h = jam.jamOf(fr.userId);
            if (h != null && h == jam.hostId) return null;
            if (h != null) {
              return TextButton(
                onPressed: () => jam.join(h),
                child: const Text('Присоединиться'),
              );
            }
            return TextButton(
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
              child: const Text('Позвать'),
            );
          }(),
        ),
    ]);
  }
}
