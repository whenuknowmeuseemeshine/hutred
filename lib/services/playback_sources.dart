import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

typedef _Source = (TrackSource, String);

/// Device-local alternatives and the last source that opened successfully.
class PlaybackSources {
  PlaybackSources._(this._prefs);

  static const _storageKey = 'playback_sources_v1';
  static const _maxTracks = 500;
  static const _maxAlternatives = 5;

  final SharedPreferences? _prefs;
  final _alternatives = <String, List<_Source>>{};
  final _lastGood = <String, _Source>{};
  Future<void> _saveTail = Future.value();

  static _Source _identity(Track track) => (track.source, track.uri);
  static String _key(Track track) => '${track.source.name}:${track.uri}';

  static bool _canPlay(_Source source) => switch (source.$1) {
        TrackSource.soundcloud || TrackSource.youtube => source.$2.isNotEmpty,
        TrackSource.url => _isAudiusLink(source.$2),
        _ => false,
      };

  static bool _isAudiusLink(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host == 'api.audius.co' &&
        uri.userInfo.isEmpty && uri.path.startsWith('/v1/tracks/') &&
        uri.path.endsWith('/stream') && uri.query == 'app_name=Hutred';
  }

  static bool _canRemember(Track track) =>
      track.source == TrackSource.spotify || _canPlay(_identity(track));

  static Future<PlaybackSources> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final memory = PlaybackSources._(prefs);
      final raw = prefs.getString(_storageKey);
      if (raw == null) return memory;
      final data = jsonDecode(raw);
      if (data is! Map) return memory;
      for (final entry in data.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final row = entry.value as Map;
        final last = _decode(row['last']);
        if (last != null) memory._lastGood[entry.key as String] = last;
        final variants = row['alternatives'];
        if (variants is List) {
          memory._alternatives[entry.key as String] =
              variants.map(_decode).whereType<_Source>().take(_maxAlternatives).toList();
        }
      }
      return memory;
    } catch (error) {
      debugPrint('[Playback] source memory unavailable: ${error.runtimeType}');
      return PlaybackSources._(null);
    }
  }

  static _Source? _decode(Object? value) {
    if (value is! List || value.length != 2 || value[1] is! String) return null;
    final kind = TrackSource.values.asNameMap()[value[0]];
    if (kind == null) return null;
    final source = (kind, value[1] as String);
    return _canPlay(source) ? source : null;
  }

  void rememberVariants(Iterable<(Track, Iterable<Track>)> groups) {
    var changed = false;
    for (final (track, variants) in groups) {
      if (!_canRemember(track)) continue;
      final key = _key(track);
      final previous = _alternatives[key] ?? const <_Source>[];
      final sources = {
        ...variants.map(_identity).where(_canPlay),
        ...previous,
      }..remove(_identity(track));
      final next = sources.take(_maxAlternatives).toList();
      if (listEquals(previous, next)) continue;
      _alternatives.remove(key);
      _alternatives[key] = next;
      changed = true;
    }
    if (changed) _save();
  }

  void opened(Track track, Track actual) {
    final source = _identity(actual);
    if (!_canRemember(track) || !_canPlay(source)) return;
    final key = _key(track);
    final previous = _lastGood[key];
    if (previous == source || previous == null && source == _identity(track)) {
      return;
    }
    _lastGood.remove(key);
    _lastGood[key] = source;
    _save();
  }

  void failed(Track track, Track actual) {
    final key = _key(track);
    if (_lastGood[key] != _identity(actual)) return;
    _lastGood.remove(key);
    _save();
  }

  List<Track> candidates(Track track, {required bool youtubeAllowed}) {
    final key = _key(track);
    final primary = _identity(track);
    final preferred = _lastGood[key];
    final variants = _alternatives[key] ?? const <_Source>[];
    final ordered = {
      if (track.source != TrackSource.spotify) primary,
      if (preferred != null) preferred,
      ...variants,
      primary,
    };
    return [
      for (final (source, uri) in ordered)
        if ((source, uri) == primary ||
            (source != TrackSource.youtube || youtubeAllowed))
          (source, uri) == primary
              ? track
              : track.copyWith(source: source, uri: uri),
    ];
  }

  void _save() {
    while (_alternatives.length > _maxTracks) {
      _alternatives.remove(_alternatives.keys.first);
    }
    while (_lastGood.length > _maxTracks) {
      _lastGood.remove(_lastGood.keys.first);
    }
    final prefs = _prefs;
    if (prefs == null) return;
    final snapshot = jsonEncode({
      for (final key in {..._alternatives.keys, ..._lastGood.keys})
        key: {
          if (_lastGood[key] case final _Source source)
            'last': [source.$1.name, source.$2],
          if (_alternatives[key] case final List<_Source> variants)
            'alternatives': [
              for (final (source, uri) in variants) [source.name, uri],
            ],
        },
    });
    _saveTail = _saveTail.then((_) async {
      try {
        await prefs.setString(_storageKey, snapshot);
      } catch (error) {
        debugPrint('[Playback] could not save source memory: ${error.runtimeType}');
      }
    });
    unawaited(_saveTail);
  }
}
