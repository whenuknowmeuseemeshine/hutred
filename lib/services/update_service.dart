import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import 'player_service.dart';
import 'settings_store.dart';

/// Автообновление. Облачная сборка кладёт новые версии в Supabase Storage
/// (корзина releases) вместе с файлом latest.json. Приложение сверяет номер
/// своей сборки с ним:
/// - на Windows само скачивает установщик и тихо ставит его поверх
///   (сразу, если музыка не играет, иначе по кнопке или при следующем запуске);
/// - на Android предлагает скачать новый APK;
/// - на iPhone обновления идут через SideStore.
class UpdateService extends ChangeNotifier {
  UpdateService({required this.settings, required this.player});

  final SettingsStore settings;
  final PlayerService player;

  /// Номер этой сборки (подставляет облачная сборка). 0 — собрано вручную,
  /// такие копии не обновляются сами.
  static const build = int.fromEnvironment('HUTRED_BUILD');

  final _http = http.Client();
  Timer? _timer;

  int? latestBuild;
  String? latestVersion;
  String? notes;
  String? _windowsUrl;
  String? _androidUrl;
  File? _ready;
  double? progress;
  String? error;
  bool checking = false;

  bool get supported => build > 0 && HutredConfig.cloudEnabled && !kIsWeb;
  bool get available => latestBuild != null && latestBuild! > build;

  /// Установщик уже скачан и ждёт перезапуска.
  bool get readyToInstall => _ready != null;

  Future<void> start() async {
    if (!supported) return;
    // Скачанное в прошлый раз ставим сразу при запуске, пока ничего не играет.
    if (Platform.isWindows && settings.autoUpdate) {
      final pending = await _pendingInstaller();
      if (pending != null) {
        // Защита от зацикливания: если эту версию уже пытались поставить
        // и всё равно запустилась старая — не повторяем.
        final mark = File('${pending.path}.tried');
        if (await mark.exists()) {
          await pending.delete().catchError((_) => pending);
          await mark.delete().catchError((_) => mark);
        } else {
          await mark.writeAsString('1');
          await _install(pending);
          return;
        }
      }
    }
    unawaited(check());
    _timer = Timer.periodic(const Duration(hours: 3), (_) => check());
  }

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}updates');
    await d.create(recursive: true);
    return d;
  }

  /// Ранее скачанный установщик новее текущей сборки.
  Future<File?> _pendingInstaller() async {
    try {
      final d = await _dir();
      File? best;
      var bestBuild = build;
      await for (final f in d.list()) {
        final m = RegExp(r'Hutred-Setup-(\d+)\.exe$').firstMatch(f.path);
        if (f is! File || m == null) continue;
        final b = int.parse(m.group(1)!);
        if (b > bestBuild) {
          bestBuild = b;
          best = f;
        } else {
          // Старые установщики больше не нужны.
          await f.delete().catchError((_) => f);
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  Future<void> check({bool manual = false}) async {
    if (!supported || checking) return;
    checking = true;
    error = null;
    notifyListeners();
    try {
      final url = Uri.parse(
          '${HutredConfig.supabaseUrl}/storage/v1/object/public/releases/latest.json'
          '?t=${DateTime.now().millisecondsSinceEpoch}');
      final res = await _http.get(url).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw Exception('сервер ответил ${res.statusCode}');
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      latestBuild = (j['build'] as num?)?.toInt();
      latestVersion = j['version'] as String?;
      notes = j['notes'] as String?;
      _windowsUrl = j['windows'] as String?;
      _androidUrl = j['android'] as String?;
      if (available && Platform.isWindows && settings.autoUpdate) {
        unawaited(_downloadWindows());
      }
    } catch (e) {
      if (manual) error = 'Не удалось проверить: $e';
      debugPrint('[Обновление] $e');
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  Future<void> _downloadWindows() async {
    final url = _windowsUrl;
    final b = latestBuild;
    if (url == null || b == null || progress != null || _ready != null) return;
    try {
      final d = await _dir();
      final file = File('${d.path}${Platform.pathSeparator}Hutred-Setup-$b.exe');
      final part = File('${file.path}.part');
      progress = 0;
      notifyListeners();
      final res = await _http.send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) throw Exception('код ${res.statusCode}');
      final total = res.contentLength ?? 0;
      var got = 0;
      final sink = part.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) {
          progress = got / total;
          notifyListeners();
        }
      }
      await sink.close();
      await part.rename(file.path);
      _ready = file;
      progress = null;
      notifyListeners();
      // Ничего не играет — обновляемся сразу.
      if (!player.playing) await _install(file);
    } catch (e) {
      progress = null;
      error = 'Не удалось скачать обновление: $e';
      notifyListeners();
    }
  }

  /// Тихо ставит новую версию поверх и закрывает приложение —
  /// установщик сам запустит его заново.
  Future<void> _install(File installer) async {
    try {
      await Process.start(
        installer.path,
        ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    } catch (e) {
      error = 'Не удалось запустить установку: $e';
      notifyListeners();
    }
  }

  /// Кнопка «Обновить сейчас».
  Future<void> updateNow() async {
    if (Platform.isWindows) {
      final f = _ready;
      if (f != null) {
        await _install(f);
      } else {
        await _downloadWindows();
        if (_ready != null) await _install(_ready!);
      }
      return;
    }
    final url = _androidUrl;
    if (url != null) {
      // APK скачает браузер, потом Android предложит установить поверх.
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Автозапуск вместе с Windows (раздел реестра Run текущего пользователя).
class WindowsAutostart {
  static const _key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _name = 'Hutred';

  static bool get supported => !kIsWeb && Platform.isWindows;

  static Future<bool> isEnabled() async {
    if (!supported) return false;
    final r = await Process.run('reg', ['query', _key, '/v', _name]);
    return r.exitCode == 0;
  }

  static Future<void> set(bool on) async {
    if (!supported) return;
    if (on) {
      // Свёрнутым, чтобы окно не выскакивало при включении компьютера.
      await Process.run('reg', [
        'add', _key, '/v', _name, '/t', 'REG_SZ', '/f',
        '/d', '"${Platform.resolvedExecutable}" --minimized',
      ]);
    } else {
      await Process.run('reg', ['delete', _key, '/v', _name, '/f']);
    }
  }
}
