import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/import_service.dart';
import '../services/library_store.dart';
import '../services/player_service.dart';

/// Файл трека переместили или переименовали: спрашиваем, где он теперь.
/// Можно указать сам файл или папку — тогда в ней (и в подпапках) найдутся
/// по имени все пропавшие файлы разом.
class MissingFiles {
  MissingFiles({
    required this.navigatorKey,
    required this.store,
    required this.player,
  }) {
    player.onMissingFile = _onMissing;
  }

  final GlobalKey<NavigatorState> navigatorKey;
  final LibraryStore store;
  final PlayerService player;

  bool _asking = false;
  final Set<String> _skipped = {};

  static String _name(String path) => path.split(RegExp(r'[\\/]')).last.toLowerCase();
  static String _dir(String path) {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i < 0 ? path : path.substring(0, i);
  }

  List<Track> _missing() => store.tracks
      .where((t) => t.source == TrackSource.local && t.cloudPath == null && !File(t.uri).existsSync())
      .toList();

  Future<void> _onMissing(Track t) async {
    // Не спрашиваем по нескольку раз и про то, что уже пропустили.
    if (_asking || _skipped.contains(_dir(t.uri))) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    _asking = true;
    try {
      final missing = _missing();
      final sameFolder = missing.where((m) => _dir(m.uri) == _dir(t.uri)).length;
      final choice = await showDialog<String>(
        context: ctx,
        builder: (d) => AlertDialog(
          icon: const Icon(Icons.find_in_page_outlined),
          title: const Text('Файл не найден'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('«${t.title}» больше не лежит здесь:'),
                const SizedBox(height: 6),
                SelectableText(t.uri, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                Text(missing.length > 1
                    ? 'Похоже, файлы переместили: не найдено ${missing.length}'
                        '${sameFolder > 1 ? ', из них $sameFolder из этой же папки' : ''}. '
                        'Укажи новую папку — найду все разом.'
                    : 'Его переместили или переименовали? Покажи, где он теперь.'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, 'skip'), child: const Text('Пропустить')),
            TextButton(onPressed: () => Navigator.pop(d, 'file'), child: const Text('Указать файл')),
            FilledButton(onPressed: () => Navigator.pop(d, 'folder'), child: const Text('Указать папку')),
          ],
        ),
      );
      if (choice == 'skip' || choice == null) {
        _skipped.add(_dir(t.uri));
        return;
      }
      var fixed = 0;
      if (choice == 'file') {
        final res = await FilePicker.platform.pickFiles(type: FileType.audio);
        final path = res?.files.single.path;
        if (path == null) return;
        _relink(t, path);
        fixed = 1;
        // Рядом, скорее всего, лежат и остальные — заодно ищем их там.
        fixed += _relinkIn(_dir(path), recursive: false);
      } else {
        final dir = await FilePicker.platform.getDirectoryPath();
        if (dir == null) return;
        fixed = _relinkIn(dir, recursive: true);
      }
      final left = _missing().length;
      final c = navigatorKey.currentContext;
      if (c != null && c.mounted) {
        ScaffoldMessenger.of(c).showSnackBar(SnackBar(
          content: Text(fixed == 0
              ? 'Там этих файлов не нашлось'
              : 'Нашлось файлов: $fixed${left > 0 ? '. Ещё не найдено: $left' : ''}'),
        ));
      }
      // Тот трек, что не смог играть, — включаем снова.
      final now = store.byId(t.id);
      if (now != null && File(now.uri).existsSync() && player.current?.id == t.id) {
        player.refreshTrack(now);
        await player.jumpTo(player.index);
      }
    } finally {
      _asking = false;
    }
  }

  void _relink(Track t, String path) {
    final stored = store.byId(t.id);
    if (stored == null) return;
    final updated = stored.copyWith(uri: path);
    store.updateTrack(updated);
    player.refreshTrack(updated);
  }

  /// Ищет пропавшие файлы в папке по имени. Возвращает, сколько нашлось.
  int _relinkIn(String dir, {required bool recursive}) {
    final byName = <String, String>{};
    try {
      for (final e in Directory(dir).listSync(recursive: recursive, followLinks: false)) {
        if (e is File) {
          final ext = e.path.split('.').last.toLowerCase();
          if (ImportService.audioExtensions.contains(ext)) byName.putIfAbsent(_name(e.path), () => e.path);
        }
      }
    } catch (_) {}
    var n = 0;
    for (final m in _missing()) {
      final found = byName[_name(m.uri)];
      if (found != null) {
        _relink(m, found);
        n++;
      }
    }
    return n;
  }
}
