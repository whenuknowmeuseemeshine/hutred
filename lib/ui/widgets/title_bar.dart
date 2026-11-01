import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme.dart';

/// Своя тонкая полоса сверху окна вместо системной: без значка и надписи,
/// за неё можно таскать окно, двойной щелчок — развернуть, справа кнопки.
class HutredTitleBar extends StatefulWidget {
  const HutredTitleBar({super.key});

  static const height = 32.0;

  @override
  State<HutredTitleBar> createState() => _HutredTitleBarState();
}

class _HutredTitleBarState extends State<HutredTitleBar> with WindowListener {
  bool _max = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _max = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _max = true);
  @override
  void onWindowUnmaximize() => setState(() => _max = false);

  Future<void> _toggleMax() async =>
      await windowManager.isMaximized() ? windowManager.unmaximize() : windowManager.maximize();

  @override
  Widget build(BuildContext context) {
    // Полупрозрачная, с лёгким размытием: фон приложения виден и под ней.
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Material(
      color: Colors.black.withValues(alpha: 0.10),
      child: SizedBox(
        height: HutredTitleBar.height,
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: _toggleMax,
              child: const SizedBox.expand(),
            ),
          ),
          _CaptionButton(
            icon: Icons.remove_rounded,
            tooltip: 'Свернуть',
            onTap: () => windowManager.minimize(),
          ),
          _CaptionButton(
            icon: _max ? Icons.filter_none_rounded : Icons.crop_square_rounded,
            iconSize: _max ? 13 : 15,
            tooltip: _max ? 'Восстановить' : 'Развернуть',
            onTap: _toggleMax,
          ),
          _CaptionButton(
            icon: Icons.close_rounded,
            tooltip: 'Закрыть',
            danger: true,
            // Дальше решает трей: спрятать или выйти.
            onTap: () => windowManager.close(),
          ),
        ]),
      ),
        ),
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.iconSize = 16,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double iconSize;
  final bool danger;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = !_hover
        ? Colors.transparent
        : widget.danger
            ? const Color(0xFFE81123)
            : Colors.white.withValues(alpha: 0.08);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 46,
          height: HutredTitleBar.height,
          color: bg,
          child: Icon(widget.icon,
              size: widget.iconSize,
              color: _hover ? Colors.white : HutredTheme.muted),
        ),
      ),
    );
  }
}
