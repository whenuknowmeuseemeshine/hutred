import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'deezer_catalog.dart';
import 'wave_service.dart';

/// «Что нового»: свежие релизы исполнителей, на которых ты подписан.
/// Проверяется при запуске и раз в несколько часов.
class ReleasesService extends ChangeNotifier {
  ReleasesService({required this.wave}) {
    wave.addListener(_onWave);
    unawaited(_init());
  }

  final WaveService wave;

  List<DzAlbum> _items = const [];
  List<DzAlbum> get items => _items;
  bool _loading = false;
  bool get loading => _loading;
  DateTime _seen = DateTime.now().subtract(const Duration(days: 7));
  Timer? _timer;
  String _followsKey = '';
  File? _file;

  /// Сколько новых с последнего открытия «Что нового».
  int get unread => _items.where((a) => a.released != null && a.released!.isAfter(_seen)).length;

  bool isNew(DzAlbum a) => a.released != null && a.released!.isAfter(_seen);

  Future<void> _init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}releases.json');
      if (await _file!.exists()) {
        final j = jsonDecode(await _file!.readAsString());
        final s = j is Map ? DateTime.tryParse('${j['seen']}') : null;
        if (s != null) _seen = s;
      }
    } catch (_) {}
    _followsKey = _key();
    await refresh();
    _timer = Timer.periodic(const Duration(hours: 4), (_) => refresh(force: true));
  }

  String _key() => (wave.follows.map((f) => f.id).toList()..sort()).join(',');

  void _onWave() {
    final k = _key();
    if (k == _followsKey) return;
    _followsKey = k;
    unawaited(refresh());
  }

  Future<void> refresh({bool force = false}) async {
    if (_loading) return;
    final follows = wave.follows;
    if (follows.isEmpty) {
      _items = const [];
      notifyListeners();
      return;
    }
    _loading = true;
    notifyListeners();
    final since = DateTime.now().subtract(const Duration(days: 120));
    final out = <DzAlbum>[];
    try {
      for (var i = 0; i < follows.length; i += 4) {
        final chunk = follows.skip(i).take(4);
        final lists = await Future.wait(chunk.map((f) async {
          final id = int.tryParse(f.id);
          if (id == null) return <DzAlbum>[];
          if (force) DeezerCatalog.forget('/artist/$id/albums');
          try {
            return await DeezerCatalog.albums(id, artist: f.name);
          } catch (_) {
            return <DzAlbum>[];
          }
        }));
        for (final l in lists) {
          out.addAll(l.where((a) => a.released != null && a.released!.isAfter(since)));
        }
      }
      out.sort((a, b) => b.released!.compareTo(a.released!));
      _items = out;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Открыли «Что нового» — всё прочитано.
  Future<void> markSeen() async {
    _seen = DateTime.now();
    notifyListeners();
    try {
      await _file?.writeAsString(jsonEncode({'seen': _seen.toIso8601String()}));
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    wave.removeListener(_onWave);
    super.dispose();
  }
}
