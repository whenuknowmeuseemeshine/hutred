import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hutred/services/xray_vpn.dart';

void main() {
  test('vpn key → xray config', () {
    final key = Platform.environment['VPN_KEY'] ?? '';
    final list = XrayVpn.parseAny(key);
    expect(list, isNotEmpty);
    File('xray-test.json').writeAsStringSync(jsonEncode(XrayVpn.configFor(list.first, 10809)));
  });
}
