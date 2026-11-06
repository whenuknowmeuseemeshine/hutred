import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/offline_service.dart';
import '../theme.dart';
import 'net_image.dart';

final _exists = <String, bool>{};

bool _fileOk(String p) => _exists[p] ??= File(p).existsSync();

/// Картинка по ссылке или по пути к файлу (своя обложка без облака).
ImageProvider artworkProvider(String url) {
  if (!url.startsWith('http')) return FileImage(File(OfflineService.fixPath(url)));
  // Скачанная обложка — чтобы была видна и без интернета.
  // Если файла уже нет (переустановка, очистка) — берём из сети.
  final saved = OfflineService.instance?.coverForUrl(url);
  if (saved != null && _fileOk(saved)) return FileImage(File(saved));
  return NetArt(url);
}

/// Обложка трека: картинка из источника или узор, сгенерированный по названию.
class Artwork extends StatelessWidget {
  const Artwork({super.key, required this.track, this.size, this.radius = 6});

  final Track? track;
  final double? size;
  final double radius;

  static Color tint(Track? t) {
    if (t == null) return const Color(0xFF2A2F3D);
    final h = '${t.artist}${t.album}'.hashCode;
    return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.45, 0.42).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final url = track?.artworkUrl;
    final fallback = _Generated(track: track);
    Widget child = url == null
        ? fallback
        : Image(
            image: artworkProvider(url),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
            gaplessPlayback: true,
          );
    // Скругление зависит от стиля: у «Стекла» мягче, у «Резкого» углов нет.
    final r = radius * HutredStyle.of(context).artScale;
    child = ClipRRect(
      borderRadius: BorderRadius.circular(size == null ? r : r.clamp(0, size! / 4)),
      child: AspectRatio(aspectRatio: 1, child: child),
    );
    return size == null ? child : SizedBox.square(dimension: size, child: child);
  }
}

class _Generated extends StatelessWidget {
  const _Generated({required this.track});
  final Track? track;

  @override
  Widget build(BuildContext context) {
    final c = Artwork.tint(track);
    final hsl = HSLColor.fromColor(c);
    final c2 = hsl
        .withHue((hsl.hue + 40) % 360)
        .withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0))
        .toColor();
    final letter = (track?.title.trim().isNotEmpty ?? false)
        ? track!.title.trim().characters.first.toUpperCase()
        : '♪';
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c, c2],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) => Center(
          child: Text(
            letter,
            style: TextStyle(
              fontSize: box.maxWidth * 0.42,
              fontWeight: FontWeight.w900,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
