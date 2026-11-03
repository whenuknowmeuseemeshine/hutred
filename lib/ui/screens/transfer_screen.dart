import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/settings_store.dart';
import '../../services/transfer_service.dart';
import '../actions.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/track_tile.dart';
import '../icons.dart';
import '../widgets/style_bits.dart';
import '../widgets/settings_kit.dart';

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

  Future<void> _pickFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || !mounted) return;
    final t = context.read<TransferService>();
    try {
      await t.startFolder(dir);
      if (mounted) _name.text = t.suggestedName;
    } catch (_) {
      if (mounted) AppActions.toast(context, 'Не получилось открыть папку');
    }
  }

  void _save() {
    final t = context.read<TransferService>();
    final relink = t.relinking;
    final r = t.save(playlistName: _name.text);
    AppActions.toast(
        context,
        relink
            ? 'Теперь играют онлайн: ${tracksWord(r.added)}. Папка больше не нужна'
            : r.playlist == null
            ? 'Добавлено в медиатеку: ${tracksWord(r.added)}'
            : 'Плейлист «${r.playlist}» готов, новых треков: ${r.added}');
    t.reset();
    _input.clear();
  }

  /// Телефон: фильтр результатов поиска.
  String _filter = 'all';

  /// Откуда ссылка — по адресу.
  static (String, Color)? _detect(String text) {
    final s = text.toLowerCase();
    String kind() => s.contains('album')
        ? 'альбом'
        : s.contains('track') || s.contains('watch?v=') || s.contains('youtu.be')
            ? 'трек'
            : 'плейлист';
    if (s.contains('spotify.com') || s.startsWith('spotify:')) {
      return ('Spotify · ${kind()}', const Color(0xFF1ED760));
    }
    if (s.contains('music.yandex') || s.contains('yandex.')) {
      return ('Яндекс Музыка · ${kind()}', const Color(0xFFFFCC00));
    }
    if (s.contains('youtube.com') || s.contains('youtu.be')) {
      return ('YouTube · ${s.contains('list=') ? 'плейлист' : kind()}', const Color(0xFFFF3D3D));
    }
    if (s.contains('soundcloud.com')) {
      return ('SoundCloud · ${s.contains('/sets/') ? 'плейлист' : 'трек'}', const Color(0xFFFF7A1A));
    }
    if (s.contains('\n')) return ('Список треков', const Color(0xFFA78BFA));
    return null;
  }

  Widget _phone(BuildContext context, TransferService t, bool busy) {
    final k = Sk.of(context);
    final st = k.st;
    final canPop = Navigator.of(context).canPop();
    final top = MediaQuery.paddingOf(context).top;
    final hasResults = t.items.isNotEmpty;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(canPop ? 4 : 16, top + 6, 16, 6),
      child: Row(children: [
        if (canPop)
          IconButton(
            tooltip: 'Назад',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(st.sharp ? 'ПЕРЕНОС МУЗЫКИ' : 'Перенос музыки',
                maxLines: 1, style: st.display(st.glass ? 22 : 28)),
          ),
        ),
      ]),
    );

    Widget card(Widget child, {EdgeInsets pad = const EdgeInsets.all(14)}) => Container(
          padding: pad,
          decoration: BoxDecoration(
            color: k.card,
            border: k.cardBorder,
            borderRadius: BorderRadius.circular(k.r),
          ),
          child: child,
        );

    final List<Widget> body;
    Widget dock;

    if (!hasResults) {
      final detected = _detect(_input.text);
      final field = Container(
        height: _src == 'text' ? null : 48,
        padding: EdgeInsets.fromLTRB(14, _src == 'text' ? 8 : 0, 6, _src == 'text' ? 8 : 0),
        decoration: BoxDecoration(
          color: k.sharp ? Colors.transparent : k.inner,
          border: k.sharp ? Border.all(color: k.ghost) : null,
          borderRadius: BorderRadius.circular(k.sharp ? 0 : k.glass ? 24 : 12),
        ),
        child: Row(children: [
          Icon(_src == 'text' ? Ic.notes : Ic.link, size: 18, color: k.muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !busy,
              minLines: _src == 'text' ? 4 : 1,
              maxLines: _src == 'text' ? 8 : 1,
              onChanged: (_) => setState(() {}),
              onSubmitted: _src == 'text' ? null : (_) => _start(),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: _src == 'text'
                    ? 'Исполнитель — Название\nИсполнитель — Название'
                    : 'Ссылка на плейлист',
              ),
            ),
          ),
          if (_src != 'text')
            SkChip('Вставить', height: 36, onTap: busy
                ? null
                : () async {
                    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
                    if (clip.trim().isEmpty) return;
                    setState(() => _input.text = clip.trim());
                  }),
        ]),
      );

      final sourceRows = [
        for (final (i, src) in _sources.indexed)
          InkWell(
            onTap: busy
                ? null
                : () {
                    setState(() => _src = src.$1);
                    if (src.$1 == 'csv') _pickFile();
                    if (src.$1 == 'folder') _pickFolder();
                  },
            child: Container(
              height: 56,
              padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
              decoration: BoxDecoration(
                color: _src == src.$1 && src.$1 != 'csv' && src.$1 != 'folder'
                    ? k.inner
                    : Colors.transparent,
                border: i == 0 ? null : Border(top: BorderSide(color: k.line)),
              ),
              child: Row(children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: src.$3,
                    borderRadius: BorderRadius.circular(k.sharp ? 0 : 8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(src.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(_shortHints[src.$1]!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: k.muted)),
                    ],
                  ),
                ),
                Icon(Ic.chevron_right, size: 18, color: k.muted),
              ]),
            ),
          ),
      ];

      final hasSp = context.watch<SettingsStore>().hasSpotifyKeys;
      final firstOpts = <(String, String)>[
        if (hasSp) ('spotify', 'Spotify'),
        ('soundcloud', 'SoundCloud'),
        ('youtube', 'YouTube'),
      ];
      final firstVal = firstOpts.any((o) => o.$1 == t.searchFirst) ? t.searchFirst : 'soundcloud';

      body = [
        Text(
          _src == 'text'
              ? 'Вставь названия — по одному в строке, как «Исполнитель — Название».'
              : 'Вставь ссылку на плейлист — Hutred найдёт каждый трек и сложит в медиатеку.',
          style: TextStyle(fontSize: 14, color: k.muted, height: 1.4),
        ),
        const SizedBox(height: 14),
        card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          field,
          if (detected != null && _src != 'text') ...[
            const SizedBox(height: 12),
            Row(children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                    color: detected.$2, borderRadius: BorderRadius.circular(k.sharp ? 0 : 6)),
              ),
              const SizedBox(width: 8),
              Text(detected.$1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('распознал по ссылке',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: k.muted)),
              ),
            ]),
          ],
        ])),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: const SkCap('Или откуда перенести'),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(k.r),
          child: card(Column(children: sourceRows), pad: EdgeInsets.zero),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Text('Искать на', style: TextStyle(fontSize: 13, color: k.muted)),
          const SizedBox(width: 10),
          Expanded(
            child: SkSeg<String>(
              options: firstOpts,
              value: firstVal,
              onChanged: t.setSearchFirst,
            ),
          ),
        ]),
        if (t.localTracks.isNotEmpty) ...[
          const SizedBox(height: 16),
          card(Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Отвязать от папки',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${tracksWord(t.localTracks.length)} из файлов — найду онлайн и заменю',
                    style: TextStyle(fontSize: 12, color: k.muted)),
              ]),
            ),
            const SizedBox(width: 10),
            SkButton('Найти', height: 34, onTap: busy ? null : t.startRelink),
          ])),
        ],
        if (busy) ...[
          const SizedBox(height: 20),
          const Center(child: CircularProgressIndicator()),
        ],
        if (t.error != null) ...[
          const SizedBox(height: 14),
          Text(t.error!, style: TextStyle(color: k.bad)),
        ],
      ];
      dock = SkButton('Найти треки',
          primary: true, height: 52, expand: true, onTap: busy ? null : () => _start());
    } else {
      final notFound = t.items.where((i) => i.done && i.found == null).toList();
      final foundN = t.items.where((i) => i.found != null).length;
      final shown = t.items.where((i) => switch (_filter) {
            'found' => i.found != null,
            'missing' => i.done && i.found == null,
            _ => true,
          });
      final firstCovers = [for (final i in t.items) if (i.found != null) i.found!].take(4).toList();
      body = [
        card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox.square(
              dimension: 44,
              child: firstCovers.isEmpty
                  ? Container(
                      decoration: BoxDecoration(
                          color: k.inner, borderRadius: BorderRadius.circular(k.sharp ? 0 : 8)))
                  : Artwork(track: firstCovers.first, size: 44, radius: k.sharp ? 0 : 8),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    t.relinking
                        ? 'Замена файлов'
                        : (_name.text.isNotEmpty ? _name.text : t.suggestedName.isEmpty ? 'Перенос' : t.suggestedName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                    busy
                        ? 'ищу ${t.doneCount} из ${t.items.length}'
                        : 'нашёл ${t.foundCount} из ${t.items.length}',
                    style: k.st.caption(color: k.muted, size: 12).copyWith(letterSpacing: 0)),
              ]),
            ),
            SkButton(busy ? 'Отменить' : 'Заново', height: 32, onTap: () {
              t.reset();
              _input.clear();
              if (busy) AppActions.toast(context, 'Перенос отменён');
            }),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(k.sharp ? 0 : 3),
            child: LinearProgressIndicator(
              value: t.items.isEmpty ? null : t.doneCount / t.items.length,
              minHeight: 6,
              color: k.btn,
              backgroundColor: k.off,
            ),
          ),
        ])),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          SkChip('Все ${t.items.length}', selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
          SkChip('Нашёл $foundN', selected: _filter == 'found', onTap: () => setState(() => _filter = 'found')),
          SkChip('Не нашёл ${notFound.length}',
              selected: _filter == 'missing', onTap: () => setState(() => _filter = 'missing')),
        ]),
        const SizedBox(height: 6),
        for (final item in shown) _PhoneItem(item: item),
      ];
      dock = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!t.relinking) ...[
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: k.sharp ? Colors.transparent : k.inner,
              border: k.sharp ? Border.all(color: k.ghost) : null,
              borderRadius: BorderRadius.circular(k.sharp ? 0 : k.glass ? 23 : 12),
            ),
            child: Row(children: [
              Icon(Ic.playlist_add, size: 18, color: k.muted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _name,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'Название плейлиста (пусто — только в медиатеку)',
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        SkButton(
          '${t.relinking ? 'Заменить' : 'Добавить'} ${tracksWord(t.selectedCount)}',
          primary: true,
          height: 52,
          expand: true,
          onTap: t.stage == TransferStage.ready && t.selectedCount > 0 ? _save : null,
        ),
        if (notFound.isNotEmpty && !busy)
          TextButton(
            onPressed: () {
              for (final i in notFound) {
                t.retry(i, where: 'youtube');
              }
            },
            child: Text('Искать ненайденные на YouTube · ${notFound.length}',
                style: TextStyle(color: k.text, fontWeight: FontWeight.w600)),
          ),
      ]);
    }

    return Scaffold(
      body: Column(children: [
        header,
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: body,
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: k.line)),
          ),
          child: dock,
        ),
      ]),
    );
  }

  static const _shortHints = {
    'spotify': 'Трек, альбом или плейлист',
    'yandex': 'Открытый плейлист или альбом',
    'youtube': 'Плейлист YouTube или YouTube Music',
    'soundcloud': 'Плейлист или альбом',
    'folder': 'Файлы на устройстве — найду онлайн',
    'csv': 'Например, из Exportify',
    'text': '«Исполнитель — Название» по строкам',
  };

  /// Выбранная плитка-источник: от неё зависят подсказка и вид поля.
  String _src = 'spotify';

  static const _sources = [
    ('spotify', 'Spotify', Color(0xFF1ED760)),
    ('yandex', 'Яндекс Музыка', Color(0xFFFFCC00)),
    ('youtube', 'YouTube', Color(0xFFFF3D3D)),
    ('soundcloud', 'SoundCloud', Color(0xFFFF7A1A)),
    ('folder', 'Из папки', Color(0xFF34D399)),
    ('csv', 'Файл CSV', Color(0xFF4DA3FF)),
    ('text', 'Списком', Color(0xFFA78BFA)),
  ];

  static const _hints = {
    'spotify': 'Ссылка на трек, альбом или плейлист Spotify. Плейлист длиннее 50 треков — '
        'скачай его в CSV на exportify.net и выбери «Файл CSV».',
    'yandex': 'Ссылка на открытый плейлист или альбом Яндекс Музыки.',
    'youtube': 'Ссылка на плейлист YouTube или YouTube Music.',
    'soundcloud': 'Ссылка на плейлист или альбом SoundCloud.',
    'folder': 'Выбери папку с музыкой — Hutred найдёт каждый трек на Spotify, SoundCloud '
        'или YouTube по названию файла и сложит в медиатеку. Сами файлы не нужны.',
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
    if (!wide) return _phone(context, t, busy);

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
            if (src.$1 == 'folder') _pickFolder();
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
        final cols = box.maxWidth >= 760 ? 7 : 4;
        const gap = 10.0;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final src in _sources) SizedBox(width: w, child: tile(src)),
        ]);
      }),
      const SizedBox(height: 14),
      if (_src == 'folder')
        Align(
          alignment: Alignment.centerLeft,
          child: StyleButton(
            label: 'Выбрать папку',
            icon: Ic.folder_open_rounded,
            onPressed: busy ? null : _pickFolder,
          ),
        )
      else
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
      if (t.localTracks.isNotEmpty) ...[
        const SizedBox(height: 24),
        StylePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StyleCaption('Отвязать от папки'),
              const SizedBox(height: 8),
              Text(
                'В медиатеке ${tracksWord(t.localTracks.length)} из файлов на этом устройстве. '
                'Hutred найдёт их на Spotify, SoundCloud или YouTube и заменит — '
                'плейлисты, «любимое» и прослушивания останутся, а папка станет не нужна.',
                style: const TextStyle(color: HutredTheme.muted, height: 1.4, fontSize: 13),
              ),
              const SizedBox(height: 12),
              StyleButton(
                label: 'Найти онлайн',
                icon: Ic.search,
                onPressed: busy ? null : t.startRelink,
              ),
            ],
          ),
        ),
      ],
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
            TextButton.icon(
              onPressed: () {
                t.reset();
                _input.clear();
                if (busy) AppActions.toast(context, 'Перенос отменён');
              },
              icon: Icon(busy ? Ic.close : Ic.restart_alt, size: 18),
              label: Text(busy ? 'Отменить' : 'Заново'),
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
          if (t.relinking) ...[
            const StyleCaption('Заменить файлы'),
            const SizedBox(height: 10),
            const Text(
              'Отмеченные треки будут играть онлайн. Проверь найденное — '
              'неверное можно снять галочкой или поискать на YouTube.',
              style: TextStyle(color: HutredTheme.muted, fontSize: 13, height: 1.4),
            ),
          ] else ...[
            const StyleCaption('Куда сложить'),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                hintText: 'Название плейлиста',
                helperText: 'Пусто — только в медиатеку',
              ),
            ),
          ],
          const SizedBox(height: 14),
          StyleButton(
            label: '${t.relinking ? 'Заменить' : 'Добавить'} ${t.selectedCount}',
            icon: Ic.add,
            onPressed: t.stage == TransferStage.ready && t.selectedCount > 0 ? _save : null,
          ),
          const SizedBox(height: 10),
          StyleButton(
            label: busy ? 'Отменить перенос' : 'Не переносить',
            primary: false,
            onPressed: () {
              t.reset();
              _input.clear();
            },
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


/// Строка результата на телефоне: обложка, название, галочка или «Найти».
class _PhoneItem extends StatelessWidget {
  const _PhoneItem({required this.item});
  final TransferItem item;

  @override
  Widget build(BuildContext context) {
    final t = context.read<TransferService>();
    final k = Sk.of(context);
    final found = item.found;
    final missing = item.done && found == null;
    final r = BorderRadius.circular(k.sharp ? 0 : 8);
    Widget leading;
    if (!item.done) {
      leading = Container(
        decoration: BoxDecoration(color: k.inner, borderRadius: r),
        alignment: Alignment.center,
        child: const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (found == null) {
      leading = Container(
        decoration: BoxDecoration(borderRadius: r, border: Border.all(color: k.bad, width: 1.5)),
        alignment: Alignment.center,
        child: Text('?', style: TextStyle(color: k.bad, fontSize: 18, fontWeight: FontWeight.w800)),
      );
    } else {
      leading = Artwork(track: found, size: 44, radius: k.sharp ? 0 : 8);
    }
    return SizedBox(
      height: 60,
      child: Row(children: [
        SizedBox.square(dimension: 44, child: leading),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(found?.title ?? item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(children: [
                if (found != null) ...[
                  Icon(sourceIcon(found.source), size: 12, color: k.muted),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                      found != null
                          ? found.artist
                          : missing
                              ? 'Не нашёл · ${item.label}'
                              : 'ищу… ${item.artist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: missing ? k.bad : k.muted)),
                ),
              ]),
            ],
          ),
        ),
        if (item.done)
          PopupMenuButton<String>(
            tooltip: 'Искать в другом месте',
            onSelected: (where) => t.retry(item, where: where),
            itemBuilder: (_) => [
              if (context.read<SettingsStore>().hasSpotifyKeys)
                const PopupMenuItem(value: 'spotify', child: Text('Искать в Spotify')),
              const PopupMenuItem(value: 'soundcloud', child: Text('Искать на SoundCloud')),
              const PopupMenuItem(value: 'youtube', child: Text('Искать на YouTube')),
            ],
            child: missing
                ? IgnorePointer(child: SkButton('Найти', height: 30, onTap: () {}))
                : Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Ic.manage_search, size: 20, color: k.muted),
                  ),
          ),
        if (found != null)
          GestureDetector(
            onTap: () => t.setSelected(item, !item.selected),
            child: Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: item.selected ? k.btn : Colors.transparent,
                border: item.selected ? null : Border.all(color: k.ghost, width: 1.5),
                borderRadius: BorderRadius.circular(k.sharp ? 0 : k.glass ? 12 : 6),
              ),
              child: item.selected ? Icon(Ic.check, size: 16, color: k.btnFg) : null,
            ),
          ),
      ]),
    );
  }
}
