import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/track.dart';
import 'player_service.dart';
import 'settings_store.dart';

/// Статус в Discord, как у Spotify: «Слушает Hutred» — трек, исполнитель,
/// обложка и полоска времени. Работает на компьютере, если открыт Discord.
///
/// Discord принимает статус через локальный канал (IPC):
/// на Windows — именованный канал \\.\pipe\discord-ipc-N,
/// на Linux/macOS — сокет discord-ipc-N во временной папке.
class DiscordPresence {
  DiscordPresence({required this.player, required this.settings}) {
    if (!_supported) return;
    player.addListener(_schedule);
    settings.addListener(_schedule);
  }

  final PlayerService player;
  final SettingsStore settings;

  static bool get _supported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  _IpcConnection? _conn;
  String? _connectedFor;
  Timer? _debounce;
  String _lastSent = '';
  bool _busy = false;
  DateTime _retryAfter = DateTime.fromMillisecondsSinceEpoch(0);

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _update);
  }

  Future<void> _update() async {
    if (_busy) {
      _schedule();
      return;
    }
    _busy = true;
    try {
      final appId = settings.discordAppId;
      final enabled = settings.discordPresence && appId.isNotEmpty;
      final t = player.current;
      final activity = enabled && t != null && player.playing ? _activity(t) : null;
      final key = jsonEncode(activity);
      // Тот же статус уже отправлен — не дёргаем Discord.
      if (key == _lastSent && _connectedFor == appId) return;
      if (!enabled) {
        if (_conn != null) await _send(null);
        await _close();
        _lastSent = key;
        return;
      }
      if (_conn == null || _connectedFor != appId) {
        if (DateTime.now().isBefore(_retryAfter)) return;
        await _close();
        _conn = await _IpcConnection.connect(appId);
        if (_conn == null) {
          // Discord не запущен — попробуем позже.
          _retryAfter = DateTime.now().add(const Duration(seconds: 30));
          return;
        }
        _connectedFor = appId;
      }
      await _send(activity);
      _lastSent = key;
    } catch (e) {
      debugPrint('[Discord] $e');
      await _close();
    } finally {
      _busy = false;
    }
  }

  Map<String, dynamic> _activity(Track t) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final pos = player.position.inMilliseconds;
    final dur = player.duration?.inMilliseconds ?? t.durationMs;
    final art = t.artworkUrl;
    String cut(String s) => s.length > 120 ? '${s.substring(0, 117)}…' : s.padRight(2);
    return {
      // 2 — «Слушает», как у Spotify.
      'type': 2,
      'details': cut(t.title),
      'state': cut(t.artist),
      'timestamps': {
        'start': now - pos,
        if (dur != null && dur > pos) 'end': now - pos + dur,
      },
      'assets': {
        if (art != null && art.startsWith('http')) 'large_image': art,
        'large_text': cut(t.album.isNotEmpty ? t.album : t.title),
      },
    };
  }

  Future<void> _send(Map<String, dynamic>? activity) async {
    final c = _conn;
    if (c == null) return;
    await c.request(1, {
      'cmd': 'SET_ACTIVITY',
      'args': {'pid': pid, 'activity': activity},
      'nonce': '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 20)}',
    });
  }

  Future<void> _close() async {
    final c = _conn;
    _conn = null;
    _connectedFor = null;
    _lastSent = '';
    await c?.close();
  }
}

/// Одно соединение с Discord: кадры [op:uint32][длина:uint32][JSON].
abstract class _IpcConnection {
  static Future<_IpcConnection?> connect(String clientId) async {
    for (var i = 0; i < 10; i++) {
      _IpcConnection? c;
      try {
        if (Platform.isWindows) {
          final f = await File('\\\\.\\pipe\\discord-ipc-$i').open(mode: FileMode.append);
          c = _PipeConnection(f);
        } else {
          final base = Platform.environment['XDG_RUNTIME_DIR'] ??
              Platform.environment['TMPDIR'] ??
              '/tmp';
          final path = '${base.replaceAll(RegExp(r'/$'), '')}/discord-ipc-$i';
          if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) continue;
          final s = await Socket.connect(
              InternetAddress(path, type: InternetAddressType.unix), 0,
              timeout: const Duration(seconds: 2));
          c = _SocketConnection(s);
        }
        // Рукопожатие: Discord отвечает событием READY.
        final ready = await c.request(0, {'v': 1, 'client_id': clientId});
        if (ready['evt'] == 'READY') return c;
        await c.close();
      } catch (_) {
        await c?.close();
      }
    }
    return null;
  }

  Future<void> write(Uint8List bytes);
  Future<Uint8List> readExactly(int n);
  Future<void> close();

  Future<Map<String, dynamic>> request(int op, Map<String, dynamic> payload) async {
    final body = utf8.encode(jsonEncode(payload));
    final header = ByteData(8)
      ..setUint32(0, op, Endian.little)
      ..setUint32(4, body.length, Endian.little);
    await write(Uint8List.fromList([...header.buffer.asUint8List(), ...body]));
    final h = ByteData.sublistView(await readExactly(8));
    final len = h.getUint32(4, Endian.little);
    final data = await readExactly(len);
    final j = jsonDecode(utf8.decode(data));
    return j is Map<String, dynamic> ? j : <String, dynamic>{};
  }
}

class _PipeConnection extends _IpcConnection {
  _PipeConnection(this._f);
  final RandomAccessFile _f;

  @override
  Future<void> write(Uint8List bytes) async {
    await _f.writeFrom(bytes);
    await _f.flush();
  }

  @override
  Future<Uint8List> readExactly(int n) async {
    final out = BytesBuilder();
    while (out.length < n) {
      final chunk = await _f.read(n - out.length).timeout(const Duration(seconds: 5));
      if (chunk.isEmpty) throw const SocketException('Discord закрыл соединение');
      out.add(chunk);
    }
    return out.takeBytes();
  }

  @override
  Future<void> close() async {
    try {
      await _f.close();
    } catch (_) {}
  }
}

class _SocketConnection extends _IpcConnection {
  _SocketConnection(this._s) {
    _sub = _s.listen((d) {
      _buf.add(d);
      _wake?.complete();
      _wake = null;
    }, onDone: () => _closed = true, onError: (_) => _closed = true);
  }

  final Socket _s;
  late final StreamSubscription<Uint8List> _sub;
  final _buf = BytesBuilder();
  Completer<void>? _wake;
  bool _closed = false;

  @override
  Future<void> write(Uint8List bytes) async {
    _s.add(bytes);
    await _s.flush();
  }

  @override
  Future<Uint8List> readExactly(int n) async {
    while (_buf.length < n) {
      if (_closed) throw const SocketException('Discord закрыл соединение');
      _wake = Completer<void>();
      await _wake!.future.timeout(const Duration(seconds: 5));
    }
    final all = _buf.takeBytes();
    _buf.add(all.sublist(n));
    return Uint8List.fromList(all.sublist(0, n));
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    _s.destroy();
  }
}
