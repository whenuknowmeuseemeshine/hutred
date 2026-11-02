import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';

import 'player_service.dart';

/// Трек в самой Windows (System Media Transport Controls): всплывающая
/// панель громкости, экран блокировки — и программы вроде Music Presence,
/// которые показывают в Discord «Слушает …» как у Spotify.
class WindowsMedia {
  WindowsMedia._(this.player, this._smtc) {
    player.addListener(_sync);
    _smtc.buttonPressStream.listen(_onButton);
    _sync();
  }

  final PlayerService player;
  final SMTCWindows _smtc;

  static Future<void> init(PlayerService player) async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await SMTCWindows.initialize();
      final smtc = SMTCWindows(
        config: const SMTCConfig(
          fastForwardEnabled: false,
          nextEnabled: true,
          pauseEnabled: true,
          playEnabled: true,
          rewindEnabled: false,
          prevEnabled: true,
          stopEnabled: false,
        ),
      );
      WindowsMedia._(player, smtc);
    } catch (e) {
      debugPrint('[SMTC] $e');
    }
  }

  String? _lastId;
  bool? _lastPlaying;
  int _lastPosSec = -1;

  void _sync() {
    final t = player.current;
    try {
      if (t == null) {
        if (_lastId != null) _smtc.disableSmtc();
        _lastId = null;
        return;
      }
      if (t.id != _lastId) {
        if (_lastId == null) _smtc.enableSmtc();
        _lastId = t.id;
        final art = t.artworkUrl;
        _smtc.updateMetadata(MusicMetadata(
          title: t.title,
          artist: t.artist,
          album: t.shownAlbum,
          albumArtist: t.artist,
          thumbnail: art != null && art.startsWith('http') ? art : null,
        ));
      }
      final playing = player.playing;
      final pos = player.position;
      final dur = player.duration;
      // Время шлём при смене трека/паузы и если позиция заметно сдвинулась (перемотка).
      if (playing != _lastPlaying || (pos.inSeconds - _lastPosSec).abs() > 2 || !playing) {
        _lastPlaying = playing;
        _lastPosSec = pos.inSeconds;
        _smtc.setPlaybackStatus(playing ? PlaybackStatus.playing : PlaybackStatus.paused);
        if (dur != null) {
          _smtc.updateTimeline(PlaybackTimeline(
            startTimeMs: 0,
            endTimeMs: dur.inMilliseconds,
            positionMs: pos.inMilliseconds,
            minSeekTimeMs: 0,
            maxSeekTimeMs: dur.inMilliseconds,
          ));
        }
      }
    } catch (e) {
      debugPrint('[SMTC] $e');
    }
  }

  void _onButton(PressedButton b) {
    switch (b) {
      case PressedButton.play:
        if (!player.playing) player.togglePlay();
      case PressedButton.pause:
        if (player.playing) player.togglePlay();
      case PressedButton.next:
        player.next();
      case PressedButton.previous:
        player.previous();
      default:
        break;
    }
  }
}
