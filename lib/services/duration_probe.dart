import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import 'library_store.dart';

/// У своих файлов при добавлении длительность неизвестна. В фоне по одному
/// открываем их «без звука» и записываем, сколько они идут.
class DurationProbe {
  DurationProbe(this.store) {
    store.addListener(_schedule);
    _schedule();
  }

  final LibraryStore store;
  Timer? _timer;
  bool _running = false;
  final Set<String> _failed = {};

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 8), _run);
  }

  Future<void> _run() async {
    if (_running) return;
    final todo = store.tracks
        .where((t) =>
            t.durationMs == null &&
            t.source == TrackSource.local &&
            !_failed.contains(t.id) &&
            File(t.uri).existsSync())
        .toList();
    if (todo.isEmpty) return;
    _running = true;
    final probe = AudioPlayer();
    try {
      for (final t in todo) {
        try {
          final d = await probe.setFilePath(t.uri, preload: true).timeout(const Duration(seconds: 8));
          final fresh = store.byId(t.id);
          if (d != null && d > Duration.zero && fresh != null && fresh.durationMs == null) {
            store.updateTrack(fresh.copyWith(durationMs: d.inMilliseconds));
          } else if (d == null) {
            _failed.add(t.id);
          }
        } catch (e) {
          _failed.add(t.id);
          debugPrint('[Длительность] ${t.title}: $e');
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    } finally {
      await probe.dispose();
      _running = false;
    }
  }
}
