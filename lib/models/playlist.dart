import 'track.dart';

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
    required this.createdAt,
    this.description = '',
    this.cover,
    this.followId,
    this.owner,
    this.followedTracks,
  });

  final String id;
  final String name;
  final List<String> trackIds;
  final DateTime createdAt;

  /// Описание под названием (как в Spotify).
  final String description;

  /// Своя обложка: ссылка в облаке или путь к файлу. null — коллаж из треков.
  final String? cover;

  /// Чужой плейлист, на который подписался: его id в облаке.
  /// Такой плейлист обновляется сам, когда автор его меняет.
  final String? followId;

  /// Кто создал (для чужих плейлистов).
  final String? owner;

  /// Треки чужого плейлиста — хранятся в нём самом, в медиатеку не попадают.
  final List<Track>? followedTracks;

  bool get isFollowed => followId != null;

  Playlist copyWith({
    String? name,
    List<String>? trackIds,
    String? description,
    String? cover,
    bool removeCover = false,
    String? owner,
    List<Track>? followedTracks,
  }) =>
      Playlist(
        id: id,
        name: name ?? this.name,
        trackIds: trackIds ?? this.trackIds,
        createdAt: createdAt,
        description: description ?? this.description,
        cover: removeCover ? null : (cover ?? this.cover),
        followId: followId,
        owner: owner ?? this.owner,
        followedTracks: followedTracks ?? this.followedTracks,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'createdAt': createdAt.toIso8601String(),
        if (description.isNotEmpty) 'description': description,
        if (cover != null) 'cover': cover,
        if (followId != null) 'followId': followId,
        if (owner != null) 'owner': owner,
        if (followedTracks != null)
          'followedTracks': [for (final t in followedTracks!) t.toJson()],
      };

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Плейлист',
        trackIds: List<String>.from(j['trackIds'] as List? ?? const []),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        description: j['description'] as String? ?? '',
        cover: j['cover'] as String?,
        followId: j['followId'] as String?,
        owner: j['owner'] as String?,
        followedTracks: (j['followedTracks'] as List?) == null
            ? null
            : [
                for (final t in j['followedTracks'] as List)
                  if (t is Map) Track.fromJson(Map<String, dynamic>.from(t)),
              ],
      );
}

/// «50 треков, 3 ч 8 мин» — как в Spotify.
String totalDuration(Iterable<Track> tracks) {
  final ms = tracks.fold<int>(0, (s, t) => s + (t.durationMs ?? 0));
  final m = (ms / 60000).round();
  if (m <= 0) return '';
  return m >= 60 ? '${m ~/ 60} ч ${m % 60} мин' : '$m мин';
}
