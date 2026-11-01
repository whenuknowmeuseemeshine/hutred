import 'package:flutter/foundation.dart';

import '../models/track.dart';
import 'genius_service.dart';
import 'library_store.dart';
import 'meta_clean.dart';
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
  /// Название сначала чистится от мусора («audiovk com», «mp3», «(Official)»),
  /// потом пробуются варианты: целиком, первые слова, только исполнитель.
  /// Слова сравниваются нечётко: «сн» подходит к «сна».
  Future<String?> fetchFor(Track t) async {
    if (!_inFlight.add(t.id)) return null;
    try {
      final split = YoutubeSource.splitTitle(t.title, t.artist);
      final variants = MetaClean.variants(split.artist, split.title);

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

      // Подходит ли найденный трек: название и (если знаем) исполнитель.
      bool fits(({String artist, String title}) v, String title, String artist) {
        if (v.artist.isEmpty) {
          // Исполнитель неизвестен — он мог попасть в название.
          return MetaClean.fuzzy(v.title, '$artist $title') >= 0.75 &&
              MetaClean.fuzzy(title, v.title) >= 0.5;
        }
        final ts = [MetaClean.fuzzy(v.title, title), MetaClean.fuzzy(title, v.title)]
            .reduce((a, b) => a > b ? a : b);
        return ts >= 0.7 && MetaClean.fuzzy(v.artist, artist) >= 0.6;
      }

      for (final v in variants) {
        if (art != null) break;
        if (v.artist.isNotEmpty) {
          await attempt('Genius', () async {
            final song = await genius.findSong(v.artist, v.title);
            return song?.artUrl;
          });
        }
        if (settings.hasSpotifyKeys) {
          await attempt('Spotify', () async {
            final page = await spotify.searchTracks(
                id: settings.spotifyId,
                secret: settings.spotifySecret,
                query: '${v.artist} ${v.title}'.trim());
            for (final c in page.items) {
              if (c.artworkUrl != null && fits(v, c.title, c.artist)) return c.artworkUrl;
            }
            return null;
          });
        }
        await attempt('iTunes', () async {
          for (final c in await itunes.songs('${v.artist} ${v.title}'.trim())) {
            if (fits(v, c.title, c.artist)) return c.art;
          }
          return null;
        });
      }

      // Последний шанс: обложка любого трека этого исполнителя.
      final artistName = variants.map((v) => v.artist).firstWhere(
          (a) => a.isNotEmpty, orElse: () => '');
      if (art == null && artistName.isNotEmpty) {
        if (settings.hasSpotifyKeys) {
          await attempt('Spotify', () async {
            final page = await spotify.searchTracks(
                id: settings.spotifyId, secret: settings.spotifySecret, query: artistName);
            for (final c in page.items) {
              if (c.artworkUrl != null && MetaClean.fuzzy(artistName, c.artist) >= 0.99) {
                return c.artworkUrl;
              }
            }
            return null;
          });
        }
        await attempt('iTunes', () async {
          for (final c in await itunes.songs(artistName)) {
            if (MetaClean.fuzzy(artistName, c.artist) >= 0.99) return c.art;
          }
          return null;
        });
      }

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
