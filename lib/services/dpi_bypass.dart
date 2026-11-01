import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Обход блокировок по DPI (как zapret / GoodbyeDPI / ByeDPI), но только
/// для трафика самого Hutred и без прав администратора.
///
/// Как это работает: все HTTPS-запросы приложения идут через маленький
/// прокси на 127.0.0.1. Первое сообщение TLS (ClientHello, в нём открытым
/// текстом имя сайта) прокси режет на две TLS-записи и два TCP-пакета
/// прямо посередине имени сайта. Оборудование провайдера (ТСПУ) не может
/// собрать имя и пропускает соединение, а сам сайт склеивает всё обратно.
/// Адреса сайтов прокси узнаёт через DNS-over-HTTPS, чтобы провайдер не
/// подсунул поддельный адрес.
class DpiBypass {
  DpiBypass._();

  /// Включён ли обход (переключается из настроек на лету).
  static bool enabled = false;

  static ServerSocket? _server;
  static int? _port;

  /// Ставит перехват HTTP-клиентов. Вызывается один раз при запуске,
  /// до создания любых сетевых клиентов.
  static Future<void> install() async {
    if (kIsWeb) return;
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      _server!.listen(_handle, onError: (Object e) => debugPrint('[Обход] $e'));
      HttpOverrides.global = _Overrides();
    } catch (e) {
      debugPrint('[Обход] не удалось запустить: $e');
    }
  }

  static String _proxyFor(Uri uri) {
    final port = _port;
    if (!enabled || port == null || uri.scheme != 'https') return 'DIRECT';
    // Локальные адреса и сам DoH-резолвер идут напрямую.
    if (uri.host == '127.0.0.1' || uri.host == 'localhost' || uri.host == _dohHost) {
      return 'DIRECT';
    }
    return 'PROXY 127.0.0.1:$port';
  }

  // ---------- Прокси ----------

  static Future<void> _handle(Socket client) async {
    Socket? remote;
    try {
      client.setOption(SocketOption.tcpNoDelay, true);
      final reader = _Reader(client);
      final head = await reader.readUntil(utf8.encode('\r\n\r\n'));
      final firstLine = latin1.decode(head).split('\r\n').first;
      final parts = firstLine.split(' ');
      if (parts.length < 2 || parts[0].toUpperCase() != 'CONNECT') {
        client.add(latin1.encode('HTTP/1.1 405 Method Not Allowed\r\n\r\n'));
        await client.close();
        return;
      }
      final hp = parts[1];
      final colon = hp.lastIndexOf(':');
      final host = colon > 0 ? hp.substring(0, colon) : hp;
      final port = colon > 0 ? int.tryParse(hp.substring(colon + 1)) ?? 443 : 443;

      final address = await _resolve(host);
      remote = await Socket.connect(address, port, timeout: const Duration(seconds: 15));
      remote.setOption(SocketOption.tcpNoDelay, true);
      client.add(latin1.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
      await client.flush();

      // Первое TLS-сообщение собираем целиком и отправляем порезанным.
      final hello = await reader.readTlsRecord();
      await _sendSplit(remote, hello, host);

      // Дальше — просто перекачиваем байты в обе стороны.
      final r = remote;
      final leftover = reader.takeRest();
      if (leftover.isNotEmpty) r.add(leftover);
      reader.pipeTo(r);
      r.listen(client.add,
          onDone: () => client.destroy(), onError: (_) => client.destroy(), cancelOnError: true);
    } catch (e) {
      debugPrint('[Обход] $e');
      remote?.destroy();
      client.destroy();
    }
  }

  /// ClientHello → две TLS-записи, разрез посередине имени сайта,
  /// и каждая уходит отдельным TCP-пакетом.
  static Future<void> _sendSplit(Socket remote, Uint8List rec, String host) async {
    // Не TLS (или что-то странное) — отправляем как есть.
    if (rec.length < 6 || rec[0] != 0x16) {
      remote.add(rec);
      await remote.flush();
      return;
    }
    final body = rec.sublist(5);
    final name = ascii.encode(host);
    var at = _indexOf(body, name);
    at = at >= 0 ? at + (name.length ~/ 2).clamp(1, name.length - 1) : body.length ~/ 2;
    if (at <= 0 || at >= body.length) at = body.length ~/ 2;

    Uint8List record(Uint8List data) => Uint8List.fromList([
          0x16, rec[1], rec[2], (data.length >> 8) & 0xff, data.length & 0xff, ...data,
        ]);

    final first = record(Uint8List.sublistView(body, 0, at));
    final second = record(Uint8List.sublistView(body, at));
    // Первую запись ещё и делим на два TCP-пакета.
    remote.add(Uint8List.sublistView(first, 0, 3));
    await remote.flush();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    remote.add(Uint8List.sublistView(first, 3));
    await remote.flush();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    remote.add(second);
    await remote.flush();
  }

  static int _indexOf(Uint8List hay, List<int> needle) {
    outer:
    for (var i = 0; i + needle.length <= hay.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (hay[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  // ---------- DNS-over-HTTPS ----------

  static const _dohHost = '1.1.1.1';
  static final Map<String, ({InternetAddress addr, DateTime until})> _dns = {};

  /// Адрес сайта через Cloudflare DoH (провайдер не подменит),
  /// при ошибке — обычным способом.
  static Future<InternetAddress> _resolve(String host) async {
    final ip = InternetAddress.tryParse(host);
    if (ip != null) return ip;
    final cached = _dns[host];
    if (cached != null && DateTime.now().isBefore(cached.until)) return cached.addr;
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      // Сам запрос к 1.1.1.1 идёт напрямую (см. _proxyFor).
      final req = await c.getUrl(Uri.https(_dohHost, '/dns-query', {'name': host, 'type': 'A'}));
      req.headers.set('accept', 'application/dns-json');
      final res = await req.close().timeout(const Duration(seconds: 5));
      final j = jsonDecode(await res.transform(utf8.decoder).join());
      c.close();
      for (final a in (j['Answer'] as List? ?? const [])) {
        if (a is Map && a['type'] == 1) {
          final addr = InternetAddress(a['data'] as String);
          final ttl = ((a['TTL'] as num?)?.toInt() ?? 300).clamp(60, 3600);
          _dns[host] = (addr: addr, until: DateTime.now().add(Duration(seconds: ttl)));
          return addr;
        }
      }
    } catch (e) {
      debugPrint('[Обход] DoH для $host: $e');
    }
    final list = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
    return list.first;
  }
}

class _Overrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final c = super.createHttpClient(context);
    c.findProxy = DpiBypass._proxyFor;
    return c;
  }
}

/// Чтение из сокета с буфером: заголовок CONNECT, затем одна TLS-запись.
class _Reader {
  _Reader(Socket s) {
    _sub = s.listen((d) {
      if (_target != null) {
        _target!.add(d);
      } else {
        _buf.add(d);
        _wake?.complete();
        _wake = null;
      }
    }, onDone: () {
      _done = true;
      _wake?.complete();
      _target?.destroy();
    }, onError: (_) {
      _done = true;
      _wake?.complete();
      _target?.destroy();
    });
  }

  late final StreamSubscription<Uint8List> _sub;
  final _buf = BytesBuilder();
  Completer<void>? _wake;
  bool _done = false;
  Socket? _target;

  Future<void> _more() async {
    if (_done) throw const SocketException('соединение закрыто');
    _wake = Completer<void>();
    await _wake!.future.timeout(const Duration(seconds: 15));
  }

  Uint8List _take(int n) {
    final all = _buf.takeBytes();
    _buf.add(Uint8List.sublistView(all, n));
    return Uint8List.fromList(Uint8List.sublistView(all, 0, n));
  }

  Future<Uint8List> readUntil(List<int> marker) async {
    while (true) {
      final bytes = _buf.toBytes();
      final i = DpiBypass._indexOf(bytes, marker);
      if (i >= 0) return _take(i + marker.length);
      if (bytes.length > 16384) throw const FormatException('слишком длинный заголовок');
      await _more();
    }
  }

  Future<Uint8List> readTlsRecord() async {
    while (_buf.length < 5) {
      await _more();
    }
    final b = _buf.toBytes();
    final need = b[0] == 0x16 ? 5 + ((b[3] << 8) | b[4]) : b.length;
    while (_buf.length < need) {
      await _more();
    }
    return _take(need);
  }

  Uint8List takeRest() => _buf.takeBytes();

  /// Всё, что придёт дальше, отправлять прямо в [s].
  void pipeTo(Socket s) => _target = s;

  Future<void> cancel() => _sub.cancel();
}
