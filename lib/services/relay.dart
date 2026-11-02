import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Сервер-посредник Hutred (свой сервер, например на Oracle Cloud).
/// Через него ходят те, у кого YouTube, SoundCloud или Spotify заблокированы:
/// приложение просит сервер скачать трек, и тот отдаёт его потоком.
/// Пускает только вошедших в Hutred и только к музыкальным сервисам.
class HutredRelay {
  HutredRelay._();

  /// Адрес сервера (раздаёт админ через общие настройки), например
  /// https://1-2-3-4.sslip.io. null — посредника нет.
  static String? url;

  /// Токен входа в Hutred — по нему сервер понимает, что это свой.
  static String? Function() token = () => null;

  /// auto — только если напрямую не пускает; always — всегда; off — никогда.
  static String Function() mode = () => 'auto';

  static bool get available {
    final u = url;
    return u != null && u.isNotEmpty && mode() != 'off' && token() != null;
  }

  /// Группы сайтов, которые переключаются вместе: ссылки на звук YouTube
  /// привязаны к адресу, с которого их получили.
  static String _group(String host) {
    final h = host.toLowerCase();
    bool any(List<String> ds) => ds.any((d) => h == d || h.endsWith('.$d'));
    if (any(['youtube.com', 'youtu.be', 'googlevideo.com', 'ytimg.com', 'googleapis.com'])) {
      return 'youtube';
    }
    if (any(['soundcloud.com', 'sndcdn.com', 'soundcloud.cloud'])) return 'soundcloud';
    if (any(['spotify.com', 'scdn.co', 'spotifycdn.com'])) return 'spotify';
    return h;
  }

  static bool _relayable(String host) {
    final g = _group(host);
    return g == 'youtube' || g == 'soundcloud' || g == 'spotify';
  }

  /// Сайты, которые в этот запуск уже не открылись напрямую.
  static final Set<String> _blocked = {};

  /// Сколько запросов прошло через посредника (для настроек).
  static int used = 0;

  static bool via(Uri u) =>
      available && _relayable(u.host) && (mode() == 'always' || _blocked.contains(_group(u.host)));

  static void markBlocked(Uri u) {
    if (_blocked.add(_group(u.host))) {
      debugPrint('[Посредник] ${u.host} напрямую не открывается — дальше через сервер');
    }
  }

  static Uri wrap(Uri target) =>
      Uri.parse('${url!.replaceAll(RegExp(r'/+$'), '')}/r')
          .replace(queryParameters: {'u': target.toString()});

  static Map<String, String> headers(Map<String, String> original) {
    final out = Map<String, String>.of(original);
    final auth = out.remove('Authorization') ?? out.remove('authorization');
    if (auth != null) out['x-spotify-auth'] = auth;
    out['apikey'] = HutredConfig.supabaseAnonKey;
    final t = token();
    if (t != null) out['x-hutred-user'] = t;
    return out;
  }

  /// Проверка сервера: работает ли и сколько через него прошло.
  static Future<Map<String, dynamic>?> health() async {
    final u = url;
    if (u == null || u.isEmpty) return null;
    try {
      final r = await http
          .get(Uri.parse('${u.replaceAll(RegExp(r'/+$'), '')}/health'))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      return {'ok': true, 'body': r.body};
    } catch (_) {
      return null;
    }
  }
}

/// HTTP-клиент, который сам уходит через посредника, если сайт заблокирован.
class RelayClient extends http.BaseClient {
  RelayClient([http.Client? inner]) : _inner = inner ?? http.Client();
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final u = request.url;
    if (HutredRelay.via(u)) return _sendViaRelay(request);
    if (!HutredRelay.available || !HutredRelay._relayable(u.host)) {
      return _inner.send(request);
    }
    // Авто: пробуем напрямую; не открылось — через посредника.
    final copy = _copyable(request);
    try {
      final r = await _inner.send(request).timeout(const Duration(seconds: 12));
      if (r.statusCode == 451) {
        HutredRelay.markBlocked(u);
        if (copy != null) return _sendViaRelay(copy);
      }
      return r;
    } on Object catch (e) {
      final network = e is SocketException ||
          e is HandshakeException ||
          e is TimeoutException ||
          e is http.ClientException ||
          e is HttpException;
      if (!network || copy == null) rethrow;
      HutredRelay.markBlocked(u);
      return _sendViaRelay(copy);
    }
  }

  /// Запрос, который можно отправить ещё раз (без потокового тела).
  http.Request? _copyable(http.BaseRequest r) {
    if (r is http.Request) {
      return http.Request(r.method, r.url)
        ..headers.addAll(r.headers)
        ..bodyBytes = r.bodyBytes
        ..followRedirects = r.followRedirects;
    }
    if (r.contentLength == 0 || r.method == 'GET' || r.method == 'HEAD') {
      return http.Request(r.method, r.url)..headers.addAll(r.headers);
    }
    return null;
  }

  Future<http.StreamedResponse> _sendViaRelay(http.BaseRequest r) {
    final copy = _copyable(r) ?? http.Request(r.method, r.url);
    final out = http.Request(copy.method, HutredRelay.wrap(r.url))
      ..headers.addAll(HutredRelay.headers(copy.headers))
      ..bodyBytes = copy.bodyBytes;
    HutredRelay.used++;
    return _inner.send(out);
  }

  @override
  void close() => _inner.close();
}
