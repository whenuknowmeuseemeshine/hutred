import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'player_service.dart';
import 'settings_store.dart';

/// Значок в трее (у часов) на компьютере: крестик прячет окно туда,
/// музыка продолжает играть. В меню значка — открыть, пауза, следующий, выход.
class DesktopTray with TrayListener, WindowListener {
  DesktopTray._(this.player, this.settings);

  final PlayerService player;
  final SettingsStore settings;

  static bool get supported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// [startHidden] — запуск вместе с Windows: окно не показываем, только значок.
  static Future<void> init({
    required PlayerService player,
    required SettingsStore settings,
    bool startHidden = false,
  }) async {
    if (!supported) return;
    try {
      await windowManager.ensureInitialized();
      final tray = DesktopTray._(player, settings);
      windowManager.addListener(tray);
      // Крестик не закрывает приложение, решаем сами в onWindowClose.
      await windowManager.setPreventClose(true);
      await trayManager.setIcon(
          Platform.isWindows ? 'assets/app_icon.ico' : 'assets/logo.png');
      await trayManager.setToolTip('Hutred');
      trayManager.addListener(tray);
      await tray._updateMenu();
      player.addListener(tray._onPlayer);
      if (startHidden) await windowManager.hide();
    } catch (e) {
      debugPrint('[Трей] $e');
    }
  }

  bool? _wasPlaying;
  String? _wasTitle;

  void _onPlayer() {
    final title = player.current?.title;
    if (player.playing != _wasPlaying || title != _wasTitle) {
      _wasPlaying = player.playing;
      _wasTitle = title;
      _updateMenu();
    }
  }

  Future<void> _updateMenu() async {
    final t = player.current;
    String cut(String s) => s.length > 40 ? '${s.substring(0, 39)}…' : s;
    await trayManager.setToolTip(t == null ? 'Hutred' : 'Hutred — ${cut(t.title)}');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: 'Открыть Hutred'),
      MenuItem.separator(),
      if (t != null) MenuItem(key: 'now', label: cut('${t.artist} — ${t.title}'), disabled: true),
      MenuItem(key: 'play', label: player.playing ? 'Пауза' : 'Играть'),
      MenuItem(key: 'next', label: 'Следующий трек'),
      MenuItem(key: 'prev', label: 'Предыдущий трек'),
      MenuItem.separator(),
      MenuItem(key: 'exit', label: 'Выйти из Hutred'),
    ]));
  }

  Future<void> _show() async {
    await windowManager.show();
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.focus();
  }

  // ---------- Окно ----------

  @override
  void onWindowClose() async {
    if (settings.closeToTray) {
      await windowManager.hide();
    } else {
      await _quit();
    }
  }

  Future<void> _quit() async {
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  // ---------- Значок ----------

  @override
  void onTrayIconMouseDown() => _show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _show();
      case 'play':
        player.togglePlay();
      case 'next':
        player.next();
      case 'prev':
        player.previous();
      case 'exit':
        _quit();
    }
  }
}
