import 'package:flutter/material.dart';

/// Логотип Hutred из assets/logo.png.
class HutredLogo extends StatelessWidget {
  const HutredLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: size >= 56 ? 2.5 : 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28 - 1.5),
        child: Image.asset(
          'assets/logo.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          cacheWidth: (size * 3).round(),
        ),
      ),
    );
  }
}
