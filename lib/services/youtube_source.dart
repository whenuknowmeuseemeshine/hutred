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
  final YoutubeExplode _yt = YoutubeExplode(httpClient: YoutubeHttpClient(RelayClient()));

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
        unawaited(Future(() => _downloads.remove(videoId)));
      }
    });
  }

  final Map<String, LiveDownload> _live = {};

  /// Источник для плеера: готовый файл из кэша или «растущий» файл,
  /// который играет, пока докачивается (YouTube отдаёт звук медленно).
  Future<AudioSource> playableSource(String videoId) async {
    final dir = await cacheDir();
    final cached = await YtDlp.findCached(dir, videoId);
    if (cached != null) return AudioSource.file(cached.path);

    final done = cachedAudio(videoId);
    var finished = false;
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
        return AudioSource.file(result!.path);
      }
      final live = _live[videoId];
      // Ждём первые ~256 КБ, этого хватает плееру на старт.
      if (live != null && await live.downloaded() >= 256 * 1024) {
        return GrowingFileAudioSource(live);
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
    if (_deadVideos.contains(videoId)) {
      throw Exception('YouTube не отдал звук этого видео');
    }
    // Библиотека уже подводила, а yt-dlp справился — сразу идём к нему,
    // не тратя по полминуты на заведомо сломанные способы.
    if (_preferYtDlp) {
      final quick = await YtDlp.download(
          'https://www.youtube.com/watch?v=$videoId', dir, videoId,
          cookiesBrowser: cookiesBrowser?.call() ?? '');
      if (quick != null) return quick;
    }
    // Сначала тот способ, что сработал в прошлый раз: обычно он и сейчас работает.
    final order = [
      if (_goodClient != null) _goodClient!,
      ..._clients.where((c) => c != _goodClient),
    ];
    for (final client in order) {
      try {
        final manifest = await _yt.videos.streams
            .getManifest(videoId, ytClients: [client])
            .timeout(const Duration(seconds: 12));
        final file = await _saveBest(videoId, manifest, _yt, pathFor);
        _goodClient = client;
        return file;
      } catch (e) {
        lastError = e;
        debugPrint('[YouTube] $videoId, клиент '
            '${client.payload['context']['client']['clientName']}: $e');
      }
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
    // Самый надёжный вариант на ПК: yt-dlp, если он установлен.
    final viaYtDlp = _preferYtDlp
        ? null
        : await YtDlp.download('https://www.youtube.com/watch?v=$videoId', dir, videoId,
            cookiesBrowser: cookiesBrowser?.call() ?? '');
    if (viaYtDlp != null) {
      _preferYtDlp = true;
      return viaYtDlp;
    }
    // Не мучаем это видео повторно до перезапуска программы.
    _deadVideos.add(videoId);
    final why = YtDlp.lastError;
    throw Exception('YouTube не отдал звук'
        '${why == null ? '' : ' (yt-dlp: ${why.length > 160 ? '${why.substring(0, 160)}…' : why})'}'
        '${lastError == null ? '' : '. Библиотека: ${'$lastError'.split('\n').first}'}');
  }

  YoutubeApiClient? _goodClient;

  /// Библиотека не справилась, а yt-dlp — да: до перезапуска качаем через него.
  bool _preferYtDlp = false;
  final Set<String> _deadVideos = {};

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
    final info =
        mp4.isNotEmpty ? mp4.withHighestBitrate() : audio.withHighestBitrate();
    // iOS и macOS определяют формат по расширению файла.
    final file = File(
        pathFor(info.container == StreamContainer.mp4 ? 'm4a' : 'webm'));

    final part = File('${file.path}.part');
    final live = LiveDownload(
      file: part,
      totalBytes: info.size.totalBytes,
      contentType: info.container == StreamContainer.mp4 ? 'audio/mp4' : 'audio/webm',
    );
    _live[videoId] = live;
    final sink = part.openWrite();
    try {
      // Пишем кусками и сразу сбрасываем на диск, чтобы плеер мог
      // начать играть, пока остальное докачивается.
      await for (final chunk in yt.videos.streams.get(info)) {
        sink.add(chunk);
        await sink.flush();
      }
    } catch (e) {
      live.fail(e);
      _live.remove(videoId);
      rethrow;
    } finally {
      await sink.close();
    }
    if (await part.length() == 0) {
      live.fail(Exception('YouTube отдал пустой файл'));
      _live.remove(videoId);
      throw Exception('YouTube отдал пустой файл');
    }
    // Не переименовываем: .part может быть открыт плеером (Windows не даст).
    await part.copy(file.path);
    live.finish();
    _live.remove(videoId);
    try {
      await part.delete();
    } catch (_) {
      // Удалим при следующей очистке кэша.
    }
    return file;
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

  Future<int> downloaded() async {
    try {
      return await file.length();
    } catch (_) {
      return 0;
    }
  }

  void finish() => done = true;

  void fail(Object e) {
    error = e;
    done = true;
  }
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
    final raf = await live.file.open();
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
