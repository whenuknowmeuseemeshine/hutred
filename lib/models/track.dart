import 'dart:math';

/// Откуда пришёл трек.
/// spotify — трек из каталога Spotify: сведения оттуда, а звук находим
/// на SoundCloud или YouTube при первом включении.
enum TrackSource { local, url, youtube, soundcloud, spotify }

const _keep = Object();
final _rand = Random();

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    required this.source,
    required this.uri,
    this.durationMs,
    this.artworkUrl,
    this.lyrics,
    this.lyricsSource,
    this.coverChecked = false,
    this.plays = 0,
    this.lyricsOffsetMs = 0,
    this.favorite = false,
    required this.addedAt,
    this.cloudPath,
    this.hiddenFromFriends = false,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final TrackSource source;

  /// Путь к файлу, прямая ссылка или id видео YouTube.
  final String uri;
  final int? durationMs;
  final String? artworkUrl;

  /// Текст песни: LRC с таймингами или обычный текст.
  final String? lyrics;

  /// Откуда текст: LRCLIB, YouTube, Genius или «свой».
  final String? lyricsSource;

  /// Обложку на Genius уже искали (чтобы не искать при каждом запуске).
  final bool coverChecked;

  /// Сколько раз трек включали (для «Моей волны»).
  final int plays;

  /// Сдвиг текста относительно звука (+ — текст раньше, − — позже).
  final int lyricsOffsetMs;
  final bool favorite;
  final DateTime addedAt;

  /// Копия своего файла в облаке (Supabase Storage), если загружена.
  /// Благодаря ей трек играет на телефоне и после удаления файла с ПК.
  final String? cloudPath;

  /// Друзья не видят этот трек в моей медиатеке.
  final bool hiddenFromFriends;

  static const unknownArtist = 'Неизвестный исполнитель';

  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);

  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      _rand.nextInt(1 << 30).toRadixString(36);

  Track copyWith({
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    Object? artworkUrl = _keep,
    Object? lyrics = _keep,
    Object? lyricsSource = _keep,
    bool? coverChecked,
    int? plays,
    int? lyricsOffsetMs,
    bool? favorite,
    Object? cloudPath = _keep,
    bool? hiddenFromFriends,
  }) {
    return Track(
      id: id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      source: source,
      uri: uri,
      durationMs: durationMs ?? this.durationMs,
      artworkUrl:
          identical(artworkUrl, _keep) ? this.artworkUrl : artworkUrl as String?,
      lyrics: identical(lyrics, _keep) ? this.lyrics : lyrics as String?,
      lyricsSource: identical(lyricsSource, _keep)
          ? this.lyricsSource
          : lyricsSource as String?,
      coverChecked: coverChecked ?? this.coverChecked,
      plays: plays ?? this.plays,
      lyricsOffsetMs: lyricsOffsetMs ?? this.lyricsOffsetMs,
      favorite: favorite ?? this.favorite,
      addedAt: addedAt,
      cloudPath: identical(cloudPath, _keep) ? this.cloudPath : cloudPath as String?,
      hiddenFromFriends: hiddenFromFriends ?? this.hiddenFromFriends,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'source': source.name,
        'uri': uri,
        'durationMs': durationMs,
        'artworkUrl': artworkUrl,
        'lyrics': lyrics,
        'lyricsSource': lyricsSource,
        'coverChecked': coverChecked,
        'plays': plays,
        'lyricsOffsetMs': lyricsOffsetMs,
        'favorite': favorite,
        'addedAt': addedAt.toIso8601String(),
        if (cloudPath != null) 'cloudPath': cloudPath,
        if (hiddenFromFriends) 'hiddenFromFriends': true,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Без названия',
        artist: j['artist'] as String? ?? unknownArtist,
        album: j['album'] as String? ?? '',
        source: TrackSource.values.asNameMap()[j['source']] ?? TrackSource.url,
        uri: j['uri'] as String,
        durationMs: (j['durationMs'] as num?)?.toInt(),
        artworkUrl: j['artworkUrl'] as String?,
        lyrics: j['lyrics'] as String?,
        lyricsSource: j['lyricsSource'] as String?,
        coverChecked: j['coverChecked'] as bool? ?? false,
        plays: (j['plays'] as num?)?.toInt() ?? 0,
        lyricsOffsetMs: (j['lyricsOffsetMs'] as num?)?.toInt() ?? 0,
        favorite: j['favorite'] as bool? ?? false,
        addedAt: DateTime.tryParse(j['addedAt'] as String? ?? '') ??
            DateTime.now(),
        cloudPath: j['cloudPath'] as String?,
        hiddenFromFriends: j['hiddenFromFriends'] as bool? ?? false,
      );
}
