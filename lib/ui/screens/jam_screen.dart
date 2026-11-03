import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/account_service.dart';
import '../../services/friends_service.dart';
import '../../services/jam_service.dart';
import '../actions.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import 'account_screen.dart';
import '../icons.dart';
import '../widgets/style_bits.dart';

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

    final wide = MediaQuery.sizeOf(context).width >= 900;
    final accent = Theme.of(context).colorScheme.primary;

    final buttons = Wrap(spacing: 10, runSpacing: 10, children: [
      if (!jam.active)
        StyleButton(
          label: 'Начать джем',
          icon: Ic.cell_tower,
          onPressed: () => _run(context, jam.start),
        ),
      if (jam.active && jam.isHost)
        StyleButton(
          label: 'Микс джема',
          icon: Ic.auto_awesome,
          onPressed: () => _run(context, () async {
            await jam.startMix();
            if (context.mounted) AppActions.toast(context, 'Играет микс джема');
          }),
        ),
      if (jam.active)
        StyleButton(
          label: jam.isHost ? 'Завершить' : 'Выйти из джема',
          primary: false,
          onPressed: () => _run(context, jam.leave),
        ),
    ]);

    final now = jam.hostTrack;
    final nowBlock = now == null
        ? const Text('Пока тишина. Включи что-нибудь — заиграет у всех.',
            style: TextStyle(color: HutredTheme.muted))
        : Row(children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(style.glass ? 28 : style.sharp ? 0 : 10),
                boxShadow: style.sharp
                    ? null
                    : [
                        BoxShadow(
                            color: style.glass
                                ? accent.withValues(alpha: 0.45)
                                : Colors.black.withValues(alpha: 0.5),
                            blurRadius: 50,
                            offset: const Offset(0, 18)),
                      ],
              ),
              child: Artwork(track: now, size: wide ? 150 : 96, radius: 10),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const StyleCaption('Сейчас у всех'),
                const SizedBox(height: 6),
                Text(now.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: style.display(wide ? 44 : 28)),
                const SizedBox(height: 4),
                Text(now.artist,
                    style: const TextStyle(fontSize: 16, color: HutredTheme.muted)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(jam.hostPlaying ? Ic.graphic_eq : Ic.pause,
                      size: 16, color: jam.hostPlaying ? accent : HutredTheme.muted),
                  const SizedBox(width: 6),
                  Text(jam.hostPlaying ? 'Играет' : 'На паузе',
                      style: const TextStyle(fontSize: 13, color: HutredTheme.muted)),
                ]),
              ]),
            ),
          ]);

    final main = <Widget>[
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Text(
              !jam.active
                  ? 'Джем'
                  : jam.isHost
                      ? 'Твой джем'
                      : 'Джем ${jam.hostName}',
              style: style.display(wide ? 52 : 32)),
        ),
        if (wide) buttons,
      ]),
      const SizedBox(height: 8),
      Text(
        !jam.active
            ? 'Слушайте вместе: у всех играет одно и то же, в одно и то же время. '
                'Каждый может ставить на паузу, переключать и добавлять треки, '
                'а «Микс джема» соберёт музыку под вкусы всех сразу.'
            : jam.isHost
                ? 'Твоя музыка играет у всех, кто в джеме'
                : 'Музыка идёт от ${jam.hostName}. Твои кнопки управляют джемом',
        style: const TextStyle(color: HutredTheme.muted, height: 1.4),
      ),
      if (!wide) ...[const SizedBox(height: 14), buttons],
      if (jam.active) ...[
        const SizedBox(height: 16),
        _Members(members: jam.members, host: jam.hostId),
        if (jam.problem != null) ...[
          const SizedBox(height: 12),
          Text(jam.problem!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 22),
        nowBlock,
        if (jam.upNext.isNotEmpty) ...[
          const _Head('Дальше в джеме'),
          for (final t in jam.upNext) _TrackRow(track: t, by: jam.pickedBy(t)),
        ],
      ],
    ];

    final invite = StylePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const StyleCaption('Позвать друзей'),
          const SizedBox(height: 8),
          const _InviteList(),
          const SizedBox(height: 12),
          const Text(
            'Микс джема собирает музыку под вкусы всех: исполнители, которых любят '
            'сразу несколько человек, звучат чаще.',
            style: TextStyle(fontSize: 13, color: HutredTheme.muted, height: 1.45),
          ),
        ],
      ),
    );

    final asTab = !Navigator.of(context).canPop();
    final topPad = asTab ? MediaQuery.paddingOf(context).top + 20 : 0.0;
    return Scaffold(
      appBar: asTab ? null : AppBar(),
      body: wide
          ? Padding(
              padding: EdgeInsets.fromLTRB(32, topPad, 32, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: ListView(padding: const EdgeInsets.only(bottom: 120), children: main),
                ),
                const SizedBox(width: 28),
                SizedBox(
                  width: 320,
                  child: ListView(
                      padding: const EdgeInsets.only(bottom: 120), children: [invite]),
                ),
              ]),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(16, topPad, 16, 120),
              children: [...main, const SizedBox(height: 24), invite],
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
            style: HutredStyle.of(context)
                .caption(color: Theme.of(context).colorScheme.primary)),
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
  const _TrackRow({required this.track, this.playing, this.by});
  final Track track;
  final bool? playing;

  /// Чей это трек в миксе: «ты» или имя друга.
  final String? by;

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
        if (by != null) _ByTag(by!),
        if (playing != null)
          Icon(playing! ? Ic.graphic_eq : Ic.pause,
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
            child: fr.avatarUrl == null ? Icon(Ic.person_outline, size: 18) : null,
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


/// Метка «чей трек»: свой — цвета акцента, друга — нейтральная.
class _ByTag extends StatelessWidget {
  const _ByTag(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final mine = name == 'ты';
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: mine ? accent : (st.sharp ? Colors.transparent : Colors.white.withValues(alpha: 0.12)),
        border: st.sharp && !mine ? Border.all(color: const Color(0xFF3A3A3A)) : null,
        borderRadius: BorderRadius.circular(st.sharp ? 0 : 999),
      ),
      child: Text(name,
          style: st.caption(
              size: 11, color: mine ? HutredTheme.onAccent(accent) : HutredTheme.text)),
    );
  }
}
