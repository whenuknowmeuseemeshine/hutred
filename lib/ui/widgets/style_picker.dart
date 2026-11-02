import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings_store.dart';
import '../theme.dart';
import '../icons.dart';

/// Три карточки стилей с маленьким превью. Выбор меняет шрифт, формы,
/// цвет и фон сразу, без перезапуска.
class StylePicker extends StatelessWidget {
  const StylePicker({super.key, this.live = false});

  /// Применить сразу (первый запуск); иначе — после перезапуска.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final info in appStyles)
              _StyleCard(
                info: info,
                selected: s.chosenStyle == info.id,
                onTap: () {
                  if (live) {
                    s.applyStyleNow(info.id);
                    Ic.style = info.id;
                  } else {
                    s.applyStyle(info.id);
                  }
                },
              ),
          ],
        ),
        if (s.styleRestartNeeded)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(children: [
              Icon(Ic.restart_alt_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                    'Чтобы стиль применился полностью, перезапусти Hutred',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (Platform.isWindows)
                TextButton(
                  onPressed: () async {
                    // Настройки уже сохранены; запускаем себя заново и выходим.
                    await Future.delayed(const Duration(milliseconds: 400));
                    await Process.start(Platform.resolvedExecutable, const [],
                        mode: ProcessStartMode.detached);
                    exit(0);
                  },
                  child: const Text('Перезапустить'),
                ),
            ]),
          ),
      ],
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({required this.info, required this.selected, required this.onTap});
  final AppStyleInfo info;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.byId(info.id);
    final a = info.accent;
    final r = BorderRadius.circular(st.cardRadius.clamp(0, 16));
    // Превью: заголовок шрифтом стиля, «обложка» и кнопка его формы.
    final preview = Container(
      height: 92,
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B0D),
        borderRadius: r,
        gradient: st.glass
            ? RadialGradient(
                center: const Alignment(-0.6, -0.8),
                radius: 1.3,
                colors: [a.withValues(alpha: 0.55), const Color(0xFF0B0B12)],
              )
            : null,
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6 * st.artScale),
              gradient: LinearGradient(colors: [
                st.mono ? const Color(0xFF5B5B5B) : a,
                const Color(0xFF1A1A1A),
              ], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Волна',
                    maxLines: 1,
                    style: st.display(20).copyWith(color: Colors.white)),
                const SizedBox(height: 8),
                Container(
                  width: 44,
                  height: 16,
                  decoration: BoxDecoration(
                    color: st.sharp ? a : Colors.white,
                    borderRadius: BorderRadius.circular(st.sharp ? 0 : 8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return SizedBox(
      width: 168,
      child: Material(
        color: Colors.white.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(st.cardRadius.clamp(0, 16) + 4),
          side: BorderSide(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.1),
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                preview,
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: Text(info.name,
                      style: TextStyle(
                          fontFamily: st.font, fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Text(info.hint,
                      style: const TextStyle(fontSize: 12, color: HutredTheme.muted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
