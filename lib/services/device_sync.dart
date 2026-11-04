import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/track.dart';
import 'account_service.dart';
import 'player_service.dart';

/// Другое моё устройство с открытым Hutred.
class RemoteDevice {
  RemoteDevice({
    required this.id,
    required this.name,
    required this.kind,
    required this.playing,
    required this.track,
    required this.posMs,
    required this.durMs,
    required this.at,
    required this.volume,
  });

  final String id;
  final String name;

  /// 'pc' или 'phone'.
  final String kind;
  final bool playing;
  final Track? track;
  final int posMs;
  final int durMs;
  final DateTime at;
  final double volume;

  /// Где сейчас трек с учётом времени, прошедшего с последнего сообщения.
  Duration get position {
    var ms = posMs;
    if (playing) ms += DateTime.now().difference(at).inMilliseconds;
    if (durMs > 0) ms = ms.clamp(0, durMs);
    return Duration(milliseconds: ms);
  }

  Duration get duration => Duration(milliseconds: durMs);
}

/// Синхронизация своих устройств, как в Spotify: что играет на компьютере,
/// видно на телефоне, и им можно управлять; музыку можно перенести.
class DeviceSync extends ChangeNotifier with WidgetsBindingObserver {
  DeviceSync({required this.account, required this.player}) {
    WidgetsBinding.instance.addObserver(this);
    // Медиатека поменялась на другом устройстве — сразу забираем.
    account.onPushed = () => unawaited(_ch?.sendBroadcastMessage(event: 'lib', payload: {'from': _id}));
    account.addListener(_onAccount);
    player.addListener(_onPlayer);
    _onAccount();
  }

  final AccountService account;
  final PlayerService player;

  SupabaseClient get _db => Supabase.instance.client;

  String _id = '';
  String get myId => _id;

  static String get myKind => Platform.isAndroid || Platform.isIOS ? 'phone' : 'pc';
  static String get myName => Platform.isIOS
      ? 'iPhone'
      : Platform.isAndroid
          ? 'Телефон'
          : Platform.isMacOS
              ? 'Mac'
              : 'Компьютер';

  RealtimeChannel? _ch;
  String? _for;
  final Map<String, RemoteDevice> _devices = {};
  Timer? _beat;
  Timer? _debounce;

  /// Кто управлял этим устройством последним (и когда).
  String? _controller;
  DateTime? _controlledAt;

  /// Другие мои устройства в сети.
  List<RemoteDevice> get others => [
        for (final d in _devices.values)
          if (d.id != _id) d,
      ]..sort((a, b) => a.name.compareTo(b.name));

  bool get online => _ch != null && account.signedIn;

  /// Устройство, где сейчас играет музыка (не это).
  RemoteDevice? get active {
    final playing = others.where((d) => d.playing && d.track != null).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return playing.firstOrNull;
  }

  /// Это устройство молчит, а музыка играет на другом: показываем пульт.
  bool get remoteMode => active != null && !player.playing;

  /// «Управляется с …» — пока пульт рядом и командовал недавно.
  String? get controlledBy {
    final c = _controller;
    final at = _controlledAt;
    if (c == null || at == null || !player.playing) return null;
    if (DateTime.now().difference(at) > const Duration(minutes: 10)) return null;
    return c;
  }

  Future<void> _loadId() async {
    if (_id.isNotEmpty) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}${Platform.pathSeparator}device_id');
      if (await f.exists()) {
        _id = (await f.readAsString()).trim();
      }
      if (_id.isEmpty) {
        final r = Random.secure();
        _id = List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join();
        await f.writeAsString(_id);
      }
    } catch (_) {
      _id = 'dev${DateTime.now().microsecondsSinceEpoch}';
    }
  }

  Future<void> _onAccount() async {
    final uid = account.signedIn ? account.user?.id : null;
    if (uid == _for) return;
    _for = uid;
    final old = _ch;
    _ch = null;
    _devices.clear();
    _beat?.cancel();
    if (old != null) unawaited(_db.removeChannel(old));
    notifyListeners();
    if (uid == null) return;
    await _loadId();
    final ch = _db.channel('devices-$uid', opts: const RealtimeChannelConfig(self: false));
    ch
        .onPresenceSync((_) {
          _devices.clear();
          for (final s in ch.presenceState()) {
            for (final p in s.presences) {
              final d = _parse(p.payload);
              if (d != null) _devices[d.id] = d;
            }
          }
          notifyListeners();
        })
        .onBroadcast(event: 'cmd', callback: _onCmd)
        .onBroadcast(event: 'take', callback: _onTake)
        .onBroadcast(event: 'lib', callback: (_) => unawaited(account.syncNow()))
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) _publish();
        });
    _ch = ch;
    // Пока играет — раз в 10 секунд уточняем позицию для пультов.
    _beat = Timer.periodic(const Duration(seconds: 10), (_) {
      if (player.playing) _publish();
    });
  }

  RemoteDevice? _parse(Map<String, dynamic> p) {
    final id = p['id'];
    if (id is! String) return null;
    Track? t;
    final tj = p['track'];
    if (tj is Map) {
      try {
        t = Track.fromJson(Map<String, dynamic>.from(tj));
      } catch (_) {}
    }
    return RemoteDevice(
      id: id,
      name: '${p['name'] ?? 'Устройство'}',
      kind: '${p['kind'] ?? 'pc'}',
      playing: p['playing'] == true,
      track: t,
      posMs: (p['pos'] as num?)?.toInt() ?? 0,
      durMs: (p['dur'] as num?)?.toInt() ?? 0,
      at: DateTime.fromMillisecondsSinceEpoch((p['at'] as num?)?.toInt() ?? 0),
      volume: (p['vol'] as num?)?.toDouble() ?? 1,
    );
  }

  String? _lastKey;

  void _onPlayer() {
    // Публикуем при смене трека или паузы — не чаще раза в 700 мс.
    final key = '${player.current?.id}|${player.playing}';
    if (key == _lastKey) return;
    _lastKey = key;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _publish);
    notifyListeners();
  }

  void _publish() {
    final ch = _ch;
    if (ch == null || _id.isEmpty) return;
    final t = player.current;
    unawaited(ch.track({
      'id': _id,
      'name': myName,
      'kind': myKind,
      'playing': player.playing,
      if (t != null) 'track': _compact(t),
      'pos': player.position.inMilliseconds,
      'dur': player.duration?.inMilliseconds ?? t?.durationMs ?? 0,
      'at': DateTime.now().millisecondsSinceEpoch,
      'vol': player.volume,
    }));
  }

  static Map<String, dynamic> _compact(Track t) {
    final j = t.toJson();
    // Текст песни в статус не нужен — он большой.
    j.remove('lyrics');
    return j;
  }

  // ---------- Команды ----------

  Future<void> _send(String event, Map<String, dynamic> payload) async {
    await _ch?.sendBroadcastMessage(event: event, payload: {
      ...payload,
      'from': _id,
      'fromName': myName,
    });
  }

  /// Команда устройству [to]: toggle, next, prev, seek (ms), volume (v).
  Future<void> command(String to, String action, {int? ms, double? v}) =>
      _send('cmd', {'to': to, 'action': action, if (ms != null) 'ms': ms, if (v != null) 'v': v});

  /// Перенести музыку сюда с устройства, где она играет.
  Future<void> playHere(RemoteDevice from) => command(from.id, 'handoff_to:$_id');

  /// Перенести музыку на устройство [to]: отсюда или с того, где играет.
  Future<void> moveTo(RemoteDevice to) async {
    if (player.playing || player.current != null && !remoteMode) {
      await _sendQueueTo(to.id);
      await player.pause();
      return;
    }
    final a = active;
    if (a != null && a.id != to.id) await command(a.id, 'handoff_to:${to.id}');
  }

  Future<void> _sendQueueTo(String target) async {
    final q = player.queue;
    final i = player.index;
    if (q.isEmpty || i < 0) return;
    final from = max(0, i - 5);
    final to = min(q.length, i + 60);
    await _send('take', {
      'to': target,
      'queue': [for (final t in q.sublist(from, to)) _compact(t)],
      'index': i - from,
      'pos': player.position.inMilliseconds,
    });
  }

  Future<void> _onCmd(Map<String, dynamic> p) async {
    if (p['to'] != _id) return;
    _controller = '${p['fromName'] ?? 'Устройство'}';
    _controlledAt = DateTime.now();
    final action = '${p['action'] ?? ''}';
    if (action.startsWith('handoff_to:')) {
      await _sendQueueTo(action.substring('handoff_to:'.length));
      await player.pause();
      return;
    }
    switch (action) {
      case 'toggle':
        await player.togglePlay();
      case 'next':
        await player.next();
      case 'prev':
        await player.previous();
      case 'seek':
        final ms = (p['ms'] as num?)?.toInt();
        if (ms != null) await player.seek(Duration(milliseconds: ms));
      case 'volume':
        final v = (p['v'] as num?)?.toDouble();
        if (v != null) await player.setVolume(v);
    }
    _publish();
    notifyListeners();
  }

  Future<void> _onTake(Map<String, dynamic> p) async {
    if (p['to'] != _id) return;
    final list = p['queue'];
    if (list is! List) return;
    final q = <Track>[
      for (final j in list)
        if (j is Map) Track.fromJson(Map<String, dynamic>.from(j)),
    ];
    if (q.isEmpty) return;
    final i = ((p['index'] as num?)?.toInt() ?? 0).clamp(0, q.length - 1);
    await player.playTracks(q, start: i);
    final ms = (p['pos'] as num?)?.toInt() ?? 0;
    if (ms > 2000) {
      // Ждём, пока трек загрузится, и перематываем на то же место.
      for (var k = 0; k < 40 && player.loading; k++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      await player.seek(Duration(milliseconds: ms));
    }
  }

  /// Вернулись в приложение — подтягиваем медиатеку и обновляем статус.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && account.signedIn) {
      unawaited(account.syncNow());
      _publish();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _beat?.cancel();
    _debounce?.cancel();
    account.removeListener(_onAccount);
    player.removeListener(_onPlayer);
    super.dispose();
  }
}
