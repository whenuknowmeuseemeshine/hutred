// Дописывает разрешения в платформенные файлы после `flutter create .`
// Запуск из корня проекта:  dart run tool/setup_platforms.dart
import 'dart:io';

void main() {
  _android();
  _macos();
  _ios();
  stdout.writeln('Готово.');
}

void _android() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  if (!f.existsSync()) return _skip(f);
  var s = f.readAsStringSync();
  if (!s.contains('android.permission.INTERNET')) {
    s = s.replaceFirst('<application',
        '<uses-permission android:name="android.permission.INTERNET"/>\n    <application');
  }
  if (!s.contains('usesCleartextTraffic')) {
    // Нужно для интернет-радио по http://
    s = s.replaceFirst('<application', '<application\n        android:usesCleartextTraffic="true"');
  }
  f.writeAsStringSync(s);
  stdout.writeln('Android: интернет и http-потоки разрешены');
}

void _macos() {
  for (final name in ['DebugProfile.entitlements', 'Release.entitlements']) {
    final f = File('macos/Runner/$name');
    if (!f.existsSync()) {
      _skip(f);
      continue;
    }
    var s = f.readAsStringSync();
    final add = StringBuffer();
    for (final key in [
      'com.apple.security.network.client',
      'com.apple.security.files.user-selected.read-only',
    ]) {
      if (!s.contains(key)) add.write('\t<key>$key</key>\n\t<true/>\n');
    }
    if (add.isNotEmpty) {
      final i = s.lastIndexOf('</dict>');
      s = s.replaceRange(i, i, add.toString());
      f.writeAsStringSync(s);
    }
    stdout.writeln('macOS: $name — сеть и выбор файлов разрешены');
  }
}

void _ios() {
  final f = File('ios/Runner/Info.plist');
  if (!f.existsSync()) return _skip(f);
  var s = f.readAsStringSync();
  if (!s.contains('NSAppTransportSecurity')) {
    const add = '\t<key>NSAppTransportSecurity</key>\n'
        '\t<dict>\n\t\t<key>NSAllowsArbitraryLoads</key>\n\t\t<true/>\n\t</dict>\n';
    final i = s.lastIndexOf('</dict>');
    s = s.replaceRange(i, i, add);
    f.writeAsStringSync(s);
  }
  stdout.writeln('iOS: http-потоки разрешены');
}

void _skip(File f) => stdout.writeln('Пропуск: нет ${f.path}');
