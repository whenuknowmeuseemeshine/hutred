import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import 'account_service.dart';

/// Человек из списка друзей или заявок.
class FriendInfo {
  const FriendInfo({
    required this.friendshipId,
    required this.userId,
    required this.username,
    required this.avatarUrl,
    required this.incoming,
    required this.accepted,
  });

  final int friendshipId;
  final String userId;
  final String? username;
  final String? avatarUrl;

  /// Заявку прислали мне (иначе — я отправил).
  final bool incoming;
  final bool accepted;

  String get name => username != null ? '@$username' : 'Без логина';
}

/// Друзья: заявки по логину, список друзей, их медиатеки.
class FriendsService extends ChangeNotifier {
  FriendsService({required this.account}) {
    account.addListener(_onAccount);
    // Новые заявки появляются сами: раз в минуту проверяем список.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (account.user != null) refresh(quiet: true);
    });
  }

  Timer? _timer;

  /// Сообщить другу о заявке сразу (через общий канал «кто в сети»).
  Future<void> Function(String toUid)? onRequestSent;

  final _newRequests = StreamController<FriendInfo>.broadcast();

  /// Пришла новая заявка в друзья — для всплывающего сообщения.
  Stream<FriendInfo> get newRequests => _newRequests.stream;
  Set<int>? _knownIncoming;

  final AccountService account;
  SupabaseClient get _db => Supabase.instance.client;

  List<FriendInfo> _all = const [];
  bool _loading = false;
  String? _error;
  bool? _libraryPublic;
  String? _loadedFor;

  bool get loading => _loading;
  String? get error => _error;
  List<FriendInfo> get friends => _all.where((f) => f.accepted).toList();
  List<FriendInfo> get incoming => _all.where((f) => !f.accepted && f.incoming).toList();
  List<FriendInfo> get outgoing => _all.where((f) => !f.accepted && !f.incoming).toList();

  /// Видят ли друзья мою медиатеку.
  bool get libraryPublic => _libraryPublic ?? true;

  void _onAccount() {
    final uid = account.user?.id;
    if (uid != _loadedFor) {
      _loadedFor = uid;
      _all = const [];
      _libraryPublic = null;
      _knownIncoming = null;
      if (uid != null) refresh();
      notifyListeners();
    }
  }

  Future<void> refresh({bool quiet = false}) async {
    final me = account.user?.id;
    if (me == null) return;
    if (!quiet) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      final rows = await _db
          .from('friendships')
          .select('id, requester, addressee, status')
          .or('requester.eq.$me,addressee.eq.$me');
      final ids = <String>{
        for (final r in rows) r['requester'] == me ? '${r['addressee']}' : '${r['requester']}',
      };
      final profiles = <String, Map<String, dynamic>>{};
      if (ids.isNotEmpty) {
        final ps = await _db
            .from('profiles')
            .select('id, username, avatar_url')
            .inFilter('id', ids.toList());
        for (final p in ps) {
          profiles['${p['id']}'] = p;
        }
      }
      _all = [
        for (final r in rows)
          () {
            final incoming = r['addressee'] == me;
            final other = incoming ? '${r['requester']}' : '${r['addressee']}';
            final p = profiles[other];
            return FriendInfo(
              friendshipId: (r['id'] as num).toInt(),
              userId: other,
              username: p?['username'] as String?,
              avatarUrl: p?['avatar_url'] as String?,
              incoming: incoming,
              accepted: r['status'] == 'accepted',
            );
          }(),
      ]..sort((a, b) => (a.username ?? '').compareTo(b.username ?? ''));
      // Новые входящие заявки (после первой загрузки) — всплывашкой.
      final inc = incoming;
      final known = _knownIncoming;
      if (known != null) {
        for (final f in inc) {
          if (!known.contains(f.friendshipId)) _newRequests.add(f);
        }
      }
      _knownIncoming = {for (final f in inc) f.friendshipId};

      final mine = await _db
          .from('profiles')
          .select('library_public')
          .eq('id', me)
          .maybeSingle();
      _libraryPublic = mine?['library_public'] as bool? ?? true;
    } catch (e) {
      _error = 'Не удалось загрузить друзей';
      debugPrint('[Друзья] $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Отправить заявку по логину. Возвращает текст ошибки или null.
  Future<String?> request(String username) async {
    final me = account.user?.id;
    if (me == null) return 'Сначала войди в аккаунт';
    final name = username.trim().replaceFirst('@', '');
    if (name.isEmpty) return 'Введи логин друга';
    if (name == account.username) return 'Это ты сам';
    try {
      final p = await _db
          .from('profiles')
          .select('id')
          .eq('username', name)
          .maybeSingle();
      if (p == null) return 'Пользователь @$name не найден';
      final other = '${p['id']}';
      final existing = _all.where((f) => f.userId == other).firstOrNull;
      if (existing != null) {
        if (existing.accepted) return '@$name уже у тебя в друзьях';
        // Он сам прислал заявку — просто принимаем.
        if (existing.incoming) return accept(existing);
        return 'Заявка уже отправлена';
      }
      await _db.from('friendships').insert({'requester': me, 'addressee': other});
      await onRequestSent?.call(other);
      await refresh();
      return null;
    } catch (e) {
      debugPrint('[Друзья] $e');
      return 'Не удалось отправить заявку';
    }
  }

  Future<String?> accept(FriendInfo f) async {
    try {
      await _db
          .from('friendships')
          .update({'status': 'accepted'}).eq('id', f.friendshipId);
      await refresh();
      return null;
    } catch (e) {
      return 'Не удалось принять заявку';
    }
  }

  /// Отклонить заявку, отменить свою или удалить из друзей.
  Future<void> remove(FriendInfo f) async {
    try {
      await _db.from('friendships').delete().eq('id', f.friendshipId);
    } catch (e) {
      debugPrint('[Друзья] $e');
    }
    await refresh();
  }

  Future<void> setLibraryPublic(bool v) async {
    final me = account.user?.id;
    if (me == null) return;
    _libraryPublic = v;
    notifyListeners();
    try {
      await _db.from('profiles').update({'library_public': v}).eq('id', me);
    } catch (e) {
      _libraryPublic = !v;
      notifyListeners();
    }
  }

  /// Треки из медиатеки друга (только те, что он не скрыл).
  /// Плейлисты друга с их треками (пустые и из одних своих файлов — пропускаем).
  Future<List<({Playlist playlist, List<Track> tracks})>> playlistsOf(String userId) async {
    final rows = await _db
        .from('library_items')
        .select('kind, item_id, data')
        .eq('user_id', userId)
        .eq('deleted', false)
        .limit(6000);
    final byId = <String, Track>{};
    final lists = <Playlist>[];
    for (final r in rows) {
      final d = r['data'];
      if (d is! Map) continue;
      try {
        final j = Map<String, dynamic>.from(d);
        if (r['kind'] == 'playlist') {
          lists.add(Playlist.fromJson(j));
        } else if (r['kind'] == 'track') {
          final orig = '${j['id']}';
          j['id'] = Track.newId();
          j['plays'] = 0;
          j['favorite'] = false;
          j.remove('cloudPath');
          final t = Track.fromJson(j);
          if (t.source != TrackSource.local && !t.hiddenFromFriends) byId[orig] = t;
        }
      } catch (_) {}
    }
    return [
      for (final p in lists)
        if (p.trackIds.any(byId.containsKey))
          (
            playlist: p,
            tracks: [
              for (final id in p.trackIds)
                if (byId[id] != null) byId[id]!,
            ],
          ),
    ];
  }

  Future<List<Track>> libraryOf(String userId) async {
    final rows = await _db
        .from('library_items')
        .select('data')
        .eq('user_id', userId)
        .eq('kind', 'track')
        .eq('deleted', false)
        .limit(5000);
    final out = <Track>[];
    for (final r in rows) {
      final d = r['data'];
      if (d is! Map) continue;
      try {
        final j = Map<String, dynamic>.from(d);
        // Свои счётчики и лайки друга мне не нужны, id — свой.
        j['id'] = Track.newId();
        j['plays'] = 0;
        j['favorite'] = false;
        j.remove('cloudPath');
        final t = Track.fromJson(j);
        // Файлы друга лежат у него — у меня они не сыграют.
        if (t.source == TrackSource.local) continue;
        if (!t.hiddenFromFriends) out.add(t);
      } catch (_) {}
    }
    out.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return out;
  }
}
