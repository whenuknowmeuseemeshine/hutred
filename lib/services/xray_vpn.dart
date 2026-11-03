import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';

/// Один сервер из VPN-ключа.
class VpnServer {
  VpnServer({required this.link, required this.name, required this.outbound});

  /// Исходная ссылка (vless://…).
  final String link;
  final String name;

  /// Готовый outbound для Xray.
  final Map<String, dynamic> outbound;

  String get protocol => outbound['protocol'] as String;
}

/// Свой VPN только для Hutred: пользователь вставляет ключ из Happ, v2rayN,
/// Hiddify и т.п. (vless://, vmess://, trojan://, ss:// или ссылку-подписку),
/// а приложение запускает рядом ядро Xray с локальным HTTP-прокси на
/// 127.0.0.1. Через него идут только запросы самого Hutred — остальной
/// компьютер или телефон работает как обычно, прав администратора не нужно.
class XrayVpn {
  XrayVpn._();

  /// Порт локального прокси, когда VPN работает и сервер отвечает.
  static int? port;

  /// Что показать в настройках: «off», «starting», «on», «error».
  static final status = ValueNotifier<String>('off');
  static final message = ValueNotifier<String?>(null);

  static Process? _proc;
  static String? _exe;
  static int _gen = 0;

  /// Есть ли ядро на этой платформе.
  static bool get supported =>
      !kIsWeb && (Platform.isWindows || Platform.isAndroid || Platform.isLinux || Platform.isMacOS);

  static bool get active => port != null && status.value == 'on';

  // ---------- разбор ссылок ----------

  /// Разбирает то, что вставил пользователь: одна или несколько ссылок
  /// или base64-подписка. Ссылки-подписки (https://) нужно сначала скачать
  /// через [loadSubscription].
  static List<VpnServer> parseMany(String text) {
    var body = text.trim();
    if (!body.contains('://')) {
      final decoded = _b64(body.replaceAll(RegExp(r'\s'), ''));
      if (decoded != null && decoded.contains('://')) body = decoded;
    }
    final out = <VpnServer>[];
    for (final line in body.split(RegExp(r'[\r\n\s]+'))) {
      final l = line.trim();
      if (l.isEmpty) continue;
      try {
        final s = parse(l);
        if (s != null) out.add(s);
      } catch (e) {
        debugPrint('[VPN] не разобрал ${l.split('://').first}: $e');
      }
    }
    return out;
  }

  static VpnServer? parse(String link) {
    final scheme = link.split('://').first.toLowerCase();
    switch (scheme) {
      case 'vless':
        return _vless(link);
      case 'vmess':
        return _vmess(link);
      case 'trojan':
        return _trojan(link);
      case 'ss':
        return _ss(link);
      case 'xrayjson':
        return _xrayJson(link);
      default:
        return null;
    }
  }

  static bool isSubscription(String text) {
    final t = text.trim();
    return (t.startsWith('https://') || t.startsWith('http://')) && !t.contains('\n');
  }

  /// Уникальный номер устройства для панелей с лимитом устройств (Remnawave и др.).
  static String hwid = '';

  /// Скачивает подписку так, как это делают Happ / v2rayNG / v2rayN.
  /// Панели часто отдают настоящие серверы только «знакомым» приложениям,
  /// а остальным — сервер-заглушку «Приложение не поддерживается»,
  /// поэтому пробуем представиться по очереди разными клиентами.
  static Future<List<VpnServer>> loadSubscription(String url) async {
    final os = Platform.isAndroid ? 'Android' : (Platform.isWindows ? 'Windows' : Platform.operatingSystem);
    const agents = [
      'Happ/3.7.0',
      'v2rayNG/1.10.16',
      'v2rayN/7.13.8',
      'Hiddify/2.5.7',
      'Streisand/1.6',
    ];
    String? lastError;
    var sawPlaceholder = false;
    for (final ua in agents) {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      try {
        final req = await c.getUrl(Uri.parse(url.trim()));
        req.headers
          ..set(HttpHeaders.userAgentHeader, ua)
          ..set(HttpHeaders.acceptHeader, '*/*');
        if (hwid.isNotEmpty) {
          req.headers
            ..set('x-hwid', hwid)
            ..set('x-device-os', os)
            ..set('x-ver-os', Platform.operatingSystemVersion.split(' ').first)
            ..set('x-device-model', 'Hutred');
        }
        final res = await req.close().timeout(const Duration(seconds: 20));
        final body = await res.transform(utf8.decoder).join();
        if (res.statusCode != 200) {
          lastError = 'сервер подписки ответил ${res.statusCode}';
          continue;
        }
        final all = parseAny(body);
        final real = all.where((x) => !_isPlaceholder(x)).toList();
        if (real.isNotEmpty) return real;
        if (all.isNotEmpty) sawPlaceholder = true;
        if (body.contains('happ://crypt')) lastError = 'подписка отдаёт только зашифрованные ссылки Happ';
      } catch (e) {
        lastError = '$e';
      } finally {
        c.close(force: true);
      }
    }
    if (sawPlaceholder) {
      throw 'Подписка не отдала серверы (вместо них — заглушка). Возможно, исчерпан '
          'лимит устройств. Скопируй в Happ один из серверов (долгое нажатие → '
          '«Копировать») и вставь сюда ключ vless://';
    }
    throw lastError ?? 'в подписке нет серверов';
  }

  static bool _isPlaceholder(VpnServer s) {
    final o = jsonEncode(s.outbound);
    final addr = RegExp(r'"address":"([^"]*)"').firstMatch(o)?.group(1) ?? '';
    final port = RegExp(r'"port":(\d+)').firstMatch(o)?.group(1) ?? '';
    final n = s.name.toLowerCase();
    return addr == '0.0.0.0' ||
        addr.startsWith('127.') ||
        addr == 'localhost' ||
        port == '1' ||
        o.contains('00000000-0000-0000-0000-000000000000') ||
        n.contains('не поддерж') ||
        n.contains('not supported') ||
        n.contains('unsupported');
  }

  /// Текст подписки в любом виде: ссылки, base64 или JSON-конфиги Xray.
  static List<VpnServer> parseAny(String body) {
    final t = body.trim();
    if (t.startsWith('[') || t.startsWith('{')) {
      try {
        final j = jsonDecode(t);
        final configs = j is List ? j : [j];
        final out = <VpnServer>[];
        for (final (i, cfg) in configs.indexed) {
          if (cfg is! Map) continue;
          final name = '${cfg['remarks'] ?? cfg['ps'] ?? 'Сервер ${i + 1}'}';
          for (final o in (cfg['outbounds'] as List? ?? const [])) {
            if (o is! Map) continue;
            final proto = '${o['protocol']}';
            if (!const ['vless', 'vmess', 'trojan', 'shadowsocks'].contains(proto)) continue;
            final ob = Map<String, dynamic>.from(o)..remove('tag');
            out.add(VpnServer(
              link: 'xrayjson://${base64Url.encode(utf8.encode(jsonEncode({'name': name, 'outbound': ob})))}',
              name: name,
              outbound: ob,
            ));
            break;
          }
        }
        return out;
      } catch (_) {}
    }
    return parseMany(t);
  }

  static VpnServer _xrayJson(String link) {
    final j = jsonDecode(_b64(link.substring('xrayjson://'.length))!) as Map<String, dynamic>;
    return VpnServer(
      link: link,
      name: '${j['name']}',
      outbound: Map<String, dynamic>.from(j['outbound'] as Map),
    );
  }

  static String? _b64(String s) {
    try {
      var t = s.replaceAll('-', '+').replaceAll('_', '/').replaceAll(RegExp(r'\s'), '');
      t = t.padRight((t.length + 3) ~/ 4 * 4, '=');
      return utf8.decode(base64.decode(t), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  static String _name(Uri u, String fallback) {
    if (u.fragment.isEmpty) return fallback;
    try {
      return Uri.decodeComponent(u.fragment);
    } catch (_) {
      return u.fragment;
    }
  }

  static int _port(Uri u) => u.hasPort ? u.port : 443;

  /// Транспорт и шифрование из параметров ссылки (общие для vless/trojan).
  static Map<String, dynamic> _stream(Map<String, String> q, String host, {String defSecurity = 'none'}) {
    final net = switch ((q['type'] ?? 'tcp').toLowerCase()) {
      'splithttp' => 'xhttp',
      'h2' || 'http' => 'xhttp',
      final n => n,
    };
    final security = (q['security'] ?? defSecurity).toLowerCase();
    final sni = q['sni'] ?? q['peer'] ?? q['host'] ?? '';
    final s = <String, dynamic>{'network': net, 'security': security};
    final path = q['path'] ?? '/';
    final hostHeader = q['host'] ?? '';
    switch (net) {
      case 'ws':
        s['wsSettings'] = {'path': path, if (hostHeader.isNotEmpty) 'host': hostHeader};
      case 'grpc':
        s['grpcSettings'] = {
          'serviceName': q['serviceName'] ?? q['path'] ?? '',
          'multiMode': (q['mode'] ?? '') == 'multi',
        };
      case 'httpupgrade':
        s['httpupgradeSettings'] = {'path': path, if (hostHeader.isNotEmpty) 'host': hostHeader};
      case 'xhttp':
        s['xhttpSettings'] = {
          'path': path,
          if (hostHeader.isNotEmpty) 'host': hostHeader,
          if ((q['mode'] ?? '').isNotEmpty) 'mode': q['mode'],
        };
      case 'tcp' || 'raw':
        if ((q['headerType'] ?? '') == 'http') {
          s['tcpSettings'] = {
            'header': {
              'type': 'http',
              'request': {
                'path': [path],
                'headers': {
                  if (hostHeader.isNotEmpty) 'Host': [hostHeader],
                },
              },
            },
          };
        }
    }
    final fp = q['fp'] ?? '';
    final alpn = (q['alpn'] ?? '').split(',').where((e) => e.isNotEmpty).toList();
    if (security == 'tls') {
      s['tlsSettings'] = {
        'serverName': sni.isNotEmpty ? sni : host,
        if (fp.isNotEmpty) 'fingerprint': fp,
        if (alpn.isNotEmpty) 'alpn': alpn,
        if (q['allowInsecure'] == '1' || q['insecure'] == '1') 'allowInsecure': true,
      };
    } else if (security == 'reality') {
      s['realitySettings'] = {
        'serverName': sni,
        'fingerprint': fp.isNotEmpty ? fp : 'chrome',
        'publicKey': q['pbk'] ?? '',
        'shortId': q['sid'] ?? '',
        if ((q['spx'] ?? '').isNotEmpty) 'spiderX': q['spx'],
      };
    }
    return s;
  }

  static VpnServer _vless(String link) {
    final u = Uri.parse(link);
    final q = u.queryParameters;
    return VpnServer(
      link: link,
      name: _name(u, '${u.host}:${_port(u)}'),
      outbound: {
        'protocol': 'vless',
        'settings': {
          'vnext': [
            {
              'address': u.host,
              'port': _port(u),
              'users': [
                {
                  'id': Uri.decodeComponent(u.userInfo),
                  'encryption': q['encryption'] ?? 'none',
                  if ((q['flow'] ?? '').isNotEmpty) 'flow': q['flow'],
                },
              ],
            },
          ],
        },
        'streamSettings': _stream(q, u.host),
      },
    );
  }

  static VpnServer _trojan(String link) {
    final u = Uri.parse(link);
    final q = u.queryParameters;
    return VpnServer(
      link: link,
      name: _name(u, '${u.host}:${_port(u)}'),
      outbound: {
        'protocol': 'trojan',
        'settings': {
          'servers': [
            {'address': u.host, 'port': _port(u), 'password': Uri.decodeComponent(u.userInfo)},
          ],
        },
        'streamSettings': _stream(q, u.host, defSecurity: 'tls'),
      },
    );
  }

  static VpnServer _vmess(String link) {
    final raw = _b64(link.substring('vmess://'.length).split('#').first);
    if (raw == null) throw 'не base64';
    final j = jsonDecode(raw) as Map<String, dynamic>;
    String v(String k) => '${j[k] ?? ''}';
    final host = v('add');
    final q = <String, String>{
      'type': v('net').isEmpty ? 'tcp' : v('net'),
      'security': v('tls').isEmpty ? 'none' : v('tls'),
      if (v('sni').isNotEmpty) 'sni': v('sni'),
      if (v('host').isNotEmpty) 'host': v('host'),
      if (v('path').isNotEmpty) 'path': v('path'),
      if (v('alpn').isNotEmpty) 'alpn': v('alpn'),
      if (v('fp').isNotEmpty) 'fp': v('fp'),
      if (v('type').isNotEmpty) 'headerType': v('type'),
      if (v('net') == 'grpc' && v('path').isNotEmpty) 'serviceName': v('path'),
    };
    return VpnServer(
      link: link,
      name: v('ps').isEmpty ? '$host:${v('port')}' : v('ps'),
      outbound: {
        'protocol': 'vmess',
        'settings': {
          'vnext': [
            {
              'address': host,
              'port': int.tryParse(v('port')) ?? 443,
              'users': [
                {'id': v('id'), 'security': v('scy').isEmpty ? 'auto' : v('scy')},
              ],
            },
          ],
        },
        'streamSettings': _stream(q, host),
      },
    );
  }

  static VpnServer _ss(String link) {
    var body = link.substring('ss://'.length);
    var name = '';
    final hash = body.indexOf('#');
    if (hash >= 0) {
      name = Uri.decodeComponent(body.substring(hash + 1));
      body = body.substring(0, hash);
    }
    body = body.split('?').first.split('/?').first;
    String method, password, host;
    int port;
    if (body.contains('@')) {
      // SIP002: base64(method:password)@host:port
      final at = body.lastIndexOf('@');
      var cred = Uri.decodeComponent(body.substring(0, at));
      if (!cred.contains(':')) cred = _b64(cred) ?? cred;
      final hp = body.substring(at + 1);
      final i = cred.indexOf(':');
      method = cred.substring(0, i);
      password = cred.substring(i + 1);
      final c = hp.lastIndexOf(':');
      host = hp.substring(0, c).replaceAll('[', '').replaceAll(']', '');
      port = int.parse(hp.substring(c + 1).replaceAll('/', ''));
    } else {
      // Старый вид: base64(method:password@host:port)
      final d = _b64(body) ?? body;
      final at = d.lastIndexOf('@');
      final cred = d.substring(0, at);
      final hp = d.substring(at + 1);
      final i = cred.indexOf(':');
      method = cred.substring(0, i);
      password = cred.substring(i + 1);
      final c = hp.lastIndexOf(':');
      host = hp.substring(0, c);
      port = int.parse(hp.substring(c + 1));
    }
    return VpnServer(
      link: link,
      name: name.isEmpty ? '$host:$port' : name,
      outbound: {
        'protocol': 'shadowsocks',
        'settings': {
          'servers': [
            {'address': host, 'port': port, 'method': method, 'password': password},
          ],
        },
      },
    );
  }

  // ---------- запуск ядра ----------

  static Future<String?> _findCore() async {
    if (_exe != null && File(_exe!).existsSync()) return _exe;
    final candidates = <String>[];
    if (Platform.isAndroid) {
      // Ядро лежит рядом с libflutter.so (папка нативных библиотек приложения).
      try {
        final maps = await File('/proc/self/maps').readAsLines();
        for (final l in maps) {
          final i = l.indexOf('/');
          if (i < 0 || !l.endsWith('libflutter.so')) continue;
          final p = l.substring(i);
          candidates.add('${File(p).parent.path}/libxray.so');
          break;
        }
      } catch (_) {}
    } else {
      final dir = File(Platform.resolvedExecutable).parent.path;
      final sep = Platform.pathSeparator;
      if (Platform.isWindows) {
        candidates.addAll(['$dir${sep}hutred-xray.exe', '$dir${sep}xray.exe']);
      } else {
        candidates.addAll(['$dir${sep}hutred-xray', '$dir${sep}xray', '/usr/local/bin/xray', '/usr/bin/xray']);
      }
    }
    for (final c in candidates) {
      if (File(c).existsSync()) return _exe = c;
    }
    if (Platform.isWindows) return _download();
    return null;
  }

  static const _coreVersion = 'v26.9.30';

  /// На Windows ядро не входит в установщик — скачиваем его один раз
  /// из нашего хранилища (там же лежат обновления Hutred).
  static Future<String?> _download() async {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}\\hutred-xray-$_coreVersion.exe');
    if (f.existsSync() && f.lengthSync() > 1000000) return _exe = f.path;
    if (HutredConfig.supabaseUrl.isEmpty) return null;
    message.value = 'Скачиваю ядро VPN (≈30 МБ, один раз)…';
    final tmp = File('${f.path}.part');
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await c.getUrl(Uri.parse('${HutredConfig.supabaseUrl}'
          '/storage/v1/object/public/releases/tools/hutred-xray-$_coreVersion.exe'));
      final res = await req.close();
      if (res.statusCode != 200) throw 'код ${res.statusCode}';
      await res.pipe(tmp.openWrite());
      if (tmp.lengthSync() < 1000000) throw 'файл повреждён';
      await tmp.rename(f.path);
      return _exe = f.path;
    } catch (e) {
      debugPrint('[VPN] не скачал ядро: $e');
      _log('Не скачал ядро: $e');
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      return null;
    } finally {
      c.close(force: true);
    }
  }

  static Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  /// Готовый конфиг Xray для одного сервера (для проверок).
  static Map<String, dynamic> configFor(VpnServer s, int port) => _config([(port, s.outbound)]);

  static Map<String, dynamic> _config(List<(int, Map<String, dynamic>)> pairs) => {
        'log': {'loglevel': 'warning'},
        'inbounds': [
          for (final (i, (p, _)) in pairs.indexed)
            {
              'tag': 'in$i',
              'listen': '127.0.0.1',
              'port': p,
              'protocol': 'http',
              'settings': {'allowTransparent': false},
            },
        ],
        'outbounds': [
          for (final (i, (_, o)) in pairs.indexed) {...o, 'tag': 'out$i'},
        ],
        'routing': {
          'rules': [
            for (var i = 0; i < pairs.length; i++)
              {
                'type': 'field',
                'inboundTag': ['in$i'],
                'outboundTag': 'out$i',
              },
          ],
        },
      };

  static Future<Process> _launch(Map<String, dynamic> config, String name) async {
    final exe = await _findCore();
    if (exe == null) throw Platform.isWindows ? 'не удалось скачать ядро VPN — проверь интернет и попробуй ещё раз' : 'ядро VPN не найдено — обнови Hutred';
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}$name.json');
    await f.writeAsString(jsonEncode(config));
    final p = await Process.start(
      exe,
      ['run', '-c', f.path],
      workingDirectory: dir.path,
      environment: {'XRAY_LOCATION_ASSET': dir.path},
    );
    final err = StringBuffer();
    p.stdout.transform(utf8.decoder).listen((l) {
      debugPrint('[VPN] $l'.trim());
      _log(l);
      if (l.contains('Failed') || l.contains('failed to')) err.write(l);
    });
    p.stderr.transform(utf8.decoder).listen((l) {
      debugPrint('[VPN] $l'.trim());
      _log(l);
      err.write(l);
    });
    // Даём ядру подняться; если оно сразу упало — показываем почему.
    final code = await p.exitCode.timeout(const Duration(milliseconds: 900), onTimeout: () => -999);
    if (code != -999) {
      final text = err.toString().trim().split('\n').where((l) => l.isNotEmpty).toList();
      throw 'ядро VPN не запустилось${text.isEmpty ? ' (код $code)' : ': ${text.last}'}';
    }
    return p;
  }

  /// Журнал ядра и проверок — чтобы было видно, почему не подключилось.
  static final journal = <String>[];
  static void _log(String text) {
    for (final l in text.split('\n')) {
      final t = l.trim();
      if (t.isEmpty) continue;
      journal.add(t);
    }
    if (journal.length > 80) journal.removeRange(0, journal.length - 80);
  }

  /// Задержка через локальный прокси на [p], мс (null — сервер не отвечает).
  static Future<int?> _ping(int p) async {
    for (final url in const [
      'https://www.gstatic.com/generate_204',
      'https://cp.cloudflare.com/generate_204',
    ]) {
      final c = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12)
        ..findProxy = ((_) => 'PROXY 127.0.0.1:$p');
      try {
        final sw = Stopwatch()..start();
        final req = await c.getUrl(Uri.parse(url));
        final res = await req.close().timeout(const Duration(seconds: 15));
        await res.drain<void>();
        if (res.statusCode < 400) return sw.elapsedMilliseconds;
        _log('Проверка $url: код ${res.statusCode}');
      } catch (e) {
        _log('Проверка $url: $e');
      } finally {
        c.close(force: true);
      }
    }
    return null;
  }

  /// Включает VPN через сервер [s].
  static Future<void> start(VpnServer s) async {
    final gen = ++_gen;
    await stop(keepStatus: true);
    status.value = 'starting';
    message.value = 'Подключаюсь к «${s.name}»…';
    _log('— Подключение к «${s.name}» (${s.protocol}), ${Platform.operatingSystem}');
    try {
      await _killStale();
      final p = await _freePort();
      final proc = await _launch(_config([(p, s.outbound)]), 'vpn');
      if (gen != _gen) {
        proc.kill();
        return;
      }
      _proc = proc;
      _lastPort = p;
      unawaited(proc.exitCode.then((code) {
        if (_proc == proc) {
          _proc = null;
          port = null;
          status.value = 'error';
          message.value = 'Ядро VPN остановилось (код $code)';
        }
      }));
      var ms = await _ping(p);
      ms ??= await _ping(p);
      if (gen != _gen) return;
      if (ms == null) {
        // Сервер не отвечает — трафик пускаем напрямую, чтобы музыка не встала.
        _log('Сервер не ответил через ядро ($_exe)');
        port = null;
        status.value = 'error';
        message.value = '«${s.name}» не отвечает. Музыка пока идёт без VPN';
        _retryLater(s, gen);
        return;
      }
      port = p;
      status.value = 'on';
      message.value = '«${s.name}» · $ms мс';
    } catch (e) {
      if (gen != _gen) return;
      port = null;
      status.value = 'error';
      message.value = '$e';
      _log('Ошибка: $e');
    }
  }

  /// Сервер мог «проснуться» — пробуем ещё раз через минуту.
  static void _retryLater(VpnServer s, int gen) {
    Timer(const Duration(minutes: 1), () async {
      if (gen != _gen || _proc == null) return;
      final p = _lastPort;
      if (p == null) return;
      final ms = await _ping(p);
      if (gen != _gen) return;
      if (ms != null) {
        port = p;
        status.value = 'on';
        message.value = '«${s.name}» · $ms мс';
      } else {
        _retryLater(s, gen);
      }
    });
  }

  static int? _lastPort;

  static Future<void> stop({bool keepStatus = false}) async {
    if (!keepStatus) _gen++;
    port = null;
    final p = _proc;
    _proc = null;
    p?.kill();
    if (!keepStatus) {
      status.value = 'off';
      message.value = null;
    }
  }

  /// После вылета приложения ядро могло остаться висеть.
  static bool _staleKilled = false;
  static Future<void> _killStale() async {
    if (_staleKilled || !Platform.isWindows) return;
    _staleKilled = true;
    try {
      for (final n in ['hutred-xray.exe', 'hutred-xray-$_coreVersion.exe']) {
        await Process.run('taskkill', ['/IM', n, '/F']).timeout(const Duration(seconds: 5));
      }
    } catch (_) {}
  }

  /// Проверяет все серверы сразу (одно ядро, у каждого сервера свой порт).
  static Future<List<int?>> pingAll(List<VpnServer> servers) async {
    if (servers.isEmpty) return const [];
    final ports = <int>[for (final _ in servers) await _freePort()];
    Process? proc;
    try {
      proc = await _launch(
        _config([for (final (i, s) in servers.indexed) (ports[i], s.outbound)]),
        'vpn-test',
      );
      return await Future.wait([for (final p in ports) _ping(p)]);
    } catch (e) {
      debugPrint('[VPN] проверка: $e');
      return List.filled(servers.length, null);
    } finally {
      proc?.kill();
    }
  }
}
