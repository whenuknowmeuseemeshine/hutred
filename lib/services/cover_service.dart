import 'package:flutter/foundation.dart';

import '../models/track.dart';
import 'genius_service.dart';
import 'library_store.dart';
import 'player_service.dart';
import 'settings_store.dart';
import 'spotify_service.dart';
import 'youtube_source.dart';

/// Подбирает обложки: Genius → Spotify (если заданы ключи) → iTunes.
/// Для играющего трека ищет автоматически, для любого — по запросу из меню.
class CoverService {
  CoverService({
    required this.genius,
    required this.spotify,
    required this.itunes,
    required this.store,
    required this.settings,
    required this.player,
  }) {
    player.addListener(_onPlayerChanged);
  }

  final GeniusService genius;
  final SpotifyService spotify;
  final ItunesService itunes;
  final LibraryStore store;
  final SettingsStore settings;
  final PlayerService player;

  String? _lastId;
  final Set<String> _inFlight = {};

  void _onPlayerChanged() {
    final cur = player.current;
    if (cur == null || cur.id == _lastId) return;
    _lastId = cur.id;
    if (!settings.geniusCovers) return;
    final t = store.byId(cur.id);
    if (t == null || t.coverChecked) return;
    final wants = t.artworkUrl == null ||
        (t.source == TrackSource.youtube && settings.replaceYoutubeCovers);
    if (wants) fetchFor(t);
  }

  /// Ищет обложку и сохраняет её. Возвращает название источника или null.
  Future<String?> fetchFor(Track t) async {
    if (!_inFlight.add(t.id)) return null;
    try {
      final title = YoutubeSource.splitTitle(t.title, t.artist).title;
      final artist = t.artist;

      String? art;
      String? from;

      Future<void> attempt(String name, Future<String?> Function() f) async {
        if (art != null) return;
        try {
          art = await f();
          if (art != null) from = name;
        } catch (e) {
          debugPrint('Обложка ($name): $e');
        }
      }

      await attempt('Genius', () async {
        final song = await genius.findSong(artist, title);
        return song?.artUrl;
      });
      if (settings.hasSpotifyKeys) {
        await attempt(
            'Spotify',
            () => spotify.findCover(
                  id: settings.spotifyId,
                  secret: settings.spotifySecret,
                  artist: artist,
                  title: title,
                ));
      }
      await attempt('iTunes', () => itunes.findCover(artist, title));

      final current = store.byId(t.id);
      if (current == null) return from;
      final updated = current.copyWith(
        artworkUrl: art ?? current.artworkUrl,
        coverChecked: true,
      );
      store.updateTrack(updated);
      player.refreshTrack(updated);
      return from;
    } finally {
      _inFlight.remove(t.id);
    }
  }

  void dispose() => player.removeListener(_onPlayerChanged);
}
