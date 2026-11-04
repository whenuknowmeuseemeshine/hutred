part of 'settings_screen.dart';

/// Страница группы настроек по макету (компьютер — колонками,
/// телефон — те же карточки друг под другом).
Widget settingsPageFor(String group) => switch (group) {
      'Внешний вид' => const _LookPage(),
      'Воспроизведение' => const _PlayPage(),
      'Медиатека и волна' => const _LibraryPage(),
      'Тексты и обложки' => const _LyricsPage(),
      'Сеть и YouTube' => const _NetPage(),
      'Discord' => const _DiscordPage(),
      'Загрузки и кэш' => const _DownloadsPage(),
      'Обновления' => const _UpdatesPage(),
      'Админ' => const _AdminPage(),
      _ => const SizedBox.shrink(),
    };

/// Подзаголовки страниц из макета.
const _pageSubtitles = {
  'Внешний вид': 'Как выглядит Hutred на этом устройстве',
  'Воспроизведение': 'Переходы, пауза и звук',
  'Медиатека и волна': 'Из чего «Моя волна» подбирает музыку и что она пропускает',
  'Тексты и обложки': 'Откуда брать караоке и картинки альбомов',
  'Сеть и YouTube': 'Как Hutred достаёт музыку, если что-то заблокировано',
  'Discord': 'Друзья в Discord видят, что ты слушаешь',
  'Загрузки и кэш': 'Что лежит на диске и сколько места занимает',
  'Обновления': 'Версия и как Hutred живёт на компьютере',
  'Админ': 'Общие ключи раздаются всем пользователям Hutred автоматически',
};

Color _hashColor(String s) {
  final h = s.hashCode;
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.22, 0.30).toColor();
}

String _fmtBytes(int b) => b >= 1024 * 1024 * 1024
    ? '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} ГБ'
    : '${(b / (1024 * 1024)).round()} МБ';

// ───────────────────────────── Внешний вид ─────────────────────────────

class _LookPage extends StatelessWidget {
  const _LookPage();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final k = Sk.of(context);

    // Стиль: три превью.
    final styles = SkCard(
      child: SkGap(children: [
        Row(children: [
          const Expanded(child: SkCap('Стиль')),
          if (s.styleRestartNeeded) ...[
            Text('Применится после перезапуска', style: k.small),
            if (Platform.isWindows) ...[
              const SizedBox(width: 10),
              SkButton('Перезапустить', height: 30, primary: true, onTap: () async {
                await XrayVpn.stop();
                await Future.delayed(const Duration(milliseconds: 400));
                await Process.start(Platform.resolvedExecutable, const [],
                    mode: ProcessStartMode.detached);
                exit(0);
              }),
            ],
          ] else
            Text('Меняется после перезапуска', style: k.small),
        ]),
        LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth < 420 ? 1 : 3;
          final w = (box.maxWidth - 14 * (cols - 1)) / cols;
          return Wrap(spacing: 14, runSpacing: 14, children: [
            for (final info in appStyles)
              SizedBox(
                width: w,
                child: _StylePreview(
                  info: info,
                  selected: s.chosenStyle == info.id,
                  onTap: () => s.applyStyle(info.id),
                ),
              ),
          ]);
        }),
      ]),
    );

    final isPreset = accentPresets.any((c) => c.toARGB32() == s.accent.toARGB32());
    final accent = SkCard(
      child: SkGap(children: [
        const SkCap('Акцент'),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final c in accentPresets)
            _Dot(
              color: c,
              selected: s.accent.toARGB32() == c.toARGB32(),
              onTap: () => s.accent = c,
            ),
          _Dot(
            selected: !isPreset,
            onTap: () => showDialog(
              context: context,
              builder: (_) => ChangeNotifierProvider.value(
                value: s,
                child: _ColorPickerDialog(
                  title: 'Свой акцентный цвет',
                  initial: s.accent,
                  onApply: (c) => s.accent = c,
                ),
              ),
            ),
          ),
        ]),
        SkRow(
          filled: false,
          divider: true,
          title: 'Подкрашивать под обложку',
          sub: 'Плеер берёт цвет из играющего трека',
          trailing: SkToggle(value: s.tintFromCover, onChanged: (v) => s.tintFromCover = v),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: SkButton('Вернуть цвета по умолчанию', height: 32, onTap: s.reset),
        ),
      ]),
    );

    Widget bgTile({
      required Widget child,
      required bool selected,
      required VoidCallback onTap,
      Color? color,
      String? tooltip,
    }) =>
        Tooltip(
          message: tooltip ?? '',
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(k.ri),
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color ?? k.inner,
                borderRadius: BorderRadius.circular(k.ri),
                border: Border.all(
                    color: selected ? k.btn : (k.cardBorder == null ? Colors.transparent : k.ghost),
                    width: selected ? 2 : 1),
              ),
              child: child,
            ),
          ),
        );

    final bg = SkCard(
      child: SkGap(children: [
        SkCap(HutredTheme.desktop ? 'Фон и масштаб' : 'Фон'),
        LayoutBuilder(builder: (context, box) {
          const cols = 4;
          final w = (box.maxWidth - 8 * (cols - 1)) / cols;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final b in backgroundPresets)
              SizedBox(
                width: w,
                child: bgTile(
                  tooltip: b.name,
                  color: b.ink,
                  selected: s.background.id == b.id,
                  onTap: () => s.backgroundId = b.id,
                  child: const SizedBox.shrink(),
                ),
              ),
            SizedBox(
              width: w,
              child: bgTile(
                tooltip: 'Свой цвет фона',
                color: s.customBgColor,
                selected: s.background.id == 'custom',
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => ChangeNotifierProvider.value(
                    value: s,
                    child: _ColorPickerDialog(
                      title: 'Свой цвет фона',
                      initial: s.customBgColor,
                      onApply: (c) => s.customBgColor = c,
                    ),
                  ),
                ),
                child: Icon(Ic.colorize, size: 16, color: k.muted),
              ),
            ),
            SizedBox(
              width: w,
              child: bgTile(
                tooltip: 'Своя картинка или GIF за кругом «Волны»',
                selected: s.waveBackground != null,
                onTap: () async {
                  if (s.waveBackground != null) {
                    await s.setWaveBackground(null);
                    return;
                  }
                  final res = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: const ['gif', 'png', 'jpg', 'jpeg', 'webp'],
                  );
                  final path = res?.files.single.path;
                  if (path != null) await s.setWaveBackground(path);
                },
                child: Text(s.waveBackground == null ? 'Своя картинка' : 'Убрать картинку',
                    textAlign: TextAlign.center, style: k.small.copyWith(fontSize: 11)),
              ),
            ),
          ]);
        }),
        if (HutredTheme.desktop)
          SkSeg<double>(
            options: const [
              (0.0, 'Авто'),
              (1.0, '100%'),
              (1.15, '115%'),
              (1.3, '130%'),
              (1.5, '150%'),
            ],
            value: s.uiScale,
            onChanged: (v) => s.uiScale = v,
          ),
      ]),
    );

    return SkGap(gap: 20, children: [
      styles,
      SkCols(children: [accent, bg]),
      const _TabsCard(),
    ]);
  }
}

class _StylePreview extends StatelessWidget {
  const _StylePreview({required this.info, required this.selected, required this.onTap});
  final AppStyleInfo info;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = Sk.of(context);
    final (Decoration pbg, double br, Color b1, Color b2) = switch (info.id) {
      'glass' => (
          BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const RadialGradient(
              center: Alignment(-0.6, -0.8),
              radius: 1.4,
              colors: [Color(0xFF1F6F6A), Color(0xFF071C22)],
            ),
          ),
          10.0,
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.18),
        ),
      'sharp' => (
          BoxDecoration(
            color: const Color(0xFF0A0A0A),
            border: Border.all(color: const Color(0xFF2A2A2A)),
          ),
          0.0,
          const Color(0xFF1C1C1C),
          const Color(0xFF3DDC97),
        ),
      _ => (
          BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
          5.0,
          const Color(0xFF161616),
          const Color(0xFF2A2A2A),
        ),
    };
    return Material(
      color: k.inner,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(k.ri),
        side: BorderSide(
            color: selected ? k.btn : const Color(0xFF2A2A2A), width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 110,
              padding: const EdgeInsets.all(8),
              decoration: pbg,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  width: 30,
                  decoration:
                      BoxDecoration(color: b1, borderRadius: BorderRadius.circular(br)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(children: [
                    Container(
                      height: 30,
                      decoration:
                          BoxDecoration(color: b2, borderRadius: BorderRadius.circular(br)),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 30,
                      decoration:
                          BoxDecoration(color: b1, borderRadius: BorderRadius.circular(br)),
                    ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Text(info.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              if (selected)
                Text('Сейчас', style: TextStyle(fontSize: 13, color: k.ok)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Кружок акцентного цвета; без [color] — «свой цвет».
class _Dot extends StatelessWidget {
  const _Dot({this.color, required this.selected, required this.onTap});
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = Sk.of(context);
    final shape = k.sharp ? BoxShape.rectangle : BoxShape.circle;
    return Tooltip(
      message: color == null ? 'Свой цвет' : '',
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: shape,
            color: color,
            gradient: color == null
                ? const SweepGradient(colors: [
                    Colors.red, Colors.yellow, Colors.green, Colors.cyan,
                    Colors.blue, Colors.purple, Colors.red,
                  ])
                : null,
            border: Border.all(color: selected ? k.text : Colors.transparent, width: 3),
          ),
          child: color == null ? Icon(Ic.colorize, size: 14, color: Colors.white) : null,
        ),
      ),
    );
  }
}

/// «Вкладки»: тянуть — порядок, нажать — скрыть/показать.
class _TabsCard extends StatelessWidget {
  const _TabsCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final k = Sk.of(context);
    final order = s.navOrder;
    Widget chip(int i) {
      final id = order[i];
      final hidden = s.isTabHidden(id);
      final tab = navTabs[id]!;
      return Padding(
        key: ValueKey(id),
        padding: const EdgeInsets.only(right: 8),
        child: Tooltip(
          message: id == 'settings'
              ? 'Настройки всегда на месте'
              : hidden
                  ? 'Скрыта — нажми, чтобы показать'
                  : 'Нажми, чтобы скрыть',
          child: ReorderableDragStartListener(
            index: i,
            child: Material(
              color: hidden ? Colors.transparent : k.inner,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(k.sharp ? 0 : 16),
                side: hidden ? BorderSide(color: k.ghost) : BorderSide.none,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(k.sharp ? 0 : 16),
                onTap: id == 'settings' ? null : () => s.setTabHidden(id, !hidden),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('⋮⋮', style: TextStyle(fontSize: 12, color: k.muted)),
                    const SizedBox(width: 6),
                    Text(tab.label,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: hidden ? k.muted : k.text)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final list = SizedBox(
      height: 32,
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        onReorder: s.reorderNav,
        proxyDecorator: (c, _, __) => Material(color: Colors.transparent, child: c),
        children: [for (var i = 0; i < order.length; i++) chip(i)],
      ),
    );
    return SkCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: LayoutBuilder(builder: (context, box) {
        final hint = Text('Тяни — поменять порядок, нажми — скрыть', style: k.small);
        final reset = SkButton('Как было', height: 30, onTap: s.resetNavOrder);
        if (box.maxWidth < 900) {
          return SkGap(gap: 12, children: [
            const SkCap('Вкладки'),
            list,
            Row(children: [Expanded(child: hint), reset]),
          ]);
        }
        return Row(children: [
          const SkCap('Вкладки'),
          const SizedBox(width: 14),
          Expanded(child: list),
          const SizedBox(width: 14),
          hint,
          const SizedBox(width: 10),
          reset,
        ]);
      }),
    );
  }
}

// ───────────────────────────── Воспроизведение ─────────────────────────────

class _PlayPage extends StatelessWidget {
  const _PlayPage();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final k = Sk.of(context);

    final crossfade = SkCard(
      child: SkGap(gap: 16, children: [
        SkHead(
          title: 'Плавный переход',
          sub: 'Конец трека перетекает в начало следующего',
          trailing: SkToggle(value: s.crossfade, onChanged: (v) => s.crossfade = v),
        ),
        // Два трека «наплывают» друг на друга — тем сильнее, чем дольше переход.
        Container(
          height: 70,
          decoration: BoxDecoration(color: k.deep, borderRadius: BorderRadius.circular(k.ri)),
          clipBehavior: Clip.antiAlias,
          child: Builder(builder: (context) {
            final overlap = s.crossfade ? 0.12 + 0.26 * (s.crossfadeSec - 1) / 11 : 0.0;
            final wf = 0.5 + overlap / 2;
            Widget bar(bool left) => Align(
                  alignment: left ? Alignment.centerLeft : Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: wf,
                    child: Opacity(
                      opacity: left ? 1 : (s.crossfade ? 0.85 : 0.3),
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(k.ri),
                          gradient: LinearGradient(
                            begin: left ? Alignment.centerLeft : Alignment.centerRight,
                            end: left ? Alignment.centerRight : Alignment.centerLeft,
                            colors: left
                                ? [k.dim, k.dim, k.dim.withValues(alpha: 0)]
                                : [k.btn, k.btn, k.btn.withValues(alpha: 0)],
                            stops: const [0, 0.7, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
            return Stack(fit: StackFit.expand, children: [bar(true), bar(false)]);
          }),
        ),
        Row(children: [
          Text('1 с', style: k.small),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: k.btn,
                inactiveTrackColor: k.off,
                thumbColor: k.text,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: SliderComponentShape.noOverlay,
                disabledActiveTrackColor: k.dim,
                disabledInactiveTrackColor: k.off,
                disabledThumbColor: k.dim,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Slider(
                  min: 1,
                  max: 12,
                  divisions: 11,
                  value: s.crossfadeSec.toDouble(),
                  onChanged: s.crossfade ? (v) => s.crossfadeSec = v.round() : null,
                ),
              ),
            ),
          ),
          Text('${s.crossfadeSec} с',
              style: k.st.caption(color: k.text, size: 13).copyWith(fontWeight: FontWeight.w700)),
        ]),
      ]),
    );

    final fade = SkCard(
      child: SkGap(gap: 16, children: [
        SkHead(
          title: 'Плавная пауза',
          sub: 'Звук затихает за полсекунды',
          trailing: SkToggle(value: s.fadePause, onChanged: (v) => s.fadePause = v),
        ),
        Container(
          height: 70,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: k.deep, borderRadius: BorderRadius.circular(k.ri)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 24; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                child: Container(
                  height: s.fadePause ? (50 - i * 2).clamp(6, 50).toDouble() : 44,
                  decoration: BoxDecoration(
                    color: k.dim,
                    borderRadius: BorderRadius.circular(k.sharp ? 0 : 3),
                  ),
                ),
              ),
            ],
          ]),
        ),
        Text('При продолжении звук так же плавно нарастает', style: k.small),
      ]),
    );

    return SkGap(gap: 20, children: [
      SkCols(equal: true, children: [crossfade, fade]),
      if (Platform.isIOS || Platform.isMacOS)
        SkCard(
          child: SkHead(
            title: 'Эквалайзер',
            sub: 'Недоступен на устройствах Apple: системный плеер не даёт менять частоты',
          ),
        )
      else
        const EqualizerScreen(embedded: true, card: true),
    ]);
  }
}

// ───────────────────────────── Медиатека и волна ─────────────────────────────

class _LibraryPage extends StatefulWidget {
  const _LibraryPage();

  @override
  State<_LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<_LibraryPage> {
  bool _allHidden = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final wave = context.watch<WaveService>();
    final fav = context.watch<LibraryStore>().favorites.length;
    final k = Sk.of(context);
    final artists = wave.favoriteArtists;

    void editArtists() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const ArtistPickerScreen(standalone: true)));

    Widget avatar(String name, {String? label, Color? color}) => SizedBox(
          width: 64,
          child: Column(children: [
            Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color ?? _hashColor(name),
                shape: k.sharp ? BoxShape.rectangle : BoxShape.circle,
              ),
              child: Text(label ?? (name.isEmpty ? '?' : name.characters.first.toUpperCase()),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 6),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Color(0xFFCFCFCF))),
          ]),
        );

    final favCard = SkCard(
      child: SkGap(children: [
        Row(children: [
          Expanded(child: Text('Любимые исполнители', style: k.h)),
          TextButton(
            onPressed: editArtists,
            child: Text(artists.isEmpty ? 'Выбрать' : 'Изменить',
                style: TextStyle(fontWeight: FontWeight.w600, color: k.text)),
          ),
        ]),
        if (artists.isEmpty)
          InkWell(
            onTap: editArtists,
            child: Container(
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(k.ri),
                border: Border.all(color: k.ghost),
              ),
              child: Text('Пока никого — нажми, чтобы выбрать', style: k.sub),
            ),
          )
        else
          LayoutBuilder(builder: (context, box) {
            final fit = ((box.maxWidth + 14) / 78).floor().clamp(1, 12);
            final shown = artists.length > fit ? artists.take(fit - 1).toList() : artists;
            final more = artists.length - shown.length;
            return Wrap(spacing: 14, runSpacing: 10, children: [
              for (final a in shown) avatar(a),
              if (more > 0) avatar('ещё $more', label: '+$more', color: k.inner),
            ]);
          }),
        Text('Пока лайков мало, волна опирается на них', style: k.small),
      ]),
    );

    Widget stat(int n, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text(label, style: k.small.copyWith(fontSize: 11)),
          ]),
        );

    final autoCard = SkCard(
      child: SkGap(gap: 12, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Добавленное — сразу в любимые',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('Как в Spotify: получает ♥ и качается с любимыми', style: k.small),
            ]),
          ),
          const SizedBox(width: 12),
          SkToggle(value: s.autoFavorite, onChanged: (v) => s.autoFavorite = v),
        ]),
        Container(
          padding: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: k.line))),
          child: Row(children: [
            stat(fav, 'любимых'),
            stat(wave.dislikedCount, 'скрыто'),
            stat(wave.blockedArtists.length, 'в чёрном списке'),
          ]),
        ),
      ]),
    );

    final blocked = wave.blockedArtists;
    final blackCard = SkCard(
      child: SkGap(gap: 12, children: [
        Text(blocked.isEmpty ? 'Чёрный список' : 'Чёрный список · ${blocked.length}', style: k.h),
        if (blocked.isEmpty)
          Container(
            constraints: const BoxConstraints(minHeight: 180),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(k.ri),
              border: Border.all(color: k.off),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Ic.person_off_outlined, size: 28, color: k.muted),
              const SizedBox(height: 8),
              const Text('Пусто', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'Исполнитель отсюда не играет нигде, даже на фитах. '
                'Добавить — в меню трека',
                textAlign: TextAlign.center,
                style: k.small,
              ),
            ]),
          )
        else
          Column(children: [
            for (final n in blocked)
              SkRow(
                filled: false,
                divider: true,
                leading: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _hashColor(n),
                    shape: k.sharp ? BoxShape.rectangle : BoxShape.circle,
                  ),
                  child: Text(n.isEmpty ? '?' : n.characters.first.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                title: n,
                trailing: SkChip('Вернуть', height: 30, onTap: () => wave.unblockArtist(n)),
              ),
          ]),
      ]),
    );

    final hidden = wave.dislikedTracks;
    final shownHidden = _allHidden ? hidden : hidden.take(6).toList();
    final hiddenCard = SkCard(
      child: SkGap(gap: 10, children: [
        Row(children: [
          Expanded(child: Text('Скрытые треки · ${hidden.length}', style: k.h)),
          SkButton('Вернуть все',
              height: 32, onTap: hidden.isEmpty ? null : wave.resetDislikes),
        ]),
        if (hidden.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text('Треки с 👎 не играют в очередях, плейлистах и волне. Пока таких нет',
                style: k.sub),
          )
        else
          Column(children: [
            for (final t in shownHidden)
              SkRow(
                filled: false,
                divider: true,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _hashColor('${t.artist}${t.title}'),
                    borderRadius: BorderRadius.circular(k.sharp ? 0 : 6),
                  ),
                ),
                title: t.title,
                sub: t.artist,
                trailing: SkChip('Вернуть', height: 30, onTap: () => wave.undislikeKey(t.key)),
              ),
            if (hidden.length > shownHidden.length)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _allHidden = true),
                  child: Text('Показать ещё ${hidden.length - shownHidden.length}',
                      style: TextStyle(color: k.text)),
                ),
              ),
          ]),
      ]),
    );

    return SkGap(gap: 20, children: [
      SkCols(flex: const [12, 10], children: [favCard, autoCard]),
      SkCols(flex: const [10, 14], children: [blackCard, hiddenCard]),
    ]);
  }
}

// ───────────────────────────── Тексты и обложки ─────────────────────────────

class _LyricsPage extends StatelessWidget {
  const _LyricsPage();

  static const _info = {
    'lrclib': ('LRCLIB и NetEase', 'Тексты с таймингами — караоке'),
    'youtube': ('Субтитры YouTube', 'Если залиты в клип'),
    'genius': ('Genius', 'Полный текст без таймингов'),
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final acc = context.watch<AccountService>();
    final k = Sk.of(context);
    final order = s.lyricsOrder;

    Widget toggleFor(String id) => switch (id) {
          'youtube' => SkToggle(value: s.youtubeLyrics, onChanged: (v) => s.youtubeLyrics = v),
          'genius' => SkToggle(value: s.geniusLyrics, onChanged: (v) => s.geniusLyrics = v),
          _ => const Tooltip(
              message: 'Основной источник — всегда включён',
              child: SkToggle(value: true),
            ),
        };

    final lyrics = SkCard(
      child: SkGap(children: [
        const SkCap('Тексты песен'),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: k.deep, borderRadius: BorderRadius.circular(k.ri)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Я иду по ночному городу',
                style: TextStyle(fontSize: 15, color: k.text.withValues(alpha: 0.35))),
            const SizedBox(height: 8),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'И не помню, '),
              TextSpan(
                  text: 'куда и зачем',
                  style: TextStyle(color: k.text.withValues(alpha: 0.4))),
            ]), style: k.st.display(20).copyWith(fontSize: 20)),
            const SizedBox(height: 8),
            Text('Свет витрин отражает лица',
                style: TextStyle(fontSize: 15, color: k.text.withValues(alpha: 0.35))),
          ]),
        ),
        Text('Где искать по порядку — перетащи, чтобы поменять', style: k.sub),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: s.moveLyricsSource,
          proxyDecorator: (c, _, __) => Material(color: Colors.transparent, child: c),
          children: [
            for (final (i, id) in order.indexed)
              Padding(
                key: ValueKey(id),
                padding: const EdgeInsets.only(bottom: 8),
                child: ReorderableDragStartListener(
                  index: i,
                  child: SkRow(
                    leading: Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: k.sharp ? Colors.transparent : const Color(0xFF262626),
                        border: k.sharp ? Border.all(color: k.ghost) : null,
                        shape: k.sharp ? BoxShape.rectangle : BoxShape.circle,
                      ),
                      child: Text('${i + 1}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    title: _info[id]!.$1,
                    sub: _info[id]!.$2,
                    trailing: toggleFor(id),
                  ),
                ),
              ),
          ],
        ),
        if (Platform.isAndroid || Platform.isIOS)
          SkRow(
            title: 'Строка текста на обложке',
            sub: 'В плеере поверх обложки — текущая строка песни',
            trailing: SkToggle(value: s.lyricsOnCover, onChanged: (v) => s.lyricsOnCover = v),
          ),
      ]),
    );

    final covers = SkCard(
      child: SkGap(children: [
        const SkCap('Обложки'),
        Row(children: [
          Container(
            width: 120,
            height: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2C),
              borderRadius: BorderRadius.circular(k.sharp ? 0 : 8),
            ),
            child: const Text('кадр из клипа',
                style: TextStyle(fontSize: 11, color: Color(0xFF9A9A9A))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Icon(Ic.arrow_forward_rounded, size: 22, color: k.muted),
          ),
          Container(
            width: 96,
            height: 96,
            padding: const EdgeInsets.all(8),
            alignment: Alignment.bottomLeft,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(k.ri),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [k.mono ? const Color(0xFF5B4A3A) : k.accent, const Color(0xFF2A2A2A)],
              ),
            ),
            child: Text('обложка альбома',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: k.mono ? Colors.white : HutredTheme.onAccent(k.accent))),
          ),
        ]),
        SkRow(
          title: 'Искать автоматически',
          sub: 'Когда трек заиграл: Genius → Spotify → iTunes',
          trailing: SkToggle(value: s.geniusCovers, onChanged: (v) => s.geniusCovers = v),
        ),
        SkRow(
          title: 'Заменять превью YouTube',
          sub: 'Квадрат альбома вместо кадра',
          trailing: SkToggle(
              value: s.replaceYoutubeCovers,
              onChanged: s.geniusCovers ? (v) => s.replaceYoutubeCovers = v : null),
        ),
        SkRow(
          title: 'Сверять новые треки',
          sub: s.hasSpotifyKeys
              ? 'Точные название, исполнитель и обложка из Spotify'
              : 'Нужны ключи Spotify',
          trailing: SkToggle(
              value: s.spotifyCheck,
              onChanged: s.hasSpotifyKeys ? (v) => s.spotifyCheck = v : null),
        ),
        if (acc.isAdmin)
          SkRow(
            filled: false,
            title: 'Ключи Spotify',
            sub: s.hasSpotifyKeys ? 'Заданы' : 'Не заданы — Spotify пропускается',
            trailing: SkButton('Изменить',
                height: 30,
                onTap: () =>
                    showDialog(context: context, builder: (_) => const _SpotifyKeysDialog())),
          ),
        // ИИ для текстов — статус; настроить может админ.
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: acc.isAdmin
                ? () => showDialog(context: context, builder: (_) => const _AiKeyDialog())
                : null,
            borderRadius: BorderRadius.circular(k.ri),
            child: Ink(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(k.ri),
                border: Border.all(color: k.sharp ? k.ghost : const Color(0xFF262626)),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('ИИ для текстов', style: k.rowTitle),
                    Text('Подгоняет тайминги, если их нет', style: k.small),
                  ]),
                ),
                Text(s.hasAi ? 'Подключён' : 'Не подключён',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: s.hasAi ? k.ok : k.muted)),
              ]),
            ),
          ),
        ),
      ]),
    );

    return SkCols(children: [lyrics, covers]);
  }
}

// ───────────────────────────── Сеть и YouTube ─────────────────────────────

class _NetPage extends StatelessWidget {
  const _NetPage();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final acc = context.watch<AccountService>();
    final k = Sk.of(context);

    final relayUrl = HutredRelay.url;
    final relayStatus = relayUrl == null
        ? 'Не настроен'
        : !acc.signedIn
            ? 'Нужен вход'
            : switch (s.relayMode) {
                'always' => 'Всегда',
                'off' => 'Выключен',
                _ => 'Когда нужно',
              };

    final noVpn = SkCard(
      child: SkGap(gap: 12, children: [
        const SkCap('Без VPN'),
        ValueListenableBuilder<String>(
          valueListenable: DpiBypass.status,
          builder: (_, st, __) => SkRow(
            title: 'Обход блокировок',
            sub: 'Как zapret, только для Hutred',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                s.dpiBypass
                    ? (s.dnsOnly ? 'Только DNS' : 'Способ: ${DpiBypass.strategyLabel(s.dpiStrategy ?? 'split').toLowerCase()}')
                    : 'Выкл',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: s.dpiBypass ? k.ok : k.muted),
              ),
              const SizedBox(width: 12),
              SkToggle(value: s.dpiBypass, onChanged: (v) => s.dpiBypass = v),
            ]),
          ),
        ),
        SkRow(
          title: 'Только безопасный DNS',
          sub: 'Мягкий режим через 1.1.1.1',
          trailing: SkToggle(
              value: s.dnsOnly, onChanged: s.dpiBypass ? (v) => s.dnsOnly = v : null),
        ),
        if (s.dpiBypass && !s.dnsOnly) const _DpiStrategies(),
        ValueListenableBuilder<bool>(
          valueListenable: DpiBypass.zapretRunning,
          builder: (_, z, __) => !z
              ? const SizedBox.shrink()
              : Text('Запущен zapret — он уже обходит блокировки, встроенный обход отключён',
                  style: k.small),
        ),
        SkRow(
          title: 'Сервер Hutred',
          sub: 'Когда трек не открывается',
          trailing: Text(relayStatus,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: relayUrl != null && acc.signedIn && s.relayMode != 'off'
                      ? k.ok
                      : k.muted)),
        ),
        if (relayUrl != null)
          SkSeg<String>(
            options: const [('auto', 'Когда нужно'), ('always', 'Всегда'), ('off', 'Никогда')],
            value: s.relayMode,
            onChanged: (v) => s.relayMode = v,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: SkButton('Проверить связь',
              primary: true, height: 38, onTap: () => showNetCheck(context)),
        ),
      ]),
    );

    return SkGap(gap: 20, children: [
      if (XrayVpn.supported) const SkCard(child: _VpnTile()),
      SkCols(children: [noVpn, const _HostCheckCard()]),
    ]);
  }
}

/// Способы разрезания соединения и «подобрать заново».
class _DpiStrategies extends StatefulWidget {
  const _DpiStrategies();

  @override
  State<_DpiStrategies> createState() => _DpiStrategiesState();
}

class _DpiStrategiesState extends State<_DpiStrategies> {
  String? _progress;

  Future<void> _tune() async {
    final s = context.read<SettingsStore>();
    setState(() => _progress = 'Проверяю…');
    final best = await DpiBypass.autotune(
        onProgress: (p) => mounted ? setState(() => _progress = p) : null);
    s.setDpiStrategy(best);
    if (mounted) setState(() => _progress = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final k = Sk.of(context);
    return ValueListenableBuilder<String>(
      valueListenable: DpiBypass.status,
      builder: (_, st, __) => SkGap(gap: 8, children: [
        Text(
            _progress ??
                (st.isEmpty ? 'Способ ещё не подбирался — Hutred проверит сам' : st),
            style: k.small),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final key in DpiBypass.strategies)
            SkChip(
              DpiBypass.strategyLabel(key),
              selected: (s.dpiStrategy ?? 'split') == key,
              onTap: () {
                DpiBypass.strategy = key;
                s.setDpiStrategy(key);
                DpiBypass.status.value =
                    'Способ: ${DpiBypass.strategyLabel(key)} (выбран вручную)';
              },
            ),
          SkButton(_progress == null ? 'Подобрать заново' : 'Подбираю…',
              height: 32, onTap: _progress == null ? _tune : null),
        ]),
      ]),
    );
  }
}

/// «Проверка связи» прямо на странице: какие сайты отвечают и как быстро.
class _HostCheckCard extends StatefulWidget {
  const _HostCheckCard();

  @override
  State<_HostCheckCard> createState() => _HostCheckCardState();
}

class _HostCheckCardState extends State<_HostCheckCard> {
  static const _hosts = [
    ('youtube.com', 'https://www.youtube.com/generate_204'),
    ('googlevideo.com', 'https://redirector.googlevideo.com/generate_204'),
    ('soundcloud.com', 'https://soundcloud.com/'),
    ('api.deezer.com', 'https://api.deezer.com/'),
    ('spotify.com', 'https://open.spotify.com/'),
    ('lrclib.net', 'https://lrclib.net/'),
  ];

  /// null — проверяется; -1 — нет связи; иначе мс.
  final Map<String, int?> _ms = {};
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _ms.clear();
    });
    await Future.wait(_hosts.map((h) async {
      final sw = Stopwatch()..start();
      int v;
      try {
        await http.get(Uri.parse(h.$2)).timeout(const Duration(seconds: 8));
        v = sw.elapsedMilliseconds;
      } catch (_) {
        v = -1;
      }
      if (mounted) setState(() => _ms[h.$1] = v);
    }));
    if (mounted) setState(() => _running = false);
  }

  static const _browsers = {
    '': 'Без входа',
    'firefox': 'Firefox',
    'chrome': 'Chrome',
    'edge': 'Edge',
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final k = Sk.of(context);
    final mono = k.st.caption(color: k.text, size: 13).copyWith(
        fontFamily: 'JetBrains Mono', fontFamilyFallback: const ['Consolas', 'monospace']);
    final browser = _browsers.containsKey(s.youtubeCookiesBrowser) ? s.youtubeCookiesBrowser : '';
    return SkCard(
      child: SkGap(gap: 12, children: [
        Row(children: [
          const Expanded(child: SkCap('Проверка связи')),
          SkButton(_running ? 'Проверяю…' : 'Ещё раз', height: 30, onTap: _running ? null : _run),
        ]),
        for (final h in _hosts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: k.sharp ? BoxShape.rectangle : BoxShape.circle,
                  color: switch (_ms[h.$1]) {
                    null => k.off,
                    -1 => k.bad,
                    final int v when v > 1500 => k.warn,
                    _ => k.ok,
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(h.$1, style: mono.copyWith(letterSpacing: 0))),
              Text(
                  switch (_ms[h.$1]) {
                    null => '…',
                    -1 => 'нет связи',
                    final int v when v > 1500 => 'медленно',
                    final int v => '$v мс',
                  },
                  style: mono.copyWith(color: k.muted, letterSpacing: 0)),
            ]),
          ),
        const SizedBox(height: 4),
        SkRow(
          title: 'Брать треки с YouTube',
          sub: s.youtubeAuto
              ? 'В поиске и когда трека нет на SoundCloud. Грузятся дольше'
              : 'Выключено: только SoundCloud — быстрее. Треки с YouTube из медиатеки играют',
          trailing: SkToggle(value: s.youtubeAuto, onChanged: (v) => s.youtubeAuto = v),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(k.ri),
            border: Border.all(color: k.sharp ? k.ghost : const Color(0xFF262626)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Вход в YouTube для 18+', style: k.rowTitle),
                Text('Берёт вход из браузера. Лучше Firefox и второй аккаунт',
                    style: k.small),
              ]),
            ),
            PopupMenuButton<String>(
              initialValue: browser,
              onSelected: (v) => s.youtubeCookiesBrowser = v,
              itemBuilder: (_) => [
                for (final e in _browsers.entries)
                  PopupMenuItem(value: e.key, child: Text(e.value)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text('${_browsers[browser]} ▾',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────────── Discord ─────────────────────────────

class _DiscordPage extends StatelessWidget {
  const _DiscordPage();

  String _t(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final acc = context.watch<AccountService>();
    final player = context.watch<PlayerService>();
    final k = Sk.of(context);
    final t = player.current;

    final preview = SkCard(
      child: SkGap(children: [
        const SkCap('Так это выглядит в профиле'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1F22),
            borderRadius: BorderRadius.circular(k.ri),
          ),
          child: StreamBuilder<Duration>(
            stream: player.positionStream,
            builder: (context, _) {
              final pos = player.position;
              final dur = player.duration ?? Duration.zero;
              final frac = dur.inMilliseconds == 0
                  ? 0.28
                  : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
              final hiddenNow = s.discordHideOnPause && !player.playing && t != null;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    !s.discordPresence || hiddenNow
                        ? 'СТАТУС СКРЫТ'
                        : player.playing || t == null
                            ? 'СЛУШАЕТ HUTRED'
                            : 'НА ПАУЗЕ · HUTRED',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: Color(0xFFB5BAC1))),
                const SizedBox(height: 10),
                Opacity(
                  opacity: !s.discordPresence || hiddenNow ? 0.35 : 1,
                  child: Row(children: [
                    SizedBox.square(
                      dimension: 72,
                      child: t == null
                          ? Container(
                              decoration: BoxDecoration(
                                  color: const Color(0xFF5B4A3A),
                                  borderRadius: BorderRadius.circular(8)))
                          : Artwork(track: t, size: 72, radius: 8),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t?.title ?? 'Призрак Оперы',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(height: 3),
                        Text(t?.artist ?? '3umph',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: Color(0xFFDBDEE1))),
                        if (s.discordTime) ...[
                          const SizedBox(height: 3),
                          Text(
                              t == null ? '0:53 из 3:13' : '${_t(pos)} из ${_t(dur)}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFFB5BAC1))),
                        ],
                      ]),
                    ),
                  ]),
                ),
                if (s.discordTime) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 4,
                      child: LinearProgressIndicator(
                        value: frac,
                        backgroundColor: const Color(0xFF4E5058),
                        color: const Color(0xFFF2F3F5),
                      ),
                    ),
                  ),
                ],
                if (s.discordButton) ...[
                  const SizedBox(height: 10),
                  Container(
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4E5058),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Слушать трек',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ],
              ]);
            },
          ),
        ),
      ]),
    );

    final opts = SkCard(
      child: SkGap(gap: 10, children: [
        const SkCap('Что показывать'),
        SkRow(
          title: 'Показывать трек',
          sub: 'Название, исполнитель, обложка',
          trailing: SkToggle(value: s.discordPresence, onChanged: (v) => s.discordPresence = v),
        ),
        SkRow(
          title: 'Время трека',
          sub: 'Полоска «сколько осталось»',
          trailing: SkToggle(
              value: s.discordTime, onChanged: s.discordPresence ? (v) => s.discordTime = v : null),
        ),
        SkRow(
          title: 'Кнопка «Слушать трек»',
          sub: 'Друг откроет трек на YouTube, Spotify или Deezer',
          trailing: SkToggle(
              value: s.discordButton,
              onChanged: s.discordPresence ? (v) => s.discordButton = v : null),
        ),
        SkRow(
          title: 'Скрывать на паузе',
          sub: 'Статус пропадает, пока музыка стоит',
          trailing: SkToggle(
              value: s.discordHideOnPause,
              onChanged: s.discordPresence ? (v) => s.discordHideOnPause = v : null),
        ),
        if (acc.isAdmin)
          SkRow(
            filled: false,
            title: 'Application ID',
            sub: s.ownDiscordAppId.isEmpty
                ? 'Не задан. discord.com/developers → New Application → Application ID'
                : s.ownDiscordAppId,
            trailing: SkButton('Изменить', height: 30, onTap: () async {
              final v = await AppActions.askText(context,
                  title: 'Application ID Discord',
                  hint: 'Например 1234567890123456789',
                  initial: s.ownDiscordAppId);
              if (v != null) s.discordAppId = v;
            }),
          ),
      ]),
    );

    final status = SkCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: ValueListenableBuilder<String>(
        valueListenable: DiscordPresence.status,
        builder: (_, st, __) {
          final connected = st.startsWith('Подключено');
          final String label;
          final Color color;
          if (!s.discordPresence) {
            label = 'Выключено';
            color = k.muted;
          } else if (s.discordAppId.isEmpty) {
            label = 'Нет Application ID';
            color = k.warn;
          } else if (connected) {
            label = 'Подключено';
            color = k.ok;
          } else if (st.isEmpty) {
            label = 'Подключаюсь…';
            color = k.muted;
          } else {
            label = 'Не подключено';
            color = k.warn;
          }
          return Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Discord должен быть открыт на этом компьютере',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                    s.discordPresence && st.isNotEmpty && !connected
                        ? st
                        : 'Статус обновляется сам при смене трека и паузе',
                    style: k.sub),
              ]),
            ),
            const SizedBox(width: 14),
            SkStatus(label, color: color),
          ]);
        },
      ),
    );

    return SkGap(gap: 20, children: [
      SkCols(children: [preview, opts]),
      status,
    ]);
  }
}

// ───────────────────────────── Загрузки и кэш ─────────────────────────────

class _DownloadsPage extends StatefulWidget {
  const _DownloadsPage();

  @override
  State<_DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<_DownloadsPage> {
  int? _cache;

  @override
  void initState() {
    super.initState();
    _refreshCache();
  }

  Future<void> _refreshCache() async {
    try {
      final b = await YoutubeSource.cacheSize() + await _dirSize(await SoundcloudSource.cacheDir());
      if (mounted) setState(() => _cache = b);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final off = context.watch<OfflineService>();
    final k = Sk.of(context);
    final mobile = Platform.isAndroid || Platform.isIOS;

    final downloads = SkCard(
      child: SkGap(gap: 10, children: [
        Text('Загрузки', style: k.h),
        Text(
          '${tracksWord(off.count)} играют без интернета'
          '${off.pending > 0 ? ' · качается ещё ${off.pending}' : ''}. '
          'Скачать — в меню трека или кнопкой ⬇ у плейлиста',
          style: k.sub,
        ),
        SkRow(
          filled: false,
          divider: true,
          title: 'Качать любимые',
          sub: 'Новые любимые скачиваются сами',
          trailing: SkToggle(
            value: off.isPinned(null),
            onChanged: (v) async {
              if (!v) {
                final ok = await AppActions.confirm(context,
                    title: 'Не качать любимые?',
                    body: 'Скачанные любимые удалятся с устройства, в медиатеке они останутся.');
                if (!ok) return;
              }
              off.pin(null, v);
            },
          ),
        ),
        if (mobile)
          SkRow(
            filled: false,
            divider: true,
            title: 'Только по Wi-Fi',
            sub: off.waitingForWifi ? 'Сейчас мобильный интернет — ждём Wi-Fi' : null,
            trailing: SkToggle(value: s.wifiOnly, onChanged: (v) => s.wifiOnly = v),
          ),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (HutredTheme.desktop && off.folder != null)
            SkButton('Открыть папку', height: 40, onTap: () {
              final path = off.folder!.path;
              if (Platform.isWindows) {
                Process.start('explorer', [path]);
              } else if (Platform.isMacOS) {
                Process.start('open', [path]);
              } else {
                Process.start('xdg-open', [path]);
              }
            }),
          SkButton('Удалить все',
              height: 40,
              onTap: off.count == 0 && off.pending == 0
                  ? null
                  : () async {
                      final ok = await AppActions.confirm(context,
                          title: 'Удалить все загрузки?',
                          body: 'Треки останутся в медиатеке, но без интернета играть не будут.');
                      if (ok) await off.removeAll();
                    }),
        ]),
      ]),
    );

    final cache = SkCard(
      child: SkGap(gap: 10, children: [
        Text('Кэш прослушанного', style: k.h),
        Text('Треки, которые ты слушал недавно, — чтобы второй раз включались мгновенно',
            style: k.sub),
        SkSeg<int>(
          options: const [(500, '500 МБ'), (1024, '1 ГБ'), (3072, '3 ГБ'), (0, 'Без лимита')],
          value: s.cacheLimitMb,
          onChanged: (v) => s.cacheLimitMb = v,
        ),
        Text('Старые файлы удаляются сами, загрузки не трогаются', style: k.small),
        const SizedBox(height: 4),
        SkButton(
          _cache == null ? 'Очистить' : 'Очистить ${_fmtBytes(_cache!)}',
          primary: true,
          height: 40,
          expand: true,
          onTap: () async {
            await YoutubeSource.clearCache();
            await _clearDir(await SoundcloudSource.cacheDir());
            await _refreshCache();
          },
        ),
      ]),
    );

    Widget q(String v, String name, String size) {
      final on = s.audioQuality == v;
      return Material(
        color: on ? k.chip : Colors.transparent,
        borderRadius: BorderRadius.circular(k.ri),
        child: InkWell(
          borderRadius: BorderRadius.circular(k.ri),
          onTap: () => s.audioQuality = v,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: k.sharp ? BoxShape.rectangle : BoxShape.circle,
                  border: Border.all(color: on ? k.btn : k.ghost, width: 2),
                ),
                child: on
                    ? Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: k.btn, shape: k.sharp ? BoxShape.rectangle : BoxShape.circle),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(name, style: const TextStyle(fontSize: 14))),
              Text(size, style: k.small),
            ]),
          ),
        ),
      );
    }

    final quality = SkCard(
      child: SkGap(gap: 10, children: [
        Text('Качество', style: k.h),
        q('best', 'Лучшее', '~6 МБ/трек'),
        q('normal', 'Обычное', '~3 МБ/трек'),
        q('saver', 'Экономия', '~1,5 МБ/трек'),
        Text('Для треков с YouTube', style: k.small),
      ]),
    );

    return SkGap(gap: 20, children: [
      const SkCard(padding: EdgeInsets.all(24), child: _StorageBar()),
      SkCols(minWidth: 900, children: [downloads, cache, quality]),
    ]);
  }
}

// ───────────────────────────── Обновления ─────────────────────────────

class _UpdatesPage extends StatelessWidget {
  const _UpdatesPage();

  @override
  Widget build(BuildContext context) {
    final u = context.watch<UpdateService>();
    final k = Sk.of(context);
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    final status = !u.supported
        ? 'Эта копия собрана вручную — сама не обновляется'
        : u.checking
            ? 'Проверяю…'
            : u.progress != null
                ? 'Скачиваю обновление… ${(u.progress! * 100).round()}%'
                : u.readyToInstall
                    ? 'Новая версия скачана — поставится при перезапуске'
                    : u.available
                        ? 'Доступна сборка ${u.latestBuild}'
                        : u.error ?? 'Последняя версия';
    final ok = !u.available && !u.readyToInstall && u.error == null && u.supported && !u.checking;

    final hero = SkCard(
      padding: const EdgeInsets.all(24),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 20,
        runSpacing: 14,
        children: [
          HutredLogo(size: 72, radius: k.sharp ? 0 : null),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 460),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  'Hutred ${UpdateService.build == 0 ? '· локальная сборка' : '1.4.${UpdateService.build}'}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(ok ? '● $status' : status,
                  style: TextStyle(fontSize: 13, color: ok ? k.ok : k.muted)),
            ]),
          ),
          if (u.available || u.readyToInstall)
            SkButton(u.readyToInstall ? 'Перезапустить' : 'Обновить',
                primary: true, height: 42, onTap: u.updateNow)
          else
            SkButton('Проверить обновления',
                primary: true,
                height: 42,
                onTap: u.supported && !u.checking ? () => u.check(manual: true) : null),
        ],
      ),
    );

    final notes = (u.notes ?? '').trim();
    final news = SkCard(
      child: SkGap(gap: 12, children: [
        const SkCap('Что нового'),
        if (notes.isEmpty)
          Text(u.checking ? 'Загружаю…' : 'Нажми «Проверить обновления», чтобы увидеть список',
              style: k.sub)
        else
          Container(
            padding: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: k.line))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: 'Сборка ${u.latestBuild ?? UpdateService.build}'),
                TextSpan(
                    text: (u.latestBuild ?? 0) > UpdateService.build ? ' · новая' : ' · у тебя',
                    style: TextStyle(fontWeight: FontWeight.w500, color: k.muted)),
              ]), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(notes,
                  style: const TextStyle(fontSize: 13, color: Color(0xFFCFCFCF), height: 1.45)),
            ]),
          ),
      ]),
    );

    return SkGap(gap: 20, children: [
      hero,
      if (desktop) SkCols(children: [const _DesktopOpts(), news]) else news,
    ]);
  }
}

/// Автообновление, трей и автозапуск.
class _DesktopOpts extends StatefulWidget {
  const _DesktopOpts();

  @override
  State<_DesktopOpts> createState() => _DesktopOptsState();
}

class _DesktopOptsState extends State<_DesktopOpts> {
  bool? _autostart;

  @override
  void initState() {
    super.initState();
    if (WindowsAutostart.supported) {
      WindowsAutostart.isEnabled().then((v) {
        if (mounted) setState(() => _autostart = v);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    return SkCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(padding: EdgeInsets.only(bottom: 8), child: SkCap('На компьютере')),
        if (Platform.isWindows)
          SkRow(
            filled: false,
            divider: true,
            title: 'Обновляться автоматически',
            sub: 'Качает в фоне, ставит, когда музыка не играет',
            trailing: SkToggle(value: s.autoUpdate, onChanged: (v) => s.autoUpdate = v),
          ),
        SkRow(
          filled: false,
          divider: true,
          title: 'Крестик сворачивает в трей',
          sub: 'Музыка играет дальше. Выйти — правой кнопкой по значку',
          trailing: SkToggle(value: s.closeToTray, onChanged: (v) => s.closeToTray = v),
        ),
        if (WindowsAutostart.supported)
          SkRow(
            filled: false,
            divider: true,
            title: 'Запускать вместе с Windows',
            sub: 'Тихо стартует в трее',
            trailing: SkToggle(
              value: _autostart ?? false,
              onChanged: _autostart == null
                  ? null
                  : (v) async {
                      await WindowsAutostart.set(v);
                      final now = await WindowsAutostart.isEnabled();
                      if (mounted) setState(() => _autostart = now);
                    },
            ),
          ),
      ]),
    );
  }
}

// ───────────────────────────── Админ ─────────────────────────────

class _AdminPage extends StatefulWidget {
  const _AdminPage();

  @override
  State<_AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<_AdminPage> {
  int? _users;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final n = await Supabase.instance.client.from('profiles').count(CountOption.exact);
        if (mounted) setState(() => _users = n);
      } catch (_) {}
    }();
  }

  String _mask(String v) {
    if (v.isEmpty) return 'не задан';
    if (v.length <= 8) return '•••• $v';
    return '${v.substring(0, 4)} •••• ${v.substring(v.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccountService>();
    final s = context.watch<SettingsStore>();
    final jam = context.watch<JamService>();
    final latest = context.watch<UpdateService>().latestBuild ?? UpdateService.build;
    final k = Sk.of(context);
    final cfg = acc.appConfig;
    final f = cfg['features'];
    final aiForAll = f is Map && f['aiForEveryone'] == true;

    bool shared(String key, String field) {
      final m = cfg[key];
      return m is Map && '${m[field] ?? ''}'.isNotEmpty;
    }

    Future<void> push(String key, Map<String, dynamic> value, String done) async {
      final err = await acc.pushConfig(key, value);
      if (context.mounted) AppActions.toast(context, err ?? done);
    }

    Widget stat(String v, String label) => SkCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(label, style: k.sub),
          ]),
        );

    Widget keyRow({
      required String name,
      required String desc,
      required String value,
      required bool isShared,
      required VoidCallback onEdit,
      VoidCallback? onPush,
      String pushLabel = 'Разослать',
    }) =>
        LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth > 640;
          final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: k.rowTitle),
            const SizedBox(height: 2),
            Text(desc, style: k.small),
          ]);
          final val = Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: k.st.caption(color: const Color(0xFF9A9A9A), size: 13).copyWith(
                  fontFamily: 'JetBrains Mono',
                  fontFamilyFallback: const ['Consolas', 'monospace'],
                  letterSpacing: 0));
          final st = Text(isShared ? 'У всех' : 'Нет',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: isShared ? k.ok : k.muted));
          final buttons = Row(mainAxisSize: MainAxisSize.min, children: [
            SkButton('Изменить', height: 34, onTap: onEdit),
            if (onPush != null) ...[
              const SizedBox(width: 8),
              SkButton(pushLabel, height: 34, onTap: onPush),
            ],
          ]);
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: k.line))),
            child: wide
                ? Row(children: [
                    SizedBox(width: 260, child: info),
                    const SizedBox(width: 14),
                    Expanded(child: val),
                    const SizedBox(width: 14),
                    st,
                    const SizedBox(width: 14),
                    buttons,
                  ])
                : SkGap(gap: 8, children: [
                    info,
                    Row(children: [Expanded(child: val), st]),
                    Align(alignment: Alignment.centerLeft, child: buttons),
                  ]),
          );
        });

    Future<void> editRelay() async {
      final ctrl = TextEditingController(text: HutredRelay.url ?? '');
      final v = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Адрес сервера'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'https://1-2-3-4.sslip.io'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(d, ctrl.text.trim()),
                child: const Text('Сохранить')),
          ],
        ),
      );
      if (v == null) return;
      var url = v;
      if (url.isNotEmpty && !url.startsWith('http')) url = 'https://$url';
      final err = await acc.pushConfig('relay', {'url': url});
      if (context.mounted) {
        AppActions.toast(
            context, err ?? (url.isEmpty ? 'Сервер убран' : 'Сервер сохранён для всех'));
      }
    }

    return SkGap(gap: 20, children: [
      SkCols(minWidth: 640, children: [
        stat(_users == null ? '…' : '$_users', 'пользователей'),
        stat('${jam.onlineCount}', 'в сети сейчас'),
        stat('${jam.onLatest(latest)}', 'в сети на сборке $latest'),
      ]),
      SkCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(padding: EdgeInsets.only(bottom: 8), child: SkCap('Общие ключи')),
          keyRow(
            name: 'Spotify',
            desc: 'Запасной поиск и обложки',
            value: _mask(s.ownSpotifyId),
            isShared: shared('spotify', 'id'),
            onEdit: () => showDialog(context: context, builder: (_) => const _SpotifyKeysDialog()),
            onPush: s.ownSpotifyId.isEmpty
                ? null
                : () => push('spotify', {'id': s.ownSpotifyId, 'secret': s.ownSpotifySecret},
                    'Ключи Spotify разосланы всем'),
          ),
          keyRow(
            name: 'ИИ для текстов',
            desc: 'Подгонка таймингов',
            value: _mask(s.ownAiKey),
            isShared: shared('ai', 'key'),
            onEdit: () => showDialog(context: context, builder: (_) => const _AiKeyDialog()),
            onPush: s.ownAiKey.isEmpty
                ? null
                : () => push('ai', {
                      'baseUrl': s.ownAiBaseUrl,
                      'key': s.ownAiKey,
                      'model': s.ownAiModel,
                    }, 'Ключи ИИ разосланы всем'),
          ),
          keyRow(
            name: 'Discord Application ID',
            desc: 'Статус «Слушает Hutred»',
            value: _mask(s.ownDiscordAppId),
            isShared: shared('discord', 'appId'),
            onEdit: () async {
              final v = await AppActions.askText(context,
                  title: 'Application ID Discord',
                  hint: 'Например 1234567890123456789',
                  initial: s.ownDiscordAppId);
              if (v != null) s.discordAppId = v;
            },
            onPush: s.ownDiscordAppId.isEmpty
                ? null
                : () => push('discord', {'appId': s.ownDiscordAppId}, 'Discord ID разослан всем'),
          ),
          keyRow(
            name: 'Сервер Hutred',
            desc: 'Для заблокированного',
            value: HutredRelay.url ?? 'не задан',
            isShared: HutredRelay.url != null,
            onEdit: editRelay,
          ),
          Container(
            padding: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: k.line))),
            child: SkRow(
              filled: false,
              title: 'ИИ-подгонка текста для всех',
              sub: 'Если выключено, кнопку ИИ видишь только ты',
              trailing: SkToggle(
                value: aiForAll,
                onChanged: (v) => push('features', {'aiForEveryone': v},
                    v ? 'Теперь ИИ доступен всем' : 'ИИ теперь только у тебя'),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}
