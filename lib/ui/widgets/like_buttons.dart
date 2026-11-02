import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/track.dart';
import '../../services/library_store.dart';
import '../../services/wave_service.dart';
import '../actions.dart';

/// Сердечко и 👎 рядом. «Добавить в плейлист» — в меню трека.
/// Работает для любого трека: если его ещё нет в медиатеке,
/// лайк сам добавит его туда.
class LikeButtons extends StatelessWidget {
  const LikeButtons({super.key, required this.track, this.size = 22});

  final Track track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final scheme = Theme.of(context).colorScheme;
    // Трек мог попасть в медиатеку под другим id (например, из поиска).
    final saved = store.byId(track.id) ?? store.findBySource(track.source, track.uri);
    final liked = saved?.favorite ?? false;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: liked ? 'Убрать из любимых' : 'В любимые',
          iconSize: size,
          onPressed: () {
            if (saved == null) {
              store.addTracks([track.copyWith(favorite: true)]);
              AppActions.toast(context, 'Добавлено в любимые');
            } else {
              store.toggleFavorite(saved.id);
            }
            // Лайк — сигнал «нравится»: исполнителя больше не штрафуем за пропуски.
            if (!liked) context.read<WaveService>().forgiveArtist(track);
          },
          icon: Icon(
            liked ? Icons.favorite_rounded : LucideIcons.heart,
            color: liked ? scheme.primary : null,
          ),
        ),
        // 👎 — скрыть трек: он не будет играть в очередях, плейлистах и волне.
        Builder(builder: (context) {
          final wave = context.watch<WaveService>();
          final hidden = wave.isDisliked(track);
          return IconButton(
            tooltip: hidden ? 'Вернуть трек' : 'Не нравится — больше не играть',
            iconSize: size,
            onPressed: () {
              wave.toggleDislike(track);
              AppActions.toast(context,
                  hidden ? 'Трек снова будет играть' : 'Трек скрыт и больше не попадётся');
            },
            icon: Icon(
              hidden ? Icons.thumb_down_rounded : LucideIcons.thumbsDown,
              color: hidden ? scheme.error : null,
            ),
          );
        }),
      ],
    );
  }
}
