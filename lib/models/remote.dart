import 'track.dart';

/// Страница результатов с возможностью догрузить следующую.
class Paged<T> {
  const Paged(this.items, [this.next]);
  final List<T> items;

  /// null — больше ничего нет.
  final Future<Paged<T>?> Function()? next;
}

/// Плейлист или альбом на YouTube / SoundCloud (ещё не в медиатеке).
class RemotePlaylist {
  const RemotePlaylist({
    required this.source,
    required this.url,
    required this.title,
    required this.owner,
    this.count,
    this.artworkUrl,
  });

  final TrackSource source;

  /// Ссылка, по которой загружаются треки.
  final String url;
  final String title;
  final String owner;
  final int? count;
  final String? artworkUrl;
}
