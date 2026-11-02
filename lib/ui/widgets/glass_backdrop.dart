import 'package:flutter/material.dart';

/// Фон стиля «Стекло»: тёмная основа и мягкое цветное свечение от акцента.
/// Страницы над ним прозрачные, панели — полупрозрачные.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.accent, required this.ink, required this.child});
  final Color accent;
  final Color ink;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(accent);
    // Второй и третий цвета — соседние оттенки акцента.
    Color shift(double deg) => hsl
        .withHue((hsl.hue + deg) % 360)
        .withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0))
        .withLightness(0.55)
        .toColor();
    Widget glow(Alignment at, Color c, double a, double r) => Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: at,
                radius: r,
                colors: [c.withValues(alpha: a), c.withValues(alpha: 0)],
              ),
            ),
          ),
        );
    return ColoredBox(
      color: ink,
      child: Stack(
        children: [
          glow(const Alignment(-0.5, -0.8), accent, 0.38, 1.0),
          glow(const Alignment(0.7, -0.3), shift(-60), 0.26, 0.9),
          glow(const Alignment(0.0, 1.1), shift(60), 0.20, 1.0),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}
