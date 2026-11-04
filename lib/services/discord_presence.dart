import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'deep_links.dart';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart'
    show
        CloseHandle,
        CreateFile,
        GENERIC_READ,
        GENERIC_WRITE,
        GetLastError,
        INVALID_HANDLE_VALUE,
        OPEN_EXISTING,
        PeekNamedPipe,
        ReadFile,
        WriteFile;

import '../config.dart';
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

  /// Что сейчас с Discord — показывается в настройках.
  static final status = ValueNotifier<String>('');

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
      final show = t != null && (player.playing || !settings.discordHideOnPause);
      final activity = enabled && show ? _activity(t) : null;
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
          status.value = _IpcConnection.lastProblem ??
              'Не вижу Discord. Нужно приложение Discord на компьютере (не браузер), '
                  'запущенное без «от имени администратора»';
          _retryAfter = DateTime.now().add(const Duration(seconds: 15));
          return;
        }
        _connectedFor = appId;
      }
      await _send(activity);
      _lastSent = key;
      status.value = lastError != null
          ? 'Discord ответил: $lastError'
          : activity == null
              ? 'Подключено. Статус появится, когда заиграет музыка'
              : 'Подключено: статус показывается';
    } catch (e) {
      debugPrint('[Discord] $e');
      status.value = 'Ошибка связи с Discord: $e';
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
      'state': cut(player.playing ? t.artist : 'На паузе · ${t.artist}'),
      if (settings.discordTime && player.playing)
        'timestamps': {
          'start': now - pos,
          if (dur != null && dur > pos) 'end': now - pos + dur,
        },
      if (settings.discordButton && (DeepLinks.pageFor(t) ?? _linkFor(t)) != null)
        'buttons': [
          {'label': 'Слушать трек', 'url': DeepLinks.pageFor(t) ?? _linkFor(t)},
        ],
      'assets': {
        // Обложка по ссылке; у своих файлов её нет — тогда логотип Hutred.
        if (art != null && art.startsWith('http') && art.length < 250)
          'large_image': art
        else if (_logoUrl != null)
          'large_image': _logoUrl,
        'large_text': cut(t.shownAlbum.isNotEmpty ? t.shownAlbum : t.title),
        if (_logoUrl != null && art != null && art.startsWith('http'))
          'small_image': _logoUrl,
        if (_logoUrl != null) 'small_text': 'Hutred',
      },
    };
  }

  /// Ссылка на трек для кнопки в статусе (у своих файлов её нет).
  static String? _linkFor(Track t) {
    final u = t.uri;
    switch (t.source) {
      case TrackSource.youtube:
        return 'https://youtu.be/$u';
      case TrackSource.soundcloud:
        return u.startsWith('https://') ? u : null;
      case TrackSource.spotify:
        return u.startsWith('deezer:')
            ? 'https://www.deezer.com/track/${u.substring(7)}'
            : 'https://open.spotify.com/track/$u';
      case TrackSource.url:
        return u.startsWith('https://') ? u : null;
      case TrackSource.local:
        return null;
    }
  }

  /// Логотип для статуса (выкладывается вместе с обновлениями).
  static final String? _logoUrl = HutredConfig.supabaseUrl.isEmpty
      ? null
      : '${HutredConfig.supabaseUrl}/storage/v1/object/public/releases/discord/logo.png';

  /// Последняя ошибка Discord (показывается в настройках).
  static String? lastError;

  Future<void> _send(Map<String, dynamic>? activity) async {
    final c = _conn;
    if (c == null) return;
    Future<Map<String, dynamic>> go(Map<String, dynamic>? a) => c.request(1, {
          'cmd': 'SET_ACTIVITY',
          'args': {'pid': pid, 'activity': a},
          'nonce': '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 20)}',
        });
    var res = await go(activity);
    if (res['evt'] == 'ERROR' && activity != null) {
      // Discord не принял что-то из статуса (чаще всего картинку) —
      // пробуем проще, чтобы хотя бы трек и время показывались.
      lastError = '${(res['data'] as Map?)?['message'] ?? res['data']}';
      debugPrint('[Discord] $lastError');
      final simple = Map<String, dynamic>.of(activity)..remove('assets');
      res = await go(simple);
    } else {
      lastError = null;
    }
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
  /// Почему не удалось подключиться (например, Discord отверг Application ID).
  static String? lastProblem;

  static Future<_IpcConnection?> connect(String clientId) async {
    lastProblem = null;
    for (var i = 0; i < 10; i++) {
      _IpcConnection? c;
      try {
        if (Platform.isWindows) {
          // Канал открываем через WinAPI: dart:io открывает файлы с «дописать
          // в конец»/«создать», а именованный канал Discord такого не понимает.
          final w = _WinPipe.open('\\\\.\\pipe\\discord-ipc-$i');
          if (w == null) continue;
          c = w;
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
        lastProblem = 'Discord не принял Application ID: '
            '${(ready['data'] as Map?)?['message'] ?? ready}';
        await c.close();
      } catch (e) {
        lastProblem ??= 'Discord найден, но не ответил: $e';
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


/// Именованный канал Windows через WinAPI. Чтение без блокировки:
/// ждём, пока в канале появятся данные (PeekNamedPipe), и только потом читаем.
class _WinPipe extends _IpcConnection {
  _WinPipe._(this._h);
  final int _h;
  bool _closed = false;

  static _WinPipe? open(String path) {
    final name = path.toNativeUtf16();
    try {
      final h = CreateFile(name, GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, 0, 0);
      if (h == INVALID_HANDLE_VALUE) return null;
      return _WinPipe._(h);
    } finally {
      calloc.free(name);
    }
  }

  @override
  Future<void> write(Uint8List bytes) async {
    final buf = calloc<Uint8>(bytes.length);
    final written = calloc<Uint32>();
    try {
      buf.asTypedList(bytes.length).setAll(0, bytes);
      if (WriteFile(_h, buf, bytes.length, written, nullptr) == 0) {
        throw SocketException('Discord: запись не удалась (${GetLastError()})');
      }
    } finally {
      calloc.free(buf);
      calloc.free(written);
    }
  }

  @override
  Future<Uint8List> readExactly(int n) async {
    final out = BytesBuilder();
    final avail = calloc<Uint32>();
    final got = calloc<Uint32>();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    try {
      while (out.length < n) {
        if (_closed) throw const SocketException('Discord закрыл соединение');
        if (PeekNamedPipe(_h, nullptr, 0, nullptr, avail, nullptr) == 0) {
          throw SocketException('Discord закрыл соединение (${GetLastError()})');
        }
        final ready = avail.value;
        if (ready == 0) {
          if (DateTime.now().isAfter(deadline)) {
            throw TimeoutException('Discord не ответил');
          }
          await Future<void>.delayed(const Duration(milliseconds: 15));
          continue;
        }
        final want = (n - out.length) < ready ? (n - out.length) : ready;
        final buf = calloc<Uint8>(want);
        try {
          if (ReadFile(_h, buf, want, got, nullptr) == 0) {
            throw SocketException('Discord: чтение не удалось (${GetLastError()})');
          }
          out.add(Uint8List.fromList(buf.asTypedList(got.value)));
        } finally {
          calloc.free(buf);
        }
      }
      return out.takeBytes();
    } finally {
      calloc.free(avail);
      calloc.free(got);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    CloseHandle(_h);
  }
}
