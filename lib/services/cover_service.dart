import 'package:flutter/foundation.dart';

import '../models/track.dart';
import 'genius_service.dart';
import 'library_store.dart';
import 'meta_clean.dart';
import 'player_service.dart';
import 'settings_store.dart';
import 'soundcloud_source.dart';
import 'spotify_service.dart';
import 'youtube_source.dart';

/// Подбирает обложки: Genius → Spotify (если заданы ключи) → iTunes.
/// Для играющего трека ищет автоматически, для любого — по запросу из меню.
class CoverService {
  CoverService({
    required this.genius,
    required this.spotify,
    required this.itunes,
    required this.soundcloud,
    required this.store,
    required this.settings,
    required this.player,
  }) {
    player.addListener(_onPlayerChanged);
  }

  final GeniusService genius;
  final SpotifyService spotify;
  final ItunesService itunes;
  final SoundcloudSource soundcloud;
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

  /// Ищет трек и обновляет у него обложку, а также название, исполнителя
  /// и альбом. Порядок: Spotify → SoundCloud → iTunes (у них есть сведения),
  /// Genius — только обложка. Возвращает название источника или null.
  ///
  /// Название сначала чистится от мусора («audiovk com», «mp3», «(Official)»),
  /// потом пробуются варианты: целиком, первые слова, только исполнитель.
  /// Слова сравниваются нечётко: «сн» подходит к «сна».
  Future<String?> fetchFor(Track t, {bool manual = false}) async {
    if (!_inFlight.add(t.id)) return null;
    try {
      final split = YoutubeSource.splitTitle(t.title, t.artist);
      final variants = MetaClean.variants(split.artist, split.title);

      // Найденное: обложка и (если источник их знает) сведения.
      String? art, title, artist, album, from;

      Future<void> attempt(String name, Future<bool> Function() f) async {
        if (art != null) return;
        try {
          if (await f()) from = name;
        } catch (e) {
          debugPrint('Обложка ($name): $e');
        }
      }

      // Подходит ли найденный трек: название и (если знаем) исполнитель.
      bool fits(({String artist, String title}) v, String ti, String ar) {
        if (v.artist.isEmpty) {
          // Исполнитель неизвестен — он мог попасть в название.
          return MetaClean.fuzzy(v.title, '$ar $ti') >= 0.75 &&
              MetaClean.fuzzy(ti, v.title) >= 0.5;
        }
        final ts = [MetaClean.fuzzy(v.title, ti), MetaClean.fuzzy(ti, v.title)]
            .reduce((a, b) => a > b ? a : b);
        return ts >= 0.7 && MetaClean.fuzzy(v.artist, ar) >= 0.6;
      }

      bool take(String? a, String ti, String ar, [String al = '']) {
        if (a == null) return false;
        art = a;
        title = ti;
        artist = ar;
        album = al;
        return true;
      }

      // Ключи Spotify общие на всех, и у них лимит запросов. Сам по себе
      // (при включении трека) спрашиваем Spotify один раз, а не по каждому варианту.
      final spotifyOk = settings.hasSpotifyKeys &&
          DateTime.now().isAfter(SpotifyService.coolingUntil);
      var vi = 0;
      for (final v in variants) {
        if (art != null) break;
        if (spotifyOk && (manual || vi++ == 0)) {
          await attempt('Spotify', () async {
            final page = await spotify.searchTracks(
                id: settings.spotifyId,
                secret: settings.spotifySecret,
                query: '${v.artist} ${v.title}'.trim());
            for (final c in page.items) {
              if (c.artworkUrl != null && fits(v, c.title, c.artist)) {
                return take(c.artworkUrl, c.title, c.artist, c.album);
              }
            }
            return false;
          });
        }
        await attempt('SoundCloud', () async {
          for (final c in await soundcloud.search('${v.artist} ${v.title}'.trim(), limit: 10)) {
            final a = c.artworkUrl;
            // Аватар загрузившего вместо обложки не берём.
            if (a != null && !a.contains('avatars-') && fits(v, c.title, c.artist)) {
              return take(a, c.title, c.artist);
            }
          }
          return false;
        });
        await attempt('iTunes', () async {
          for (final c in await itunes.songs('${v.artist} ${v.title}'.trim())) {
            if (fits(v, c.title, c.artist)) return take(c.art, c.title, c.artist, c.album);
          }
          return false;
        });
        if (v.artist.isNotEmpty) {
          await attempt('Genius', () async {
            final song = await genius.findSong(v.artist, v.title);
            final a = song?.artUrl;
            if (a == null) return false;
            art = a;
            return true;
          });
        }
      }

      // Нашли трек, но источник не знает альбома (SoundCloud) или Spotify
      // недоступен — спрашиваем альбом у Genius.
      if (art != null && title != null && artist != null && (album ?? '').isEmpty) {
        try {
          final al = await genius.albumOf(artist!, title!);
          if (al != null) album = al;
        } catch (e) {
          debugPrint('Альбом (Genius): $e');
        }
      }

      // Последний шанс: обложка любого трека этого исполнителя (сведения не трогаем).
      final artistName = variants.map((v) => v.artist).firstWhere(
          (a) => a.isNotEmpty, orElse: () => '');
      if (art == null && artistName.isNotEmpty) {
        if (spotifyOk && manual) {
          await attempt('Spotify', () async {
            final page = await spotify.searchTracks(
                id: settings.spotifyId, secret: settings.spotifySecret, query: artistName);
            for (final c in page.items) {
              if (c.artworkUrl != null && MetaClean.fuzzy(artistName, c.artist) >= 0.99) {
                art = c.artworkUrl;
                return true;
              }
            }
            return false;
          });
        }
        await attempt('iTunes', () async {
          for (final c in await itunes.songs(artistName)) {
            if (MetaClean.fuzzy(artistName, c.artist) >= 0.99) {
              art = c.art;
              return true;
            }
          }
          return false;
        });
      }

      final current = store.byId(t.id);
      if (current == null) return from;
      final newTitle = (title ?? '').trim();
      final newArtist = (artist ?? '').trim();
      final renamed = newTitle.isNotEmpty &&
          newArtist.isNotEmpty &&
          (newTitle != current.title || newArtist != current.artist);
      // Свой текст (вставленный или подогнанный ИИ) не трогаем.
      final keepLyrics = !renamed ||
          current.lyricsSource == 'custom' ||
          current.lyricsSource == 'ai';
      final updated = current.copyWith(
        artworkUrl: art ?? current.artworkUrl,
        coverChecked: true,
        title: renamed ? newTitle : null,
        artist: renamed ? newArtist : null,
        // У синглов «альбом» = название трека — такой не записываем.
        // Источник знает сведения о треке (Spotify, SoundCloud, iTunes):
        // альбом берём его, а если у него альбома нет (или это сингл) —
        // стираем старый, например «123» из тегов файла. Genius даёт только
        // обложку — тогда альбом не трогаем.
        album: album == null
            ? null
            : (album!.trim().isEmpty ||
                    Track.sameAsTitle(album!, newTitle.isNotEmpty ? newTitle : current.title))
                ? ''
                : album!.trim(),
        lyrics: keepLyrics ? current.lyrics : null,
        lyricsSource: keepLyrics ? current.lyricsSource : null,
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
