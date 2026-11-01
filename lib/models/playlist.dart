class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
    required this.createdAt,
  });

  final String id;
  final String name;
  final List<String> trackIds;
  final DateTime createdAt;

  Playlist copyWith({String? name, List<String>? trackIds}) => Playlist(
        id: id,
        name: name ?? this.name,
        trackIds: trackIds ?? this.trackIds,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Плейлист',
        trackIds: List<String>.from(j['trackIds'] as List? ?? const []),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
