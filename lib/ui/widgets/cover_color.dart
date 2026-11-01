import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/track.dart';
import 'artwork.dart';

final Map<String, Color?> _cache = {};
final Map<String, Future<Color?>> _pending = {};

/// Основной цвет обложки: уменьшаем картинку до 24×24 и берём
/// средний цвет самых насыщенных пикселей. Подгоняем яркость, чтобы на
/// таком фоне хорошо читался белый текст.
Future<Color?> coverColor(String url) {
  if (_cache.containsKey(url)) return Future.value(_cache[url]);
  return _pending.putIfAbsent(url, () async {
    try {
      final provider = ResizeImage(artworkProvider(url), width: 24, height: 24);
      final stream = provider.resolve(ImageConfiguration.empty);
      final done = Completer<ui.Image>();
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!done.isCompleted) done.complete(info.image);
        },
        onError: (e, _) {
          if (!done.isCompleted) done.completeError(e);
        },
      );
      stream.addListener(listener);
      final image = await done.future.timeout(const Duration(seconds: 10));
      stream.removeListener(listener);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return _cache[url] = null;

      double r = 0, g = 0, b = 0, weight = 0;
      for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
        final c = Color.fromARGB(255, data.getUint8(i), data.getUint8(i + 1),
            data.getUint8(i + 2));
        final hsl = HSLColor.fromColor(c);
        // Насыщенные и не слишком тёмные/светлые пиксели важнее.
        final w = 0.05 +
            hsl.saturation * (1 - (hsl.lightness - 0.5).abs() * 2).clamp(0.0, 1.0);
        r += data.getUint8(i) * w;
        g += data.getUint8(i + 1) * w;
        b += data.getUint8(i + 2) * w;
        weight += w;
      }
      if (weight == 0) return _cache[url] = null;
      final avg = Color.fromARGB(
          255, (r / weight).round(), (g / weight).round(), (b / weight).round());
      final hsl = HSLColor.fromColor(avg);
      final tuned = hsl
          .withSaturation((hsl.saturation * 1.15).clamp(0.0, 0.75))
          .withLightness(hsl.lightness.clamp(0.28, 0.42))
          .toColor();
      return _cache[url] = tuned;
    } catch (_) {
      return _cache[url] = null;
    } finally {
      _pending.remove(url);
    }
  });
}

/// Подставляет цвет обложки трека (или запасной цвет, пока он считается).
class CoverColorBuilder extends StatelessWidget {
  const CoverColorBuilder({
    super.key,
    required this.track,
    required this.builder,
    this.fallback,
  });

  final Track track;
  final Color? fallback;
  final Widget Function(BuildContext context, Color color) builder;

  @override
  Widget build(BuildContext context) {
    final fb = fallback ?? Artwork.tint(track);
    final url = track.artworkUrl;
    if (url == null) return builder(context, fb);
    return FutureBuilder<Color?>(
      key: ValueKey(url),
      future: coverColor(url),
      initialData: _cache[url],
      builder: (context, snap) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: snap.data ?? fb),
        duration: const Duration(milliseconds: 500),
        builder: (context, c, _) => builder(context, c ?? fb),
      ),
    );
  }
}
