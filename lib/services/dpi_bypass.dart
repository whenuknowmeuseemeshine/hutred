import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'xray_vpn.dart';

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

  /// На компьютере запущен zapret (winws.exe) — он уже обходит блокировки
  /// для всей системы, свой обход тогда выключаем, чтобы они не мешали друг другу.
  static final zapretRunning = ValueNotifier<bool>(false);

  static Timer? _zapretTimer;

  /// [wanted] — включён ли обход в настройках.
  static void watchZapret(bool Function() wanted) {
    if (kIsWeb || !Platform.isWindows) {
      enabled = wanted();
      return;
    }
    Future<void> check() async {
      try {
        final r = await Process.run('tasklist', ['/FI', 'IMAGENAME eq winws.exe', '/NH']);
        zapretRunning.value = '${r.stdout}'.toLowerCase().contains('winws.exe');
      } catch (_) {}
      enabled = wanted() && !zapretRunning.value;
    }

    enabled = wanted();
    check();
    _zapretTimer ??= Timer.periodic(const Duration(seconds: 30), (_) => check());
  }

  /// Настройку переключили.
  static void refresh(bool wanted) => enabled = wanted && !zapretRunning.value;

  static ServerSocket? _server;
  static int? _port;

  /// Ставит перехват HTTP-клиентов. Вызывается один раз при запуске,
  /// до создания любых сетевых клиентов.
  static Future<void> install() async {
    if (kIsWeb) return;
    try {
      await _bind();
      HttpOverrides.global = _Overrides();
      // iOS закрывает слушающий сокет, пока приложение в фоне, —
      // после возврата проверяем прокси и поднимаем заново.
      WidgetsBinding.instance.addObserver(_Life());
    } catch (e) {
      debugPrint('[Обход] не удалось запустить: $e');
    }
  }

  static Future<void> _bind() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _server!.listen(_handle, onError: (Object e) => debugPrint('[Обход] $e'), onDone: () => _port = null);
  }

  static Future<void>? _checking;

  /// Жив ли локальный прокси; если нет — поднимает новый.
  static Future<void> ensureAlive() => _checking ??= _ensureAlive().whenComplete(() => _checking = null);

  static Future<void> _ensureAlive() async {
    if (kIsWeb || _server == null) return;
    final port = _port;
    if (port != null) {
      try {
        final s = await Socket.connect(InternetAddress.loopbackIPv4, port,
            timeout: const Duration(seconds: 2));
        s.destroy();
        return;
      } catch (_) {}
    }
    debugPrint('[Обход] прокси не отвечает — перезапуск');
    _port = null;
    try {
      await _server?.close();
    } catch (_) {}
    try {
      await _bind();
    } catch (e) {
      debugPrint('[Обход] не удалось перезапустить: $e');
    }
  }

  /// Можно ли пробовать запрос напрямую (без своего VPN-ключа).
  static bool get mayGoDirect => !(XrayVpn.port != null && XrayVpn.active);

  static String _proxyFor(Uri uri) {
    // Свой VPN-ключ важнее обхода: весь трафик Hutred идёт через ядро Xray.
    final vpn = XrayVpn.port;
    if (vpn != null &&
        XrayVpn.active &&
        uri.host != '127.0.0.1' &&
        uri.host != 'localhost' &&
        uri.host != '::1') {
      return 'PROXY 127.0.0.1:$vpn';
    }
    final port = _port;
    if (!enabled || port == null || uri.scheme != 'https') return 'DIRECT';
    // Локальные адреса и сам DoH-резолвер идут напрямую.
    if (uri.host == '127.0.0.1' ||
        uri.host == 'localhost' ||
        uri.host == _dohHost ||
        uri.host == _dohHost2) {
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

      final address = await resolve(host);
      Socket sock;
      try {
        sock = await Socket.connect(address, port, timeout: const Duration(seconds: 10));
      } catch (_) {
        // Адрес из DoH не открылся (например, сеть только IPv6 у мобильного
        // оператора) — пробуем адрес от системы.
        _dns.remove(host);
        sock = await Socket.connect(host, port, timeout: const Duration(seconds: 10));
      }
      remote = sock;
      remote.setOption(SocketOption.tcpNoDelay, true);
      client.add(latin1.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
      await client.flush();

      // Первое TLS-сообщение собираем целиком и отправляем порезанным
      // (в режиме «только DNS» — как есть).
      final hello = await reader.readTlsRecord();
      final how = _testStrategy ?? strategy;
      if (splitHello && how != 'none') {
        await _sendWith(how, remote, hello, host);
      } else {
        remote.add(hello);
        await remote.flush();
      }

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

  // ---------- Способы обхода (как в ByeDPI) ----------

  /// Выбранный способ: split, multisplit, disorder, disorder_multi или none.
  static String strategy = 'split';

  /// Способ на время проверки (автоподбор).
  static String? _testStrategy;

  static const strategies = ['split', 'multisplit', 'disorder', 'disorder_multi'];

  static String strategyLabel(String s) => switch (s) {
        'split' => 'разрез имени сайта',
        'multisplit' => 'мелкая нарезка',
        'disorder' => 'разрез с перестановкой пакетов',
        'disorder_multi' => 'мелкая нарезка с перестановкой',
        _ => 'без хитростей',
      };

  /// Что подобрано и как быстро открывается YouTube (для настроек).
  static final status = ValueNotifier<String>('');

  static Future<void> _sendWith(String how, Socket remote, Uint8List hello, String host) async {
    switch (how) {
      case 'multisplit':
        return _sendMulti(remote, hello, host, disorder: false);
      case 'disorder':
        return _sendDisorder(remote, hello, host);
      case 'disorder_multi':
        return _sendMulti(remote, hello, host, disorder: true);
      default:
        return _sendSplit(remote, hello, host);
    }
  }

  // TTL: 1 — пакет «теряется» на первом же узле, ОС потом пошлёт его заново.
  static int get _ipTtl => Platform.isWindows || Platform.isMacOS || Platform.isIOS ? 4 : 2;
  static int get _defaultTtl => Platform.isWindows ? 128 : 64;

  static bool _setTtl(Socket s, int ttl) {
    try {
      s.setRawOption(RawSocketOption.fromInt(RawSocketOption.levelIPv4, _ipTtl, ttl));
      return true;
    } catch (e) {
      debugPrint('[Обход] TTL не поменять: $e');
      return false;
    }
  }

  /// «Беспорядок»: начало ClientHello уходит с TTL=1 и теряется по дороге,
  /// за ним — остальное. Провайдер видит хвост без начала и не узнаёт сайт,
  /// а ОС сама дошлёт потерянное начало — сервер соберёт всё как надо.
  static Future<void> _sendDisorder(Socket remote, Uint8List rec, String host) async {
    final at = _sniCut(rec, host);
    if (at == null || !_setTtl(remote, 1)) return _sendSplit(remote, rec, host);
    remote.add(Uint8List.sublistView(rec, 0, at));
    await remote.flush();
    await Future<void>.delayed(const Duration(milliseconds: 3));
    _setTtl(remote, _defaultTtl);
    remote.add(Uint8List.sublistView(rec, at));
    await remote.flush();
  }

  /// Где в записи начинается имя сайта (+1 байт), или null.
  static int? _sniCut(Uint8List rec, String host) {
    if (rec.length < 6 || rec[0] != 0x16) return null;
    final i = _indexOf(rec, ascii.encode(host));
    return i > 0 ? i + 1 : null;
  }

  /// Мелкая нарезка: ClientHello делится на много TLS-записей — до имени
  /// сайта, само имя по 2 байта, остальное — и каждая уходит своим пакетом.
  /// С [disorder] первый пакет ещё и уходит с TTL=1.
  static Future<void> _sendMulti(Socket remote, Uint8List rec, String host,
      {required bool disorder}) async {
    if (rec.length < 6 || rec[0] != 0x16) {
      remote.add(rec);
      await remote.flush();
      return;
    }
    final body = rec.sublist(5);
    final name = ascii.encode(host);
    final at = _indexOf(body, name);
    final cuts = <int>[0];
    if (at > 0) {
      cuts.add(at);
      for (var i = at + 2; i < at + name.length; i += 2) {
        cuts.add(i);
      }
      cuts.add(at + name.length);
    } else {
      for (var i = 1; i < 6; i++) {
        cuts.add(body.length * i ~/ 6);
      }
    }
    cuts.add(body.length);
    final pieces = <Uint8List>[];
    for (var i = 0; i + 1 < cuts.length; i++) {
      if (cuts[i + 1] <= cuts[i]) continue;
      final data = Uint8List.sublistView(body, cuts[i], cuts[i + 1]);
      pieces.add(Uint8List.fromList(
          [0x16, rec[1], rec[2], (data.length >> 8) & 0xff, data.length & 0xff, ...data]));
    }
    final lowTtl = disorder && _setTtl(remote, 1);
    for (var i = 0; i < pieces.length; i++) {
      remote.add(pieces[i]);
      await remote.flush();
      if (i == 0 && lowTtl) {
        await Future<void>.delayed(const Duration(milliseconds: 3));
        _setTtl(remote, _defaultTtl);
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  /// Автоподбор: по очереди пробуем способы на YouTube и берём самый быстрый.
  /// Возвращает выбранный способ.
  static Future<String> autotune({void Function(String)? onProgress}) async {
    if (_port == null) return strategy;
    final results = <String, double>{};
    for (final s in ['none', ...strategies]) {
      onProgress?.call('Пробую: ${strategyLabel(s)}…');
      results[s] = await _measure(s);
      debugPrint('[Обход] $s: ${(results[s]! / 1024).round()} КБ/с');
    }
    final best = results.entries.reduce((a, b) => b.value > a.value ? b : a);
    strategy = best.value <= 0 ? 'split' : best.key;
    final speed = best.value <= 0
        ? 'YouTube не открылся ни одним способом'
        : 'YouTube: ${(best.value / 1024 / 1024).toStringAsFixed(1)} МБ/с';
    status.value = 'Подобрано: ${strategyLabel(strategy)} · $speed';
    return strategy;
  }

  /// Скорость (байт/с) загрузки страницы YouTube этим способом; 0 — не открылось.
  static Future<double> _measure(String how) async {
    final wasEnabled = enabled;
    enabled = true;
    _testStrategy = how;
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    final sw = Stopwatch()..start();
    var got = 0;
    try {
      final req = await c.getUrl(Uri.parse('https://www.youtube.com/?hl=ru&_=${sw.hashCode}'));
      req.headers.set('accept-encoding', 'identity');
      req.headers.set('user-agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36');
      final res = await req.close().timeout(const Duration(seconds: 8));
      await for (final chunk in res.timeout(const Duration(seconds: 8))) {
        got += chunk.length;
        if (got > 700 * 1024 || sw.elapsedMilliseconds > 8000) break;
      }
    } catch (_) {
      // не открылось
    } finally {
      c.close(force: true);
      _testStrategy = null;
      enabled = wasEnabled;
    }
    if (got < 20 * 1024) return 0;
    return got / (sw.elapsedMilliseconds.clamp(1, 1 << 30) / 1000);
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

  /// Резать ли ClientHello (обход DPI). false — режим «только безопасный DNS»:
  /// адреса сайтов узнаём у Cloudflare/Google, а соединение не трогаем.
  static bool splitHello = true;

  static const _dohHost = '1.1.1.1';
  static const _dohHost2 = '8.8.8.8';
  static final Map<String, ({InternetAddress addr, DateTime until})> _dns = {};

  /// Адрес сайта через Cloudflare DoH (провайдер не подменит),
  /// при ошибке — обычным способом.
  static final _resolving = <String, Future<InternetAddress>>{};

  /// Один запрос DoH на сайт, даже если картинок с него грузится сотня разом.
  static Future<InternetAddress> resolve(String host) {
    final ip = InternetAddress.tryParse(host);
    if (ip != null) return Future.value(ip);
    final cached = _dns[host];
    if (cached != null && DateTime.now().isBefore(cached.until)) return Future.value(cached.addr);
    return _resolving[host] ??= _resolve(host).whenComplete(() {
      // Без «=>»: remove вернул бы этот же Future, и whenComplete ждал бы сам себя.
      _resolving.remove(host);
    });
  }

  static Future<InternetAddress> _resolve(String host) async {
    // Сначала Cloudflare (1.1.1.1), не ответил — Google (8.8.8.8).
    // Сами эти запросы идут напрямую (см. _proxyFor).
    for (final doh in [
      Uri.https(_dohHost, '/dns-query', {'name': host, 'type': 'A'}),
      Uri.https(_dohHost2, '/resolve', {'name': host, 'type': 'A'}),
    ]) {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      try {
        final req = await c.getUrl(doh);
        req.headers.set('accept', 'application/dns-json');
        final res = await req.close().timeout(const Duration(seconds: 5));
        final j = jsonDecode(await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 5)));
        for (final a in (j['Answer'] as List? ?? const [])) {
          if (a is Map && a['type'] == 1) {
            final addr = InternetAddress(a['data'] as String);
            final ttl = ((a['TTL'] as num?)?.toInt() ?? 300).clamp(60, 3600);
            _dns[host] = (addr: addr, until: DateTime.now().add(Duration(seconds: ttl)));
            return addr;
          }
        }
      } catch (e) {
        debugPrint('[Обход] DoH ${doh.host} для $host: $e');
      } finally {
        c.close(force: true);
      }
    }
    final list = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
    return list.first;
  }
}

class _Life with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(DpiBypass.ensureAlive());
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
