import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Готовый набор фоновых цветов.
class BackgroundPreset {
  const BackgroundPreset(this.id, this.name, this.ink, this.surface, this.raised);
  final String id;
  final String name;
  final Color ink;
  final Color surface;
  final Color raised;
}

const backgroundPresets = [
  BackgroundPreset('midnight', 'Полночь', Color(0xFF0D0F14), Color(0xFF151821), Color(0xFF1D212D)),
  BackgroundPreset('black', 'Чёрный', Color(0xFF000000), Color(0xFF0E0E0E), Color(0xFF1A1A1A)),
  BackgroundPreset('graphite', 'Графит', Color(0xFF18181A), Color(0xFF222225), Color(0xFF2D2D31)),
  BackgroundPreset('ocean', 'Океан', Color(0xFF09131F), Color(0xFF0F1D2E), Color(0xFF17293F)),
  BackgroundPreset('plum', 'Слива', Color(0xFF150D1B), Color(0xFF201528), Color(0xFF2C1E37)),
  BackgroundPreset('forest', 'Лес', Color(0xFF0B140F), Color(0xFF122019), Color(0xFF1B2C23)),
  BackgroundPreset('wine', 'Вино', Color(0xFF1A0B0E), Color(0xFF261216), Color(0xFF341A20)),
];

const accentPresets = <Color>[
  Color(0xFFFFB547), // янтарь
  Color(0xFF1ED760), // зелёный
  Color(0xFFFF4D5E), // красный
  Color(0xFFFF5FA2), // розовый
  Color(0xFFA78BFA), // фиолетовый
  Color(0xFF4DA3FF), // синий
  Color(0xFF2DD4BF), // бирюза
  Color(0xFFEDEDED), // белый
];

/// Настройки приложения: цвета и источники текстов/обложек.
class SettingsStore extends ChangeNotifier {
  Color _accent = accentPresets.first;
  String _backgroundId = backgroundPresets.first.id;
  bool _youtubeLyrics = true;
  bool _geniusLyrics = true;
  bool _geniusCovers = true;
  bool _replaceYoutubeCovers = true;
  String _youtubeCookiesBrowser = '';
  double _volume = 1.0;
  bool _fullscreenCover = true;
  bool _fullscreenLyrics = true;
  bool _queuePanel = false;
  static const defaultNavOrder = [
    'wave', 'library', 'search', 'playlists', 'friends', 'transfer', 'settings'
  ];
  List<String> _navOrder = List.of(defaultNavOrder);

  /// Скрытые вкладки. null — ещё не настраивали: на телефоне по умолчанию
  /// видны только Волна, Медиатека, Плейлисты и Настройки.
  Set<String>? _hiddenTabs;
  static bool get _phone => Platform.isAndroid || Platform.isIOS;
  static const _phoneHidden = {'search', 'friends', 'transfer'};
  String? _waveBackground;
  Set<String> _searchSources = {'library', 'spotify', 'soundcloud', 'youtube'};
  final List<String> _searchHistory = [];
  String _aiBaseUrl = 'https://api.groq.com/openai/v1';
  String _aiKey = '';
  String _aiModel = 'whisper-large-v3';
  String _spotifyId = '';
  String _spotifySecret = '';
  bool _tintFromCover = true;
  bool _cloudFiles = true;
  bool _spotifyCheck = true;
  bool _autoFavorite = true;
  bool _discordPresence = true;
  bool? _dpiBypass;
  bool _autoUpdate = true;
  bool _closeToTray = true;
  bool _crossfade = false;
  int _crossfadeSec = 6;
  bool _fadePause = true;
  bool _guest = false;
  bool _dnsOnly = false;
  bool _pickArtists = false;
  String _discordAppId = '';
  File? _file;

  Color get accent => _accent;
  BackgroundPreset get background {
    if (_backgroundId == 'custom') return customBackground;
    return backgroundPresets.firstWhere((b) => b.id == _backgroundId,
        orElse: () => backgroundPresets.first);
  }

  /// Свой цвет фона: из него делаются три оттенка (фон, панели, карточки).
  Color _customBg = const Color(0xFF14121C);
  Color get customBgColor => _customBg;

  BackgroundPreset get customBackground {
    final hsl = HSLColor.fromColor(_customBg);
    Color lift(double d) =>
        hsl.withLightness((hsl.lightness + d).clamp(0.0, 1.0)).toColor();
    return BackgroundPreset('custom', 'Свой цвет', _customBg, lift(0.04), lift(0.09));
  }

  set customBgColor(Color c) {
    // Фон тёмный: светлые цвета приглушаем, чтобы читался белый текст.
    final hsl = HSLColor.fromColor(c.withAlpha(255));
    _customBg = hsl.withLightness(hsl.lightness.clamp(0.0, 0.22)).toColor();
    _backgroundId = 'custom';
    _save();
  }
  bool get youtubeLyrics => _youtubeLyrics;
  bool get geniusLyrics => _geniusLyrics;
  bool get geniusCovers => _geniusCovers;

  /// Менять превью YouTube (16:9, часто с надписями) на обложку с Genius.
  bool get replaceYoutubeCovers => _replaceYoutubeCovers;

  /// Подкрашивать экран плеера под цвет обложки.
  bool get tintFromCover => _tintFromCover;

  /// Загружать свои файлы в облако, чтобы они были на всех устройствах.
  bool get cloudFiles => _cloudFiles;

  /// Сверять новые треки с YouTube/SoundCloud со Spotify и предлагать
  /// подставить точные название, исполнителя и обложку.
  bool get spotifyCheck => _spotifyCheck;

  /// Добавленные в медиатеку треки сразу отмечаются ♥ (как в Spotify).
  bool get autoFavorite => _autoFavorite;

  /// Обход блокировок (как zapret) для трафика Hutred.
  /// По умолчанию включён, если похоже, что компьютер в России
  /// (русский язык системы и московское время).
  bool get dpiBypass =>
      _dpiBypass ??
      (Platform.localeName.toLowerCase().contains('ru') &&
          DateTime.now().timeZoneOffset == const Duration(hours: 3));
  set dpiBypass(bool v) {
    _dpiBypass = v;
    _save();
  }

  /// Плавный переход между треками, как в Spotify.
  bool get crossfade => _crossfade;
  set crossfade(bool v) {
    _crossfade = v;
    _save();
  }

  /// Длительность перехода, секунды (1–12).
  int get crossfadeSec => _crossfadeSec;
  set crossfadeSec(int v) {
    _crossfadeSec = v.clamp(1, 12);
    _save();
  }

  /// Обход в режиме «только безопасный DNS» (без разрезания соединения).
  bool get dnsOnly => _dnsOnly;
  set dnsOnly(bool v) {
    _dnsOnly = v;
    _save();
  }

  /// Пользователь выбрал «без аккаунта» на приветственном экране.
  bool get guest => _guest;
  set guest(bool v) {
    _guest = v;
    _save();
  }

  /// Только что зарегистрировался — спросить любимых исполнителей.
  bool get pickArtists => _pickArtists;
  set pickArtists(bool v) {
    _pickArtists = v;
    _save();
  }

  /// Пауза и продолжение плавно, без резкого обрыва звука.
  bool get fadePause => _fadePause;
  set fadePause(bool v) {
    _fadePause = v;
    _save();
  }

  /// Крестик прячет окно в трей, музыка продолжает играть.
  bool get closeToTray => _closeToTray;
  set closeToTray(bool v) {
    _closeToTray = v;
    _save();
  }

  /// Обновляться автоматически (на Windows — тихо ставить новую версию).
  bool get autoUpdate => _autoUpdate;
  set autoUpdate(bool v) {
    _autoUpdate = v;
    _save();
  }

  /// Статус «Слушает Hutred» в Discord.
  bool get discordPresence => _discordPresence;
  set discordPresence(bool v) {
    _discordPresence = v;
    _save();
  }

  /// Application ID приложения в Discord Developer Portal
  /// (свой или тот, что админ раздал всем).
  String get discordAppId =>
      _discordAppId.isNotEmpty ? _discordAppId : _sharedStr('discord', 'appId');
  String get ownDiscordAppId => _discordAppId;
  set discordAppId(String v) {
    _discordAppId = v.trim();
    _save();
  }
  set autoFavorite(bool v) {
    _autoFavorite = v;
    _save();
  }
  set spotifyCheck(bool v) {
    _spotifyCheck = v;
    _save();
  }
  set cloudFiles(bool v) {
    _cloudFiles = v;
    _save();
  }

  /// Браузер, где выполнен вход в YouTube: firefox, chrome, edge или ''.
  String get youtubeCookiesBrowser => _youtubeCookiesBrowser;

  set youtubeCookiesBrowser(String v) {
    _youtubeCookiesBrowser = v;
    _save();
  }

  /// Свой фон вкладки «Волна» (путь к картинке или GIF), null — без фона.
  String? get waveBackground =>
      (_waveBackground != null && File(_waveBackground!).existsSync())
          ? _waveBackground
          : null;

  /// Копирует выбранную картинку к себе (оригинал можно удалить).
  Future<void> setWaveBackground(String? sourcePath) async {
    final old = _waveBackground;
    if (sourcePath == null) {
      _waveBackground = null;
    } else {
      final dir = await getApplicationSupportDirectory();
      final dot = sourcePath.lastIndexOf('.');
      final ext = dot < 0 ? 'png' : sourcePath.substring(dot + 1).toLowerCase();
      // Новое имя каждый раз, чтобы картинка не бралась из старого кэша.
      final target =
          '${dir.path}${Platform.pathSeparator}wave_bg_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(sourcePath).copy(target);
      _waveBackground = target;
    }
    await _save();
    if (old != null && old != _waveBackground) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
  }

  /// Порядок вкладок в боковой/нижней панели.
  List<String> get navOrder => List.unmodifiable(_navOrder);

  Set<String> get hiddenTabs => _hiddenTabs ?? (_phone ? _phoneHidden : const {});

  /// Вкладки, которые видны на панели (Настройки скрыть нельзя).
  List<String> get visibleNav =>
      _navOrder.where((t) => t == 'settings' || !hiddenTabs.contains(t)).toList();

  bool isTabHidden(String id) => id != 'settings' && hiddenTabs.contains(id);

  void setTabHidden(String id, bool hidden) {
    if (id == 'settings') return;
    final h = Set.of(hiddenTabs);
    hidden ? h.add(id) : h.remove(id);
    _hiddenTabs = h;
    _save();
  }

  void reorderNav(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final id = _navOrder.removeAt(oldIndex);
    _navOrder.insert(newIndex, id);
    _save();
  }

  void resetNavOrder() {
    _navOrder = List.of(defaultNavOrder);
    _hiddenTabs = null;
    _save();
  }

  /// Панель очереди справа в полноэкранном плеере (на компьютере).
  bool get queuePanel => _queuePanel;

  set queuePanel(bool v) {
    _queuePanel = v;
    _save();
  }

  /// Показывать обложку слева в полноэкранном плеере (на компьютере).
  bool get fullscreenCover => _fullscreenCover;

  /// Показывать текст в полноэкранном плеере (кнопка «Текст» прячет только его).
  bool get fullscreenLyrics => _fullscreenLyrics;
  set fullscreenLyrics(bool v) {
    _fullscreenLyrics = v;
    _save();
  }

  set fullscreenCover(bool v) {
    _fullscreenCover = v;
    _save();
  }

  /// Громкость плеера 0..1 — запоминается между запусками.
  double get volume => _volume;

  set volume(double v) {
    _volume = v.clamp(0.0, 1.0);
    _saveSoon();
  }

  Timer? _volumeTimer;

  // Ползунок двигается часто — пишем на диск не чаще раза в полсекунды.
  void _saveSoon() {
    _volumeTimer?.cancel();
    _volumeTimer = Timer(const Duration(milliseconds: 500), _save);
  }

  /// Где искать: library, soundcloud, youtube.
  Set<String> get searchSources => Set.unmodifiable(_searchSources);

  void toggleSearchSource(String s) {
    if (_searchSources.contains(s)) {
      if (_searchSources.length > 1) _searchSources.remove(s);
    } else {
      _searchSources.add(s);
    }
    _save();
  }

  List<String> get searchHistory => List.unmodifiable(_searchHistory);

  void rememberQuery(String q) {
    q = q.trim();
    if (q.length < 2) return;
    _searchHistory.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    _searchHistory.insert(0, q);
    if (_searchHistory.length > 15) _searchHistory.removeLast();
    _save();
  }

  void forgetQuery(String q) {
    _searchHistory.remove(q);
    _save();
  }

  void clearHistory() {
    _searchHistory.clear();
    _save();
  }

  /// Общие настройки, которые админ применил для всех (из облака).
  /// Свои значения важнее: общие используются, только если своих нет.
  Map<String, dynamic> _shared = const {};

  void applyShared(Map<String, dynamic> config) {
    _shared = config;
    notifyListeners();
  }

  String _sharedStr(String group, String key) {
    final g = _shared[group];
    return g is Map ? '${g[key] ?? ''}'.trim() : '';
  }

  bool get _ownAi => _aiKey.isNotEmpty && _aiBaseUrl.isNotEmpty;

  /// ИИ-распознавание речи (OpenAI-совместимый Whisper API).
  String get aiBaseUrl => _ownAi ? _aiBaseUrl : _sharedStr('ai', 'baseUrl');
  String get aiKey => _ownAi ? _aiKey : _sharedStr('ai', 'key');
  String get aiModel {
    final m = _ownAi ? _aiModel : _sharedStr('ai', 'model');
    return m.isEmpty ? 'whisper-large-v3' : m;
  }
  bool get hasAi => aiKey.isNotEmpty && aiBaseUrl.isNotEmpty;

  /// Свои значения (для админа — их он отправляет всем).
  String get ownAiBaseUrl => _aiBaseUrl;
  String get ownAiKey => _aiKey;
  String get ownAiModel => _aiModel;
  String get ownSpotifyId => _spotifyId;
  String get ownSpotifySecret => _spotifySecret;

  void setAi({required String baseUrl, required String key, required String model}) {
    _aiBaseUrl = baseUrl.trim();
    _aiKey = key.trim();
    _aiModel = model.trim().isEmpty ? 'whisper-large-v3' : model.trim();
    _save();
  }

  /// Ключи своего приложения Spotify (для поиска обложек).
  bool get _ownSpotify => _spotifyId.isNotEmpty && _spotifySecret.isNotEmpty;
  String get spotifyId => _ownSpotify ? _spotifyId : _sharedStr('spotify', 'id');
  String get spotifySecret =>
      _ownSpotify ? _spotifySecret : _sharedStr('spotify', 'secret');
  bool get hasSpotifyKeys => spotifyId.isNotEmpty && spotifySecret.isNotEmpty;

  Future<void> load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      _file = File('${dir.path}${Platform.pathSeparator}settings.json');
      if (!await _file!.exists()) return;
      final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
      _accent = Color((j['accent'] as num?)?.toInt() ?? _accent.toARGB32());
      _backgroundId = j['background'] as String? ?? _backgroundId;
      final cb = (j['customBg'] as num?)?.toInt();
      if (cb != null) _customBg = Color(cb);
      _youtubeLyrics = j['youtubeLyrics'] as bool? ?? true;
      _geniusLyrics = j['geniusLyrics'] as bool? ?? true;
      _geniusCovers = j['geniusCovers'] as bool? ?? true;
      _replaceYoutubeCovers = j['replaceYoutubeCovers'] as bool? ?? true;
      _youtubeCookiesBrowser = j['youtubeCookiesBrowser'] as String? ?? '';
      _volume = ((j['volume'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0);
      _waveBackground = j['waveBackground'] as String?;
      _fullscreenCover = j['fullscreenCover'] as bool? ?? true;
      _fullscreenLyrics = j['fullscreenLyrics'] as bool? ?? true;
      _queuePanel = j['queuePanel'] as bool? ?? false;
      final hidden = j['hiddenTabs'] as List?;
      if (hidden != null) _hiddenTabs = hidden.map((e) => '$e').toSet();
      final nav = (j['navOrder'] as List?)?.map((e) => '$e').toList();
      // Сохранённый порядок; новые вкладки встают перед «Настройками».
      if (nav != null) {
        final kept = nav.where(defaultNavOrder.contains).toSet().toList();
        for (final id in defaultNavOrder) {
          if (kept.contains(id)) continue;
          final at = kept.indexOf('settings');
          kept.insert(at < 0 ? kept.length : at, id);
        }
        _navOrder = kept;
      }
      final src = (j['searchSources'] as List?)?.map((e) => '$e').toSet();
      if (src != null && src.isNotEmpty) _searchSources = src;
      // Spotify в поиске появился позже — включаем его один раз у всех.
      if (j['searchSpotifyAdded'] != true) _searchSources.add('spotify');
      _searchHistory
        ..clear()
        ..addAll((j['searchHistory'] as List? ?? const []).map((e) => '$e'));
      _aiBaseUrl = j['aiBaseUrl'] as String? ?? _aiBaseUrl;
      _aiKey = j['aiKey'] as String? ?? '';
      _aiModel = j['aiModel'] as String? ?? _aiModel;
      _spotifyId = j['spotifyId'] as String? ?? '';
      _spotifySecret = j['spotifySecret'] as String? ?? '';
      _tintFromCover = j['tintFromCover'] as bool? ?? true;
      _cloudFiles = j['cloudFiles'] as bool? ?? true;
      _spotifyCheck = j['spotifyCheck'] as bool? ?? true;
      _autoFavorite = j['autoFavorite'] as bool? ?? true;
      _discordPresence = j['discordPresence'] as bool? ?? true;
      _dpiBypass = j['dpiBypass'] as bool?;
      _autoUpdate = j['autoUpdate'] as bool? ?? true;
      _closeToTray = j['closeToTray'] as bool? ?? true;
      _crossfade = j['crossfade'] as bool? ?? false;
      _crossfadeSec = ((j['crossfadeSec'] as num?)?.toInt() ?? 6).clamp(1, 12);
      _fadePause = j['fadePause'] as bool? ?? true;
      _guest = j['guest'] as bool? ?? false;
      _dnsOnly = j['dnsOnly'] as bool? ?? false;
      _pickArtists = j['pickArtists'] as bool? ?? false;
      _discordAppId = j['discordAppId'] as String? ?? '';
    } catch (e) {
      debugPrint('Не удалось прочитать настройки: $e');
    }
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      await _file?.writeAsString(jsonEncode({
        'accent': _accent.toARGB32(),
        'background': _backgroundId,
        'customBg': _customBg.toARGB32(),
        'youtubeLyrics': _youtubeLyrics,
        'geniusLyrics': _geniusLyrics,
        'geniusCovers': _geniusCovers,
        'replaceYoutubeCovers': _replaceYoutubeCovers,
        'tintFromCover': _tintFromCover,
        'cloudFiles': _cloudFiles,
        'spotifyCheck': _spotifyCheck,
        'autoFavorite': _autoFavorite,
        'discordPresence': _discordPresence,
        if (_dpiBypass != null) 'dpiBypass': _dpiBypass,
        'autoUpdate': _autoUpdate,
        'closeToTray': _closeToTray,
        'crossfade': _crossfade,
        'crossfadeSec': _crossfadeSec,
        'fadePause': _fadePause,
        'guest': _guest,
        'dnsOnly': _dnsOnly,
        'pickArtists': _pickArtists,
        'discordAppId': _discordAppId,
        'youtubeCookiesBrowser': _youtubeCookiesBrowser,
        'volume': _volume,
        'waveBackground': _waveBackground,
        'fullscreenCover': _fullscreenCover,
        'fullscreenLyrics': _fullscreenLyrics,
        'queuePanel': _queuePanel,
        'navOrder': _navOrder,
        if (_hiddenTabs != null) 'hiddenTabs': _hiddenTabs!.toList(),
        'searchSources': _searchSources.toList(),
        'searchSpotifyAdded': true,
        'searchHistory': _searchHistory,
        'aiBaseUrl': _aiBaseUrl,
        'aiKey': _aiKey,
        'aiModel': _aiModel,
        'spotifyId': _spotifyId,
        'spotifySecret': _spotifySecret,
      }));
    } catch (e) {
      debugPrint('Не удалось сохранить настройки: $e');
    }
  }

  set accent(Color c) {
    _accent = c.withAlpha(255);
    _save();
  }

  set backgroundId(String id) {
    _backgroundId = id;
    _save();
  }

  set youtubeLyrics(bool v) {
    _youtubeLyrics = v;
    _save();
  }

  set geniusLyrics(bool v) {
    _geniusLyrics = v;
    _save();
  }

  set geniusCovers(bool v) {
    _geniusCovers = v;
    _save();
  }

  set replaceYoutubeCovers(bool v) {
    _replaceYoutubeCovers = v;
    _save();
  }

  set tintFromCover(bool v) {
    _tintFromCover = v;
    _save();
  }

  void setSpotifyKeys(String id, String secret) {
    _spotifyId = id.trim();
    _spotifySecret = secret.trim();
    _save();
  }

  void reset() {
    _accent = accentPresets.first;
    _backgroundId = backgroundPresets.first.id;
    _save();
  }
}
