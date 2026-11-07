import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'package:http/http.dart' as http;

import 'hutred_server.dart';
import 'relay.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import 'library_store.dart';
import 'wave_service.dart';
import 'settings_store.dart';

/// Аккаунты (Supabase) и синхронизация медиатеки между устройствами.
/// Треки с YouTube, SoundCloud и по ссылкам доступны на любом устройстве.
/// Локальные файлы синхронизируются как записи, но играют только там,
/// где лежит сам файл.
class AccountService extends ChangeNotifier {
  AccountService({required this.store, this.settings});

  final LibraryStore store;

  /// Сюда передаются общие настройки, которые задал админ.
  final SettingsStore? settings;

  String? _username;
  String? _avatarUrl;
  String _role = 'user';
  Map<String, dynamic> _config = {};

  /// Логин (показывается под «Hutred»).
  String? get username => _username;
  String? get avatarUrl => _avatarUrl;

  /// Админ видит ИИ, ключи и может применять настройки для всех.
  /// Без облака (только это устройство) хозяин — админ.
  bool get isAdmin => !enabled || _role == 'admin';

  /// Общие настройки от админа.
  Map<String, dynamic> get appConfig => _config;

  /// ИИ-подгонка текста доступна: админу всегда, остальным — если админ разрешил.
  bool get aiAllowed {
    final f = _config['features'];
    return isAdmin || (f is Map && f['aiForEveryone'] == true);
  }

  bool _ready = false;
  bool _syncing = false;
  String? _syncError;
  DateTime? _lastSync;
  Timer? _pushTimer;
  Timer? _pullTimer;
  StreamSubscription<AuthState>? _authSub;

  bool get enabled => HutredConfig.cloudEnabled;
  bool get syncing => _syncing;
  String? get syncError => _syncError;
  DateTime? get lastSync => _lastSync;
  User? get user => _ready ? Supabase.instance.client.auth.currentUser : null;
  bool get signedIn => user != null;
  String? get email => user?.email;

  SupabaseClient get _db => Supabase.instance.client;

  /// Запуск: подключаемся к облаку и открываем медиатеку нужного пользователя.
  Future<void> init() async {
    if (!enabled) {
      await store.load();
      return;
    }
    try {
      await Supabase.initialize(
        url: HutredConfig.supabaseUrl,
        anonKey: HutredConfig.supabaseAnonKey,
      );
      _ready = true;
      store.onTrackRemoved = _onTrackRemoved;
      store.addListener(_scheduleUpload);
    } catch (e) {
      debugPrint('Облако недоступно: $e');
      await store.load();
      return;
    }
    await store.load(userId: user?.id);
    _authSub = _db.auth.onAuthStateChange.listen((s) async {
      if (s.event == AuthChangeEvent.passwordRecovery) _recovery();
      final uid = s.session?.user.id;
      if (uid != store.userId) {
        await store.load(userId: uid);
      }
      if (uid == null) {
        _username = null;
        _avatarUrl = null;
        _role = 'user';
        _config = {};
        settings?.applyShared(const {});
      } else {
        unawaited(refreshProfile());
      }
      notifyListeners();
      if (uid != null) {
        unawaited(syncNow());
        unawaited(refreshFollowed());
      }
    });
    store.addListener(_onLocalChange);
    store.addListener(_schedulePublish);
    _pullTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      if (signedIn) {
        syncNow();
        refreshFollowed();
      }
    });
    if (signedIn) unawaited(refreshFollowed());
    if (signedIn) {
      unawaited(syncNow());
      unawaited(refreshProfile());
    }
  }

  // ---------- Профиль и общие настройки ----------

  /// Загружает логин, аватарку, роль и общие настройки от админа.
  /// Если таблиц ещё нет (не выполнен SQL), просто ничего не меняется.
  Future<void> refreshProfile() async {
    final uid = user?.id;
    if (uid == null) return;
    try {
      final row =
          await _db.from('profiles').select().eq('id', uid).maybeSingle();
      if (row != null) {
        _username = row['username'] as String?;
        _avatarUrl = row['avatar_url'] as String?;
        _role = (row['role'] as String?) ?? 'user';
      }
    } catch (e) {
      debugPrint('[Профиль] $e');
    }
    try {
      final rows = await _db.from('app_config').select('key, value');
      _config = {for (final r in rows) '${r['key']}': r['value']};
      settings?.applyShared(_config);
      _applyRelay();
    } catch (e) {
      debugPrint('[Общие настройки] $e');
    }
    notifyListeners();
    // Админ зашёл — его ключи сразу у всех.
    unawaited(shareAdminKeys());
  }

  /// Адрес сервера-посредника из общих настроек.
  void _applyRelay() {
    final r = _config['relay'];
    final u = r is Map ? '${r['url'] ?? ''}'.trim() : '';
    HutredRelay.url = u.isEmpty ? null : u;
  }

  static final _usernameRe = RegExp(r'^[A-Za-z0-9_.]{3,24}$');

  /// Проверка логина: null — подходит, иначе текст ошибки.
  Future<String?> checkUsername(String name, {bool forSignUp = false}) async {
    if (!_usernameRe.hasMatch(name)) {
      return 'Логин: 3–24 символа, латиница, цифры, точка и _';
    }
    try {
      final rows = await _db.from('profiles').select('id').eq('username', name).limit(1);
      if (rows.isNotEmpty && rows.first['id'] != user?.id) return 'Этот логин уже занят';
    } catch (_) {
      // До входа таблица профилей может быть недоступна — проверим при сохранении.
    }
    return null;
  }

  /// Меняет логин. Возвращает текст ошибки или null.
  Future<String?> updateUsername(String name) async {
    final uid = user?.id;
    if (uid == null) return 'Сначала войди';
    final problem = await checkUsername(name);
    if (problem != null) return problem;
    try {
      await _db.from('profiles').update({
        'username': name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
      _username = name;
      notifyListeners();
      return null;
    } catch (e) {
      final t = e.toString();
      if (t.contains('duplicate') || t.contains('unique')) return 'Этот логин уже занят';
      return 'Не удалось сохранить логин: ${_short(e)}';
    }
  }

  /// Загружает новую аватарку (картинка с компьютера или телефона).
  Future<String?> uploadAvatar(String filePath) async {
    final uid = user?.id;
    if (uid == null) return 'Сначала войди';
    try {
      final file = File(filePath);
      if (await file.length() > 5 * 1024 * 1024) return 'Картинка больше 5 МБ';
      final dot = filePath.lastIndexOf('.');
      final ext = dot < 0 ? 'png' : filePath.substring(dot + 1).toLowerCase();
      if (!const {'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(ext)) {
        return 'Нужна картинка jpg, png, webp или gif';
      }
      final path = '$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _db.storage.from('avatars').uploadBinary(
            path,
            await file.readAsBytes(),
            fileOptions: FileOptions(upsert: true, contentType: _imageType(ext)),
          );
      final url = _db.storage.from('avatars').getPublicUrl(path);
      await _db.from('profiles').update({
        'avatar_url': url,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
      _avatarUrl = url;
      notifyListeners();
      return null;
    } catch (e) {
      return 'Не удалось загрузить аватарку: ${_short(e)}';
    }
  }

  /// Своя обложка трека: загружается в облако, чтобы была на всех устройствах.
  /// Без аккаунта копируется в папку приложения. Возвращает ссылку или путь.
  Future<String> saveCover(String filePath, String trackId) async {
    final dot = filePath.lastIndexOf('.');
    final ext = dot < 0 ? 'jpg' : filePath.substring(dot + 1).toLowerCase();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final uid = user?.id;
    if (uid != null) {
      try {
        final path = '$uid/covers/${trackId}_$stamp.$ext';
        await _db.storage.from('avatars').uploadBinary(
              path,
              await File(filePath).readAsBytes(),
              fileOptions: FileOptions(upsert: true, contentType: _imageType(ext)),
            );
        return _db.storage.from('avatars').getPublicUrl(path);
      } catch (e) {
        debugPrint('[Обложка] $e');
      }
    }
    final dir = await getApplicationSupportDirectory();
    final sep = Platform.pathSeparator;
    final folder = Directory('${dir.path}${sep}covers');
    await folder.create(recursive: true);
    final copy = await File(filePath).copy('${folder.path}$sep${trackId}_$stamp.$ext');
    return copy.path;
  }

  // ---------- Плейлисты: ссылки, подписки ----------

  static const playlistLinkPrefix = 'hutred://playlist/';

  Timer? _publishTimer;
  String _lastPublished = '';

  /// Свои плейлисты сами выкладываются в облако (через несколько секунд после
  /// изменения): у друзей и у тех, кто подписан по ссылке, они обновляются сами.
  void _schedulePublish() {
    if (!signedIn) return;
    _publishTimer?.cancel();
    _publishTimer = Timer(const Duration(seconds: 6), () => unawaited(publishPlaylists()));
  }

  Map<String, dynamic> _row(Playlist p, String uid) => {
        'id': p.id,
        'owner': uid,
        'owner_name': username ?? '',
        'name': p.name,
        'description': p.description,
        'cover': (p.cover ?? '').startsWith('http') ? p.cover : null,
        // Свои файлы без копии в облаке другим не сыграть — их не передаём.
        'tracks': [
          for (final t in store.tracksOf(p))
            if (t.source != TrackSource.local || t.cloudPath != null) t.toJson(),
        ],
      };

  Future<void> publishPlaylists() async {
    final uid = user?.id;
    if (uid == null) return;
    final own = store.playlists.where((p) => !p.isFollowed).toList();
    final rows = [for (final p in own) _row(p, uid)];
    final key = jsonEncode(rows);
    if (key == _lastPublished) return;
    try {
      if (rows.isNotEmpty) {
        await _db.from('shared_playlists').upsert([
          for (final r in rows) {...r, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        ]);
      }
      // Удалённые плейлисты убираем и из облака.
      final ids = own.map((p) => p.id).toList();
      final existing = await _db.from('shared_playlists').select('id').eq('owner', uid);
      final gone = [
        for (final r in existing)
          if (!ids.contains('${r['id']}')) '${r['id']}',
      ];
      if (gone.isNotEmpty) {
        await _db.from('shared_playlists').delete().inFilter('id', gone);
      }
      _lastPublished = key;
    } catch (e) {
      debugPrint('[Плейлисты] выложить не удалось: $e');
    }
  }

  /// Ссылка на плейлист. Ссылка постоянная: по ней всегда последняя версия.
  Future<String> sharePlaylist(Playlist p, List<Track> tracks) async {
    final uid = user?.id;
    if (uid == null) throw Exception('Чтобы делиться, войди в аккаунт');
    if (p.isFollowed) return '$playlistLinkPrefix${p.followId}';
    await _db.from('shared_playlists').upsert(
        {..._row(p, uid), 'updated_at': DateTime.now().toUtc().toIso8601String()});
    return '$playlistLinkPrefix${p.id}';
  }

  static ({String id, String name, String description, String? cover, String owner, List<Track> tracks})
      _parseShared(Map row) => (
            id: '${row['id']}',
            name: '${row['name'] ?? 'Плейлист'}',
            description: '${row['description'] ?? ''}',
            cover: row['cover'] as String?,
            owner: '${row['owner_name'] ?? ''}',
            tracks: [
              for (final t in (row['tracks'] as List? ?? const []))
                if (t is Map) Track.fromJson(Map<String, dynamic>.from(t)),
            ],
          );

  /// Плейлист по ссылке hutred://playlist/<id>.
  Future<({String id, String name, String description, String? cover, String owner, List<Track> tracks})>
      fetchSharedPlaylist(String link) async {
    final id = link.trim().substring(playlistLinkPrefix.length).split(RegExp(r'[/?#\s]')).first;
    final row = await _db.from('shared_playlists').select().eq('id', id).maybeSingle();
    if (row == null) throw Exception('Плейлист не найден — возможно, автор его удалил');
    return _parseShared(row);
  }

  /// Плейлисты пользователя (для страницы друга).
  Future<List<({String id, String name, String description, String? cover, String owner, List<Track> tracks})>>
      playlistsOfUser(String userId) async {
    final rows = await _db
        .from('shared_playlists')
        .select()
        .eq('owner', userId)
        .order('updated_at', ascending: false);
    return [
      for (final r in rows)
        if ((r['tracks'] as List? ?? const []).isNotEmpty) _parseShared(r),
    ];
  }

  /// Подписки обновляем из облака: что поменял автор — то и у тебя.
  Future<void> refreshFollowed() async {
    final ids = [
      for (final p in store.playlists)
        if (p.followId != null) p.followId!,
    ];
    if (ids.isEmpty || !signedIn) return;
    try {
      final rows = await _db.from('shared_playlists').select().inFilter('id', ids);
      for (final r in rows) {
        final sp = _parseShared(r);
        store.refreshFollowed(sp.id,
            name: sp.name,
            description: sp.description,
            cover: sp.cover,
            owner: sp.owner.isEmpty ? null : sp.owner,
            tracks: sp.tracks);
      }
    } catch (e) {
      debugPrint('[Плейлисты] обновить подписки не удалось: $e');
    }
  }

  /// Админ: свои ключи Spotify и ИИ (и Discord ID) сразу раздаются всем,
  /// без отдельной кнопки. ИИ-подгонка текста тоже включается всем.
  Future<void> shareAdminKeys() async {
    final s = settings;
    if (s == null || !enabled || !signedIn || !isAdmin) return;
    await _loadSecrets();
    bool differs(String group, Map<String, dynamic> want) {
      final have = _secretKeys.contains(group) ? _secrets[group] : _config[group];
      if (have is! Map) return true;
      return want.entries.any((e) => '${have[e.key] ?? ''}' != '${e.value}');
    }

    if (s.ownSpotifyId.isNotEmpty) {
      final want = {'id': s.ownSpotifyId, 'secret': s.ownSpotifySecret};
      if (differs('spotify', want)) await pushConfig('spotify', want);
    }
    if (s.ownAiKey.isNotEmpty) {
      final want = {'baseUrl': s.ownAiBaseUrl, 'key': s.ownAiKey, 'model': s.ownAiModel};
      if (differs('ai', want)) await pushConfig('ai', want);
      if (differs('features', {'aiForEveryone': true})) {
        await pushConfig('features', {'aiForEveryone': true});
      }
    }
    if (s.ownDiscordAppId.isNotEmpty) {
      final want = {'appId': s.ownDiscordAppId};
      if (differs('discord', want)) await pushConfig('discord', want);
    }
  }

  /// Группы с секретами: они уходят в app_secrets (их видит только админ
  /// и сервер), а всем остальным — только флажок «включено».
  static const _secretKeys = {'ai', 'spotify'};
  Map<String, dynamic> _secrets = const {};

  Future<void> _loadSecrets() async {
    if (!isAdmin) return;
    try {
      final rows = await _db.from('app_secrets').select('key, value');
      _secrets = {for (final r in rows) '${r['key']}': r['value']};
    } catch (e) {
      debugPrint('[Секреты] $e');
    }
  }

  /// Админ: сохранить общую настройку для всех пользователей.
  Future<String?> pushConfig(String key, Map<String, dynamic> value) async {
    if (!isAdmin) return 'Это может только админ';
    if (_secretKeys.contains(key)) {
      final filled = value.values.any((v) => '$v'.trim().isNotEmpty);
      try {
        await _db.from('app_secrets').upsert({
          'key': key,
          'value': value,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
        _secrets = {..._secrets, key: value};
      } catch (e) {
        return 'Не удалось сохранить ключ: ${_short(e)}. Выполни supabase/security.sql';
      }
      value = {'enabled': filled};
    }
    try {
      await _db.from('app_config').upsert({
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      _config = {..._config, key: value};
      settings?.applyShared(_config);
      _applyRelay();
      notifyListeners();
      return null;
    } catch (e) {
      return 'Не удалось сохранить: ${_short(e)}';
    }
  }

  // ---------- Вход ----------

  /// Куда ведут ссылки из писем: приложение открывает их само.
  static const authRedirect = 'hutred://auth';

  /// Вход по почте или логину. Через сервер Hutred — там лимит попыток
  /// и поиск почты по логину (почты других людей приложению не видны).
  Future<void> signIn(String login, String password) async {
    final l = login.trim();
    http.Response? res;
    try {
      res = await http
          .post(HutredServer.fn('login'),
              headers: {'apikey': HutredConfig.supabaseAnonKey, 'Content-Type': 'application/json'},
              body: jsonEncode({'login': l, 'password': password}))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      res = null;
    }
    if (res != null && res.statusCode == 200) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      await _db.auth.setSession(j['refresh_token'] as String);
      return;
    }
    if (res != null && res.statusCode != 404) {
      throw AuthException(HutredServer.errorOf(res.body, res.statusCode));
    }
    // Функция ещё не выложена или сервер недоступен — входим напрямую по почте.
    if (!l.contains('@')) throw const AuthException('Войди по почте: вход по логину пока недоступен');
    await _db.auth.signInWithPassword(email: l, password: password);
  }

  /// Новый пароль (после ссылки «сбросить пароль» или из аккаунта).
  Future<void> changePassword(String password) async {
    await _db.auth.updateUser(UserAttributes(password: password));
  }

  /// Пароль достаточно надёжный? null — да, иначе что не так.
  static String? weakPassword(String p) {
    if (p.length < 8) return 'Пароль — от 8 символов';
    if (!RegExp(r'[A-Za-zА-Яа-яЁё]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) {
      return 'В пароле нужны и буквы, и цифры';
    }
    return null;
  }

  /// Пришла ссылка «сбросить пароль» — показываем окно нового пароля.
  void Function()? _onRecovery;
  bool _recoveryPending = false;
  set onPasswordRecovery(void Function()? f) {
    _onRecovery = f;
    if (f != null && _recoveryPending) {
      _recoveryPending = false;
      f();
    }
  }

  void _recovery() {
    final f = _onRecovery;
    if (f == null) {
      _recoveryPending = true;
    } else {
      f();
    }
  }

  /// Возвращает true, если нужно подтвердить почту по письму.
  Future<bool> signUp(String email, String password, {String? username}) async {
    final res = await _db.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: authRedirect,
      data: {if (username != null && username.isNotEmpty) 'username': username},
    );
    return res.session == null;
  }

  Future<void> resetPassword(String email) =>
      _db.auth.resetPasswordForEmail(email.trim(), redirectTo: authRedirect);

  Future<void> signOut() async {
    await syncNow();
    await _db.auth.signOut();
  }

  /// Перенести треки, добавленные без входа, в свой аккаунт.
  Future<int> importGuestLibrary() async {
    final guest = LibraryStore();
    await guest.load();
    final added = store.addTracks(guest.tracks);
    for (final p in guest.playlists) {
      if (store.playlistById(p.id) == null) {
        final np = store.createPlaylist(p.name);
        store.addToPlaylist(np.id, p.trackIds);
      }
    }
    return added;
  }

  // ---------- Синхронизация ----------

  /// Вызывается, когда свои изменения ушли в облако (для мгновенной синхронизации).
  VoidCallback? onPushed;

  /// Скрытые треки и чёрный список волны — тоже синхронизируются.
  WaveService? _wave;
  bool _waveDirty = false;
  static const _waveItem = '__wave__';

  set wave(WaveService w) {
    _wave = w;
    // При запуске отправляем своё (старые скрытые ещё не были в облаке).
    _waveDirty = true;
    if (signedIn) _onLocalChange();
    w.onSyncChange = () {
      _waveDirty = true;
      _onLocalChange();
    };
  }

  void _onLocalChange() {
    if (!signedIn) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 3), syncNow);
  }

  Future<File> _stateFile(String uid) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}sync_$uid.json');
  }

  Future<({DateTime? pushed, DateTime? pulled})> _readState(String uid) async {
    try {
      final f = await _stateFile(uid);
      if (!await f.exists()) return (pushed: null, pulled: null);
      final j = jsonDecode(await f.readAsString()) as Map;
      return (
        pushed: DateTime.tryParse('${j['pushed']}'),
        pulled: DateTime.tryParse('${j['pulled']}'),
      );
    } catch (_) {
      return (pushed: null, pulled: null);
    }
  }

  Future<void> _writeState(String uid, DateTime? pushed, DateTime? pulled) async {
    try {
      await (await _stateFile(uid)).writeAsString(jsonEncode({
        'pushed': pushed?.toIso8601String(),
        'pulled': pulled?.toIso8601String(),
      }));
    } catch (_) {}
  }

  Future<void> syncNow() async {
    final uid = user?.id;
    if (uid == null || _syncing) return;
    _syncing = true;
    _syncError = null;
    notifyListeners();
    try {
      final state = await _readState(uid);
      final started = DateTime.now().toUtc();

      // 1. Забираем изменения с других устройств.
      var query = _db.from('library_items').select().eq('user_id', uid);
      if (state.pulled != null) {
        query = query.gt('updated_at', state.pulled!.toIso8601String());
      }
      final rows = await query.order('updated_at').limit(5000);
      var pulled = state.pulled;
      final remote = <SyncRecord>[];
      for (final r in rows) {
        final at = DateTime.parse('${r['updated_at']}').toUtc();
        if (r['item_id'] == _waveItem) {
          if (pulled == null || at.isAfter(pulled)) pulled = at;
          continue;
        }
        remote.add(SyncRecord(
          '${r['kind']}',
          '${r['item_id']}',
          r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : null,
          r['deleted'] == true,
          at,
        ));
        if (pulled == null || at.isAfter(pulled)) pulled = at;
      }
      store.applyRemote(remote);

      // Скрытые треки и чёрный список — одна маленькая запись, читаем всегда.
      if (_wave != null) {
        final w = await _db
            .from('library_items')
            .select('data')
            .eq('user_id', uid)
            .eq('item_id', _waveItem)
            .maybeSingle();
        if (w != null && w['data'] is Map) {
          await _wave!.mergeRemote(Map<String, dynamic>.from(w['data'] as Map));
        }
      }

      // 2. Отправляем свои изменения.
      final local = store.changesSince(state.pushed);
      for (var i = 0; i < local.length; i += 200) {
        final chunk = local.sublist(i, i + 200 > local.length ? local.length : i + 200);
        await _db.from('library_items').upsert([
          for (final r in chunk)
            {
              'user_id': uid,
              'kind': r.kind,
              'item_id': r.id,
              'data': r.data,
              'deleted': r.deleted,
              'updated_at': r.updatedAt.toIso8601String(),
            }
        ]);
      }
      final pushedWave = _wave != null && (_waveDirty || state.pushed == null);
      if (_wave != null && (_waveDirty || state.pushed == null)) {
        _waveDirty = false;
        await _db.from('library_items').upsert({
          'user_id': uid,
          'kind': 'playlist',
          'item_id': _waveItem,
          'data': _wave!.syncData(),
          'deleted': false,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
      await _writeState(uid, started, pulled);
      // Другие мои устройства сразу заберут изменения, не дожидаясь таймера.
      if (local.isNotEmpty || pushedWave) onPushed?.call();
      _lastSync = DateTime.now();
    } catch (e) {
      _syncError = 'Не удалось синхронизировать: ${_short(e)}';
      debugPrint('[Облако] $e');
    } finally {
      _syncing = false;
      notifyListeners();
    }
    unawaited(uploadLocalFiles());
  }

  // ---------- Облако для своих файлов ----------

  static const _maxCloudFile = 50 * 1024 * 1024;
  bool _uploading = false;
  int _uploadLeft = 0;
  String? _uploadError;
  Timer? _uploadTimer;
  final Set<String> _skipUpload = {};

  bool get uploading => _uploading;
  int get uploadLeft => _uploadLeft;
  String? get uploadError => _uploadError;

  int get localFiles => store.tracks.where((t) => t.source == TrackSource.local).length;
  int get cloudFiles => store.tracks
      .where((t) => t.source == TrackSource.local && t.cloudPath != null)
      .length;

  void _scheduleUpload() {
    if (_uploading || user == null) return;
    _uploadTimer?.cancel();
    _uploadTimer = Timer(const Duration(seconds: 5), () => uploadLocalFiles());
  }

  /// Загружает в облако свои файлы, у которых ещё нет копии.
  Future<void> uploadLocalFiles() async {
    final uid = user?.id;
    if (uid == null || _uploading || settings?.cloudFiles == false) return;
    final todo = store.tracks
        .where((t) =>
            t.source == TrackSource.local &&
            t.cloudPath == null &&
            !_skipUpload.contains(t.id) &&
            File(t.uri).existsSync())
        .toList();
    if (todo.isEmpty) return;
    _uploading = true;
    _uploadLeft = todo.length;
    _uploadError = null;
    notifyListeners();
    try {
      for (final t in todo) {
        if (user?.id != uid || settings?.cloudFiles == false) break;
        try {
          final file = File(t.uri);
          if (await file.length() > _maxCloudFile) {
            _skipUpload.add(t.id);
            _uploadError = 'Файлы больше 50 МБ не загружаются в облако';
            continue;
          }
          final dot = t.uri.lastIndexOf('.');
          final ext = dot < 0 ? 'mp3' : t.uri.substring(dot + 1).toLowerCase();
          final path = '$uid/${t.id}.$ext';
          await _db.storage
              .from('tracks')
              .upload(path, file, fileOptions: FileOptions(upsert: true, contentType: _audioType(ext)));
          final fresh = store.byId(t.id);
          if (fresh != null) store.updateTrack(fresh.copyWith(cloudPath: path));
        } catch (e) {
          _skipUpload.add(t.id);
          _uploadError = 'Не удалось загрузить «${t.title}»: ${_short(e)}';
          debugPrint('[Облако файлов] $e');
        } finally {
          _uploadLeft--;
          notifyListeners();
        }
      }
    } finally {
      _uploading = false;
      _uploadLeft = 0;
      notifyListeners();
    }
    // Новые записи (cloudPath) — сразу на другие устройства.
    unawaited(syncNow());
  }

  /// Путь к файлу трека: скачивает копию из облака в кэш, если её ещё нет.
  Future<String?> cloudFileFor(Track t) async {
    final path = t.cloudPath;
    if (path == null || user == null) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      final sep = Platform.pathSeparator;
      final folder = Directory('${dir.path}${sep}cloud_tracks');
      await folder.create(recursive: true);
      final local = File('${folder.path}$sep${path.split('/').last}');
      if (await local.exists() && await local.length() > 0) return local.path;
      final bytes = await _db.storage.from('tracks').download(path);
      await local.writeAsBytes(bytes, flush: true);
      return local.path;
    } catch (e) {
      debugPrint('[Облако файлов] $e');
      return null;
    }
  }

  void _onTrackRemoved(Track t) {
    final path = t.cloudPath;
    if (path == null || user == null) return;
    _db.storage.from('tracks').remove([path]).ignore();
  }

  /// Облако принимает только картинки jpeg/png/webp/gif.
  static String _imageType(String ext) => switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };

  /// Облако принимает только звук.
  static String _audioType(String ext) => switch (ext) {
        'mp3' => 'audio/mpeg',
        'm4a' || 'mp4' || 'aac' => 'audio/mp4',
        'flac' => 'audio/flac',
        'wav' => 'audio/wav',
        'ogg' || 'opus' => 'audio/ogg',
        'webm' || 'weba' => 'audio/webm',
        _ => 'audio/mpeg',
      };

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 140 ? '${s.substring(0, 140)}…' : s;
  }

  /// Понятный текст ошибки входа.
  static String authError(Object e) {
    final s = e.toString().toLowerCase();
    if (e is AuthException && !s.contains('invalid login') && !s.contains('email not confirmed')) {
      final m = e.message;
      if (RegExp(r'[А-Яа-яЁё]').hasMatch(m)) return m;
    }
    if (s.contains('invalid login')) return 'Неверный логин или пароль';
    if (s.contains('same_password') || s.contains('different from the old')) {
      return 'Новый пароль совпадает со старым';
    }
    if (s.contains('weak_password') || s.contains('weak password')) return 'Пароль слишком простой';
    if (s.contains('email not confirmed')) {
      return 'Почта не подтверждена. Открой письмо от Supabase и нажми ссылку';
    }
    if (s.contains('already registered')) return 'Такой аккаунт уже есть — войди';
    if (s.contains('password should be')) return 'Пароль слишком короткий';
    if (s.contains('rate limit')) return 'Слишком много попыток, подожди минуту';
    if (s.contains('socket') || s.contains('host lookup')) {
      return 'Нет связи с сервером. Проверь интернет или VPN';
    }
    return _short(e);
  }

  @override
  void dispose() {
    _pushTimer?.cancel();
    _pullTimer?.cancel();
    _authSub?.cancel();
    store.removeListener(_onLocalChange);
    super.dispose();
  }
}
