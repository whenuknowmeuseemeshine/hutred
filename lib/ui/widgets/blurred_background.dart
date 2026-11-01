import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Свой фон (картинка или GIF), сильно размытый и затемнённый,
/// чтобы не мешать читать список.
class BlurredBackground extends StatelessWidget {
  const BlurredBackground({super.key, required this.imagePath, required this.child});

  final String? imagePath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    if (path == null) return child;
    final ink = Theme.of(context).scaffoldBackgroundColor;
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                ink.withValues(alpha: 0.55),
                ink.withValues(alpha: 0.75),
                ink.withValues(alpha: 0.9),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
