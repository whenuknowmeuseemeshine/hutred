import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hutred/ui/widgets/net_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a temporary cover failure is retried and successful bytes are cached',
      () async {
    final temp = await Directory.systemTemp.createTemp('hutred-art-test');
    addTearDown(() => temp.delete(recursive: true));
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => temp.path);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j81sAAAAASUVORK5CYII=',
    );
    var requests = 0;
    server.listen((request) async {
      if (++requests == 1) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
      } else {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(png);
      }
      await request.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}/cover.png';

    await HttpOverrides.runWithHttpOverrides(() async {
      final downloaded = await ArtCache.get(url);
      expect(downloaded.fromDisk, isFalse);
      expect(downloaded.bytes, png);
      final cached = await ArtCache.get(url);
      expect(cached.fromDisk, isTrue);
      expect(cached.bytes, png);
    }, _LoopbackHttp());
    expect(requests, 2);
  });
}

class _LoopbackHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}
