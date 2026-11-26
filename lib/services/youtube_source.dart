import 'dart:typed_data';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'relay.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/solvers.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/remote.dart';
import '../models/track.dart';
import 'yt_dlp.dart';

/// Поиск и потоковое воспроизведение с YouTube / YouTube Music.
class YoutubeSource {
  YoutubeSource({this.cookiesBrowser});

  // Через посредника Hutred, если YouTube напрямую не открывается.
  final YoutubeHttpClient _ytHttp = YoutubeHttpClient(RelayClient());
  late final YoutubeExplode _yt = YoutubeExplode(httpClient: _ytHttp);

  /// Браузер, из которого yt-dlp берёт вход в YouTube (для видео 18+).
  /// Пустая строка — без входа.
  final String Function()? cookiesBrowser;

  static final _ytUrl = RegExp(
      r'(youtube\.com|youtu\.be|music\.youtube\.com)',
      caseSensitive: false);

  static bool isYoutubeUrl(String s) => _ytUrl.hasMatch(s);

  /// Ссылка на плейлист без конкретного видео.
  static bool isPlaylistUrl(String s) =>
      s.contains('list=') && !s.contains('v=') && !s.contains('youtu.be/');

  Future<List<Track>> search(String query) async =>
      (await searchPaged(query)).items.take(25).toList();

  /// Поиск с подгрузкой следующих страниц. Сначала свой запрос к YouTube
  /// (он не ломается от изменений вёрстки), при ошибке — через библиотеку.
  Future<Paged<Track>> searchPaged(String query) async {
    try {
      final page = await _innertubeSearch(query);
      if (page.items.isNotEmpty) return page;
    } catch (e) {
      debugPrint('[YouTube поиск] $e');
    }
    return _wrap(await _yt.search.search(query));
  }

  final http.Client _http = RelayClient();

  /// Поиск видео через внутренний API YouTube (тот же, что у сайта).
  Future<Paged<Track>> _innertubeSearch(String query, {String? continuation}) async {
    final body = <String, dynamic>{
      'context': {
        'client': {
          'clientName': 'WEB',
          'clientVersion': '2.20251101.00.00',
          'hl': 'ru',
          'gl': 'RU',
        }
      },
      if (continuation == null) 'query': query,
      // Фильтр «только видео».
      if (continuation == null) 'params': 'EgIQAQ%3D%3D',
      if (continuation != null) 'continuation': continuation,
    };
    final res = await _http
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/search?prettyPrint=false'),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('YouTube ответил ${res.statusCode}');
    final j = jsonDecode(utf8.decode(res.bodyBytes));

    final tracks = <Track>[];
    String? next;
    void walk(dynamic o) {
      if (o is List) {
        for (final x in o) {
          walk(x);
        }
      } else if (o is Map) {
        final v = o['videoRenderer'];
        if (v is Map) {
          final t = _fromRenderer(v);
          if (t != null) tracks.add(t);
          return;
        }
        final c = o['continuationItemRenderer'];
        if (c is Map) {
          final token = c['continuationEndpoint']?['continuationCommand']?['token'];
          if (token is String) next = token;
          return;
        }
        for (final x in o.values) {
          walk(x);
        }
      }
    }

    walk(j);
    final token = next;
    return Paged(
      tracks,
      token == null || tracks.isEmpty
          ? null
          : () async => _innertubeSearch(query, continuation: token),
    );
  }

  static String _text(dynamic t) {
    if (t is! Map) return '';
    if (t['simpleText'] is String) return t['simpleText'] as String;
    final runs = t['runs'];
    if (runs is List) return runs.map((r) => r is Map ? '${r['text'] ?? ''}' : '').join();
    return '';
  }

  Track? _fromRenderer(Map v) {
    final id = v['videoId'];
    if (id is! String) return null;
    final title = _text(v['title']);
    if (title.isEmpty) return null;
    final author = _text(v['longBylineText']).isNotEmpty
        ? _text(v['longBylineText'])
        : _text(v['ownerText']);
    // «3:04» или «1:02:03» → миллисекунды; у трансляций длительности нет.
    int? ms;
    final len = _text(v['lengthText']);
    if (len.isNotEmpty) {
      var sec = 0;
      for (final p in len.split(':')) {
        sec = sec * 60 + (int.tryParse(p.trim()) ?? 0);
      }
      ms = sec * 1000;
    }
    final parsed = splitTitle(title, author);
    return Track(
      id: Track.newId(),
      title: parsed.title,
      artist: parsed.artist,
      source: TrackSource.youtube,
      uri: id,
      durationMs: ms,
      artworkUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      addedAt: DateTime.now(),
    );
  }

  Paged<Track> _wrap(VideoSearchList list) => Paged(
        list.map(_toTrack).toList(),
        () async {
          final next = await list.nextPage();
          return next == null || next.isEmpty ? null : _wrap(next);
        },
      );

  Future<List<RemotePlaylist>> searchPlaylists(String query) async {
    final res =
        await _yt.search.searchContent(query, filter: TypeFilters.playlist);
    return res.whereType<SearchPlaylist>().map((p) {
      return RemotePlaylist(
        source: TrackSource.youtube,
        url: 'https://www.youtube.com/playlist?list=${p.id.value}',
        title: p.title,
        owner: 'YouTube',
        count: p.videoCount,
        artworkUrl:
            p.thumbnails.isEmpty ? null : p.thumbnails.last.url.toString(),
      );
    }).toList();
  }

  Future<Track> fromVideoUrl(String url) async {
    final video = await _yt.videos.get(VideoId(url));
    return _toTrack(video);
  }

  Future<List<Track>> fromPlaylistUrl(String url, {int limit = 300}) async {
    final videos =
        await _yt.playlists.getVideos(PlaylistId(url)).take(limit).toList();
    return videos.map(_toTrack).toList();
  }

  final Map<String, Future<File>> _downloads = {};

  static Future<Directory> cacheDir() async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}youtube_audio');
    await dir.create(recursive: true);
    return dir;
  }

  /// Скачивает звук видео в кэш и возвращает файл.
  /// Плеер не может открыть ссылку YouTube напрямую (YouTube проверяет,
  /// кто скачивает), поэтому качаем через библиотеку, а играем из файла.
  /// Повторное воспроизведение берётся из кэша мгновенно и работает без сети.
  Future<File> cachedAudio(String videoId) {
    return _downloads.putIfAbsent(videoId, () async {
      try {
        return await _download(videoId);
      } finally {
        // Ошибку не запоминаем, чтобы можно было попробовать ещё раз.
        _downloads.remove(videoId);
      }
    });
  }

  final Map<String, LiveDownload> _live = {};

  /// Источник для плеера: готовый файл из кэша или «растущий» файл,
  /// который играет, пока докачивается (YouTube отдаёт звук медленно).
  Future<AudioSource> playableSource(String videoId) async {
    final elapsed = Stopwatch()..start();
    final dir = await cacheDir();
    final cached = await YtDlp.findCached(dir, videoId);
    if (cached != null) {
      debugPrint('[Playback] youtube cache ready after ${elapsed.elapsedMilliseconds} ms');
      return AudioSource.file(cached.path);
    }

    final done = cachedAudio(videoId);
    var finished = false;
    var firstBytesLogged = false;
    Object? error;
    File? result;
    done.then((f) {
      finished = true;
      result = f;
    }, onError: (Object e) {
      finished = true;
      error = e;
    });

    while (true) {
      if (finished) {
        if (error != null) throw error!;
        debugPrint('[Playback] youtube file ready after ${elapsed.elapsedMilliseconds} ms');
        return AudioSource.file(result!.path);
      }
      final live = _live[videoId];
      if (live != null) {
        final bytes = await live.downloaded();
        if (bytes > 0 && !firstBytesLogged) {
          firstBytesLogged = true;
          debugPrint('[Playback] youtube first bytes after '
              '${elapsed.elapsedMilliseconds} ms');
        }
        // Ждём первые ~256 КБ, этого хватает плееру на старт.
        if (bytes >= 256 * 1024) {
          debugPrint('[Playback] youtube initial buffer ready after '
              '${elapsed.elapsedMilliseconds} ms');
          return GrowingFileAudioSource(live);
        }
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  Future<File> _download(String videoId) async {
    final dir = await cacheDir();
    String pathFor(String ext) =>
        '${dir.path}${Platform.pathSeparator}$videoId.$ext';
    final cached = await YtDlp.findCached(dir, videoId);
    if (cached != null) return cached;

    Object? lastError;
    // Разные «клиенты» YouTube по-разному отдают видео: пробуем по очереди,
    // пока какой-нибудь не отдаст звук.
    if (isUnavailable(videoId)) {
      throw Exception('YouTube не отдал звук этого видео');
    }
    // Библиотека уже подводила, а yt-dlp справился — сразу идём к нему,
    // не тратя по полминуты на заведомо сломанные способы.
    if (_preferYtDlp) {
      final fast = await _viaYtDlpStream(videoId, pathFor);
      if (fast != null) return fast;
      final quick = await YtDlp.download(
          'https://www.youtube.com/watch?v=$videoId', dir, videoId,
          cookiesBrowser: cookiesBrowser?.call() ?? '');
      if (quick != null) return quick;
    }
    // Спрашиваем всех «клиентов» YouTube сразу и берём первый ответ —
    // раньше перебирали по очереди, и на неудачных уходило до минуты.
    Object? manifestError;
    final got = await _firstManifest(videoId, onFailure: (e) => manifestError = e);
    if (got != null) {
      try {
        final file = await _saveBest(videoId, got.$1, _yt, pathFor);
        _goodClient = got.$2;
        return file;
      } catch (e) {
        lastError = e;
        debugPrint('[YouTube] $videoId: $e');
      }
    } else {
      lastError = manifestError;
    }
    // Последняя попытка: решатель JS-проверок YouTube через Deno (только ПК,
    // если Deno установлен: https://deno.com).
    final solverYt = await _solverClient();
    if (solverYt != null) {
      try {
        final manifest = await solverYt.videos.streams.getManifest(videoId);
        return await _saveBest(videoId, manifest, solverYt, pathFor);
      } catch (e) {
        lastError = e;
        debugPrint('[YouTube] $videoId, Deno: $e');
      }
    }
    // На ПК — yt-dlp. Сначала просим у него только ссылку и качаем сами
    // кусками: играть начинает сразу, а не после загрузки всего файла.
    final streamed = await _viaYtDlpStream(videoId, pathFor);
    if (streamed != null) {
      _preferYtDlp = true;
      return streamed;
    }
    // Самый надёжный вариант на ПК: yt-dlp, если он установлен.
    final viaYtDlp = _preferYtDlp
        ? null
        : await YtDlp.download('https://www.youtube.com/watch?v=$videoId', dir, videoId,
            cookiesBrowser: cookiesBrowser?.call() ?? '');
    if (viaYtDlp != null) {
      _preferYtDlp = true;
      return viaYtDlp;
    }
    // Сетевой сбой и обрыв скачивания не делают видео недоступным.
    if (manifestError is VideoUnavailableException && lastError is VideoUnavailableException) {
      _deadVideos[videoId] = DateTime.now().add(const Duration(minutes: 1));
    }
    final why = YtDlp.lastError;
    throw Exception('YouTube не отдал звук'
        '${why == null ? '' : ' (yt-dlp: ${why.length > 160 ? '${why.substring(0, 160)}…' : why})'}'
        '${lastError == null ? '' : '. Библиотека: ${'$lastError'.split('\n').first}'}');
  }

  YoutubeApiClient? _goodClient;

  /// Первый успешный ответ от любого клиента (тот, что сработал в прошлый
  /// раз, получает полсекунды форы — обычно он и сейчас самый быстрый).
  Future<(StreamManifest, YoutubeApiClient)?> _firstManifest(
    String videoId, {
    bool Function(StreamManifest)? accept,
    void Function(Object)? onFailure,
  }) async {
    final done = Completer<(StreamManifest, YoutubeApiClient)?>();
    var left = _clients.length;
    Object? failure;
    for (final client in _clients) {
      () async {
        try {
          if (_goodClient != null && client != _goodClient) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            if (done.isCompleted) return;
          }
          final m = await _yt.videos.streams
              .getManifest(videoId, ytClients: [client])
              .timeout(const Duration(seconds: 12));
          if (m.audioOnly.isEmpty) throw Exception('нет аудио');
          if (!done.isCompleted && (accept == null || accept(m))) {
            done.complete((m, client));
          }
        } catch (e) {
          // При смешанных ответах считаем сбой временным.
          if (failure == null || failure is VideoUnavailableException) failure = e;
        } finally {
          left--;
          if (left == 0 && !done.isCompleted) {
            final error = failure;
            if (error != null) onFailure?.call(error);
            done.complete(null);
          }
        }
      }();
    }
    return done.future;
  }

  /// Библиотека не справилась, а yt-dlp — да: до перезапуска качаем через него.
  bool _preferYtDlp = false;
  final Map<String, DateTime> _deadVideos = {};

  /// Недавно все запросы к манифесту вернули, что видео недоступно.
  bool isUnavailable(String videoId) {
    final until = _deadVideos[videoId];
    if (until == null) return false;
    if (until.isAfter(DateTime.now())) return true;
    _deadVideos.remove(videoId);
    return false;
  }

  static final _clients = [
    YoutubeApiClient.androidVr,
    YoutubeApiClient.ios,
    YoutubeApiClient.androidSdkless,
    YoutubeApiClient.androidMusic,
    YoutubeApiClient.tv,
    YoutubeApiClient.mweb,
  ];

  Future<YoutubeExplode?>? _solverFuture;

  Future<YoutubeExplode?> _solverClient() {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return Future.value(null);
    }
    return _solverFuture ??= () async {
      try {
        final solver = await DenoEJSSolver.init();
        return YoutubeExplode(httpClient: YoutubeHttpClient(RelayClient()), jsSolver: solver);
      } catch (_) {
        return null; // Deno не установлен.
      }
    }();
  }

  Future<File> _saveBest(String videoId, StreamManifest manifest,
      YoutubeExplode yt, String Function(String ext) pathFor) async {
    final audio = manifest.audioOnly;
    if (audio.isEmpty) throw Exception('У видео нет аудиопотока');
    // m4a воспроизводится на всех платформах, включая iOS и macOS.
    final mp4 = audio.where((s) => s.container == StreamContainer.mp4);
    final pool = (mp4.isNotEmpty ? mp4 : audio).toList()
      ..sort((a, b) => a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond));
    // Качество из настроек: лучшее, обычное (~128 кбит/с) или экономия.
    final info = switch (quality) {
      'saver' => pool.first,
      'normal' => pool.lastWhere((s) => s.bitrate.bitsPerSecond <= 140000,
          orElse: () => pool.first),
      _ => pool.last,
    };
    // iOS и macOS определяют формат по расширению файла.
    final file = File(
        pathFor(info.container == StreamContainer.mp4 ? 'm4a' : 'webm'));

    return _writeLive(videoId, file, info.size.totalBytes,
        info.container == StreamContainer.mp4 ? 'audio/mp4' : 'audio/webm',
        (sink) async {
      // Качаем файл в 4 потока кусками по 512 КБ (замедление YouTube
      // у провайдера действует на каждое соединение отдельно), а пишем
      // по порядку — плеер начинает играть с первого куска.
      final url = info.url.toString();
      if (info.fragments.isEmpty &&
          info.size.totalBytes > 0 &&
          !url.contains('hls_playlist') &&
          !url.contains('.m3u8')) {
        final pos = _Written();
        var src = info.url;
        for (var attempt = 0;; attempt++) {
          try {
            await _parallelGet(src, info.size.totalBytes, sink, pos);
            break;
          } catch (e) {
            debugPrint('[YouTube] загрузка прервалась на ${pos.bytes} байтах '
                '(${e.runtimeType})');
            // Ссылка протухла или YouTube оборвал соединение: берём свежую
            // ссылку на тот же поток и докачиваем с того же места — файл,
            // который уже играет, не трогаем.
            if (attempt >= 3) {
              throw Exception('YouTube оборвал загрузку трека, попробуй ещё раз');
            }
            await Future<void>.delayed(Duration(seconds: 1 + attempt));
            final fresh = await _freshUrl(videoId, info);
            if (fresh != null) {
              src = fresh;
            } else if (e is _RejectedRange) {
              rethrow;
            }
          }
        }
      } else {
        await for (final chunk in yt.videos.streams.get(info)) {
          sink.add(chunk);
          await sink.flush();
        }
      }
    });
  }

  Future<File?> _viaYtDlpStream(String videoId, String Function(String ext) pathFor) async {
    final info = await YtDlp.streamInfo('https://www.youtube.com/watch?v=$videoId',
        cookiesBrowser: cookiesBrowser?.call() ?? '');
    if (info == null || info.size <= 0) return null;
    final ext = info.ext == 'm4a' || info.ext == 'mp4' ? 'm4a' : info.ext;
    final file = File(pathFor(ext));
    try {
      return await _writeLive(videoId, file, info.size,
          ext == 'm4a' ? 'audio/mp4' : (ext == 'mp3' ? 'audio/mpeg' : 'audio/webm'),
          (sink) => _parallelGet(info.url, info.size, sink, _Written(), headers: info.headers));
    } catch (e) {
      debugPrint('[YouTube] yt-dlp-ссылка $videoId: $e');
      return null;
    }
  }

  int _downloadAttempt = 0;

  Future<File> _writeLive(String videoId, File file, int totalBytes,
      String contentType, Future<void> Function(IOSink) write) async {
    // Повторная попытка не должна перезаписать файл, который ещё открыт.
    final part = File('${file.path}.$pid.${_downloadAttempt++}.part');
    final staging = File('${part.path}.ready.part');
    final live = LiveDownload(file: part, totalBytes: totalBytes, contentType: contentType);
    final sink = part.openWrite();
    sink.done.ignore();
    if (totalBytes > 0 && !Platform.isWindows) _live[videoId] = live;
    try {
      try {
        await write(sink);
      } finally {
        await sink.close();
      }
      if (await part.length() == 0) throw Exception('YouTube отдал пустой файл');
      // Готовое имя становится видно другим запросам только после записи.
      if (Platform.isWindows) {
        await part.rename(file.path);
      } else {
        await part.copy(staging.path);
        await staging.rename(file.path);
      }
      live.finish(file);
      return file;
    } catch (e) {
      live.fail(e);
      rethrow;
    } finally {
      _live.remove(videoId);
      for (final temporary in [part, staging]) {
        try {
          await temporary.delete();
        } on FileSystemException {
          // Файл уже перемещён или ещё открыт читателем.
        }
      }
    }
  }

  /// Свежая ссылка на то же аудио, чтобы продолжить с записанного байта.
  Future<Uri?> _freshUrl(String videoId, AudioOnlyStreamInfo original) async {
    bool sameStream(AudioOnlyStreamInfo stream) =>
        stream.tag == original.tag &&
        stream.container == original.container &&
        stream.size.totalBytes == original.size.totalBytes;

    final found = await _firstManifest(
      videoId,
      accept: (manifest) => manifest.audioOnly.any(sameStream),
    );
    if (found == null) return null;
    return found.$1.audioOnly.firstWhere(sameStream).url;
  }

  /// Загрузка файла в несколько потоков; куски пишутся строго по порядку.
  Future<void> _parallelGet(Uri url, int total, IOSink sink, _Written pos,
      {Map<String, String>? headers}) async {
    const chunk = 512 * 1024;
    const workers = 4;
    final base = pos.bytes;
    final n = (total - base + chunk - 1) ~/ chunk;
    final results = List.generate(n, (_) => Completer<Uint8List>());
    for (final c in results) {
      c.future.ignore();
    }
    var next = 0;
    var failed = false;
    Future<void> worker() async {
      while (!failed) {
        final i = next++;
        if (i >= n) return;
        final from = base + i * chunk;
        final to = min(total, from + chunk) - 1;
        try {
          results[i].complete(await _range(url, from, to, headers: headers));
        } catch (e) {
          failed = true;
          results[i].completeError(e);
          return;
        }
      }
    }

    final running = [for (var w = 0; w < workers; w++) worker()];
    for (final c in results) {
      final bytes = await c.future;
      sink.add(bytes);
      await sink.flush();
      pos.bytes += bytes.length;
    }
    await Future.wait(running);
  }

  Future<Uint8List> _range(Uri url, int from, int to, {Map<String, String>? headers}) async {
    for (var attempt = 0;; attempt++) {
      try {
        final http.Request req;
        if (headers != null) {
          // Ссылка от yt-dlp: его заголовки и обычный Range.
          req = http.Request('GET', url)
            ..headers.addAll(headers)
            ..headers['Range'] = 'bytes=$from-$to';
        } else if (url.queryParameters['c'] == 'ANDROID') {
          req = http.Request('GET', url)..headers['Range'] = 'bytes=$from-$to';
        } else {
          req = http.Request(
              'GET', url.replace(queryParameters: {...url.queryParameters, 'range': '$from-$to'}));
        }
        final res = await _ytHttp.send(req).timeout(const Duration(seconds: 12));
        if (res.statusCode >= 400) {
          res.stream.listen(null).cancel().ignore();
          if (const {401, 403, 404, 410, 416}.contains(res.statusCode)) {
            throw _RejectedRange(res.statusCode);
          }
          throw HttpException('YouTube ответил ${res.statusCode}');
        }
        final bytes = await http.ByteStream(
          res.stream.timeout(const Duration(seconds: 10)),
        ).toBytes();
        if (bytes.length != to - from + 1) {
          throw HttpException('YouTube отдал ${bytes.length} байт вместо ${to - from + 1}');
        }
        return bytes;
      } on _RejectedRange {
        rethrow;
      } catch (e) {
        if (attempt >= 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
  }

  /// Качество звука: best, normal или saver (из настроек).
  static String quality = 'best';

  /// Лимит кэша прослушанного в байтах (0 — без лимита).
  static int cacheLimitBytes = 0;

  /// Удаляет самые старые файлы кэша, пока он больше лимита.
  static Future<void> trimCaches(List<Directory> dirs) async {
    if (cacheLimitBytes <= 0) return;
    final files = <(File, int, DateTime)>[];
    var total = 0;
    for (final d in dirs) {
      try {
        await for (final e in d.list()) {
          if (e is! File || e.path.endsWith('.part')) continue;
          final st = await e.stat();
          files.add((e, st.size, st.modified));
          total += st.size;
        }
      } catch (_) {}
    }
    if (total <= cacheLimitBytes) return;
    files.sort((a, b) => a.$3.compareTo(b.$3));
    for (final (f, size, _) in files) {
      if (total <= cacheLimitBytes) break;
      try {
        await f.delete();
        total -= size;
      } catch (_) {}
    }
  }

  /// Размер кэша в байтах.
  static Future<int> cacheSize() async {
    var total = 0;
    await for (final e in (await cacheDir()).list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  static Future<void> clearCache() async {
    await for (final e in (await cacheDir()).list()) {
      if (e is File) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  }

  /// Ручные субтитры видео в формате LRC (тексты в клипах часто так и залиты).
  /// Автосубтитры не берём: для музыки там обычно «[Музыка]».
  Future<String?> captionsAsLrc(String videoId) async {
    final manifest = await _yt.videos.closedCaptions.getManifest(videoId);
    final manual =
        manifest.tracks.where((t) => !t.isAutoGenerated).toList();
    if (manual.isEmpty) return null;
    final track = await _yt.videos.closedCaptions.get(manual.first);
    final lines = <String>[];
    for (final c in track.captions) {
      final text = c.text
          .replaceAll(RegExp(r'[♪♫🎵🎶]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isEmpty) continue;
      final ms = c.offset.inMilliseconds;
      final m = (ms ~/ 60000).toString().padLeft(2, '0');
      final s = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
      final cs = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
      lines.add('[$m:$s.$cs]$text');
    }
    // Пара строк — это скорее подпись к видео, а не текст песни.
    return lines.length >= 6 ? lines.join('\n') : null;
  }

  /// Синхронный текст из субтитров: у самого видео или у найденных клипов.
  Future<String?> findCaptionLyrics({
    String? videoId,
    required String artist,
    required String title,
    Duration? duration,
  }) async {
    if (videoId != null) {
      final own = await captionsAsLrc(videoId);
      if (own != null) return own;
    }
    final hasArtist = artist.isNotEmpty && artist != Track.unknownArtist;
    final results = await _yt.search.search(hasArtist ? '$artist $title' : title);
    var tried = 0;
    for (final v in results) {
      if (tried >= 3) break;
      if (v.id.value == videoId) continue;
      // Длительность клипа должна совпадать с треком, иначе тайминги поедут.
      if (duration != null && v.duration != null &&
          (v.duration! - duration).inSeconds.abs() > 4) {
        continue;
      }
      tried++;
      try {
        final lrc = await captionsAsLrc(v.id.value);
        if (lrc != null) return lrc;
      } catch (_) {}
    }
    return null;
  }

  Track _toTrack(Video v) {
    final parsed = splitTitle(v.title, v.author);
    return Track(
      id: Track.newId(),
      title: parsed.title,
      artist: parsed.artist,
      source: TrackSource.youtube,
      uri: v.id.value,
      durationMs: v.duration?.inMilliseconds,
      artworkUrl: v.thumbnails.highResUrl,
      addedAt: DateTime.now(),
    );
  }

  static final _junk = RegExp(
    r'\s*[\(\[][^\)\]]*(official|video|audio|lyric|mv|hd|4k|visuali[sz]er|клип|премьера|текст)[^\)\]]*[\)\]]',
    caseSensitive: false,
  );

  /// «Исполнитель - Название (Official Video)» → исполнитель и чистое название.
  static ({String artist, String title}) splitTitle(String raw, String author) {
    var title = raw.replaceAll(_junk, '').trim();
    final pipe = title.indexOf(' | ');
    if (pipe > 0) title = title.substring(0, pipe).trim();
    var artist = author
        .replaceAll(RegExp(r'\s*-\s*Topic$'), '')
        .replaceAll(RegExp(r'VEVO$', caseSensitive: false), '')
        .trim();
    // Разделитель между исполнителем и названием: -, --, –, —, ~
    final sep = RegExp(r'\s+(?:-{1,2}|–|—|~)\s+').firstMatch(title);
    if (sep != null && sep.start > 0) {
      artist = title.substring(0, sep.start).trim();
      title = title.substring(sep.end).trim();
    } else if (artist.isNotEmpty &&
        title.toLowerCase().startsWith('${artist.toLowerCase()} ')) {
      // «Исполнитель Название» без разделителя.
      title = title.substring(artist.length).replaceFirst(RegExp(r'^[\s\-–—~:]+'), '');
    }
    title = title.replaceAll(RegExp(r'^["«“]|["»”]$'), '').trim();
    return (
      artist: artist.isEmpty ? Track.unknownArtist : artist,
      title: title.isEmpty ? raw : title,
    );
  }

  /// Название для поиска текста: без «(prod. …)», «feat. …» и пометок в скобках.
  static String searchTitle(String title) {
    final t = title
        .replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ')
        .replaceAll(RegExp(r'\s+(feat|ft|prod)\.?\s.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t.isEmpty ? title : t;
  }

  void dispose() => _yt.close();
}

/// Сколько байт уже записано (чтобы докачать с места обрыва).
class _Written {
  int bytes = 0;
}

/// Скачивание, которое идёт прямо сейчас.
class LiveDownload {
  LiveDownload({
    required this.file,
    required this.totalBytes,
    required this.contentType,
  });

  final File file;
  final int totalBytes;
  final String contentType;
  bool done = false;
  Object? error;
  File? _completedFile;

  Future<RandomAccessFile> open() async {
    try {
      return await (_completedFile ?? file).open();
    } on FileSystemException {
      // Пока открывали .part, он мог уже смениться готовым файлом.
      final completed = _completedFile;
      if (completed == null) rethrow;
      return completed.open();
    }
  }

  Future<int> downloaded() async {
    try {
      return await file.length();
    } catch (_) {
      return 0;
    }
  }

  void finish(File completedFile) {
    _completedFile = completedFile;
    done = true;
  }

  void fail(Object e) {
    error = e;
    done = true;
  }
}

class _RejectedRange implements Exception {
  const _RejectedRange(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'YouTube отклонил запрос звука ($statusCode)';
}

/// Отдаёт плееру файл, который ещё докачивается: если плеер просит
/// байты, которых пока нет, — ждём их.
// ignore: experimental_member_use
class GrowingFileAudioSource extends StreamAudioSource {
  GrowingFileAudioSource(this.live);

  final LiveDownload live;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final total = live.totalBytes;
    start ??= 0;
    end ??= total;
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: end - start,
      offset: start,
      contentType: live.contentType,
      stream: _read(start, end),
    );
  }

  Stream<List<int>> _read(int start, int end) async* {
    final raf = await live.open();
    try {
      var pos = start;
      await raf.setPosition(pos);
      while (pos < end) {
        final available = await raf.length();
        if (available > pos) {
          final want = (end < available ? end : available) - pos;
          final chunk = await raf.read(want > 65536 ? 65536 : want);
          if (chunk.isEmpty) continue;
          pos += chunk.length;
          yield chunk;
        } else if (live.done) {
          if (live.error != null) throw live.error!;
          break;
        } else {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    } finally {
      await raf.close();
    }
  }
}
