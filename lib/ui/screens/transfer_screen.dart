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

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TransferService>();
    final busy = t.stage == TransferStage.reading || t.stage == TransferStage.matching;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Перенос'),
        actions: [
          if (t.items.isNotEmpty)
            IconButton(
              tooltip: 'Начать заново',
              onPressed: () {
                t.reset();
                _input.clear();
              },
              icon: const Icon(Icons.restart_alt),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        children: [
          if (t.items.isEmpty) ...[
            const Text(
              'Перенеси свою музыку из Spotify, Яндекс Музыки, YouTube, SoundCloud '
              'или любой другой площадки. Hutred найдёт каждый трек и сложит их '
              'в медиатеку и новый плейлист.',
              style: TextStyle(color: HutredTheme.muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _input,
              minLines: 4,
              maxLines: 10,
              enabled: !busy,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Ссылка на плейлист или список, по треку в строке:\n'
                    'Исполнитель — Название',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : _start,
                  icon: const Icon(Icons.search),
                  label: const Text('Найти треки'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : _pickFile,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Файл CSV или TXT'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Искать сначала на', style: TextStyle(color: HutredTheme.muted)),
                const SizedBox(width: 12),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    if (context.watch<SettingsStore>().hasSpotifyKeys)
                      const ButtonSegment(value: 'spotify', label: Text('Spotify')),
                    const ButtonSegment(value: 'soundcloud', label: Text('SoundCloud')),
                    const ButtonSegment(value: 'youtube', label: Text('YouTube')),
                  ],
                  selected: {
                    t.searchFirst == 'spotify' && !context.read<SettingsStore>().hasSpotifyKeys
                        ? 'soundcloud'
                        : t.searchFirst
                  },
                  onSelectionChanged: (v) => t.setSearchFirst(v.first),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _Hint(
              icon: Icons.table_chart_outlined,
              title: 'Длинный плейлист Spotify (больше 50 треков)',
              text: 'Открой exportify.net, войди через Spotify, скачай плейлист '
                  'в CSV и загрузи его кнопкой «Файл CSV».',
            ),
            const _Hint(
              icon: Icons.link,
              title: 'По ссылке',
              text: 'Треки, плейлисты и альбомы Spotify, открытые плейлисты и альбомы '
                  'Яндекс Музыки, плейлисты YouTube и SoundCloud.',
            ),
            const _Hint(
              icon: Icons.notes,
              title: 'Любая другая площадка',
              text: 'Скопируй названия треков текстом — по одному в строке, '
                  'как «Исполнитель — Название».',
            ),
          ],
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
          if (t.items.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              busy
                  ? 'Ищу треки… ${t.doneCount} из ${t.items.length}'
                  : 'Найдено ${t.foundCount} из ${t.items.length}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: t.items.isEmpty ? null : t.doneCount / t.items.length,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 12),
            for (final item in t.items) _ItemTile(item: item),
          ],
        ],
      ),
      bottomNavigationBar: t.stage == TransferStage.ready && t.foundCount > 0
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _name,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Плейлист (оставь пустым — только в медиатеку)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: t.selectedCount == 0 ? null : _save,
                      icon: const Icon(Icons.download_done),
                      label: Text('Добавить ${t.selectedCount}'),
                    ),
                  ],
                ),
              ),
            )
          : null,
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
          dimension: 44, child: Icon(Icons.search_off, color: scheme.error));
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
          if (item.done)
            PopupMenuButton<String>(
              tooltip: 'Искать в другом месте',
              icon: const Icon(Icons.manage_search, size: 20),
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

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(text, style: const TextStyle(color: HutredTheme.muted, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      );
}
