import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings_store.dart';
import '../../services/transfer_service.dart';
import '../actions.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/track_tile.dart';
import '../icons.dart';
import '../widgets/style_bits.dart';

/// Перенос треков с других площадок.
class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _input = TextEditingController();
  final _name = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _start({String? fileName}) async {
    final t = context.read<TransferService>();
    final text = _input.text;
    if (text.trim().isEmpty) {
      AppActions.toast(context, 'Вставь ссылку или список треков');
      return;
    }
    await t.start(text, fileName: fileName);
    if (mounted) _name.text = t.suggestedName;
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
    );
    final f = res?.files.single;
    if (f?.path == null) return;
    try {
      _input.text = await File(f!.path!).readAsString();
    } catch (_) {
      if (mounted) AppActions.toast(context, 'Не получилось прочитать файл');
      return;
    }
    await _start(fileName: f.name);
  }

  void _save() {
    final t = context.read<TransferService>();
    final r = t.save(playlistName: _name.text);
    AppActions.toast(
        context,
        r.playlist == null
            ? 'Добавлено в медиатеку: ${tracksWord(r.added)}'
            : 'Плейлист «${r.playlist}» готов, новых треков: ${r.added}');
    t.reset();
    _input.clear();
  }

  /// Выбранная плитка-источник: от неё зависят подсказка и вид поля.
  String _src = 'spotify';

  static const _sources = [
    ('spotify', 'Spotify', Color(0xFF1ED760)),
    ('yandex', 'Яндекс Музыка', Color(0xFFFFCC00)),
    ('youtube', 'YouTube', Color(0xFFFF3D3D)),
    ('soundcloud', 'SoundCloud', Color(0xFFFF7A1A)),
    ('csv', 'Файл CSV', Color(0xFF4DA3FF)),
    ('text', 'Списком', Color(0xFFA78BFA)),
  ];

  static const _hints = {
    'spotify': 'Ссылка на трек, альбом или плейлист Spotify. Плейлист длиннее 50 треков — '
        'скачай его в CSV на exportify.net и выбери «Файл CSV».',
    'yandex': 'Ссылка на открытый плейлист или альбом Яндекс Музыки.',
    'youtube': 'Ссылка на плейлист YouTube или YouTube Music.',
    'soundcloud': 'Ссылка на плейлист или альбом SoundCloud.',
    'csv': 'Файл CSV (например, из Exportify) или TXT со списком треков.',
    'text': 'Вставь названия — по одному в строке, как «Исполнитель — Название». '
        'Подойдёт список из любой площадки.',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TransferService>();
    final busy = t.stage == TransferStage.reading || t.stage == TransferStage.matching;
    final scheme = Theme.of(context).colorScheme;
    final st = HutredStyle.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pad = stylePagePadding(context);
    final accent = scheme.primary;
    final multi = _src == 'text';

    Widget tile((String, String, Color) src) {
      final on = _src == src.$1;
      final r = BorderRadius.circular(st.sharp ? 0 : st.glass ? 18 : 12);
      final onC = st.sharp && on ? HutredTheme.onAccent(accent) : HutredTheme.text;
      return Material(
        color: on
            ? (st.sharp
                ? accent
                : st.glass
                    ? accent.withValues(alpha: 0.22)
                    : const Color(0xFF1F1F1F))
            : (st.sharp
                ? Colors.transparent
                : st.glass
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFF141414)),
        shape: RoundedRectangleBorder(
          borderRadius: r,
          side: st.sharp
              ? BorderSide(color: on ? accent : const Color(0xFF2A2A2A))
              : st.glass
                  ? BorderSide(
                      color: on
                          ? accent.withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.08))
                  : on
                      ? const BorderSide(color: Color(0xFFF5F5F5))
                      : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: r,
          onTap: () {
            setState(() => _src = src.$1);
            if (src.$1 == 'csv') _pickFile();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: st.sharp && on ? HutredTheme.onAccent(accent) : src.$3,
                  borderRadius: BorderRadius.circular(st.sharp ? 0 : 8),
                ),
              ),
              const SizedBox(height: 10),
              Text(src.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: onC)),
            ]),
          ),
        ),
      );
    }

    final findButton = StyleButton(
      label: 'Найти треки',
      icon: Ic.search,
      onPressed: busy ? null : _start,
    );

    final field = Container(
      padding: EdgeInsets.fromLTRB(18, multi ? 10 : 4, 6, multi ? 10 : 4),
      decoration: BoxDecoration(
        color: st.sharp
            ? null
            : st.glass
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFF1F1F1F),
        border: st.sharp ? Border.all(color: const Color(0xFF333333)) : null,
        borderRadius: BorderRadius.circular(st.sharp ? 0 : multi ? 18 : 99),
      ),
      child: Row(
        crossAxisAlignment: multi ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: multi ? 12 : 0),
            child: Icon(multi ? Ic.notes : Ic.link, size: 18, color: HutredTheme.muted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !busy,
              minLines: multi ? 5 : 1,
              maxLines: multi ? 12 : 1,
              onSubmitted: multi ? null : (_) => _start(),
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: multi
                    ? 'Исполнитель — Название\nИсполнитель — Название'
                    : 'Вставь ссылку на плейлист',
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!multi) findButton,
        ],
      ),
    );

    final setup = <Widget>[
      LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 760 ? 6 : 3;
        const gap = 10.0;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final src in _sources) SizedBox(width: w, child: tile(src)),
        ]);
      }),
      const SizedBox(height: 14),
      field,
      if (multi) ...[const SizedBox(height: 10), Align(alignment: Alignment.centerLeft, child: findButton)],
      const SizedBox(height: 10),
      Text(_hints[_src]!, style: const TextStyle(fontSize: 13, color: HutredTheme.muted, height: 1.4)),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Искать сначала на  ', style: TextStyle(color: HutredTheme.muted, fontSize: 13)),
          for (final (key, label) in [
            if (context.watch<SettingsStore>().hasSpotifyKeys) ('spotify', 'Spotify'),
            ('soundcloud', 'SoundCloud'),
            ('youtube', 'YouTube'),
          ])
            StyleChip(
              label: label,
              selected: t.searchFirst == key ||
                  (key == 'soundcloud' &&
                      t.searchFirst == 'spotify' &&
                      !context.read<SettingsStore>().hasSpotifyKeys),
              onTap: () => t.setSearchFirst(key),
            ),
        ],
      ),
    ];

    final notFound = t.items.where((i) => i.done && i.found == null).toList();
    final results = StylePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                busy
                    ? 'Ищу треки… ${t.doneCount} из ${t.items.length}'
                    : 'Нашёл ${t.foundCount} из ${t.items.length}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            if (!busy)
              TextButton.icon(
                onPressed: () {
                  t.reset();
                  _input.clear();
                },
                icon: Icon(Ic.restart_alt, size: 18),
                label: const Text('Заново'),
              ),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(st.sharp ? 0 : 3),
            child: LinearProgressIndicator(
              value: t.items.isEmpty ? null : t.doneCount / t.items.length,
              minHeight: st.sharp ? 2 : 6,
              color: accent,
              backgroundColor: const Color(0xFF2A2A2A),
            ),
          ),
          const SizedBox(height: 8),
          for (final item in t.items) _ItemTile(item: item),
        ],
      ),
    );

    final savePanel = StylePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const StyleCaption('Куда сложить'),
          const SizedBox(height: 10),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              hintText: 'Название плейлиста',
              helperText: 'Пусто — только в медиатеку',
            ),
          ),
          const SizedBox(height: 14),
          StyleButton(
            label: 'Добавить ${t.selectedCount}',
            icon: Ic.add,
            onPressed: t.stage == TransferStage.ready && t.selectedCount > 0 ? _save : null,
          ),
          if (notFound.isNotEmpty && !busy) ...[
            const SizedBox(height: 10),
            StyleButton(
              label: 'Искать ненайденные на YouTube (${notFound.length})',
              primary: false,
              onPressed: () {
                for (final i in notFound) {
                  t.retry(i, where: 'youtube');
                }
              },
            ),
          ],
        ],
      ),
    );

    final top = MediaQuery.paddingOf(context).top + pad.top;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad.left, top, pad.right, 120),
        children: [
          Text('Перенос музыки', style: st.display(wide ? 48 : 30)),
          const SizedBox(height: 8),
          const Text(
            'Вставь ссылку на плейлист из любого сервиса — Hutred найдёт каждый трек '
            'и сложит в медиатеку и новый плейлист.',
            style: TextStyle(color: HutredTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (t.items.isEmpty) ...setup,
          if (busy && t.items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (t.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(t.error!, style: TextStyle(color: scheme.error)),
            ),
          if (t.items.isNotEmpty)
            wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: results),
                    const SizedBox(width: 24),
                    SizedBox(width: 320, child: savePanel),
                  ])
                : Column(children: [savePanel, const SizedBox(height: 16), results]),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});
  final TransferItem item;

  @override
  Widget build(BuildContext context) {
    final t = context.read<TransferService>();
    final found = item.found;
    final scheme = Theme.of(context).colorScheme;

    Widget leading;
    if (!item.done) {
      leading = const SizedBox.square(
          dimension: 44,
          child: Center(
              child: SizedBox.square(
                  dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))));
    } else if (found == null) {
      leading = SizedBox.square(
          dimension: 44, child: Icon(Ic.search_off, color: scheme.error));
    } else {
      leading = Artwork(track: found, size: 44, radius: 4);
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: leading,
      title: Text(found?.title ?? item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          if (found != null) ...[
            Icon(sourceIcon(found.source), size: 13, color: HutredTheme.muted),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              found != null
                  ? found.artist
                  : (item.done ? 'Не нашёл: ${item.label}' : item.artist),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!item.done)
            const Text('ищу…', style: TextStyle(color: HutredTheme.muted, fontSize: 13))
          else if (found != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Ic.check, size: 16, color: const Color(0xFF4ADE80)),
              const SizedBox(width: 4),
              Text(sourceLabel(found.source),
                  style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 13)),
            ])
          else
            Text('Не нашёл',
                style: TextStyle(color: Colors.amber.shade300, fontSize: 13)),
          if (item.done)
            PopupMenuButton<String>(
              tooltip: 'Искать в другом месте',
              icon: Icon(Ic.manage_search, size: 20),
              onSelected: (where) => t.retry(item, where: where),
              itemBuilder: (_) => [
                if (context.read<SettingsStore>().hasSpotifyKeys)
                  const PopupMenuItem(value: 'spotify', child: Text('Искать в Spotify')),
                const PopupMenuItem(value: 'soundcloud', child: Text('Искать на SoundCloud')),
                const PopupMenuItem(value: 'youtube', child: Text('Искать на YouTube')),
              ],
            ),
          Checkbox(
            value: found != null && item.selected,
            onChanged: found == null
                ? null
                : (v) => t.setSelected(item, v ?? false),
          ),
        ],
      ),
    );
  }
}
