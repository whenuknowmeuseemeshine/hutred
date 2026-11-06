import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/account_service.dart';
import '../theme.dart';
import 'net_image.dart';

/// Аватарка пользователя: картинка из профиля или первая буква логина/почты.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.radius = 15});
  final double radius;

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccountService>();
    final scheme = Theme.of(context).colorScheme;
    final name = acc.username ?? acc.email ?? '?';
    final letter = Text(
      acc.signedIn && name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: TextStyle(fontWeight: FontWeight.w800, fontSize: radius * 0.9),
    );
    final url = acc.avatarUrl;
    // «Резкий»: квадратная аватарка.
    if (Theme.of(context).extension<HutredStyle>()?.sharp ?? false) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        color: scheme.primary,
        alignment: Alignment.center,
        child: url == null
            ? DefaultTextStyle.merge(style: TextStyle(color: scheme.onPrimary), child: letter)
            : Image.network(url,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => letter),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      foregroundImage: url == null ? null : NetArt(url),
      onForegroundImageError: url == null ? null : (_, __) {},
      child: letter,
    );
  }
}
