import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/account_service.dart';
import '../screens/account_screen.dart';
import 'user_avatar.dart';

/// Кнопка аккаунта: «Войти», если не вошёл, или кружок с буквой почты.
class AccountButton extends StatelessWidget {
  const AccountButton({super.key, this.extended = false});

  /// Широкая форма: кнопка с подписью (боковая панель на ПК).
  final bool extended;

  void _open(BuildContext context) => Navigator.of(context, rootNavigator: true)
      .push(MaterialPageRoute(builder: (_) => const AccountScreen()));

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccountService>();
    if (!acc.enabled) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    if (!acc.signedIn) {
      return extended
          ? FilledButton.tonalIcon(
              onPressed: () => _open(context),
              icon: const Icon(Icons.login, size: 18),
              label: const Text('Войти'),
            )
          : IconButton(
              tooltip: 'Войти в аккаунт',
              onPressed: () => _open(context),
              icon: const Icon(Icons.account_circle_outlined),
            );
    }

    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        const UserAvatar(radius: 15),
        // Точка состояния синхронизации.
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: scheme.surface, width: 2),
              color: acc.syncError != null
                  ? scheme.error
                  : (acc.syncing ? Colors.amber : Colors.greenAccent),
            ),
          ),
        ),
      ],
    );

    return Tooltip(
      message: acc.syncError ?? acc.email ?? 'Аккаунт',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: extended
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    avatar,
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Text(acc.username != null ? '@${acc.username}' : acc.email ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                )
              : avatar,
        ),
      ),
    );
  }
}
