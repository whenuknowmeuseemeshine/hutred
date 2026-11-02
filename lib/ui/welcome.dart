import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/settings_store.dart';
import '../services/soundcloud_source.dart';
import '../services/wave_service.dart';
import 'screens/account_screen.dart';
import 'theme.dart';
import 'widgets/artwork.dart';

/// Первый экран: войти или создать аккаунт, потом уже пользоваться.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              shrinkWrap: true,
              children: [
                const SignInForm(),
                Center(
                  child: TextButton(
                    onPressed: () => context.read<SettingsStore>().guest = true,
                    style: TextButton.styleFrom(foregroundColor: HutredTheme.muted),
                    child: const Text('Продолжить без аккаунта'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// После регистрации: «Кого ты слушаешь?» — по ним «Волна» работает сразу.
class ArtistPickerScreen extends StatefulWidget {
  const ArtistPickerScreen({super.key, this.standalone = false});

  /// Открыт из Настроек (а не при знакомстве): закрывается назад.
  final bool standalone;

  @override
  State<ArtistPickerScreen> createState() => _ArtistPickerScreenState();
}

class _ArtistPickerScreenState extends State<ArtistPickerScreen> {
  final _query = TextEditingController();
  final Map<String, ScArtist> _picked = {};
  List<String> _found = [];
  bool _searching = false;
  bool _saving = false;
  String? _adding;

  @override
  void initState() {
    super.initState();
    // Уже выбранные раньше — показываем отмеченными.
    for (final name in context.read<WaveService>().favoriteArtists) {
      _picked[name] = ScArtist(name: name, avatarUrl: null, followers: 0, url: null, tracks: const []);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final tracks = await context.read<SoundcloudSource>().search(q, limit: 30);
      final names = <String>[];
      final seen = <String>{};
      for (final t in tracks) {
        final a = t.artist.trim();
        if (a.isEmpty || a == Track.unknownArtist) continue;
        if (seen.add(a.toLowerCase())) names.add(a);
        if (names.length >= 8) break;
      }
      if (mounted) setState(() => _found = names);
    } catch (_) {
      if (mounted) setState(() => _found = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _toggle(String name) async {
    if (_picked.containsKey(name)) {
      setState(() => _picked.remove(name));
      return;
    }
    setState(() => _adding = name);
    try {
      final a = await context.read<SoundcloudSource>().artist(name);
      if (!mounted) return;
      setState(() => _picked[name] = a ??
          ScArtist(name: name, avatarUrl: null, followers: 0, url: null, tracks: const []));
    } catch (_) {
    } finally {
      if (mounted) setState(() => _adding = null);
    }
  }

  Future<void> _done() async {
    setState(() => _saving = true);
    final wave = context.read<WaveService>();
    final settings = context.read<SettingsStore>();
    final sc = context.read<SoundcloudSource>();
    final result = <String, List<Track>>{};
    for (final e in _picked.entries) {
      var tracks = e.value.tracks;
      if (tracks.isEmpty) {
        // Выбран раньше (без треков в памяти) — подгружаем.
        try {
          tracks = (await sc.artist(e.key))?.tracks ?? const [];
        } catch (_) {}
      }
      result[e.key] = tracks.take(4).toList();
    }
    await wave.setFavoriteArtists(result);
    settings.pickArtists = false;
    if (mounted && widget.standalone) Navigator.of(context).pop();
  }

  void _skip() {
    context.read<SettingsStore>().pickArtists = false;
    if (widget.standalone) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: widget.standalone ? AppBar(title: const Text('Любимые исполнители')) : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (!widget.standalone) ...[
                  const Text('Кого ты слушаешь?',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                ],
                const Text(
                  'Выбери пару любимых исполнителей — «Моя волна» сразу начнёт '
                  'подбирать похожее. Потом подстроится под твои ♥.',
                  style: TextStyle(color: HutredTheme.muted),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'Имя исполнителя',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox.square(
                                dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            onPressed: _search, icon: const Icon(Icons.arrow_forward_rounded)),
                  ),
                ),
                const SizedBox(height: 12),
                if (_found.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final n in _found)
                        FilterChip(
                          label: Text(n),
                          selected: _picked.containsKey(n),
                          showCheckmark: false,
                          avatar: _adding == n
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : null,
                          onSelected: (_) => _toggle(n),
                        ),
                    ],
                  ),
                if (_picked.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text('Выбрано', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final a in _picked.values)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: scheme.surfaceContainerHighest,
                        foregroundImage:
                            a.avatarUrl == null ? null : artworkProvider(a.avatarUrl!),
                        child: Text(a.name.characters.first.toUpperCase()),
                      ),
                      title: Text(a.name),
                      trailing: IconButton(
                        tooltip: 'Убрать',
                        onPressed: () => setState(() => _picked.remove(a.name)),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _picked.isEmpty || _saving ? null : _done,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Готово'),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _saving ? null : _skip,
                    style: TextButton.styleFrom(foregroundColor: HutredTheme.muted),
                    child: Text(widget.standalone ? 'Отмена' : 'Пропустить'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// После регистрации: выбрать оформление (меняется сразу, видно вживую).
class ThemePickerScreen extends StatelessWidget {
  const ThemePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text('Как будет выглядеть Hutred?',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                const Text('Выбери цвет и фон — потом можно поменять в Настройках → Внешний вид.',
                    style: TextStyle(color: HutredTheme.muted)),
                const SizedBox(height: 24),
                const Text('Цвет', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final c in accentPresets)
                      GestureDetector(
                        onTap: () => s.accent = c,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: s.accent.toARGB32() == c.toARGB32()
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('Фон', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final b in backgroundPresets)
                      GestureDetector(
                        onTap: () => s.backgroundId = b.id,
                        child: Column(
                          children: [
                            Container(
                              width: 72,
                              height: 52,
                              decoration: BoxDecoration(
                                color: b.ink,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: s.background.id == b.id
                                      ? s.accent
                                      : Colors.white.withValues(alpha: 0.15),
                                  width: s.background.id == b.id ? 3 : 1,
                                ),
                              ),
                              alignment: Alignment.bottomLeft,
                              padding: const EdgeInsets.all(8),
                              child: Container(
                                width: 22,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: s.accent,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(b.name, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () => s.pickTheme = false,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: const Text('Дальше'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
