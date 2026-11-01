import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/library_store.dart';
import '../actions.dart';

/// Сердечко и «Добавить в плейлист» рядом, как в Spotify.
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
          },
          icon: Icon(
            liked ? Icons.favorite : Icons.favorite_border,
            color: liked ? scheme.primary : null,
          ),
        ),
        IconButton(
          tooltip: 'Добавить в плейлист',
          iconSize: size,
          onPressed: () => AppActions.addToPlaylistDialog(context, saved ?? track),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}
