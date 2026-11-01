import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/account_service.dart';
import '../../services/offline_service.dart';
import '../../services/settings_store.dart';
import '../../services/update_service.dart';
import '../../services/soundcloud_source.dart';
import '../../services/spotify_service.dart';
import '../../services/youtube_source.dart';
import '../actions.dart';
import '../theme.dart';
import '../widgets/logo.dart';
import '../home_shell.dart';
import '../widgets/user_avatar.dart';
import 'account_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// Слова, по которым находится раздел в поиске (кроме его названия).
const _sectionKeywords = {
  'Аккаунт': 'вход войти логин аватар аватарка почта пароль облако синхронизация файлы',
  'Акцентный цвет': 'цвет тема оформление акцент',
  'Фон': 'фон цвет тема оформление обои плеер подкрашивать',
  'Медиатека': 'любимые избранное лайк добавленные',
  'Порядок вкладок': 'вкладки меню навигация порядок',
  'Тексты песен': 'текст караоке субтитры genius ии ai groq whisper тайминги',
  'Обложки': 'обложка spotify itunes genius ключи сверять сведения превью',
  'Админ': 'админ всем ключи раздать',
  'Discord': 'дискорд статус активность rich presence слушает',
  'Обновления': 'обновление версия сборка автозапуск автозагрузка windows трей',
  'Сеть': 'обход блокировок zapret vpn впн россия прокси',
  'YouTube': 'ютуб вход cookies браузер 18+',
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

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final acc = context.watch<AccountService>();

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
                prefixIcon: const Icon(Icons.search),
                hintText: 'Поиск по настройкам',
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
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
          ..._filter([
          const _AccountTile(),
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
                icon: const Icon(Icons.restart_alt),
                label: const Text('Вернуть цвета по умолчанию'),
              ),
            ),
          ),
          const _Section('Медиатека'),
          SwitchListTile(
            title: const Text('Добавленные треки сразу в любимые'),
            subtitle: const Text(
                'Как в Spotify: всё, что добавляешь, получает ♥ и скачивается '
                'вместе с любимыми, если они скачаны'),
            value: s.autoFavorite,
            onChanged: (v) => s.autoFavorite = v,
          ),
          const _Section('Порядок вкладок'),
          const _NavOrderEditor(),
          const _Section('Тексты песен'),
          const ListTile(
            dense: true,
            title: Text(
              'Сначала ищу текст с таймингами в LRCLIB и NetEase Music, потом '
              'в субтитрах YouTube, потом обычный текст на Genius.',
              style: TextStyle(color: HutredTheme.muted),
            ),
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
            leading: const Icon(Icons.auto_awesome),
            title: const Text('ИИ для текстов'),
            subtitle: Text(s.hasAi
                ? 'Подключён: подгоняет текст под трек и распознаёт песни без текста'
                : 'Не подключён. Нужен бесплатный ключ Groq или ключ OpenAI'),
            trailing: const Icon(Icons.chevron_right),
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
            leading: const Icon(Icons.key_outlined),
            title: const Text('Ключи Spotify'),
            subtitle: Text(s.hasSpotifyKeys
                ? 'Заданы, Spotify используется для обложек'
                : 'Не заданы, Spotify пропускается'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog(
              context: context,
              builder: (_) => const _SpotifyKeysDialog(),
            ),
          ),
          if (acc.isAdmin && acc.enabled && acc.signedIn) ...[
            const _Section('Админ'),
            const _AdminTiles(),
          ],
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) ...[
            const _Section('Discord'),
            SwitchListTile(
              secondary: const Icon(Icons.headset_mic_outlined),
              title: const Text('Показывать трек в Discord'),
              subtitle: Text(s.discordAppId.isEmpty
                  ? 'Нужен Application ID — нажми ниже'
                  : 'Как у Spotify: «Слушает Hutred», трек, обложка и время. Discord должен быть открыт'),
              value: s.discordPresence,
              onChanged: (v) => s.discordPresence = v,
            ),
            if (acc.isAdmin)
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('Application ID для Discord'),
                subtitle: Text(s.ownDiscordAppId.isEmpty
                    ? 'Не задан. discord.com/developers → New Application «Hutred» → скопируй Application ID'
                    : s.ownDiscordAppId),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final v = await AppActions.askText(context,
                      title: 'Application ID Discord',
                      hint: 'Например 1234567890123456789',
                      initial: s.ownDiscordAppId);
                  if (v != null) s.discordAppId = v;
                },
              ),
          ],
          const _Section('Обновления'),
          const _UpdatesTiles(),
          const _Section('Сеть'),
          SwitchListTile(
            secondary: const Icon(Icons.vpn_lock_outlined),
            title: const Text('Обход блокировок (для России)'),
            subtitle: const Text(
                'Как zapret, но только для Hutred и без прав администратора: '
                'YouTube, SoundCloud и обложки открываются без VPN. '
                'Если включён VPN — можно выключить'),
            value: s.dpiBypass,
            onChanged: (v) => s.dpiBypass = v,
          ),
          const _Section('YouTube'),
          const _YoutubeLoginTile(),
          const _Section('Загрузки и кэш'),
          const _DownloadsTile(),
          const _CacheTile(),
          const _Footer(),
          ]),
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
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            )),
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
            ? Icon(Icons.check, color: HutredTheme.onAccent(color), size: 20)
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
          child: const Icon(Icons.colorize, size: 18, color: Colors.white),
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
                  const Icon(Icons.colorize, size: 14, color: Colors.white),
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
      leading: const Icon(Icons.arrow_circle_down),
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
      leading: const Icon(Icons.storage_outlined),
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
          leading: const Icon(Icons.verified_user_outlined),
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
          secondary: const Icon(Icons.auto_awesome),
          title: const Text('ИИ-подгонка текста для всех'),
          subtitle: const Text('Если выключено, кнопку ИИ видишь только ты'),
          value: aiForAll,
          onChanged: (v) => push('features', {'aiForEveryone': v},
              v ? 'Теперь ИИ доступен всем' : 'ИИ теперь только у тебя'),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_upload_outlined),
          title: const Text('Применить мои ключи ИИ для всех'),
          subtitle: const Text('Другие будут пользоваться твоим ключом Groq/OpenAI'),
          enabled: s.ownAiKey.isNotEmpty,
          onTap: () => push('ai', {
            'baseUrl': s.ownAiBaseUrl,
            'key': s.ownAiKey,
            'model': s.ownAiModel,
          }, 'Ключи ИИ разосланы всем'),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_upload_outlined),
          title: const Text('Применить мой Discord ID для всех'),
          subtitle: const Text('У всех появится статус «Слушает Hutred» в Discord'),
          enabled: s.ownDiscordAppId.isNotEmpty,
          onTap: () => push('discord', {'appId': s.ownDiscordAppId},
              'Discord ID разослан всем'),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_upload_outlined),
          title: const Text('Применить мои ключи Spotify для всех'),
          subtitle: const Text('Обложки из Spotify появятся у всех'),
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
      trailing: const Icon(Icons.chevron_right),
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
                title: Text(navTabs[order[i]]!.label),
                trailing: ReorderableDragStartListener(
                  index: i,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.drag_handle),
                  ),
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
              icon: const Icon(Icons.restart_alt),
              label: const Text('Вернуть порядок по умолчанию'),
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
    final u = context.watch<UpdateService>();
    final s = context.watch<SettingsStore>();
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
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.system_update_alt),
          title: Text(
              'Hutred, сборка ${UpdateService.build == 0 ? 'локальная' : UpdateService.build}'),
          subtitle: Text(status),
          trailing: u.available
              ? FilledButton(onPressed: u.updateNow, child: const Text('Обновить'))
              : TextButton(
                  onPressed:
                      u.supported && !u.checking ? () => u.check(manual: true) : null,
                  child: const Text('Проверить'),
                ),
        ),
        if (Platform.isWindows)
          SwitchListTile(
            secondary: const Icon(Icons.autorenew),
            title: const Text('Обновляться автоматически'),
            subtitle: const Text(
                'Новая версия скачивается сама и ставится, когда музыка не играет'),
            value: s.autoUpdate,
            onChanged: (v) => s.autoUpdate = v,
          ),
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
          SwitchListTile(
            secondary: const Icon(Icons.close_fullscreen),
            title: const Text('Крестик сворачивает в трей'),
            subtitle: const Text(
                'Окно прячется к часам, музыка играет дальше. Выйти — правой кнопкой по значку'),
            value: s.closeToTray,
            onChanged: (v) => s.closeToTray = v,
          ),
        if (WindowsAutostart.supported)
          SwitchListTile(
            secondary: const Icon(Icons.power_settings_new),
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
