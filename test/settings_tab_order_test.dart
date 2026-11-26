import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hutred/services/settings_store.dart';
import 'package:hutred/ui/screens/settings_screen.dart';
import 'package:hutred/ui/theme.dart';
import 'package:provider/provider.dart';

void main() {
  for (final (width, pointer) in [
    (700.0, PointerDeviceKind.mouse),
    (700.0, PointerDeviceKind.touch),
    (1100.0, PointerDeviceKind.mouse),
  ]) {
    testWidgets('tabs reorder by dragging immediately at $width with $pointer', (tester) async {
      final settings = SettingsStore();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1100);
      addTearDown(() {
        settings.dispose();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          theme: HutredTheme.build(settings.accent, settings.background),
          home: Scaffold(body: SingleChildScrollView(child: settingsPageFor('Внешний вид'))),
        ),
      ));

      final wave = find.byTooltip('Переместить «Волна»');
      final search = find.byTooltip('Переместить «Поиск»');
      await tester.ensureVisible(search);
      await tester.pumpAndSettle();
      final start = tester.getCenter(wave);
      final target = tester.getCenter(search) + Offset(0, width < 860 ? 21 : 0);
      final drag = await tester.startGesture(start, kind: pointer);
      for (final step in [0.08, 0.2, 0.45, 0.7, 1.0]) {
        await drag.moveTo(Offset.lerp(start, target, step)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 270));
      await drag.up();
      await tester.pumpAndSettle();

      expect(settings.navOrder.take(3), ['library', 'search', 'wave']);
      expect(settings.visibleNav.take(3), ['library', 'search', 'wave']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
