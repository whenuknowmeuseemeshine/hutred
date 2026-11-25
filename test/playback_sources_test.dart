import 'package:flutter_test/flutter_test.dart';
import 'package:hutred/models/track.dart';
import 'package:hutred/services/playback_sources.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track song(TrackSource source, String uri) => Track(
      id: uri,
      title: 'A track',
      artist: 'An artist',
      source: source,
      uri: uri,
      addedAt: DateTime(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final spotify = song(TrackSource.spotify, 'spotify-id');
  final soundcloud = song(TrackSource.soundcloud, 'soundcloud-id');
  final youtube = song(TrackSource.youtube, 'youtube-id');

  test('remembered source wins until it fails', () async {
    SharedPreferences.setMockInitialValues({});
    final memory = await PlaybackSources.load();
    memory.rememberVariants([
      (spotify, [soundcloud, youtube, soundcloud]),
    ]);
    List<String> uris() => memory
        .candidates(spotify, youtubeAllowed: true)
        .map((track) => track.uri)
        .toList();

    expect(uris(), ['soundcloud-id', 'youtube-id', 'spotify-id']);
    memory.opened(spotify, youtube);
    expect(uris(), ['youtube-id', 'soundcloud-id', 'spotify-id']);
    memory.failed(spotify, youtube);
    expect(uris(), ['soundcloud-id', 'youtube-id', 'spotify-id']);
  });

  test('saved YouTube fallback respects the playback setting', () async {
    SharedPreferences.setMockInitialValues({
      'playback_sources_v1': '''
{"spotify:spotify-id":{"last":["youtube","youtube-id"],"alternatives":[["soundcloud","soundcloud-id"]]}}
''',
    });
    final memory = await PlaybackSources.load();
    expect(memory.candidates(spotify, youtubeAllowed: true).first.uri,
        'youtube-id');
    expect(memory.candidates(spotify, youtubeAllowed: false)
        .map((track) => track.source), [TrackSource.soundcloud, TrackSource.spotify]);
    expect(memory.candidates(youtube, youtubeAllowed: false).single.uri,
        'youtube-id');
  });
}
