import 'dart:async';

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/library_store.dart';
import '../services/meta_clean.dart';
import '../services/player_service.dart';
import '../services/settings_store.dart';
import '../services/spotify_service.dart';
import 'widgets/artwork.dart';
import 'icons.dart';

/// Сверка новых треков со Spotify: когда трек с YouTube или SoundCloud
/// попадает в медиатеку, ищем его в Spotify и спрашиваем, подставить ли
/// точные название, исполнителя, альбом и обложку (по ним лучше ищется текст).
class SpotifyCheck {
  SpotifyCheck({
    required this.navigatorKey,
    required this.store,
    required this.settings,
    required this.spotify,
    required this.player,
  }) {
    store.onTracksAdded = _onAdded;
  }

  final GlobalKey<NavigatorState> navigatorKey;
  final LibraryStore store;
  final SettingsStore settings;
  final SpotifyService spotify;
  final PlayerService player;

  final List<(Track, Track)> _queue = [];
  bool _asking = false;

  static String _n(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  /// Ищет трек в Spotify по очищенным вариантам названия.
  Future<Track?> matchLoose(Track t) async {
    for (final v in MetaClean.variants(t.artist, t.title)) {
      final m = await spotify.bestMatch(
        id: settings.spotifyId,
        secret: settings.spotifySecret,
        artist: v.artist,
        title: v.title,
        durationMs: t.durationMs,
      );
      if (m != null) return m;
    }
    return null;
  }

  /// Подставляет сведения из Spotify сразу многим трекам (без вопросов —
  /// пользователь сам выбрал треки и нажал кнопку). Возвращает число исправленных.
  Future<int> applyAll(List<Track> tracks, void Function(int done, int total) progress) async {
    var fixed = 0;
    for (var i = 0; i < tracks.length; i++) {
      progress(i, tracks.length);
      final t = tracks[i];
      // Трек из Spotify и так с точными сведениями.
      if (t.source == TrackSource.spotify) continue;
      try {
        final m = await matchLoose(t);
        if (m != null) {
          _apply(t, m);
          fixed++;
        }
      } catch (e) {
        debugPrint('[Сверка со Spotify] ${t.title}: $e');
        // Spotify попросил подождать — дальше не долбим, остальное потом.
        if (DateTime.now().isBefore(SpotifyService.coolingUntil)) break;
      }
    }
    progress(tracks.length, tracks.length);
    return fixed;
  }

  void _apply(Track t, Track m) {
    final stored = store.byId(t.id) ?? store.findBySource(t.source, t.uri);
    if (stored == null) return;
    // Свой текст (вставленный или подогнанный ИИ) при переименовании не трогаем.
    final changedName = (m.title != stored.title || m.artist != stored.artist) &&
        stored.lyricsSource != 'custom' &&
        stored.lyricsSource != 'ai';
    final updated = stored.copyWith(
      title: m.title,
      artist: m.artist,
      album: Track.sameAsTitle(m.album, m.title) ? '' : m.album,
      artworkUrl: m.artworkUrl ?? stored.artworkUrl,
      coverChecked: true,
      // Сведения поменялись — текст ищем заново, уже по точным данным.
      lyrics: changedName ? null : stored.lyrics,
      lyricsSource: changedName ? null : stored.lyricsSource,
    );
    store.updateTrack(updated);
    player.refreshTrack(updated);
  }

  void _onAdded(List<Track> added) {
    if (!settings.spotifyCheck || !settings.hasSpotifyKeys) return;
    // Массовый перенос не трогаем — спрашивать про каждый трек было бы мучением.
    if (added.length > 3) return;
    for (final t in added) {
      if (t.source == TrackSource.youtube ||
          t.source == TrackSource.soundcloud ||
          t.source == TrackSource.url) {
        unawaited(_check(t));
      }
    }
  }

  Future<void> _check(Track t) async {
    try {
      final m = await matchLoose(t);
      if (m == null) return;
      // Сведения и так совпадают — спрашивать незачем.
      if (_n(m.title) == _n(t.title) &&
          _n(m.artist) == _n(t.artist) &&
          t.source != TrackSource.youtube) {
        return;
      }
      _queue.add((t, m));
      unawaited(_next());
    } catch (e) {
      debugPrint('[Сверка со Spotify] $e');
    }
  }

  Future<void> _next() async {
    if (_asking || _queue.isEmpty) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    _asking = true;
    final (t, m) = _queue.removeAt(0);
    try {
      final ok = await showDialog<bool>(
        context: ctx,
        builder: (d) => _Prompt(original: t, match: m),
      );
      if (ok == true) _apply(t, m);
    } finally {
      _asking = false;
      unawaited(_next());
    }
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.original, required this.match});
  final Track original;
  final Track match;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, Track t) => Row(
          children: [
            Artwork(track: t, size: 56, radius: 6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  Text(t.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                      t.album.isEmpty ? t.artist : '${t.artist} · ${t.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        );

    return AlertDialog(
      title: const Text('Нашёл этот трек в Spotify'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Сейчас', original),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Icon(Ic.arrow_downward, size: 18),
            ),
            row('Из Spotify', match),
            const SizedBox(height: 16),
            const Text(
              'Подставить точное название, исполнителя и обложку? '
              'По ним лучше находится текст песни. Звук останется тот же.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Оставить как есть')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Подставить')),
      ],
    );
  }
}

