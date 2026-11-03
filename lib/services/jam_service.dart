import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/track.dart';
import 'account_service.dart';
import 'library_store.dart';
import 'player_service.dart';
import 'wave_service.dart';

/// Участник джема.
class JamMember {
  const JamMember({required this.uid, required this.name, this.avatar});
  final String uid;
  final String name;
  final String? avatar;
}

/// Приглашение в джем от друга.
class JamInvite {
  const JamInvite({required this.host, required this.fromName});
  final String host;
  final String fromName;
}

/// Джем: слушать музыку вместе с друзьями, как в Spotify.
///
/// Хозяин джема управляет очередью и раз в несколько секунд рассылает,
/// что и с какого места играет. Гости подстраиваются под него, а их кнопки
/// «пауза», «дальше», «назад» и перемотка уходят хозяину.
///
/// Всё идёт через Supabase Realtime: канал `jam-<id хозяина>` для самого
/// джема и общий канал `hutred-online`, где видно, кто в каком джеме,
/// и ходят приглашения.
class JamService extends ChangeNotifier {
  JamService({
    required this.account,
    required this.player,
    required this.store,
    required this.wave,
  }) {
    account.addListener(_onAccount);
    player.addListener(_onPlayerForPresence);
    _onAccount();
  }

  final AccountService account;
  final PlayerService player;
  final LibraryStore store;
  final WaveService wave;

  SupabaseClient get _db => Supabase.instance.client;
  String? get _me => account.user?.id;
  String get _myName => account.username != null ? '@${account.username}' : 'Друг';

  // ---------- Общий канал: кто в джеме, приглашения ----------

  RealtimeChannel? _online;
  String? _onlineFor;

  /// id пользователя → id хозяина джема, в котором он сейчас.
  final Map<String, String> _jamOf = {};

  final _invites = StreamController<JamInvite>.broadcast();

  /// Приглашения мне (показываются всплывающим сообщением).
  Stream<JamInvite> get invites => _invites.stream;

  /// В каком джеме сейчас друг (id хозяина) или null.
  String? jamOf(String uid) => _jamOf[uid];

  // ---------- Кто в сети ----------

  /// Показывать ли другим, что я в сети и что слушаю (настройка).
  bool Function() shareOnline = () => true;

  /// Кто сейчас в сети: id → что слушает («Название — Исполнитель» или '').
  final Map<String, String> _online2 = {};

  /// Когда друг был в сети последний раз (пока приложение открыто).
  final Map<String, DateTime> _lastSeen = {};

  bool isOnline(String uid) => _online2.containsKey(uid);

  /// Что друг слушает прямо сейчас (null — ничего или скрыл).
  String? listeningOf(String uid) {
    final t = _online2[uid];
    return t == null || t.isEmpty ? null : t;
  }

  DateTime? lastSeenOf(String uid) => _lastSeen[uid];

  final _friendPings = StreamController<String>.broadcast();

  /// Кто-то прислал мне заявку в друзья (имя) — чтобы сразу обновить список.
  Stream<String> get friendRequests => _friendPings.stream;

  /// Сообщить другу, что я отправил ему заявку.
  Future<void> pingFriendRequest(String toUid) async {
    await _online?.sendBroadcastMessage(
      event: 'friend_request',
      payload: {'to': toUid, 'fromName': _myName},
    );
  }

  String _nowPlaying() {
    final t = player.current;
    if (t == null || !player.playing) return '';
    return '${t.title} — ${t.artist}';
  }

  String _lastShared = '';
  Timer? _shareDebounce;

  /// Трек сменился или пауза — обновляем «что слушаю» (не чаще раза в 2 с).
  void _onPlayerForPresence() {
    final now = _nowPlaying();
    if (now == _lastShared) return;
    _shareDebounce?.cancel();
    _shareDebounce = Timer(const Duration(seconds: 2), () {
      _lastShared = _nowPlaying();
      _trackOnline();
    });
  }

  /// Настройку «показывать, что я в сети» поменяли.
  void refreshPresence() {
    final ch = _online;
    if (ch == null) return;
    if (shareOnline()) {
      _trackOnline();
    } else {
      unawaited(ch.untrack());
    }
  }

  void _onAccount() {
    final me = _me;
    if (me == _onlineFor) return;
    _onlineFor = me;
    final old = _online;
    _online = null;
    if (old != null) unawaited(_db.removeChannel(old));
    if (me == null) {
      unawaited(leave());
      return;
    }
    final ch = _db.channel('hutred-online',
        opts: const RealtimeChannelConfig(self: false));
    ch
        .onPresenceSync((_) {
          _jamOf.clear();
          final was = Set.of(_online2.keys);
          _online2.clear();
          for (final s in ch.presenceState()) {
            for (final p in s.presences) {
              final uid = p.payload['uid'];
              final jam = p.payload['jam'];
              if (uid is String && jam is String) _jamOf[uid] = jam;
              if (uid is String) _online2[uid] = '${p.payload['track'] ?? ''}';
            }
          }
          final now = DateTime.now();
          for (final uid in was.difference(_online2.keys.toSet())) {
            _lastSeen[uid] = now;
          }
          notifyListeners();
        })
        .onBroadcast(
          event: 'friend_request',
          callback: (p) {
            if (p['to'] != _me) return;
            _friendPings.add('${p['fromName'] ?? 'Кто-то'}');
          },
        )
        .onBroadcast(
          event: 'invite',
          callback: (p) {
            if (p['to'] != _me) return;
            final host = p['host'];
            if (host is! String || host == _host) return;
            _invites.add(JamInvite(host: host, fromName: '${p['fromName'] ?? 'Друг'}'));
          },
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) _trackOnline();
        });
    _online = ch;
  }

  void _trackOnline() {
    final me = _me;
    final ch = _online;
    if (me == null || ch == null) return;
    if (!shareOnline()) {
      unawaited(ch.untrack());
      return;
    }
    unawaited(ch.track({
      'uid': me,
      if (_host != null) 'jam': _host,
      'track': _lastShared = _nowPlaying(),
    }));
  }

  /// Позвать друга в свой джем (если джема нет — он начнётся).
  Future<void> invite(String friendUid) async {
    if (_host == null) await start();
    await _online?.sendBroadcastMessage(
      event: 'invite',
      payload: {'to': friendUid, 'host': _host, 'fromName': _myName},
    );
  }

  // ---------- Сам джем ----------

  RealtimeChannel? _jam;
  String? _host;
  Timer? _beat;
  List<JamMember> _members = const [];

  /// Треки, на которые опирается микс: id участника → его любимое.
  final Map<String, List<Track>> _seeds = {};

  /// Что сейчас играет у хозяина (для экрана джема у гостей).
  Track? _hostTrack;
  List<Track> _hostUpNext = const [];
  bool _hostPlaying = false;
  String? _problem;

  bool get active => _host != null;
  bool get isHost => _host != null && _host == _me;
  String? get hostId => _host;
  List<JamMember> get members => _members;
  Track? get hostTrack => isHost ? player.current : _hostTrack;
  List<Track> get upNext {
    if (!isHost) return _hostUpNext;
    final q = player.queue;
    return q.skip(player.index + 1).take(10).toList();
  }

  bool get hostPlaying => isHost ? player.playing : _hostPlaying;

  /// Последняя проблема у гостя (например, трек не удалось включить).
  String? get problem => _problem;

  String get hostName {
    for (final m in _members) {
      if (m.uid == _host) return m.name;
    }
    return 'друг';
  }

  /// Начать свой джем: я — хозяин, моя музыка играет у всех.
  Future<void> start() async {
    final me = _me;
    if (me == null) throw Exception('Войди в аккаунт, чтобы слушать вместе');
    if (_host == me) return;
    await leave();
    await _open(me);
  }

  /// Присоединиться к джему друга.
  Future<void> join(String host) async {
    if (_me == null) throw Exception('Войди в аккаунт, чтобы слушать вместе');
    if (_host == host) return;
    await leave();
    await _open(host);
  }

  /// Выйти из джема (хозяин завершает его для всех).
  Future<void> leave() async {
    final ch = _jam;
    if (ch == null && _host == null) return;
    if (isHost) {
      await ch?.sendBroadcastMessage(event: 'end', payload: {});
      player.removeListener(_onPlayer);
    }
    _beat?.cancel();
    _beat = null;
    player.remoteControl = null;
    _jam = null;
    _host = null;
    _members = const [];
    _seeds.clear();
    _hostTrack = null;
    _hostUpNext = const [];
    _problem = null;
    if (ch != null) await _db.removeChannel(ch);
    _trackOnline();
    notifyListeners();
  }

  Future<void> _open(String host) async {
    final me = _me!;
    _host = host;
    final ch = _db.channel('jam-$host', opts: const RealtimeChannelConfig(self: false));
    ch
        .onPresenceSync((_) {
          final list = <JamMember>[];
          final seen = <String>{};
          for (final s in ch.presenceState()) {
            for (final p in s.presences) {
              final uid = p.payload['uid'];
              if (uid is! String || !seen.add(uid)) continue;
              list.add(JamMember(
                uid: uid,
                name: '${p.payload['name'] ?? 'Друг'}',
                avatar: p.payload['avatar'] as String?,
              ));
            }
          }
          // Хозяин — первым.
          list.sort((a, b) => a.uid == host ? -1 : (b.uid == host ? 1 : 0));
          _members = list;
          // Ушедшие больше не влияют на микс.
          _seeds.removeWhere((k, _) => !seen.contains(k));
          if (isHost) _sendState();
          notifyListeners();
        })
        .onBroadcast(event: 'state', callback: _onState)
        .onBroadcast(event: 'cmd', callback: _onCmd)
        .onBroadcast(event: 'seeds', callback: (p) {
          final uid = p['uid'];
          final list = p['tracks'];
          if (uid is! String || list is! List) return;
          _seeds[uid] = [
            for (final j in list)
              if (j is Map) Track.fromJson(Map<String, dynamic>.from(j)),
          ];
          notifyListeners();
        })
        .onBroadcast(event: 'hello', callback: (_) {
          // Новый участник: хозяин сразу присылает, что играет; все — свои треки.
          if (isHost) _sendState();
          _sendSeeds();
        })
        .onBroadcast(event: 'end', callback: (_) {
          _problem = null;
          unawaited(leave());
        })
        .subscribe((status, _) async {
          if (status != RealtimeSubscribeStatus.subscribed) return;
          await ch.track({'uid': me, 'name': _myName, 'avatar': account.avatarUrl});
          await ch.sendBroadcastMessage(event: 'hello', payload: {'uid': me});
          _sendSeeds();
          if (isHost) _sendState();
        });
    _jam = ch;
    _seeds[me] = _mySeeds();
    if (host == me) {
      player.addListener(_onPlayer);
      _beat = Timer.periodic(const Duration(seconds: 3), (_) => _sendState());
    } else {
      // Мои кнопки управления теперь уходят хозяину.
      player.remoteControl = _sendCmd;
    }
    _trackOnline();
    notifyListeners();
  }

  // ---------- Хозяин ----------

  String? _lastTrackId;
  bool? _lastPlaying;

  void _onPlayer() {
    final id = player.current?.id;
    // Сразу рассылаем смену трека и паузу; позиция — по таймеру.
    if (id != _lastTrackId || player.playing != _lastPlaying) {
      _lastTrackId = id;
      _lastPlaying = player.playing;
      _sendState();
    }
  }

  void _sendState() {
    final ch = _jam;
    if (ch == null || !isHost) return;
    final t = player.current;
    unawaited(ch.sendBroadcastMessage(event: 'state', payload: {
      'track': t == null ? null : _wire(t),
      'pos': player.position.inMilliseconds,
      'playing': player.playing && !player.loading,
      'next': [for (final n in upNext) _wire(n)],
    }));
  }

  Future<void> _onCmd(Map<String, dynamic> p) async {
    if (!isHost) return;
    switch (p['cmd']) {
      case 'toggle':
        await player.togglePlay();
      case 'next':
        await player.next();
      case 'prev':
        await player.previous();
      case 'seek':
        await player.seek(Duration(milliseconds: (p['ms'] as num?)?.toInt() ?? 0));
      case 'add':
        final j = p['track'];
        if (j is Map) await player.addToQueue(Track.fromJson(Map<String, dynamic>.from(j)));
    }
    _sendState();
  }

  /// Микс джема: волна по любимым трекам всех участников.
  /// Исполнители, которые нравятся сразу нескольким, попадаются чаще.
  Future<void> startMix() async {
    if (!isHost) return;
    _seeds[_me!] = _mySeeds();
    final fans = <String, Set<String>>{};
    _seeds.forEach((uid, list) {
      for (final t in list) {
        fans.putIfAbsent(t.artist.toLowerCase(), () => {}).add(uid);
      }
    });
    final seeds = <({Track track, int weight})>[];
    _seeds.forEach((uid, list) {
      for (final t in list) {
        final shared = (fans[t.artist.toLowerCase()]?.length ?? 1) > 1;
        seeds.add((track: t, weight: shared ? 6 : 2));
      }
    });
    if (seeds.isEmpty) {
      throw Exception('Пока не из чего собрать микс — поставьте ♥ любимым трекам');
    }
    await wave.startCustom(seeds, label: 'Микс джема');
    if (wave.error != null) throw Exception(wave.error);
  }

  /// Добавить трек в очередь джема (у гостя — просьба хозяину).
  Future<void> addTrack(Track t) async {
    if (isHost) {
      await player.addToQueue(t);
      _sendState();
    } else {
      await _sendCmd('add', track: t);
    }
  }

  // ---------- Гость ----------

  Future<bool> _sendCmd(String cmd, {int? ms, Track? track}) async {
    final ch = _jam;
    if (ch == null || isHost) return false;
    await ch.sendBroadcastMessage(event: 'cmd', payload: {
      'cmd': cmd,
      if (ms != null) 'ms': ms,
      if (track != null) 'track': _wire(track),
    });
    return true;
  }

  bool _applying = false;

  /// Ищет трек онлайн (SoundCloud / YouTube) — для треков из файлов хозяина.
  Future<Track?> Function(Track t)? findOnline;

  /// Трек-файл хозяина → найденная онлайн-копия (чтобы не искать заново).
  final Map<String, Track?> _onlineCopy = {};

  Future<Track?> _playableFor(Track t) async {
    if (t.source != TrackSource.local) return store.findBySource(t.source, t.uri) ?? t;
    final mine = store.findBySource(t.source, t.uri);
    if (mine != null && File(mine.uri).existsSync()) return mine;
    if (_onlineCopy.containsKey(t.uri)) return _onlineCopy[t.uri];
    final f = findOnline;
    Track? found;
    if (f != null) {
      try {
        found = await f(t).timeout(const Duration(seconds: 30));
      } catch (_) {}
    }
    return _onlineCopy[t.uri] = found;
  }

  Future<void> _onState(Map<String, dynamic> p) async {
    if (isHost || _host == null) return;
    final j = p['track'];
    final track = j is Map ? Track.fromJson(Map<String, dynamic>.from(j)) : null;
    final playing = p['playing'] == true;
    final pos = Duration(milliseconds: (p['pos'] as num?)?.toInt() ?? 0);
    _hostTrack = track;
    _hostPlaying = playing;
    _hostUpNext = [
      for (final n in (p['next'] as List? ?? const []))
        if (n is Map) Track.fromJson(Map<String, dynamic>.from(n)),
    ];
    notifyListeners();
    if (track == null || _applying) return;
    _applying = true;
    try {
      // Пока сообщение шло, у хозяина трек проиграл ещё немного.
      final target = playing ? pos + const Duration(milliseconds: 300) : pos;
      final cur = player.current;
      final copy = _onlineCopy[track.uri];
      final same = cur != null &&
          ((cur.source == track.source && cur.uri == track.uri) ||
              (copy != null && cur.source == copy.source && cur.uri == copy.uri));
      if (!same) {
        // Если трек есть у меня в медиатеке — берём свою копию (вдруг скачан).
        // Трек из файла хозяина у гостей ищем онлайн.
        if (track.source == TrackSource.local) {
          _problem = 'Ищу «${track.title}» онлайн — у хозяина он из файла…';
          notifyListeners();
        }
        final mine = await _playableFor(track);
        if (mine == null) {
          _problem = '«${track.title}» есть только в файле у хозяина — онлайн не нашёлся';
          if (player.playing) await player.pause();
          notifyListeners();
          return;
        }
        if (_hostTrack?.uri != track.uri) return; // хозяин уже переключил
        await player.playTracks([mine]);
        if (player.error != null) {
          _problem = 'Не получилось включить «${track.title}»: ${player.error}';
          notifyListeners();
          return;
        }
        _problem = null;
        await player.syncSeek(target);
      } else if ((player.position - target).abs() > const Duration(milliseconds: 2500)) {
        await player.syncSeek(target);
      }
      if (playing && !player.playing && !player.loading) {
        await player.resume();
      } else if (!playing && player.playing) {
        await player.pause();
      }
    } catch (e) {
      debugPrint('Джем: $e');
    } finally {
      _applying = false;
    }
  }

  // ---------- Общее ----------

  /// Мои любимые треки для микса: лайки и самое слушаемое.
  List<Track> _mySeeds() {
    final list = store.tracks
        .where((t) => t.favorite || t.plays > 2)
        .where((t) => t.source != TrackSource.local)
        .toList()
      ..sort((a, b) => (b.plays + (b.favorite ? 20 : 0)).compareTo(a.plays + (a.favorite ? 20 : 0)));
    return list.take(40).toList();
  }

  void _sendSeeds() {
    final me = _me;
    if (me == null) return;
    unawaited(_jam?.sendBroadcastMessage(event: 'seeds', payload: {
      'uid': me,
      'tracks': [for (final t in _mySeeds()) _wire(t)],
    }));
  }

  /// Трек для передачи: без личного (сколько слушал, лайк, путь к файлу).
  Map<String, dynamic> _wire(Track t) {
    final j = t.toJson();
    j.remove('plays');
    j.remove('favorite');
    j.remove('lyrics');
    j.remove('cloudPath');
    return j;
  }

  @override
  void dispose() {
    account.removeListener(_onAccount);
    player.removeListener(_onPlayerForPresence);
    _shareDebounce?.cancel();
    _friendPings.close();
    _beat?.cancel();
    _invites.close();
    super.dispose();
  }
}
