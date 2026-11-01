import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/account_service.dart';

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
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      foregroundImage: url == null ? null : NetworkImage(url),
      onForegroundImageError: url == null ? null : (_, __) {},
      child: letter,
    );
  }
}
