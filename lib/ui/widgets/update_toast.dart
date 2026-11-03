import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/update_service.dart';
import '../icons.dart';
import '../theme.dart';

/// Плашка обновления по стилю:
/// Моно — карточка снизу справа (на телефоне — над мини-плеером),
/// Стекло — стеклянная капсула сверху по центру,
/// Резкий — строка во всю ширину сверху.
/// Кладётся в Stack поверх содержимого вкладки.
class UpdateToast extends StatefulWidget {
  const UpdateToast({super.key});

  @override
  State<UpdateToast> createState() => _UpdateToastState();
}

class _UpdateToastState extends State<UpdateToast> {
  /// «Позже»/«Скрыть»: прячем до следующего состояния (готово / новая сборка).
  String? _hidden;

  String _state(UpdateService u) {
    if (u.readyToInstall) return 'ready:${u.latestBuild}';
    if (u.progress != null) return 'loading:${u.latestBuild}';
    if (u.available && !Platform.isWindows) return 'available:${u.latestBuild}';
    return '';
  }

  void _whatsNew(UpdateService u) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Что нового · сборка ${u.latestBuild ?? ''}'),
        content: Text((u.notes ?? '').isEmpty ? 'Исправления и улучшения' : u.notes!),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<UpdateService>();
    final state = _state(u);
    final show = state.isNotEmpty && state != _hidden;
    final st = HutredStyle.of(context);
    final phone = MediaQuery.sizeOf(context).width < 700;
    final top = MediaQuery.paddingOf(context).top;

    final card = show ? _card(context, u, state.split(':').first, st, phone) : null;
    Widget anim(Widget? child, Offset from) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
                position: Tween(begin: from, end: Offset.zero).animate(a), child: c),
          ),
          child: child ?? const SizedBox.shrink(),
        );

    if (st.sharp) {
      return Positioned(left: 0, right: 0, top: top, child: anim(card, const Offset(0, -0.5)));
    }
    if (st.glass) {
      return Positioned(
        left: 12,
        right: 12,
        top: top + (phone ? 6 : 14),
        child: Center(child: anim(card, const Offset(0, -0.6))),
      );
    }
    return Positioned(
      left: phone ? 10 : null,
      right: phone ? 10 : 24,
      bottom: phone ? 10 : 24,
      child: anim(card, const Offset(0, 0.5)),
    );
  }

  Widget _card(BuildContext context, UpdateService u, String kind, HutredStyle st, bool phone) {
    final accent = Theme.of(context).colorScheme.primary;
    final onAccent = HutredTheme.onAccent(accent);
    final build = u.latestBuild ?? 0;
    final loading = kind == 'loading';
    final ready = kind == 'ready';
    final pct = ((u.progress ?? 0) * 100).round();
    final title = loading
        ? 'Скачиваю новую версию'
        : ready
            ? (phone ? 'Новая версия готова' : 'Hutred обновился до сборки $build')
            : 'Вышла новая версия Hutred';
    final sub = loading
        ? 'Сборка $build · $pct%'
        : ready
            ? (phone ? 'Сборка $build' : 'Перезапусти, чтобы включить новую версию')
            : Platform.isIOS
                ? 'Сборка $build · обнови в SideStore'
                : 'Сборка $build';
    final action = ready
        ? (phone ? 'Обновить' : 'Перезапустить')
        : Platform.isIOS
            ? 'Открыть'
            : 'Скачать';
    void hide() => setState(() => _hidden = '$kind:${u.latestBuild}');

    // ---------- Резкий ----------
    if (st.sharp) {
      final segs = (pct / 5).round();
      return Material(
        key: ValueKey(kind),
        color: const Color(0xFF0F0F0F),
        shape: const Border(bottom: BorderSide(color: Color(0xFF333333))),
        child: phone
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('UPDATE / BUILD ${build.toString().padLeft(3, '0')}',
                        style: st.caption(size: 11, color: HutredTheme.muted)),
                    const SizedBox(height: 4),
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
                if (loading)
                  _segments(segs, accent)
                else
                  Container(
                    decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0xFF333333)))),
                    height: 48,
                    child: Row(children: [
                      Expanded(child: _sharpBtn('ПОЗЖЕ', hide, st)),
                      Container(width: 1, color: const Color(0xFF333333)),
                      Expanded(
                          child: _sharpBtn('${action.toUpperCase()} →', u.updateNow, st,
                              bg: accent, fg: onAccent)),
                    ]),
                  ),
              ])
            : SizedBox(
                height: 52,
                child: Row(children: [
                  const SizedBox(width: 18),
                  Text('UPDATE / BUILD ${build.toString().padLeft(3, '0')}',
                      style: st.caption(color: HutredTheme.muted)),
                  const SizedBox(width: 20),
                  Flexible(
                    child: Text(loading ? title : '$title — $sub',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (loading) ...[
                    const SizedBox(width: 20),
                    Expanded(child: _segments(segs, accent)),
                    const SizedBox(width: 14),
                    Text('$pct%', style: st.caption()),
                    const SizedBox(width: 18),
                  ] else ...[
                    const SizedBox(width: 14),
                    TextButton(
                      onPressed: () => _whatsNew(u),
                      child: Text('ЧТО НОВОГО', style: st.caption(color: HutredTheme.text)),
                    ),
                    const Spacer(),
                    Container(width: 1, color: const Color(0xFF333333)),
                    _sharpBtn('ПОЗЖЕ', hide, st, w: 110),
                    _sharpBtn('${action.toUpperCase()} →', u.updateNow, st,
                        bg: accent, fg: onAccent, w: 200),
                  ],
                ]),
              ),
      );
    }

    // ---------- Стекло ----------
    if (st.glass) {
      return ClipRRect(
        key: ValueKey(kind),
        borderRadius: BorderRadius.circular(26),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0C3B3D).withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 36, offset: Offset(0, 14))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: loading
                    ? null
                    : LinearGradient(colors: [accent, const Color(0xFF5BC8F5)]),
                color: loading ? Colors.white.withValues(alpha: 0.10) : null,
              ),
              alignment: Alignment.center,
              child: loading
                  ? Stack(alignment: Alignment.center, children: [
                      SizedBox.square(
                        dimension: 40,
                        child: CircularProgressIndicator(
                            value: u.progress, strokeWidth: 3, color: accent),
                      ),
                      Text('$pct', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ])
                  : Icon(Ic.check, color: onAccent, size: 22),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: st.display(14)),
                  const SizedBox(height: 2),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Color(0xFFCFE3E0))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (loading)
              IconButton(
                tooltip: 'Скрыть',
                onPressed: hide,
                style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.10)),
                icon: Icon(Ic.close, size: 18),
              )
            else ...[
              if (!phone)
                TextButton(onPressed: hide, child: const Text('Позже')),
              FilledButton(
                onPressed: u.updateNow,
                style: FilledButton.styleFrom(
                    backgroundColor: accent, foregroundColor: onAccent, shape: const StadiumBorder()),
                child: Text(action, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ]),
        ),
      );
    }

    // ---------- Моно ----------
    return Container(
      key: ValueKey(kind),
      width: phone ? null : 460,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: phone ? const Color(0xFF1C1C1C) : const Color(0xFF181818),
        borderRadius: BorderRadius.circular(phone ? 16 : 14),
        boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, 12))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: loading ? const Color(0xFF262626) : accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(loading ? Ic.download_outlined : Ic.refresh,
                color: loading ? HutredTheme.text : onAccent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(fontSize: 13, color: HutredTheme.muted)),
            ]),
          ),
          if (loading) TextButton(onPressed: hide, child: const Text('Скрыть')),
        ]),
        const SizedBox(height: 14),
        if (loading)
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: u.progress,
              minHeight: 4,
              color: accent,
              backgroundColor: const Color(0xFF2E2E2E),
            ),
          )
        else
          Row(children: [
            if (!phone)
              TextButton(onPressed: () => _whatsNew(u), child: const Text('Что нового')),
            if (!phone) const Spacer(),
            Expanded(
              flex: phone ? 1 : 0,
              child: OutlinedButton(
                onPressed: hide,
                style: OutlinedButton.styleFrom(
                    shape: const StadiumBorder(),
                    side: const BorderSide(color: Color(0xFF3A3A3A)),
                    minimumSize: const Size(0, 42)),
                child: const Text('Позже'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: phone ? 1 : 0,
              child: FilledButton(
                onPressed: u.updateNow,
                style: FilledButton.styleFrom(
                    backgroundColor: HutredTheme.text,
                    foregroundColor: Colors.black,
                    shape: const StadiumBorder(),
                    minimumSize: const Size(0, 42)),
                child: Text(action, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
      ]),
    );
  }

  Widget _segments(int on, Color accent) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
        child: Row(children: [
          for (var i = 0; i < 20; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(child: Container(height: 10, color: i < on ? accent : const Color(0xFF262626))),
          ],
        ]),
      );

  Widget _sharpBtn(String label, VoidCallback onTap, HutredStyle st,
          {Color? bg, Color? fg, double? w}) =>
      Material(
        color: bg ?? Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: w,
            height: double.infinity,
            child: Center(
              child: Text(label,
                  style: bg != null
                      ? TextStyle(fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.5)
                      : st.caption(color: HutredTheme.text)),
            ),
          ),
        ),
      );
}
