import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/account_service.dart';
import '../services/import_service.dart';
import '../services/library_store.dart';
import '../services/player_service.dart';
import '../services/soundcloud_source.dart';
import '../services/transfer_service.dart';
import '../services/youtube_source.dart';
import 'theme.dart';
import 'widgets/artwork.dart';

/// Общие действия: добавление источников, плейлисты, правка треков.
class AppActions {
  static final _importer = ImportService();

  static void toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Нижняя панель «Добавить музыку».
  static Future<void> showAddSheet(BuildContext context) {
    // На компьютере — аккуратное окошко посередине, а не шторка снизу.
    if (MediaQuery.sizeOf(context).width >= 700) return _showAddDialog(context);
    return showModalBottomSheet(
      context: context,
      showDragHandle: true,
      // На низком окне меню прокручивается, а не обрезается.
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Добавить музыку',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.smart_display_outlined),
              title: const Text('С YouTube'),
              subtitle: const Text(
                  'Ссылка на видео, плейлист или YouTube Music'),
              onTap: () {
                Navigator.pop(sheet);
                addUrlDialog(context, youtube: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: Text(ImportService.isDesktop ? 'Файлы или папка' : 'Аудиофайлы'),
              subtitle: Text(ImportService.isDesktop
                  ? 'Отдельные треки или целая папка с подпапками'
                  : 'mp3, flac, m4a, ogg, wav и другие'),
              onTap: () {
                Navigator.pop(sheet);
                addFromDevice(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('По ссылке'),
              subtitle: const Text('SoundCloud, mp3, интернет-радио и другие ссылки'),
              onTap: () {
                Navigator.pop(sheet);
                addUrlDialog(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        )),
      ),
    );
  }

  static Future<void> _showAddDialog(BuildContext context) {
    Widget option(BuildContext d, IconData icon, String title, String sub, VoidCallback go) =>
        _AddOption(icon: icon, title: title, subtitle: sub, onTap: () {
          Navigator.pop(d);
          go();
        });
    return showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (d) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Добавить музыку',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    iconSize: 20,
                    onPressed: () => Navigator.pop(d),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
                const SizedBox(height: 4),
                option(d, Icons.smart_display_outlined, 'С YouTube',
                    'Ссылка на видео, плейлист или YouTube Music',
                    () => addUrlDialog(context, youtube: true)),
                option(d, Icons.folder_open_rounded, 'Файлы или папка',
                    'Отдельные треки или целая папка с подпапками',
                    () => addFromDevice(context)),
                option(d, Icons.link_rounded, 'По ссылке',
                    'SoundCloud, Spotify, mp3, интернет-радио',
                    () => addUrlDialog(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Подписка на плейлист по ссылке hutred://playlist/… — он появится
  /// в плейлистах и будет обновляться, когда автор его меняет.
  static Future<void> importSharedPlaylist(BuildContext context, String link) async {
    final store = context.read<LibraryStore>();
    final acc = context.read<AccountService>();
    toast(context, 'Загружаю плейлист…');
    try {
      final sp = await acc.fetchSharedPlaylist(link);
      if (!context.mounted) return;
      if (sp.id.isNotEmpty && store.playlistById(sp.id) != null) {
        toast(context, 'Это твой плейлист');
        return;
      }
      store.followPlaylist(
        followId: sp.id,
        name: sp.name,
        description: sp.description,
        cover: sp.cover,
        owner: sp.owner.isEmpty ? null : sp.owner,
        tracks: sp.tracks,
      );
      toast(context, '«${sp.name}» теперь в твоих плейлистах');
    } catch (e) {
      if (context.mounted) toast(context, '$e'.replaceFirst('Exception: ', ''));
    }
  }

  static Future<void> addFiles(BuildContext context) async {
    final store = context.read<LibraryStore>();
    try {
      final tracks = await _importer.pickFiles();
      if (tracks.isEmpty || !context.mounted) return;
      final n = store.addTracks(tracks);
      toast(context, n == 0 ? 'Эти треки уже в медиатеке' : 'Добавлено: ${tracksWord(n)}');
    } catch (e) {
      if (context.mounted) toast(context, 'Не удалось открыть файлы: $e');
    }
  }

  static Future<void> addFolder(BuildContext context) async {
    final store = context.read<LibraryStore>();
    try {
      final tracks = await _importer.pickFolder();
      if (!context.mounted) return;
      if (tracks.isEmpty) {
        toast(context, 'В папке не нашлось аудиофайлов');
        return;
      }
      final n = store.addTracks(tracks);
      toast(context, 'Добавлено: ${tracksWord(n)}');
    } catch (e) {
      if (context.mounted) toast(context, 'Не удалось прочитать папку: $e');
    }
  }

  /// Одна кнопка для файлов и папок: на компьютере спрашиваем, что именно.
  static Future<void> addFromDevice(BuildContext context) async {
    if (!ImportService.isDesktop) return addFiles(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('Добавить с компьютера'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'files'),
            child: const ListTile(
              leading: Icon(Icons.audio_file_outlined),
              title: Text('Файлы'),
              subtitle: Text('Выбрать один или несколько треков'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'folder'),
            child: const ListTile(
              leading: Icon(Icons.folder_open_outlined),
              title: Text('Папку'),
              subtitle: Text('Все треки из неё и подпапок'),
            ),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'files') await addFiles(context);
    if (choice == 'folder') await addFolder(context);
  }

  static Future<void> addUrlDialog(BuildContext context,
      {String initial = '', bool youtube = false}) async {
    final ctrl = TextEditingController(text: initial);
    final url = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(youtube ? 'Добавить с YouTube' : 'Добавить по ссылке'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: youtube
                  ? 'https://youtube.com/watch?v=…'
                  : 'https://…',
              helperText: youtube
                  ? 'Видео, плейлист или трек с music.youtube.com. '
                      'Плейлист добавится целиком.'
                  : 'YouTube, прямая ссылка на аудио или поток радио',
              helperMaxLines: 2,
            ),
            onSubmitted: (v) => Navigator.pop(d, v.trim()),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(d, ctrl.text.trim()),
              child: const Text('Добавить')),
        ],
      ),
    );
    if (url == null || url.isEmpty || !context.mounted) return;
    if (youtube && !YoutubeSource.isYoutubeUrl(url)) {
      toast(context, 'Это не ссылка на YouTube');
      return;
    }
    await addUrl(context, url);
  }

  /// Ссылка Spotify: читаем список треков и ищем каждый на SoundCloud/YouTube.
  static Future<void> _addFromSpotify(BuildContext context, String url) async {
    final transfer = context.read<TransferService>();
    toast(context, 'Ищу треки из Spotify на SoundCloud и YouTube…');
    await transfer.start(url);
    if (!context.mounted) return;
    if (transfer.error != null && transfer.foundCount == 0) {
      toast(context, transfer.error!);
      transfer.reset();
      return;
    }
    final single = transfer.items.length == 1;
    final r = transfer.save(playlistName: single ? null : transfer.suggestedName);
    final missed = transfer.items.length - transfer.foundCount;
    transfer.reset();
    toast(
        context,
        r.added == 0 && missed == 0
            ? 'Уже в медиатеке'
            : [
                if (r.playlist != null) 'Плейлист «${r.playlist}»',
                'добавлено: ${tracksWord(r.added)}',
                if (missed > 0) 'не нашлось: $missed',
              ].join(', '));
  }

  static Future<void> addUrl(BuildContext context, String url) async {
    final store = context.read<LibraryStore>();
    // Плейлист, которым поделился друг.
    if (url.trim().startsWith(AccountService.playlistLinkPrefix)) {
      await importSharedPlaylist(context, url);
      return;
    }
    final yt = context.read<YoutubeSource>();
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      toast(context, 'Это не похоже на ссылку');
      return;
    }
    // Spotify сам звук не отдаёт: находим эти треки на SoundCloud/YouTube.
    if (uri.host.contains('spotify.com') || url.startsWith('spotify:')) {
      await _addFromSpotify(context, url);
      return;
    }
    toast(context, 'Загружаю…');
    try {
      List<Track> tracks;
      if (SoundcloudSource.isSoundcloudUrl(url)) {
        tracks = await context.read<SoundcloudSource>().fromUrl(url);
      } else if (YoutubeSource.isYoutubeUrl(url)) {
        tracks = YoutubeSource.isPlaylistUrl(url)
            ? await yt.fromPlaylistUrl(url)
            : [await yt.fromVideoUrl(url)];
      } else {
        tracks = [_importer.trackFromUrl(url)];
      }
      if (!context.mounted) return;
      final n = store.addTracks(tracks);
      toast(
          context,
          n == 0
              ? 'Уже в медиатеке'
              : n == 1
                  ? 'Добавлено: «${tracks.first.title}»'
                  : 'Добавлено: ${tracksWord(n)}');
    } catch (e) {
      if (!context.mounted) return;
      final msg = e.toString();
      if (msg.contains('VideoUnavailable') || msg.contains('unavailable')) {
        toast(
            context,
            'YouTube не отдал это видео. Оно может быть приватным, 18+ или '
            'заблокированным в регионе. Если в браузере оно открывается — '
            'обнови библиотеку: flutter pub upgrade youtube_explode_dart');
      } else {
        toast(context, 'Не удалось добавить: $msg');
      }
    }
  }

  /// Добавить трек в медиатеку, если его там ещё нет. Возвращает трек из медиатеки.
  static Track ensureInLibrary(BuildContext context, Track t) {
    final store = context.read<LibraryStore>();
    final existing = store.findBySource(t.source, t.uri);
    if (existing != null) return existing;
    store.addTracks([t]);
    return t;
  }

  static Future<void> addToPlaylistDialog(
      BuildContext context, Track track) async {
    final store = context.read<LibraryStore>();
    final t = ensureInLibrary(context, track);
    final choice = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('Добавить в плейлист'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, '__new__'),
            child: const Row(children: [
              Icon(Icons.add),
              SizedBox(width: 12),
              Text('Новый плейлист'),
            ]),
          ),
          for (final p in store.playlists.where((p) => !p.isFollowed))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, p.id),
              child: Text(p.name),
            ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    var pid = choice;
    if (choice == '__new__') {
      final name = await askText(context,
          title: 'Новый плейлист', hint: 'Название', action: 'Создать');
      if (name == null || !context.mounted) return;
      pid = store.createPlaylist(name).id;
    }
    final n = store.addToPlaylist(pid, [t.id]);
    final p = store.playlistById(pid);
    toast(context,
        n == 0 ? 'Уже есть в «${p?.name}»' : 'Добавлено в «${p?.name}»');
  }

  /// Добавить сразу много треков в плейлист (выбор в медиатеке).
  static Future<void> addManyToPlaylistDialog(
      BuildContext context, List<Track> tracks) async {
    final store = context.read<LibraryStore>();
    final choice = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text('Добавить ${tracksWord(tracks.length)} в плейлист'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, '__new__'),
            child: const Row(children: [
              Icon(Icons.add),
              SizedBox(width: 12),
              Text('Новый плейлист'),
            ]),
          ),
          for (final p in store.playlists)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, p.id),
              child: Text(p.name),
            ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    var pid = choice;
    if (choice == '__new__') {
      final name = await askText(context,
          title: 'Новый плейлист', hint: 'Название', action: 'Создать');
      if (name == null || !context.mounted) return;
      pid = store.createPlaylist(name).id;
    }
    final n = store.addToPlaylist(pid, tracks.map((t) => t.id));
    final p = store.playlistById(pid);
    toast(context, 'В «${p?.name}» добавлено: ${tracksWord(n)}');
  }

  static Future<String?> askText(
    BuildContext context, {
    required String title,
    String hint = '',
    String initial = '',
    String action = 'Сохранить',
  }) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(d, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(d, ctrl.text),
              child: Text(action)),
        ],
      ),
    );
  }

  static Future<void> editTrackDialog(BuildContext context, Track t) async {
    final store = context.read<LibraryStore>();
    final player = context.read<PlayerService>();
    final account = context.read<AccountService>();
    final title = TextEditingController(text: t.title);
    final artist = TextEditingController(text: t.artist);
    final album = TextEditingController(text: t.shownAlbum);
    // Обложка: новая картинка с диска (путь) или null — убрать.
    String? pickedCover;
    var removeCover = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (d, setState) => AlertDialog(
        title: const Text('Сведения о треке'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Artwork(
                    track: t.copyWith(
                        artworkUrl: removeCover ? null : (pickedCover ?? t.artworkUrl)),
                    size: 96,
                    radius: 8,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            final res =
                                await FilePicker.platform.pickFiles(type: FileType.image);
                            final path = res?.files.single.path;
                            if (path != null) {
                              setState(() {
                                pickedCover = path;
                                removeCover = false;
                              });
                            }
                          },
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Выбрать обложку'),
                        ),
                        if (!removeCover && (pickedCover ?? t.artworkUrl) != null)
                          TextButton(
                            onPressed: () => setState(() {
                              pickedCover = null;
                              removeCover = true;
                            }),
                            child: const Text('Убрать обложку'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Название')),
              const SizedBox(height: 10),
              TextField(
                  controller: artist,
                  decoration: const InputDecoration(labelText: 'Исполнитель')),
              const SizedBox(height: 10),
              TextField(
                  controller: album,
                  decoration: const InputDecoration(labelText: 'Альбом')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Сохранить')),
        ],
      )),
    );
    if (ok != true) return;
    String? cover = t.artworkUrl;
    if (removeCover) cover = null;
    if (pickedCover != null) {
      try {
        cover = await account.saveCover(pickedCover!, t.id);
      } catch (_) {
        cover = pickedCover;
      }
    }
    final coverChanged = cover != t.artworkUrl;
    final updated = t.copyWith(
      artworkUrl: cover,
      title: title.text.trim().isEmpty ? t.title : title.text.trim(),
      artist: artist.text.trim().isEmpty ? t.artist : artist.text.trim(),
      album: album.text.trim(),
      // Метаданные поменялись — текст ищем заново.
      lyrics: (title.text.trim() != t.title || artist.text.trim() != t.artist)
          ? null
          : t.lyrics,
      lyricsSource:
          (title.text.trim() != t.title || artist.text.trim() != t.artist)
              ? null
              : t.lyricsSource,
      // Свою обложку автоматический поиск больше не заменит.
      coverChecked: coverChanged
          ? true
          : ((title.text.trim() != t.title || artist.text.trim() != t.artist)
              ? false
              : t.coverChecked),
    );
    store.updateTrack(updated, manual: true);
    player.refreshTrack(updated);
  }

  static Future<bool> confirm(BuildContext context,
      {required String title, required String body, String action = 'Удалить'}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }
}


/// Строчка в окошке «Добавить музыку» на компьютере.
class _AddOption extends StatelessWidget {
  const _AddOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 22, color: scheme.onSurface),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
