import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';

/// Импорт треков из файлов, папок и прямых ссылок.
class ImportService {
  static const audioExtensions = {
    'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'oga', 'opus', 'wma', 'aiff',
    'aif', 'alac', 'webm', 'mka',
  };

  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  Future<List<Track>> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null) return const [];
    final tracks = <Track>[];
    for (final f in result.files) {
      final path = f.path;
      if (path == null) continue;
      tracks.add(trackFromPath(await _persist(path)));
    }
    return tracks;
  }

  /// Рекурсивно сканирует папку (только десктоп).
  Future<List<Track>> pickFolder() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return const [];
    final tracks = <Track>[];
    await for (final e
        in Directory(dirPath).list(recursive: true, followLinks: false)) {
      if (e is File && audioExtensions.contains(_ext(e.path))) {
        tracks.add(trackFromPath(e.path, albumFromFolder: true));
      }
    }
    tracks.sort((a, b) => a.uri.compareTo(b.uri));
    return tracks;
  }

  /// Трек по прямой ссылке: mp3, поток интернет-радио, m3u8 и т.п.
  Track trackFromUrl(String url) {
    final uri = Uri.parse(url);
    final last = uri.pathSegments.isEmpty
        ? ''
        : Uri.decodeComponent(uri.pathSegments.last);
    final name = _stripExt(last);
    final parsed = _splitName(name.isEmpty ? uri.host : name);
    return Track(
      id: Track.newId(),
      title: parsed.title,
      artist: parsed.artist ?? uri.host,
      source: TrackSource.url,
      uri: url,
      addedAt: DateTime.now(),
    );
  }

  Track trackFromPath(String path, {bool albumFromFolder = false}) {
    final parts = path.split(RegExp(r'[\\/]'));
    final parsed = _splitName(_stripExt(parts.last));
    final folder = parts.length > 1 ? parts[parts.length - 2] : '';
    return Track(
      id: Track.newId(),
      title: parsed.title,
      artist: parsed.artist ?? Track.unknownArtist,
      album: albumFromFolder ? folder : '',
      source: TrackSource.local,
      uri: path,
      addedAt: DateTime.now(),
    );
  }

  /// На телефонах выбранный файл лежит во временном кэше — копируем к себе.
  Future<String> _persist(String path) async {
    if (!_isMobile) return path;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}music');
    await dir.create(recursive: true);
    final name = path.split(RegExp(r'[\\/]')).last;
    var target = File('${dir.path}${Platform.pathSeparator}$name');
    var n = 1;
    while (await target.exists()) {
      target = File(
          '${dir.path}${Platform.pathSeparator}${_stripExt(name)} ($n).${_ext(name)}');
      n++;
    }
    await File(path).copy(target.path);
    return target.path;
  }

  static String _ext(String p) {
    final i = p.lastIndexOf('.');
    return i < 0 ? '' : p.substring(i + 1).toLowerCase();
  }

  static String _stripExt(String name) {
    final i = name.lastIndexOf('.');
    return i <= 0 ? name : name.substring(0, i);
  }

  /// «01. Исполнитель - Название» → исполнитель и название.
  static ({String? artist, String title}) _splitName(String name) {
    var clean = name.replaceAll('_', ' ').trim();
    clean = clean.replaceFirst(RegExp(r'^\d{1,3}[\s.\-)]+\s*'), '');
    for (final sep in [' - ', ' – ', ' — ']) {
      final i = clean.indexOf(sep);
      if (i > 0) {
        return (
          artist: clean.substring(0, i).trim(),
          title: clean.substring(i + sep.length).trim(),
        );
      }
    }
    return (artist: null, title: clean.isEmpty ? name : clean);
  }
}
