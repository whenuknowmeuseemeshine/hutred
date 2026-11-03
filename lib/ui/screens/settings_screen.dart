import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;

import '../../services/account_service.dart';
import '../../services/jam_service.dart';
import '../../services/library_store.dart';
import '../../services/offline_service.dart';
import '../../services/settings_store.dart';
import '../../services/update_service.dart';
import '../../services/wave_service.dart';
import '../../services/soundcloud_source.dart';
import '../../services/spotify_service.dart';
import '../../services/youtube_source.dart';
import '../actions.dart';
import '../../services/discord_presence.dart';
import '../../services/dpi_bypass.dart';
import '../net_check.dart';
import '../theme.dart';
import '../welcome.dart';
import 'equalizer_screen.dart';
import '../widgets/logo.dart';
import '../home_shell.dart';
import '../widgets/style_picker.dart';
import '../widgets/style_bits.dart';
import '../widgets/user_avatar.dart';
import 'account_screen.dart';
import '../icons.dart';
import '../../services/relay.dart';
import '../../services/player_service.dart';
import '../widgets/artwork.dart';
import '../widgets/settings_kit.dart';
import '../../services/xray_vpn.dart';

part 'settings_pages.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// Слова, по которым находится раздел в поиске (кроме его названия).
const _sectionKeywords = {
  'Аккаунт': 'вход войти логин аватар аватарка почта пароль облако синхронизация файлы',
  'Стиль': 'стиль тема оформление дизайн шрифт моно стекло резкий вид масштаб размер крупнее полный экран',
  'Акцентный цвет': 'цвет тема оформление акцент',
  'Фон': 'фон цвет тема оформление обои плеер подкрашивать волна картинка gif',
  'Медиатека': 'любимые избранное лайк добавленные исполнители волна',
  'Воспроизведение': 'плавный переход crossfade кроссфейд пауза затихание громкость эквалайзер eq басы частоты',
  'Вкладки': 'вкладки меню навигация порядок скрыть показать панель друзья перенос поиск',
  'Чёрный список': 'черный блок заблокировать исполнитель скрытые не нравится дизлайк',
  'Тексты песен': 'текст караоке субтитры genius ии ai groq whisper тайминги',
  'Обложки': 'обложка spotify itunes genius ключи сверять сведения превью',
  'Админ': 'админ всем ключи раздать',
  'Discord': 'дискорд статус активность rich presence слушает',
  'Обновления': 'обновление версия сборка автозапуск автозагрузка windows трей',
  'Сеть': 'сервер посредник oracle прокси впн обход блокировок zapret vpn впн россия прокси проверить связь соединение dns днс 1.1.1.1 google cloudflare',
  'YouTube': 'ютуб вход cookies браузер 18+',
  'Версия': 'обновление обновить проверить версия сборка',
  'Загрузки и кэш': 'скачать скачанные офлайн без интернета кэш память место удалить',
};

class _SettingsScreenState extends State<SettingsScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Оставляет только разделы, где совпало название или ключевые слова.
  List<Widget> _filter(List<Widget> all) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return all;
    final out = <Widget>[];
    var title = 'Аккаунт';
    var group = <Widget>[];
    void flush() {
      final words = '${title.toLowerCase()} ${_sectionKeywords[title] ?? ''}';
      if (q.split(RegExp(r'\s+')).every(words.contains)) out.addAll(group);
    }

    for (final w in all) {
      if (w is _Section) {
        flush();
        title = w.text;
        group = [w];
      } else if (w is _Footer) {
        // Логотип внизу при поиске не нужен.
      } else {
        group.add(w);
      }
    }
    flush();
    if (out.isEmpty) {
      out.add(const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
            child: Text('Ничего не нашлось', style: TextStyle(color: HutredTheme.muted))),
      ));
    }
    return out;
  }

  /// Все пункты настроек подряд (разделы — через _Section).
  List<Widget> _items(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final acc = context.watch<AccountService>();
    return [
          const _AccountTile(),
          const _Section('Стиль'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: StylePicker(),
          ),
          if (HutredTheme.desktop)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Масштаб интерфейса  ',
                      style: TextStyle(color: HutredTheme.muted, fontSize: 13)),
                  for (final (v, label) in const [
                    (0.0, 'Авто'),
                    (1.0, '100%'),
                    (1.15, '115%'),
                    (1.3, '130%'),
                    (1.5, '150%'),
                  ])
                    StyleChip(
                      label: label,
                      selected: s.uiScale == v,
                      onTap: () => s.uiScale = v,
                    ),
                ],
              ),
            ),
          const _Section('Акцентный цвет'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in accentPresets)
                  _Swatch(
                    color: c,
                    selected: s.accent.toARGB32() == c.toARGB32(),
                    onTap: () => s.accent = c,
                  ),
                _CustomSwatch(selected: !accentPresets
                    .any((c) => c.toARGB32() == s.accent.toARGB32())),
              ],
            ),
          ),
          const _Section('Фон'),
          ListTile(
            leading: Icon(Ic.wallpaper_outlined),
            title: const Text('Фон «Моей волны»'),
            subtitle: Text(s.waveBackground == null
                ? 'Своя картинка или GIF за кругом «Волны»'
                : 'Своя картинка выбрана'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (s.waveBackground != null)
                IconButton(
                  tooltip: 'Убрать фон',
                  onPressed: () => s.setWaveBackground(null),
                  icon: Icon(Ic.close_rounded),
                ),
              Icon(Ic.chevron_right),
            ]),
            onTap: () async {
              final res = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: const ['gif', 'png', 'jpg', 'jpeg', 'webp'],
              );
              final path = res?.files.single.path;
              if (path != null) await s.setWaveBackground(path);
            },
          ),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: backgroundPresets.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                if (i == backgroundPresets.length) {
                  // Свой цвет фона — тот же подбор, что у акцентного.
                  return _BackgroundCard(
                    preset: s.customBackground,
                    accent: s.accent,
                    selected: s.background.id == 'custom',
                    custom: true,
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
                  );
                }
                final b = backgroundPresets[i];
                return _BackgroundCard(
                  preset: b,
                  accent: s.accent,
                  selected: s.background.id == b.id,
                  onTap: () => s.backgroundId = b.id,
                );
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Подкрашивать плеер под трек'),
            subtitle: const Text(
                'Выключи, чтобы плеер всегда был в акцентном цвете'),
            value: s.tintFromCover,
            onChanged: (v) => s.tintFromCover = v,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton.icon(
                onPressed: s.reset,
                icon: Icon(Ic.restart_alt),
                label: const Text('Вернуть цвета по умолчанию'),
              ),
            ),
          ),
          const _Section('Медиатека'),
          const _LibraryStats(),
          ListTile(
            leading: Icon(Ic.favorite_outline_rounded),
            title: const Text('Любимые исполнители'),
            subtitle: Builder(builder: (context) {
              final fav = context.watch<WaveService>().favoriteArtists;
              return Text(fav.isEmpty
                  ? 'По ним «Моя волна» подбирает музыку, пока лайков мало'
                  : fav.join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis);
            }),
            trailing: Icon(Ic.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ArtistPickerScreen(standalone: true))),
          ),
          SwitchListTile(
            title: const Text('Добавленные треки сразу в любимые'),
            subtitle: const Text(
                'Как в Spotify: всё, что добавляешь, получает ♥ и скачивается '
                'вместе с любимыми, если они скачаны'),
            value: s.autoFavorite,
            onChanged: (v) => s.autoFavorite = v,
          ),
          const _Section('Воспроизведение'),
          SwitchListTile(
            secondary: Icon(Ic.swap_horiz_rounded),
            title: const Text('Плавный переход между треками'),
            subtitle: Text(s.crossfade
                ? 'Конец трека затихает, следующий нарастает: ${s.crossfadeSec} с'
                : 'Как в Spotify: треки перетекают друг в друга без тишины'),
            value: s.crossfade,
            onChanged: (v) => s.crossfade = v,
          ),
          if (s.crossfade)
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
              child: Row(children: [
                const Text('1 с', style: TextStyle(color: HutredTheme.muted)),
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 12,
                    divisions: 11,
                    value: s.crossfadeSec.toDouble(),
                    label: '${s.crossfadeSec} с',
                    onChanged: (v) => s.crossfadeSec = v.round(),
                  ),
                ),
                const Text('12 с', style: TextStyle(color: HutredTheme.muted)),
              ]),
            ),
          if (!HutredTheme.desktop || Platform.isMacOS) ListTile(
            leading: Icon(Ic.equalizer_rounded),
            title: const Text('Эквалайзер'),
            subtitle: Text(Platform.isIOS || Platform.isMacOS
                ? 'Недоступен на устройствах Apple'
                : (s.eqOn ? 'Включён' : 'Выключен')),
            trailing: Icon(Ic.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const EqualizerScreen())),
          ),
          SwitchListTile(
            secondary: Icon(Ic.volume_down_rounded),
            title: const Text('Плавная пауза'),
            subtitle: const Text('При паузе звук за полсекунды затихает, при продолжении — нарастает'),
            value: s.fadePause,
            onChanged: (v) => s.fadePause = v,
          ),
          if (HutredTheme.desktop && !Platform.isMacOS) ...[
            const _Section('Эквалайзер'),
            const EqualizerScreen(embedded: true),
          ],
          const _Section('Чёрный список'),
          const _BlacklistTiles(),
          const _Section('Вкладки'),
          const _NavOrderEditor(),
          const _Section('Тексты песен'),
          const _LyricsOrder(),
          if (Platform.isAndroid || Platform.isIOS)
            SwitchListTile(
              title: const Text('Строка текста на обложке'),
              subtitle: const Text('В плеере поверх обложки — текущая строка песни'),
              value: s.lyricsOnCover,
              onChanged: (v) => s.lyricsOnCover = v,
            ),
          SwitchListTile(
            title: const Text('Субтитры YouTube'),
            subtitle: const Text('Текст по таймеру из клипа, если он там залит'),
            value: s.youtubeLyrics,
            onChanged: (v) => s.youtubeLyrics = v,
          ),
          SwitchListTile(
            title: const Text('Genius'),
            subtitle: const Text('Полный текст с genius.com, без таймингов'),
            value: s.geniusLyrics,
            onChanged: (v) => s.geniusLyrics = v,
          ),
          if (acc.isAdmin) ListTile(
            leading: Icon(Ic.auto_awesome),
            title: const Text('ИИ для текстов'),
            subtitle: Text(s.hasAi
                ? 'Подключён: подгоняет текст под трек и распознаёт песни без текста'
                : 'Не подключён. Нужен бесплатный ключ Groq или ключ OpenAI'),
            trailing: Icon(Ic.chevron_right),
            onTap: () => showDialog(
              context: context,
              builder: (_) => const _AiKeyDialog(),
            ),
          ),
          const _Section('Обложки'),
          SwitchListTile(
            title: const Text('Искать обложки автоматически'),
            subtitle: const Text(
                'Когда трек начинает играть: Genius → Spotify → iTunes'),
            value: s.geniusCovers,
            onChanged: (v) => s.geniusCovers = v,
          ),
          SwitchListTile(
            title: const Text('Сверять новые треки со Spotify'),
            subtitle: Text(s.hasSpotifyKeys
                ? 'При добавлении трека с YouTube или SoundCloud спрошу, подставить ли '
                    'точное название, исполнителя и обложку из Spotify'
                : 'Нужны ключи Spotify'),
            value: s.spotifyCheck,
            onChanged: s.hasSpotifyKeys ? (v) => s.spotifyCheck = v : null,
          ),
          SwitchListTile(
            title: const Text('Заменять превью YouTube'),
            subtitle: const Text('Квадратная обложка альбома вместо кадра из клипа'),
            value: s.replaceYoutubeCovers,
            onChanged: s.geniusCovers ? (v) => s.replaceYoutubeCovers = v : null,
          ),
          if (acc.isAdmin) ListTile(
            leading: Icon(Ic.key_outlined),
            title: const Text('Ключи Spotify'),
            subtitle: Text(s.hasSpotifyKeys
                ? 'Заданы, Spotify используется для обложек'
                : 'Не заданы, Spotify пропускается'),
            trailing: Icon(Ic.chevron_right),
            onTap: () => showDialog(
              context: context,
              builder: (_) => const _SpotifyKeysDialog(),
            ),
          ),
          if (acc.isAdmin && acc.enabled && acc.signedIn) ...[
            const _Section('Админ'),
            const _AdminStats(),
            const _AdminTiles(),
            const _RelayAdminTile(),
          ],
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) ...[
            const _Section('Discord'),
            SwitchListTile(
              secondary: Icon(Ic.headset_mic_outlined),
              title: const Text('Показывать трек в Discord'),
              subtitle: Text(s.discordAppId.isEmpty
                  ? 'Нужен Application ID — нажми ниже'
                  : 'Как у Spotify: «Слушает Hutred», трек, обложка и время. Discord должен быть открыт'),
              value: s.discordPresence,
              onChanged: (v) => s.discordPresence = v,
            ),
            if (s.discordPresence && s.discordAppId.isNotEmpty)
              ValueListenableBuilder<String>(
                valueListenable: DiscordPresence.status,
                builder: (_, st, __) => st.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                        child: Text(st,
                            style: const TextStyle(color: HutredTheme.muted, fontSize: 13)),
                      ),
              ),
            if (s.discordPresence) ...[
              SwitchListTile(
                title: const Text('Время трека'),
                subtitle: const Text('Полоска «сколько осталось» в статусе'),
                value: s.discordTime,
                onChanged: (v) => s.discordTime = v,
              ),
              SwitchListTile(
                title: const Text('Кнопка «Слушать трек»'),
                subtitle: const Text('Друг откроет этот трек на YouTube, Spotify или Deezer'),
                value: s.discordButton,
                onChanged: (v) => s.discordButton = v,
              ),
              SwitchListTile(
                title: const Text('Скрывать на паузе'),
                subtitle: const Text('Иначе в статусе будет «На паузе»'),
                value: s.discordHideOnPause,
                onChanged: (v) => s.discordHideOnPause = v,
              ),
            ],
            if (acc.isAdmin)
              ListTile(
                leading: Icon(Ic.key_outlined),
                title: const Text('Application ID для Discord'),
                subtitle: Text(s.ownDiscordAppId.isEmpty
                    ? 'Не задан. discord.com/developers → New Application «Hutred» → скопируй Application ID'
                    : s.ownDiscordAppId),
                trailing: Icon(Ic.chevron_right),
                onTap: () async {
                  final v = await AppActions.askText(context,
                      title: 'Application ID Discord',
                      hint: 'Например 1234567890123456789',
                      initial: s.ownDiscordAppId);
                  if (v != null) s.discordAppId = v;
                },
              ),
          ],
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) ...[
            const _Section('Обновления'),
            const _UpdatesTiles(),
          ],
          const _Section('Сеть'),
          if (XrayVpn.supported) const _VpnTile(),
          const _RelayTile(),
          SwitchListTile(
            secondary: Icon(Ic.vpn_lock_outlined),
            title: const Text('Обход блокировок (для России)'),
            subtitle: const Text(
                'Как zapret, но только для Hutred и без прав администратора: '
                'YouTube, SoundCloud и обложки открываются без VPN. '
                'Если включён VPN — можно выключить'),
            value: s.dpiBypass,
            onChanged: (v) => s.dpiBypass = v,
          ),
          SwitchListTile(
            secondary: Icon(Ic.dns_outlined),
            title: const Text('Только безопасный DNS'),
            subtitle: const Text(
                'Мягкий режим: адреса сайтов через Cloudflare 1.1.1.1 и Google 8.8.8.8, '
                'без разрезания соединения. Попробуй, если с обычным обходом что-то не грузится'),
            value: s.dnsOnly,
            onChanged: s.dpiBypass ? (v) => s.dnsOnly = v : null,
          ),
          if (s.dpiBypass && !s.dnsOnly) const _DpiTuneTile(),
          ValueListenableBuilder<bool>(
            valueListenable: DpiBypass.zapretRunning,
            builder: (_, z, __) => !z
                ? const SizedBox.shrink()
                : const Padding(
                    padding: EdgeInsets.fromLTRB(72, 0, 16, 8),
                    child: Text(
                        'Запущен zapret — он уже обходит блокировки, встроенный обход отключён',
                        style: TextStyle(color: HutredTheme.muted, fontSize: 13)),
                  ),
          ),
          ListTile(
            leading: Icon(Ic.network_check_rounded),
            title: const Text('Проверить связь'),
            subtitle: const Text(
                'Что открывается, а что нет: SoundCloud, Spotify, YouTube, облако. '
                'Если что-то не играет — пришли скриншот'),
            onTap: () => showNetCheck(context),
          ),
          const _Section('YouTube'),
          const _YoutubeLoginTile(),
          const _Section('Загрузки и кэш'),
          const _StorageBar(),
          const _DownloadsTile(),
          const _CacheTile(),
          const _AudioPrefs(),
          const _Section('Версия'),
          const _UpdateCheckTile(),
          const _Footer(),
    ];
  }

  /// Разделы настроек, собранные в несколько понятных групп.
  static final _groups = <(String, IconData, String, List<String>)>[
    ('Внешний вид', Ic.palette_outlined, 'Стиль, цвет, фон, вкладки',
        ['Стиль', 'Акцентный цвет', 'Фон', 'Вкладки']),
    ('Воспроизведение', Ic.play_circle_outline, 'Плавный переход, пауза, эквалайзер',
        ['Воспроизведение', 'Эквалайзер']),
    ('Медиатека и волна', Ic.library_music_outlined, 'Любимые исполнители, чёрный список',
        ['Медиатека', 'Чёрный список']),
    ('Тексты и обложки', Ic.lyrics_outlined, 'Караоке, Spotify, Genius',
        ['Тексты песен', 'Обложки']),
    ('Сеть и YouTube', Ic.public, 'Обход блокировок, проверка связи, вход в YouTube',
        ['Сеть', 'YouTube']),
    ('Discord', Ic.headphones, 'Трек в статусе Discord', ['Discord']),
    ('Загрузки и кэш', Ic.download_outlined, 'Скачанное, место на диске',
        ['Загрузки и кэш']),
    ('Обновления', Ic.refresh, 'Версия, автообновление, трей',
        ['Обновления', 'Версия']),
    ('Админ', Ic.verified_user_outlined, 'Общие ключи для всех', ['Админ']),
  ];

  /// Раздел → его пункты (с заголовком раздела).
  Map<String, List<Widget>> _sections(List<Widget> all) {
    final out = <String, List<Widget>>{};
    String? title;
    for (final w in all) {
      if (w is _Section) {
        title = w.text;
        out[title] = [w];
      } else if (title != null && w is! _Footer) {
        out[title]!.add(w);
      }
    }
    return out;
  }

  /// Без поиска — аккаунт и список групп; при поиске — найденные пункты.
  List<Widget> _body(BuildContext context) {
    final all = _items(context);
    if (_q.trim().isNotEmpty) return _asCards(_filter(all));
    final sections = _sections(all);
    final st = HutredStyle.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final shown = [for (final g in _groups) if (g.$4.any(sections.containsKey)) g];
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: StylePanel(padding: EdgeInsets.zero, child: _AccountTile()),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: StylePanel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final (i, g) in shown.indexed)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(
                          top: BorderSide(
                              color: st.glass
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : const Color(0xFF1F1F1F))),
                ),
                child: ListTile(
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: st.sharp
                          ? Colors.transparent
                          : st.glass
                              ? accent.withValues(alpha: 0.22)
                              : const Color(0xFF262626),
                      borderRadius: BorderRadius.circular(st.sharp ? 0 : st.glass ? 17 : 8),
                    ),
                    child: Icon(g.$2, size: 18, color: st.mono ? HutredTheme.text : accent),
                  ),
                  title: Text(g.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(g.$3, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Icon(Ic.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _GroupPage(title: g.$1),
                  )),
                ),
              ),
            // На телефоне «Перенос» не в нижнем меню — открываем отсюда.
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: st.glass
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFF1F1F1F))),
              ),
              child: ListTile(
                leading: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: st.sharp
                        ? Colors.transparent
                        : st.glass
                            ? accent.withValues(alpha: 0.22)
                            : const Color(0xFF262626),
                    borderRadius: BorderRadius.circular(st.sharp ? 0 : st.glass ? 17 : 8),
                  ),
                  child: Icon(Ic.swap_horiz_rounded, size: 18, color: st.mono ? HutredTheme.text : accent),
                ),
                title: const Text('Перенос музыки', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Spotify, Яндекс, YouTube, папка', maxLines: 1),
                trailing: Icon(Ic.chevron_right),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => navPage('transfer'))),
              ),
            ),
          ]),
        ),
      ),
      const _Footer(),
    ];
  }

  /// Открытая группа на компьютере (настройки в две колонки).
  int _group = 0;

  Widget _searchField() => TextField(
        controller: _search,
        onChanged: (v) => setState(() => _q = v),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: Icon(Ic.search),
          hintText: 'Поиск по настройкам',
          suffixIcon: _q.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Ic.close),
                  onPressed: () => setState(() {
                    _search.clear();
                    _q = '';
                  }),
                ),
        ),
      );

  /// Компьютер по макету: слева аккаунт и группы, справа открытая группа.
  Widget _twoPane(BuildContext context) {
    final st = HutredStyle.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final all = _items(context);
    final sections = _sections(all);
    final groups = [for (final g in _groups) if (g.$4.any(sections.containsKey)) g];
    final sel = _group.clamp(0, groups.length - 1);
    final g = groups[sel];
    final searching = _q.trim().isNotEmpty;
    final right = searching ? _filter(all) : [for (final name in g.$4) ...?sections[name]];
    final top = MediaQuery.paddingOf(context).top;

    Widget groupTile(int i) {
      final gr = groups[i];
      final on = !searching && i == sel;
      final fg = on && st.sharp ? HutredTheme.onAccent(accent) : HutredTheme.text;
      final sub = on && st.sharp ? HutredTheme.onAccent(accent) : HutredTheme.muted;
      final r = BorderRadius.circular(st.sharp ? 0 : st.glass ? 16 : 8);
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: !on
              ? Colors.transparent
              : st.sharp
                  ? accent
                  : st.glass
                      ? accent.withValues(alpha: 0.18)
                      : const Color(0xFF1A1A1A),
          borderRadius: r,
          child: InkWell(
            borderRadius: r,
            onTap: () => setState(() {
              _group = i;
              _search.clear();
              _q = '';
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: st.sharp && !on
                  ? const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF1F1F1F))))
                  : null,
              child: Row(children: [
                Icon(gr.$2, size: 19, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(gr.$1,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: fg)),
                    Text(gr.$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: sub)),
                  ]),
                ),
                Icon(Ic.chevron_right, size: 16, color: sub),
              ]),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.fromLTRB(24, top + (st.mono ? 20 : 8), 24, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 310,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  _searchField(),
                  const SizedBox(height: 12),
                  const StylePanel(padding: EdgeInsets.zero, child: _AccountTile()),
                  const SizedBox(height: 10),
                  for (var i = 0; i < groups.length; i++) groupTile(i),
                ],
              ),
            ),
            const SizedBox(width: 28),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Text(searching ? 'Поиск: ${_q.trim()}' : g.$1,
                        style: st.display(Sk.of(context).titleSize)),
                  ),
                  if (!searching) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      child: Text(_pageSubtitles[g.$1] ?? g.$3,
                          style: st.caption(color: Sk.of(context).muted, size: 14)
                              .copyWith(letterSpacing: 0, fontWeight: FontWeight.w400)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: settingsPageFor(g.$1),
                    ),
                  ] else
                    _CardGrid(cards: _asCards(right)),
                  if (!searching && sel == groups.length - 1) const _Footer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsStore>();
    context.watch<AccountService>();
    if (MediaQuery.sizeOf(context).width >= 1000) return _twoPane(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          // Поиск по настройкам.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: Icon(Ic.search),
                hintText: 'Поиск по настройкам',
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Ic.close),
                        onPressed: () => setState(() {
                          _search.clear();
                          _q = '';
                        }),
                      ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          ..._body(context),
        ],
      ),
    );
  }
}


/// Раздел настроек — отдельной карточкой с подписью, как в макете.
List<Widget> _asCards(List<Widget> items) {
  final out = <Widget>[];
  String? title;
  var group = <Widget>[];
  void flush() {
    if (group.isEmpty && title == null) return;
    final t = title;
    final g = group;
    out.add(Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: StylePanel(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (t != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: StyleCaption(t),
              ),
            ...g,
          ],
        ),
      ),
    ));
  }

  for (final w in items) {
    if (w is _Section) {
      flush();
      title = w.text;
      group = [];
    } else if (w is _Footer) {
      flush();
      title = null;
      group = [];
      out.add(w);
    } else {
      group.add(w);
    }
  }
  flush();
  return out;
}

/// Карточки разделов на широком экране — в две колонки, как в макете:
/// первая во всю ширину, остальные попеременно слева и справа.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.cards});
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final panels = [for (final c in cards) if (c is! _Footer) c];
      final rest = [for (final c in cards) if (c is _Footer) c];
      if (box.maxWidth < 1000 || panels.length < 3) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: cards);
      }
      final left = <Widget>[], right = <Widget>[];
      for (var i = 1; i < panels.length; i++) {
        (i.isOdd ? left : right).add(panels[i]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        panels.first,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
        ]),
        ...rest,
      ]);
    });
  }
}

/// Качество звука, лимит кэша, «только по Wi-Fi», папка загрузок.
class _AudioPrefs extends StatelessWidget {
  const _AudioPrefs();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final off = context.watch<OfflineService>();
    Widget row(String title, String sub, List<Widget> chips) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(sub, style: const TextStyle(fontSize: 12, color: HutredTheme.muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row('Качество звука', 'Для YouTube: лучшее ~6 МБ на трек, экономия ~1,5 МБ', [
        for (final (v, l) in const [('best', 'Лучшее'), ('normal', 'Обычное'), ('saver', 'Экономия')])
          StyleChip(label: l, selected: s.audioQuality == v, onTap: () => s.audioQuality = v),
      ]),
      row('Лимит кэша прослушанного', 'Старые файлы удаляются сами, загрузки не трогаются', [
        for (final (v, l) in const [(500, '500 МБ'), (1024, '1 ГБ'), (3072, '3 ГБ'), (0, 'Без лимита')])
          StyleChip(label: l, selected: s.cacheLimitMb == v, onTap: () => s.cacheLimitMb = v),
      ]),
      if (Platform.isAndroid || Platform.isIOS)
        SwitchListTile(
          title: const Text('Качать только по Wi-Fi'),
          subtitle: Text(off.waitingForWifi
              ? 'Сейчас мобильный интернет — загрузки ждут Wi-Fi'
              : 'Загрузки не тратят мобильный трафик'),
          value: s.wifiOnly,
          onChanged: (v) => s.wifiOnly = v,
        ),
      if (HutredTheme.desktop && off.folder != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: StyleButton(
              label: 'Открыть папку загрузок',
              icon: Ic.folder_open_rounded,
              primary: false,
              onPressed: () {
                final path = off.folder!.path;
                if (Platform.isWindows) {
                  Process.start('explorer', [path]);
                } else if (Platform.isMacOS) {
                  Process.start('open', [path]);
                } else {
                  Process.start('xdg-open', [path]);
                }
              },
            ),
          ),
        ),
    ]);
  }
}

/// Для админа: сколько всего людей, сколько в сети и на последней сборке.
class _AdminStats extends StatefulWidget {
  const _AdminStats();

  @override
  State<_AdminStats> createState() => _AdminStatsState();
}

class _AdminStatsState extends State<_AdminStats> {
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

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    final jam = context.watch<JamService>();
    final latest = context.watch<UpdateService>().latestBuild ?? UpdateService.build;
    Widget stat(String v, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v, style: st.display(28)),
            Text(label, style: const TextStyle(fontSize: 12, color: HutredTheme.muted)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(children: [
        stat(_users == null ? '…' : '$_users', 'пользователей'),
        stat('${jam.onlineCount}', 'в сети сейчас'),
        stat('${jam.onLatest(latest)}', 'в сети на сборке $latest'),
      ]),
    );
  }
}

/// Где искать текст по порядку — перетаскиванием.
class _LyricsOrder extends StatelessWidget {
  const _LyricsOrder();

  static const _info = {
    'lrclib': ('LRCLIB и NetEase', 'Тексты с таймингами — караоке'),
    'youtube': ('Субтитры YouTube', 'Если текст залит в клип'),
    'genius': ('Genius', 'Полный текст без таймингов'),
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final st = HutredStyle.of(context);
    final order = s.lyricsOrder;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Text('Где искать по порядку — перетащи, чтобы поменять',
            style: TextStyle(fontSize: 13, color: HutredTheme.muted)),
      ),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorder: s.moveLyricsSource,
        children: [
          for (final (i, id) in order.indexed)
            ListTile(
              key: ValueKey(id),
              leading: CircleAvatar(
                radius: 12,
                backgroundColor: st.sharp ? Colors.transparent : const Color(0xFF262626),
                child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              title: Text(_info[id]!.$1),
              subtitle: Text(_info[id]!.$2),
              trailing: ReorderableDragStartListener(
                index: i,
                child: Icon(Ic.drag_handle),
              ),
            ),
        ],
      ),
    ]);
  }
}

/// Сводка медиатеки: сколько любимых, скрытых и в чёрном списке.
class _LibraryStats extends StatelessWidget {
  const _LibraryStats();

  @override
  Widget build(BuildContext context) {
    final st = HutredStyle.of(context);
    final fav = context.watch<LibraryStore>().favorites.length;
    final wave = context.watch<WaveService>();
    Widget stat(int n, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n', style: st.display(26)),
            Text(label, style: const TextStyle(fontSize: 12, color: HutredTheme.muted)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(children: [
        stat(fav, 'любимых'),
        stat(wave.dislikedCount, 'скрыто'),
        stat(wave.blockedArtists.length, 'в чёрном списке'),
      ]),
    );
  }
}

/// Сколько места занимает Hutred: загрузки, кэш — полосой.
class _StorageBar extends StatefulWidget {
  const _StorageBar();

  @override
  State<_StorageBar> createState() => _StorageBarState();
}

class _StorageBarState extends State<_StorageBar> {
  int? _dl;
  int? _cache;
  int _seen = -1;

  Future<void> _load(OfflineService off) async {
    try {
      final dl = await off.sizeBytes();
      final cache =
          await YoutubeSource.cacheSize() + await _dirSize(await SoundcloudSource.cacheDir());
      if (mounted) setState(() {
        _dl = dl;
        _cache = cache;
      });
    } catch (_) {}
  }

  String _fmt(int b) => b >= 1024 * 1024 * 1024
      ? '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} ГБ'
      : '${(b / (1024 * 1024)).round()} МБ';

  @override
  Widget build(BuildContext context) {
    final off = context.watch<OfflineService>();
    if (_seen != off.count) {
      _seen = off.count;
      _load(off);
    }
    final st = HutredStyle.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final main = st.mono ? HutredTheme.text : accent;
    final dl = _dl ?? 0, cache = _cache ?? 0;
    final total = dl + cache;
    final r = BorderRadius.circular(st.sharp ? 0 : 7);
    Widget legend(Color c, String n, int v) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(st.sharp ? 0 : 3))),
          const SizedBox(width: 8),
          Text('$n ', style: const TextStyle(fontSize: 13)),
          Text(_fmt(v), style: const TextStyle(fontSize: 13, color: HutredTheme.muted)),
        ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(_dl == null ? '…' : _fmt(total), style: st.display(38)),
          const SizedBox(width: 10),
          const Text('занимает Hutred', style: TextStyle(color: HutredTheme.muted)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: r,
          child: SizedBox(
            height: 14,
            child: Row(children: [
              if (total > 0) ...[
                Expanded(flex: (dl * 1000 ~/ total).clamp(1, 1000), child: ColoredBox(color: main)),
                Expanded(flex: (cache * 1000 ~/ total).clamp(1, 1000), child: const ColoredBox(color: Color(0xFF8A8A8A))),
              ] else
                const Expanded(child: ColoredBox(color: Color(0xFF262626))),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 22, runSpacing: 6, children: [
          legend(main, 'Загрузки', dl),
          legend(const Color(0xFF8A8A8A), 'Кэш', cache),
        ]),
      ]),
    );
  }
}

/// «Проверить обновления» — в самом низу настроек.
class _UpdateCheckTile extends StatelessWidget {
  const _UpdateCheckTile();

  @override
  Widget build(BuildContext context) {
    final u = context.watch<UpdateService>();
    final status = !u.supported
        ? 'Эта копия собрана вручную — сама не обновляется'
        : u.checking
            ? 'Проверяю…'
            : u.progress != null
                ? 'Скачиваю обновление… ${(u.progress! * 100).round()}%'
                : u.readyToInstall
                    ? 'Новая версия скачана — поставится при перезапуске'
                    : u.available
                        ? 'Доступна новая сборка ${u.latestBuild}'
                        : u.error ?? 'У тебя последняя версия';
    final st = HutredStyle.of(context);
    final ok = !u.available && !u.readyToInstall && u.error == null && u.supported;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 18,
        runSpacing: 12,
        children: [
          HutredLogo(size: 64, radius: st.sharp ? 0 : null),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hutred ${UpdateService.build == 0 ? '· локальная сборка' : '1.4.${UpdateService.build}'}',
                  style: st.display(22)),
              const SizedBox(height: 4),
              Text(ok ? '● $status' : status,
                  style: TextStyle(
                      fontSize: 13,
                      color: ok ? const Color(0xFF4ADE80) : HutredTheme.muted)),
            ]),
          ),
          if (u.available || u.readyToInstall)
            StyleButton(label: u.readyToInstall ? 'Перезапустить' : 'Обновить', onPressed: u.updateNow)
          else
            StyleButton(
              label: 'Проверить обновления',
              primary: false,
              onPressed: u.supported && !u.checking ? () => u.check(manual: true) : null,
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) => const Column(
        children: [
          SizedBox(height: 24),
          Center(child: HutredLogo(size: 72)),
          SizedBox(height: 8),
          Center(
            child: Text('Hutred',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ],
      );
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Text(text.toUpperCase(),
            style: HutredStyle.of(context)
                .caption(color: Theme.of(context).colorScheme.primary)),
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected
            ? Icon(Ic.check, color: HutredTheme.onAccent(color), size: 20)
            : null,
      ),
    );
  }
}

/// Кнопка «свой цвет»: открывает подбор по оттенку, насыщенности и яркости.
class _CustomSwatch extends StatelessWidget {
  const _CustomSwatch({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final s = context.read<SettingsStore>();
    return Tooltip(
      message: 'Свой цвет',
      child: InkResponse(
        radius: 28,
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
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? Colors.white : Colors.white30, width: selected ? 3 : 1.5),
            gradient: const SweepGradient(colors: [
              Colors.red, Colors.yellow, Colors.green, Colors.cyan,
              Colors.blue, Colors.purple, Colors.red,
            ]),
          ),
          child: Icon(Ic.colorize, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.title,
    required this.initial,
    required this.onApply,
  });

  final String title;
  final Color initial;
  final ValueChanged<Color> onApply;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSLColor _hsl;
  final _hex = TextEditingController();

  @override
  void initState() {
    super.initState();
    _hsl = HSLColor.fromColor(widget.initial);
    _syncHex();
  }

  void _syncHex() {
    final v = _hsl.toColor().toARGB32() & 0xFFFFFF;
    _hex.text = v.toRadixString(16).padLeft(6, '0').toUpperCase();
  }

  void _set(HSLColor c) {
    setState(() => _hsl = c);
    _syncHex();
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsl.toColor();
    Widget slider(String label, double value, double max, List<Color> track,
        ValueChanged<double> onChanged) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: HutredTheme.muted, fontSize: 12)),
          SizedBox(
            height: 36,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    gradient: LinearGradient(colors: track),
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                  ),
                  child: Slider(value: value, max: max, onChanged: onChanged),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text('Hutred',
                  style: TextStyle(
                      color: HutredTheme.onAccent(color),
                      fontWeight: FontWeight.w900,
                      fontSize: 20)),
            ),
            const SizedBox(height: 16),
            slider('Оттенок', _hsl.hue, 360, [
              for (var h = 0; h <= 360; h += 60)
                HSLColor.fromAHSL(1, h.toDouble(), 0.9, 0.55).toColor()
            ], (v) => _set(_hsl.withHue(v))),
            slider('Насыщенность', _hsl.saturation, 1, [
              _hsl.withSaturation(0).toColor(),
              _hsl.withSaturation(1).toColor(),
            ], (v) => _set(_hsl.withSaturation(v))),
            slider('Яркость', _hsl.lightness, 1, [
              Colors.black,
              _hsl.withLightness(0.5).toColor(),
              Colors.white,
            ], (v) => _set(_hsl.withLightness(v))),
            TextField(
              controller: _hex,
              decoration: const InputDecoration(prefixText: '#', labelText: 'HEX'),
              maxLength: 6,
              onChanged: (v) {
                if (v.length == 6) {
                  final n = int.tryParse(v, radix: 16);
                  if (n != null) {
                    setState(() => _hsl = HSLColor.fromColor(Color(0xFF000000 | n)));
                  }
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            widget.onApply(color);
            Navigator.pop(context);
          },
          child: const Text('Применить'),
        ),
      ],
    );
  }
}

class _BackgroundCard extends StatelessWidget {
  const _BackgroundCard({
    required this.preset,
    required this.accent,
    required this.selected,
    required this.onTap,
    this.custom = false,
  });
  final BackgroundPreset preset;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  /// Карточка «Свой цвет» — со значком пипетки.
  final bool custom;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 104,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: preset.ink,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : Colors.white12,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 14,
              decoration: BoxDecoration(
                  color: preset.surface, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                      color: preset.raised, borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                        color: accent, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                if (custom) ...[
                  Icon(Ic.colorize, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(preset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Ввод и проверка ключей своего приложения Spotify.
class _SpotifyKeysDialog extends StatefulWidget {
  const _SpotifyKeysDialog();

  @override
  State<_SpotifyKeysDialog> createState() => _SpotifyKeysDialogState();
}

class _SpotifyKeysDialogState extends State<_SpotifyKeysDialog> {
  late final TextEditingController _id;
  late final TextEditingController _secret;
  bool _checking = false;
  String? _status;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsStore>();
    _id = TextEditingController(text: s.ownSpotifyId);
    _secret = TextEditingController(text: s.ownSpotifySecret);
  }

  Future<void> _save() async {
    final id = _id.text.trim();
    final secret = _secret.text.trim();
    final settings = context.read<SettingsStore>();
    if (id.isEmpty && secret.isEmpty) {
      settings.setSpotifyKeys('', '');
      Navigator.pop(context);
      return;
    }
    setState(() {
      _checking = true;
      _status = null;
    });
    try {
      await context.read<SpotifyService>().checkKeys(id, secret);
      settings.setSpotifyKeys(id, secret);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _ok = false;
        _status = 'Ключи не подошли. Проверь Client ID и Client Secret.';
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ключи Spotify'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Создай приложение на developer.spotify.com → Dashboard → Create app '
              '(Redirect URI можно указать http://127.0.0.1:8888/callback, '
              'API — Web API). Скопируй Client ID и Client Secret сюда. '
              'Ключи хранятся только на этом устройстве.',
              style: TextStyle(color: HutredTheme.muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _id,
              decoration: const InputDecoration(labelText: 'Client ID'),
            ),
            TextField(
              controller: _secret,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Client Secret'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(_status!,
                  style: TextStyle(
                      color: _ok
                          ? Colors.greenAccent
                          : Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
          onPressed: _checking ? null : _save,
          child: _checking
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Проверить и сохранить'),
        ),
      ],
    );
  }
}

/// Размер кэша скачанных с YouTube треков и кнопка очистки.
/// Скачанное для прослушивания без интернета.
class _DownloadsTile extends StatefulWidget {
  const _DownloadsTile();

  @override
  State<_DownloadsTile> createState() => _DownloadsTileState();
}

class _DownloadsTileState extends State<_DownloadsTile> {
  int? _bytes;
  int _seen = -1;

  @override
  Widget build(BuildContext context) {
    final off = context.watch<OfflineService>();
    if (_seen != off.count) {
      _seen = off.count;
      off.sizeBytes().then((b) {
        if (mounted) setState(() => _bytes = b);
      });
    }
    final mb = _bytes == null ? '…' : (_bytes! / (1024 * 1024)).toStringAsFixed(1);
    return ListTile(
      leading: Icon(Ic.arrow_circle_down),
      title: const Text('Загрузки'),
      subtitle: Text(
        'Скачано: ${tracksWord(off.count)}, $mb МБ'
        '${off.pending > 0 ? ' · качается ещё ${off.pending}' : ''}. '
        'Играют без интернета. Скачать — в меню трека или кнопкой ⬇ у плейлиста.',
      ),
      trailing: TextButton(
        onPressed: off.count == 0 && off.pending == 0
            ? null
            : () async {
                final ok = await AppActions.confirm(context,
                    title: 'Удалить все загрузки?',
                    body: 'Треки останутся в медиатеке, но без интернета играть не будут.');
                if (ok) await off.removeAll();
              },
        child: const Text('Удалить все'),
      ),
    );
  }
}

class _CacheTile extends StatefulWidget {
  const _CacheTile();

  @override
  State<_CacheTile> createState() => _CacheTileState();
}

class _CacheTileState extends State<_CacheTile> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final b = await YoutubeSource.cacheSize() + await _dirSize(await SoundcloudSource.cacheDir());
      if (mounted) setState(() => _bytes = b);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final mb = _bytes == null ? '…' : (_bytes! / (1024 * 1024)).toStringAsFixed(1);
    return ListTile(
      leading: Icon(Ic.storage_outlined),
      title: const Text('Кэш прослушанного'),
      subtitle: Text('Занято $mb МБ. Временные файлы — можно очистить, загрузки останутся.'),
      trailing: TextButton(
        onPressed: () async {
          await YoutubeSource.clearCache();
          await _clearDir(await SoundcloudSource.cacheDir());
          await _refresh();
        },
        child: const Text('Очистить'),
      ),
    );
  }
}

/// Вход в YouTube через браузер — нужен для видео с пометкой 18+.
class _YoutubeLoginTile extends StatelessWidget {
  const _YoutubeLoginTile();

  static const _browsers = {
    '': 'Без входа',
    'firefox': 'Firefox',
    'chrome': 'Google Chrome',
    'edge': 'Microsoft Edge',
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(Ic.verified_user_outlined),
          title: const Text('Вход для видео 18+'),
          subtitle: const Text(
              'yt-dlp возьмёт вход в YouTube из браузера, где ты уже залогинен'),
          trailing: DropdownButton<String>(
            value: _browsers.containsKey(s.youtubeCookiesBrowser)
                ? s.youtubeCookiesBrowser
                : '',
            underline: const SizedBox.shrink(),
            onChanged: (v) => s.youtubeCookiesBrowser = v ?? '',
            items: [
              for (final e in _browsers.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Нужен установленный yt-dlp. Лучше всего работает Firefox: Chrome и Edge '
            'на Windows шифруют вход так, что yt-dlp часто не может его прочитать. '
            'Google может заблокировать аккаунт за скачивание через сторонние '
            'программы, поэтому надёжнее войти в браузере во второй аккаунт, '
            'а не в основной.',
            style: TextStyle(color: HutredTheme.muted, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    );
  }
}

Future<int> _dirSize(Directory dir) async {
  var total = 0;
  await for (final e in dir.list()) {
    if (e is File) total += await e.length();
  }
  return total;
}

Future<void> _clearDir(Directory dir) async {
  await for (final e in dir.list()) {
    if (e is File) {
      try {
        await e.delete();
      } catch (_) {}
    }
  }
}

/// Настройка ИИ-распознавания (Whisper через OpenAI-совместимый API).
class _AiKeyDialog extends StatefulWidget {
  const _AiKeyDialog();

  @override
  State<_AiKeyDialog> createState() => _AiKeyDialogState();
}

class _AiKeyDialogState extends State<_AiKeyDialog> {
  late final TextEditingController _base;
  late final TextEditingController _key;
  late final TextEditingController _model;

  static const _presets = {
    'Groq (бесплатно)': ('https://api.groq.com/openai/v1', 'whisper-large-v3'),
    'OpenAI': ('https://api.openai.com/v1', 'whisper-1'),
  };

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsStore>();
    _base = TextEditingController(text: s.ownAiBaseUrl);
    _key = TextEditingController(text: s.ownAiKey);
    _model = TextEditingController(text: s.ownAiModel.isEmpty ? 'whisper-large-v3' : s.ownAiModel);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ИИ для текстов'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ИИ (модель Whisper) прослушивает трек и находит, когда звучит '
                'каждая строка. Проще всего взять бесплатный ключ на console.groq.com '
                '→ API Keys → Create API Key. Ключ хранится только на этом устройстве. '
                'Трек отправляется в выбранный сервис на распознавание.',
                style: TextStyle(color: HutredTheme.muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in _presets.entries)
                    ActionChip(
                      label: Text(e.key),
                      onPressed: () => setState(() {
                        _base.text = e.value.$1;
                        _model.text = e.value.$2;
                      }),
                    ),
                ],
              ),
              TextField(
                controller: _key,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Ключ API'),
              ),
              TextField(
                controller: _base,
                decoration: const InputDecoration(labelText: 'Адрес сервиса'),
              ),
              TextField(
                controller: _model,
                decoration: const InputDecoration(labelText: 'Модель'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            context.read<SettingsStore>().setAi(
                  baseUrl: _base.text,
                  key: _key.text,
                  model: _model.text,
                );
            Navigator.pop(context);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

/// Кнопки админа: разослать свои настройки всем пользователям.
class _AdminTiles extends StatelessWidget {
  const _AdminTiles();

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccountService>();
    final s = context.read<SettingsStore>();
    final f = acc.appConfig['features'];
    final aiForAll = f is Map && f['aiForEveryone'] == true;

    Future<void> push(String key, Map<String, dynamic> value, String done) async {
      final err = await acc.pushConfig(key, value);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err ?? done)));
      }
    }

    return Column(
      children: [
        SwitchListTile(
          secondary: Icon(Ic.auto_awesome),
          title: const Text('ИИ-подгонка текста для всех'),
          subtitle: const Text('Если выключено, кнопку ИИ видишь только ты'),
          value: aiForAll,
          onChanged: (v) => push('features', {'aiForEveryone': v},
              v ? 'Теперь ИИ доступен всем' : 'ИИ теперь только у тебя'),
        ),
        ListTile(
          leading: Icon(Ic.cloud_upload_outlined),
          title: const Text('Применить мои ключи ИИ для всех'),
          subtitle: const Text('Раздаются всем автоматически, как только ты их вводишь. Кнопка — разослать заново'),
          enabled: s.ownAiKey.isNotEmpty,
          onTap: () => push('ai', {
            'baseUrl': s.ownAiBaseUrl,
            'key': s.ownAiKey,
            'model': s.ownAiModel,
          }, 'Ключи ИИ разосланы всем'),
        ),
        ListTile(
          leading: Icon(Ic.cloud_upload_outlined),
          title: const Text('Применить мой Discord ID для всех'),
          subtitle: const Text('Раздаётся всем автоматически. Кнопка — разослать заново'),
          enabled: s.ownDiscordAppId.isNotEmpty,
          onTap: () => push('discord', {'appId': s.ownDiscordAppId},
              'Discord ID разослан всем'),
        ),
        ListTile(
          leading: Icon(Ic.cloud_upload_outlined),
          title: const Text('Применить мои ключи Spotify для всех'),
          subtitle: const Text('Раздаются всем автоматически. Кнопка — разослать заново'),
          enabled: s.ownSpotifyId.isNotEmpty,
          onTap: () => push('spotify', {
            'id': s.ownSpotifyId,
            'secret': s.ownSpotifySecret,
          }, 'Ключи Spotify разосланы всем'),
        ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile();

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccountService>();
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      leading: const UserAvatar(radius: 20),
      title: Text(
          acc.signedIn
              ? (acc.username != null ? '@${acc.username}' : acc.email ?? 'Аккаунт')
              : 'Войти в аккаунт',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(acc.signedIn
          ? (acc.syncError ?? 'Медиатека синхронизируется между устройствами')
          : 'Чтобы медиатека была на телефоне и компьютере'),
      trailing: Icon(Ic.chevron_right),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AccountScreen())),
    );
  }
}

/// Перетаскивание вкладок: в каком порядке они стоят в боковой панели.
class _NavOrderEditor extends StatelessWidget {
  const _NavOrderEditor();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final order = s.navOrder;
    return Column(
      children: [
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: s.reorderNav,
          children: [
            for (var i = 0; i < order.length; i++)
              ListTile(
                key: ValueKey(order[i]),
                leading: Icon(navTabs[order[i]]!.icon),
                // Скрытую вкладку можно открыть отсюда.
                onTap: s.isTabHidden(order[i])
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => navPage(order[i])))
                    : null,
                subtitle: s.isTabHidden(order[i]) ? const Text('Скрыта — нажми, чтобы открыть') : null,
                title: Text(navTabs[order[i]]!.label,
                    style: TextStyle(
                        color: s.isTabHidden(order[i]) ? HutredTheme.muted : null)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Глазик: показывать вкладку на панели или нет.
                    if (order[i] != 'settings')
                      IconButton(
                        tooltip: s.isTabHidden(order[i]) ? 'Показать на панели' : 'Скрыть',
                        onPressed: () => s.setTabHidden(order[i], !s.isTabHidden(order[i])),
                        icon: Icon(s.isTabHidden(order[i])
                            ? Ic.visibility_off_outlined
                            : Ic.visibility_outlined),
                      ),
                    ReorderableDragStartListener(
                      index: i,
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Ic.drag_handle),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton.icon(
              onPressed: s.resetNavOrder,
              icon: Icon(Ic.restart_alt),
              label: const Text('Вернуть как было'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Версия, автообновление и автозапуск вместе с Windows.
class _UpdatesTiles extends StatefulWidget {
  const _UpdatesTiles();

  @override
  State<_UpdatesTiles> createState() => _UpdatesTilesState();
}

class _UpdatesTilesState extends State<_UpdatesTiles> {
  bool? _autostart;

  @override
  void initState() {
    super.initState();
    WindowsAutostart.isEnabled().then((v) {
      if (mounted) setState(() => _autostart = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    return Column(
      children: [
        if (Platform.isWindows)
          SwitchListTile(
            secondary: Icon(Ic.autorenew),
            title: const Text('Обновляться автоматически'),
            subtitle: const Text(
                'Новая версия скачивается сама и ставится, когда музыка не играет'),
            value: s.autoUpdate,
            onChanged: (v) => s.autoUpdate = v,
          ),
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
          SwitchListTile(
            secondary: Icon(Ic.close_fullscreen),
            title: const Text('Крестик сворачивает в трей'),
            subtitle: const Text(
                'Окно прячется к часам, музыка играет дальше. Выйти — правой кнопкой по значку'),
            value: s.closeToTray,
            onChanged: (v) => s.closeToTray = v,
          ),
        if (WindowsAutostart.supported)
          SwitchListTile(
            secondary: Icon(Ic.power_settings_new),
            title: const Text('Запускать вместе с Windows'),
            subtitle: const Text('Hutred тихо стартует в трее при включении компьютера'),
            value: _autostart ?? false,
            onChanged: _autostart == null
                ? null
                : (v) async {
                    await WindowsAutostart.set(v);
                    final now = await WindowsAutostart.isEnabled();
                    if (mounted) setState(() => _autostart = now);
                  },
          ),
      ],
    );
  }
}


/// Исполнители в чёрном списке и скрытые треки.
class _BlacklistTiles extends StatelessWidget {
  const _BlacklistTiles();

  @override
  Widget build(BuildContext context) {
    final wave = context.watch<WaveService>();
    final names = wave.blockedArtists;
    return Column(
      children: [
        // Заголовок с иконкой — всегда, а под ним список (как у скрытых треков).
        ListTile(
          leading: Icon(Ic.person_off_outlined),
          title: Text(names.isEmpty
              ? 'Исполнителей в чёрном списке нет'
              : 'Исполнители в чёрном списке: ${names.length}'),
          subtitle: const Text('Не играют нигде, даже на фитах. Добавить — в меню трека '
              '«Не показывать исполнителя…» или на странице исполнителя'),
        ),
        for (final n in names)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            title: Text(n),
            trailing: TextButton(
              onPressed: () => wave.unblockArtist(n),
              child: const Text('Вернуть'),
            ),
          ),
        ListTile(
          leading: Icon(Ic.thumb_down_outlined),
          title: Text('Скрытые треки: ${wave.dislikedCount}'),
          subtitle: const Text('Треки с 👎 не играют в очередях, плейлистах и волне'),
          trailing: TextButton(
            onPressed: wave.dislikedCount == 0 ? null : wave.resetDislikes,
            child: const Text('Вернуть все'),
          ),
        ),
        for (final t in wave.dislikedTracks)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: t.artist.isEmpty
                ? null
                : Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: TextButton(
              onPressed: () => wave.undislikeKey(t.key),
              child: const Text('Вернуть'),
            ),
          ),
      ],
    );
  }
}


/// Страница одной группы настроек.
class _GroupPage extends StatelessWidget {
  const _GroupPage({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 110),
          children: [
            if (_pageSubtitles[title] != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                child: Text(_pageSubtitles[title]!,
                    style: TextStyle(fontSize: 13, color: Sk.of(context).muted)),
              ),
            settingsPageFor(title),
          ],
        ),
      );
}


/// Сервер-посредник: как через него ходить и работает ли он.
class _RelayTile extends StatefulWidget {
  const _RelayTile();

  @override
  State<_RelayTile> createState() => _RelayTileState();
}

class _RelayTileState extends State<_RelayTile> {
  String? _status;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (HutredRelay.url == null) return;
    final h = await HutredRelay.health();
    if (mounted) setState(() => _status = h == null ? 'не отвечает' : 'работает');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final acc = context.watch<AccountService>();
    final url = HutredRelay.url;
    final host = url == null ? null : Uri.tryParse(url)?.host;
    final String sub;
    if (url == null) {
      sub = 'Сервер ещё не настроен админом';
    } else if (!acc.signedIn) {
      sub = 'Работает только после входа в аккаунт';
    } else {
      sub = 'Сервер $host · ${_status ?? 'проверяю…'}'
          '${HutredRelay.used > 0 ? ' · через него прошло запросов: ${HutredRelay.used}' : ''}';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Ic.public, size: 22, color: HutredTheme.muted),
            const SizedBox(width: 16),
            const Expanded(
              child: Text('Сервер Hutred для заблокированного',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 38, top: 4),
            child: Text(
              'Если YouTube, SoundCloud или Spotify не открываются (например, в России), '
              'Hutred скачает трек через свой сервер. Остальной интернет не трогает. $sub',
              style: const TextStyle(color: HutredTheme.muted, fontSize: 13, height: 1.4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 38, top: 10),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (v, label) in const [
                ('auto', 'Когда не открывается'),
                ('always', 'Всегда'),
                ('off', 'Никогда'),
              ])
                StyleChip(
                  label: label,
                  selected: s.relayMode == v,
                  onTap: () => s.relayMode = v,
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Админ: адрес сервера-посредника для всех.
class _RelayAdminTile extends StatelessWidget {
  const _RelayAdminTile();

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccountService>();
    return ListTile(
      leading: Icon(Ic.dns_outlined),
      title: const Text('Сервер-посредник для всех'),
      subtitle: Text(HutredRelay.url ?? 'Не задан — вставь адрес из установки сервера'),
      trailing: Icon(Ic.edit_outlined),
      onTap: () async {
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
          AppActions.toast(context, err ?? (url.isEmpty ? 'Сервер убран' : 'Сервер сохранён для всех'));
        }
      },
    );
  }
}


/// Способ обхода блокировок: что подобрано и кнопка «подобрать заново».
class _DpiTuneTile extends StatefulWidget {
  const _DpiTuneTile();

  @override
  State<_DpiTuneTile> createState() => _DpiTuneTileState();
}

class _DpiTuneTileState extends State<_DpiTuneTile> {
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
    return ValueListenableBuilder<String>(
      valueListenable: DpiBypass.status,
      builder: (_, st, __) => Padding(
        padding: const EdgeInsets.fromLTRB(72, 0, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _progress ??
                  (st.isEmpty
                      ? 'Способ обхода ещё не подбирался — Hutred проверит сам через пару секунд'
                      : st),
              style: const TextStyle(color: HutredTheme.muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              StyleButton(
                label: _progress == null ? 'Подобрать способ заново' : 'Подбираю…',
                primary: false,
                onPressed: _progress == null ? _tune : null,
              ),
              for (final k in DpiBypass.strategies)
                StyleChip(
                  label: DpiBypass.strategyLabel(k),
                  selected: (s.dpiStrategy ?? 'split') == k,
                  onTap: () {
                    DpiBypass.strategy = k;
                    s.setDpiStrategy(k);
                    DpiBypass.status.value = 'Способ: ${DpiBypass.strategyLabel(k)} (выбран вручную)';
                  },
                ),
            ]),
          ],
        ),
      ),
    );
  }
}


/// Свой VPN-ключ только для Hutred (ядро Xray рядом с приложением).
class _VpnTile extends StatefulWidget {
  const _VpnTile();

  @override
  State<_VpnTile> createState() => _VpnTileState();
}

class _VpnTileState extends State<_VpnTile> {
  final _field = TextEditingController();
  bool _busy = false;
  bool _editing = false;
  List<int?>? _pings;
  String? _error;
  String? _step;

  @override
  void initState() {
    super.initState();
    // Пинг серверов сразу — чтобы рядом с названием было видно задержку.
    final list = _servers(context.read<SettingsStore>());
    if (list.length > 1) {
      XrayVpn.pingAll(list).then((r) {
        if (mounted && _pings == null) setState(() => _pings = r);
      });
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  List<VpnServer> _servers(SettingsStore s) =>
      [for (final l in s.vpnServers) XrayVpn.parse(l)].whereType<VpnServer>().toList();

  Future<void> _applyKey(String text) async {
    final s = context.read<SettingsStore>();
    text = text.trim();
    if (text.isEmpty) return;
    XrayVpn.hwid = s.vpnHwid;
    setState(() {
      _busy = true;
      _error = null;
      _pings = null;
      _step = XrayVpn.isSubscription(text) ? 'Загружаю подписку…' : 'Читаю ключ…';
    });
    try {
      if (text.startsWith('happ://')) {
        throw 'Это зашифрованная ссылка Happ, её может прочитать только Happ. '
            'Вставь ссылку-подписку https://… или ключ сервера vless://…';
      }
      final list = XrayVpn.isSubscription(text)
          ? await XrayVpn.loadSubscription(text)
          : XrayVpn.parseAny(text);
      if (list.isEmpty) {
        throw 'Не нашёл в ключе ни одного сервера. Подходят vless://, vmess://, '
            'trojan://, ss:// и ссылки-подписки https://';
      }
      var best = 0;
      if (list.length > 1) {
        if (mounted) setState(() => _step = 'Ищу самый быстрый из ${list.length} серверов…');
        final p = await XrayVpn.pingAll(list);
        _pings = p;
        for (var i = 0; i < p.length; i++) {
          if (p[i] != null && (p[best] == null || p[i]! < p[best]!)) best = i;
        }
      }
      s.setVpn(link: text, servers: [for (final x in list) x.link], index: best, on: true);
      _field.clear();
      _editing = false;
      if (mounted) setState(() => _step = null);
      await XrayVpn.start(list[best]);
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _step = null;
        });
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (clip.trim().isEmpty) return;
    _field.text = clip.trim();
    await _applyKey(clip);
  }

  void _showJournal() {
    final text = XrayVpn.journal.join('\n');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Журнал VPN'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: SelectableText(text, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
              AppActions.toast(context, 'Журнал скопирован');
            },
            child: const Text('Скопировать'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
        ],
      ),
    );
  }

  Future<void> _pingAll() async {
    final list = _servers(context.read<SettingsStore>());
    setState(() => _pings = null);
    final r = await XrayVpn.pingAll(list);
    if (mounted) setState(() => _pings = r);
  }

  Future<void> _toggle(bool on) async {
    final s = context.read<SettingsStore>();
    s.setVpn(on: on);
    if (!on) {
      await XrayVpn.stop();
      return;
    }
    final list = _servers(s);
    if (list.isEmpty) {
      setState(() => _editing = true);
      return;
    }
    await XrayVpn.start(list[s.vpnIndex.clamp(0, list.length - 1)]);
  }

  Widget _keyField() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _field,
              enabled: !_busy,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Вставь ключ сюда: https://… (подписка) или vless://…',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Вставить из буфера',
                  icon: Icon(Ic.content_paste_rounded),
                  onPressed: _busy ? null : _pasteFromClipboard,
                ),
              ),
              onSubmitted: _busy ? null : _applyKey,
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              SkButton(_busy ? 'Подключаю…' : 'Подключить',
                  primary: true, onTap: _busy ? null : () => _applyKey(_field.text)),
              if (context.read<SettingsStore>().vpnServers.isNotEmpty)
                SkButton('Отмена',
                    onTap: _busy ? null : () => setState(() => _editing = false)),
            ]),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final k = Sk.of(context);
    final list = _servers(s);
    final showField = list.isEmpty || _editing;
    return ValueListenableBuilder<String>(
      valueListenable: XrayVpn.status,
      builder: (_, st, __) => ValueListenableBuilder<String?>(
        valueListenable: XrayVpn.message,
        builder: (_, msg, __) {
          final on = s.vpnOn && st == 'on';
          final cur = list.isEmpty ? null : list[s.vpnIndex.clamp(0, list.length - 1)];
          final ping = cur == null || _pings == null || s.vpnIndex >= _pings!.length
              ? null
              : _pings![s.vpnIndex];
          final String line;
          final Color color;
          if (list.isEmpty) {
            line = 'Ключ из Happ, v2rayN или Hiddify. Через VPN пойдёт только музыка';
            color = k.muted;
          } else if (!s.vpnOn) {
            line = 'Выключен · ${list.length == 1 ? list.first.name : '${list.length} серверов'}';
            color = k.muted;
          } else if (st == 'on') {
            line = '● Музыка идёт через VPN · ${cur?.name ?? ''}${ping != null ? ' · $ping мс' : ''}';
            color = k.ok;
          } else if (st == 'starting') {
            line = '● Подключаюсь…';
            color = k.warn;
          } else {
            line = '● ${msg ?? 'VPN не работает — музыка идёт напрямую'}';
            color = k.bad;
          }
          final icon = Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: on ? k.ok.withValues(alpha: 0.14) : k.inner,
              borderRadius: BorderRadius.circular(k.ri),
            ),
            child: Icon(Ic.vpn_lock_outlined, color: on ? k.ok : k.muted, size: 22),
          );
          final title = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Свой VPN-ключ · только для Hutred', style: k.h),
            const SizedBox(height: 2),
            Text(line, style: TextStyle(fontSize: 13, color: color)),
          ]);
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (XrayVpn.journal.isNotEmpty) SkButton('Журнал', onTap: _showJournal),
              if (!showField)
                SkButton('Другой ключ',
                    onTap: _busy ? null : () => setState(() => _editing = true)),
              if (!showField && XrayVpn.isSubscription(s.vpnLink))
                SkButton(_busy ? 'Обновляю…' : 'Обновить подписку',
                    onTap: _busy ? null : () => _applyKey(s.vpnLink)),
              SkToggle(value: s.vpnOn, onChanged: _busy ? null : _toggle),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(builder: (context, box) {
                if (box.maxWidth < 700) {
                  return SkGap(gap: 12, children: [
                    Row(children: [icon, const SizedBox(width: 14), Expanded(child: title)]),
                    actions,
                  ]);
                }
                return Row(children: [
                  icon,
                  const SizedBox(width: 14),
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  actions,
                ]);
              }),
              if (showField) ...[const SizedBox(height: 14), _keyField()],
              if (_step != null) ...[
                const SizedBox(height: 10),
                Text(_step!, style: k.sub),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: k.bad, fontSize: 13)),
              ],
              if (list.length > 1 && !showField) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (i, x) in list.indexed)
                    SkChip(
                      _pings == null || i >= _pings!.length
                          ? x.name
                          : '${x.name} · ${_pings![i] == null ? 'нет связи' : '${_pings![i]} мс'}',
                      height: 34,
                      selected: s.vpnIndex == i,
                      onTap: _busy
                          ? null
                          : () {
                              s.setVpn(index: i, on: true);
                              XrayVpn.start(x);
                            },
                    ),
                  SkButton(_pings == null ? 'Проверить скорость' : 'Ещё раз',
                      height: 34, onTap: _busy ? null : _pingAll),
                ]),
              ],
            ],
          );
        },
      ),
    );
  }
}
