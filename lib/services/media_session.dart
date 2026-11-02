import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

import 'offline_service.dart';
import 'player_service.dart';

/// Трек в системе: «Исполняется» на iPhone (пункт управления, экран
/// блокировки, наушники) и уведомление с кнопками на Android.
/// Сам звук играет PlayerService — здесь только зеркало его состояния.
class MediaSession extends BaseAudioHandler with SeekHandler {
  MediaSession._(this.player) {
    player.addListener(_sync);
    _sync();
  }

  final PlayerService player;

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<void> init(PlayerService player) async {
    if (!supported) return;
    try {
      // Обычная музыка: играет в фоне, приглушает другие приложения.
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await AudioService.init(
        builder: () => MediaSession._(player),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'ru.hutred.hutred.audio',
          androidNotificationChannelName: 'Hutred',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (e) {
      debugPrint('[Медиа] $e');
    }
  }

  String? _lastId;

  void _sync() {
    final t = player.current;
    if (t == null) {
      mediaItem.add(null);
    } else if (t.id != _lastId || mediaItem.value?.duration != player.duration) {
      _lastId = t.id;
      final art = t.artworkUrl;
      Uri? artUri;
      if (art != null) {
        // Без интернета — скачанная обложка, если есть.
        final local = art.startsWith('http') ? OfflineService.instance?.coverForUrl(art) : art;
        artUri = local != null && !local.startsWith('http')
            ? Uri.file(local)
            : (art.startsWith('http') ? Uri.parse(art) : null);
      }
      mediaItem.add(MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.shownAlbum.isEmpty ? null : t.shownAlbum,
        duration: player.duration,
        artUri: artUri,
      ));
    }
    final playing = player.playing;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: player.loading
          ? AudioProcessingState.loading
          : (t == null ? AudioProcessingState.idle : AudioProcessingState.ready),
      playing: playing,
      updatePosition: player.position,
    ));
  }

  @override
  Future<void> play() async {
    if (!player.playing) await player.togglePlay();
  }

  @override
  Future<void> pause() async {
    if (player.playing) await player.togglePlay();
  }

  @override
  Future<void> skipToNext() => player.next();

  @override
  Future<void> skipToPrevious() => player.previous();

  @override
  Future<void> seek(Duration position) async {
    await player.seek(position);
    _sync();
  }

  @override
  Future<void> stop() async {
    if (player.playing) await player.togglePlay();
  }
}
