class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
    required this.createdAt,
    this.description = '',
    this.cover,
  });

  final String id;
  final String name;
  final List<String> trackIds;
  final DateTime createdAt;

  /// Описание под названием (как в Spotify).
  final String description;

  /// Своя обложка: ссылка в облаке или путь к файлу. null — коллаж из треков.
  final String? cover;

  Playlist copyWith({
    String? name,
    List<String>? trackIds,
    String? description,
    String? cover,
    bool removeCover = false,
  }) =>
      Playlist(
        id: id,
        name: name ?? this.name,
        trackIds: trackIds ?? this.trackIds,
        createdAt: createdAt,
        description: description ?? this.description,
        cover: removeCover ? null : (cover ?? this.cover),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'createdAt': createdAt.toIso8601String(),
        if (description.isNotEmpty) 'description': description,
        if (cover != null) 'cover': cover,
      };

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Плейлист',
        trackIds: List<String>.from(j['trackIds'] as List? ?? const []),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        description: j['description'] as String? ?? '',
        cover: j['cover'] as String?,
      );
}
