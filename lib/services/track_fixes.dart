import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/track.dart';
import 'account_service.dart';
import 'library_store.dart';

/// Исправления треков от админа: текст, тайминги, сдвиг, сведения и обложка.
/// Админ правит трек у себя — правка уходит в облако. У остальных она
/// применяется, когда трек включают (если правка новее уже применённой).
class TrackFixes {
  TrackFixes({required this.account, required this.store}) {
    store.onManualEdit = _onManualEdit;
  }

  final AccountService account;
  final LibraryStore store;

  /// Ключ → время правки, которую уже применили на этом устройстве.
  final Map<String, String> _applied = {};
  final Set<String> _checked = {};
  final Map<String, Timer> _pending = {};
  File? _file;

  SupabaseClient get _db => Supabase.instance.client;
  bool get _online => account.enabled && account.signedIn;

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  /// Для потоковых треков — источник и id, для файлов — исполнитель и название.
  static String keyFor(Track t) => t.source == TrackSource.local
      ? 'meta:${_norm(t.artist)}|${_norm(t.title)}'
      : '${t.source.name}:${t.uri}';

  Future<void> load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}fixes_applied.json');
      if (await _file!.exists()) {
        final j = jsonDecode(await _file!.readAsString());
        if (j is Map) j.forEach((k, v) => _applied['$k'] = '$v');
      }
    } catch (e) {
      debugPrint('[Исправления] $e');
    }
  }

  Future<void> _saveApplied() async {
    try {
      await _file?.writeAsString(jsonEncode(_applied));
    } catch (_) {}
  }

  // ---------- Админ: отправка ----------

  void _onManualEdit(Track before, Track after) {
    if (!_online || !account.isAdmin) return;
    // Ключ по старым сведениям: у других трек ещё называется по-старому.
    final key = keyFor(before);
    _pending[key]?.cancel();
    // Сдвиг двигают кнопками по много раз подряд — отправляем последнее.
    _pending[key] = Timer(const Duration(seconds: 2), () {
      _pending.remove(key);
      final fresh = store.byId(after.id) ?? after;
      publish(fresh, key: key);
    });
  }

  /// Отправить исправление трека всем пользователям.
  Future<String?> publish(Track t, {String? key}) async {
    if (!_online || !account.isAdmin) return 'Это может только админ';
    final k = key ?? keyFor(t);
    final art = t.artworkUrl;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await _db.from('track_fixes').upsert({
        'key': k,
        'data': {
          'title': t.title,
          'artist': t.artist,
          'album': t.album,
          'lyrics': t.lyrics,
          'lyricsSource': t.lyricsSource,
          'lyricsOffsetMs': t.lyricsOffsetMs,
          // Обложку с диска другим не передать — только ссылки.
          if (art != null && art.startsWith('http')) 'artworkUrl': art,
        },
        'updated_by': account.user?.id,
        'updated_at': now,
      });
      _applied[k] = now;
      unawaited(_saveApplied());
      return null;
    } catch (e) {
      debugPrint('[Исправления] $e');
      return 'Не удалось отправить исправление';
    }
  }

  // ---------- Все: получение ----------

  /// Проверяет, есть ли для трека исправление новее применённого.
  /// Возвращает исправленный трек или null.
  Future<Track?> check(Track t) async {
    if (!_online) return null;
    final key = keyFor(t);
    if (!_checked.add(key)) return null;
    try {
      final row = await _db
          .from('track_fixes')
          .select('data, updated_at')
          .eq('key', key)
          .maybeSingle();
      if (row == null) return null;
      final at = '${row['updated_at']}';
      final d = row['data'];
      if (d is! Map) return null;
      final stored = store.byId(t.id) ?? store.findBySource(t.source, t.uri);
      final base = stored ?? t;
      final fixed = base.copyWith(
        title: (d['title'] as String?)?.isNotEmpty == true ? d['title'] as String : null,
        artist: (d['artist'] as String?)?.isNotEmpty == true ? d['artist'] as String : null,
        album: d['album'] as String?,
        lyrics: d.containsKey('lyrics') ? d['lyrics'] as String? : base.lyrics,
        lyricsSource:
            d.containsKey('lyricsSource') ? d['lyricsSource'] as String? : base.lyricsSource,
        lyricsOffsetMs: (d['lyricsOffsetMs'] as num?)?.toInt(),
        artworkUrl: d['artworkUrl'] as String? ?? base.artworkUrl,
        coverChecked: d['artworkUrl'] != null ? true : null,
      );
      _applied[key] = at;
      unawaited(_saveApplied());
      // Правка админа главнее своей: если у тебя трек отличается
      // (например, сам подогнал текст), всё равно ставим версию админа.
      final same = fixed.title == base.title &&
          fixed.artist == base.artist &&
          fixed.album == base.album &&
          fixed.lyrics == base.lyrics &&
          fixed.lyricsOffsetMs == base.lyricsOffsetMs &&
          fixed.artworkUrl == base.artworkUrl;
      if (same) return null;
      if (stored != null) store.updateTrack(fixed);
      return fixed;
    } catch (e) {
      _checked.remove(key);
      debugPrint('[Исправления] $e');
      return null;
    }
  }
}
