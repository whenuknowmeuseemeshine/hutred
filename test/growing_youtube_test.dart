import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hutred/services/youtube_source.dart';

void main() {
  test('YouTube starts reading before completion and serves seeks after completion', () async {
    final dir = await Directory.systemTemp.createTemp('hutred-live-test');
    addTearDown(() => dir.delete(recursive: true));
    final part = File('${dir.path}/audio.part');
    await part.writeAsBytes([1, 2]);
    final live = LiveDownload(file: part, totalBytes: 4, contentType: 'audio/mp4');
    final source = GrowingFileAudioSource(live);
    final chunks = StreamIterator((await source.request()).stream);
    addTearDown(chunks.cancel);
    expect(await chunks.moveNext(), isTrue);
    expect(chunks.current, [1, 2]);
    await part.writeAsBytes([3, 4], mode: FileMode.append);
    live.finish(await part.copy('${dir.path}/audio.m4a'));
    expect(await chunks.moveNext(), isTrue);
    expect(chunks.current, [3, 4]);
    expect(await chunks.moveNext(), isFalse);
    expect(await (await source.request(1, 3)).stream.expand((chunk) => chunk).toList(), [2, 3]);
  });
}
