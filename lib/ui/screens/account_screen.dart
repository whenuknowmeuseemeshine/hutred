import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/account_service.dart';
import '../../services/library_store.dart';
import '../../services/settings_store.dart';
import '../actions.dart';
import '../theme.dart';
import '../widgets/logo.dart';
import '../widgets/user_avatar.dart';

/// Вход, регистрация и состояние синхронизации.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccountService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Аккаунт')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: !acc.enabled
              ? const _NotConfigured()
              : acc.signedIn
                  ? const _Profile()
                  : const SignInForm(),
        ),
      ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Облако ещё не подключено. Чтобы появились аккаунты и синхронизация '
        'между телефоном и компьютером, создай бесплатный проект Supabase и '
        'впиши его адрес и ключ в lib/config.dart (инструкция в README, '
        'раздел «Аккаунты и синхронизация»).',
        textAlign: TextAlign.center,
        style: TextStyle(color: HutredTheme.muted, height: 1.5),
      ),
    );
  }
}

class SignInForm extends StatefulWidget {
  const SignInForm();

  @override
  State<SignInForm> createState() => SignInFormState();
}

class SignInFormState extends State<SignInForm> {
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@')) {
      setState(() {
        _message = 'Введи почту полностью, например name@mail.ru';
        _messageIsError = true;
      });
      return;
    }
    if (password.length < 6) {
      setState(() {
        _message = 'Пароль должен быть не короче 6 символов';
        _messageIsError = true;
      });
      return;
    }
    final acc = context.read<AccountService>();
    final username = _username.text.trim();
    if (_register) {
      final problem = await acc.checkUsername(username, forSignUp: true);
      if (problem != null) {
        setState(() {
          _message = problem;
          _messageIsError = true;
        });
        return;
      }
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_register) {
        final needConfirm = await acc.signUp(email, password, username: username);
        // После входа спросим любимых исполнителей — «Волна» заработает сразу.
        if (mounted) {
          context.read<SettingsStore>()
            ..pickTheme = true
            ..pickArtists = true;
        }
        if (needConfirm) {
          setState(() {
            _message = 'Аккаунт создан. Открой письмо на $email и нажми ссылку, '
                'потом войди здесь.';
            _messageIsError = false;
            _register = false;
          });
        }
      } else {
        await acc.signIn(email, password);
      }
    } catch (e) {
      setState(() {
        _message = AccountService.authError(e);
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() {
        _message = 'Сначала впиши почту, на неё придёт ссылка для сброса';
        _messageIsError = true;
      });
      return;
    }
    try {
      await context.read<AccountService>().resetPassword(email);
      setState(() {
        _message = 'Письмо для сброса пароля отправлено на $email';
        _messageIsError = false;
      });
    } catch (e) {
      setState(() {
        _message = AccountService.authError(e);
        _messageIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(24),
      children: [
        const Center(child: HutredLogo(size: 72)),
        const SizedBox(height: 16),
        Text(
          _register ? 'Создать аккаунт' : 'Вход в Hutred',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Медиатека и плейлисты будут одинаковыми на телефоне и компьютере.',
          textAlign: TextAlign.center,
          style: TextStyle(color: HutredTheme.muted),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
              labelText: 'Почта', border: OutlineInputBorder()),
        ),
        if (_register) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            autofillHints: const [AutofillHints.newUsername],
            decoration: const InputDecoration(
                labelText: 'Логин',
                helperText: 'Латиница, цифры, точка и _ (3–24 символа)',
                prefixText: '@',
                border: OutlineInputBorder()),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: [
            _register ? AutofillHints.newPassword : AutofillHints.password
          ],
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
              labelText: 'Пароль', border: OutlineInputBorder()),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!,
              style: TextStyle(
                  color: _messageIsError
                      ? Theme.of(context).colorScheme.error
                      : Colors.greenAccent)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _busy
              ? const SizedBox.square(
                  dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_register ? 'Создать аккаунт' : 'Войти'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => setState(() {
            _register = !_register;
            _message = null;
          }),
          child: Text(_register ? 'Уже есть аккаунт? Войти' : 'Нет аккаунта? Создать'),
        ),
        if (!_register)
          TextButton(onPressed: _busy ? null : _forgot, child: const Text('Забыл пароль')),
      ],
    );
  }
}

class _Profile extends StatelessWidget {
  const _Profile();

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccountService>();
    final store = context.watch<LibraryStore>();
    final last = acc.lastSync;
    final status = acc.syncing
        ? 'Синхронизация…'
        : acc.syncError ??
            (last == null
                ? 'Ещё не синхронизировано'
                : 'Синхронизировано в ${last.hour.toString().padLeft(2, '0')}:'
                    '${last.minute.toString().padLeft(2, '0')}');

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: Stack(
            children: [
              const UserAvatar(radius: 48),
              Positioned(
                right: 0,
                bottom: 0,
                child: IconButton.filledTonal(
                  tooltip: 'Сменить аватарку',
                  iconSize: 18,
                  onPressed: () => _pickAvatar(context),
                  icon: const Icon(Icons.photo_camera_outlined),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _editUsername(context),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(acc.username != null ? '@${acc.username}' : 'Задать логин',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.edit_outlined, size: 18, color: HutredTheme.muted),
              ],
            ),
          ),
        ),
        Text(acc.email ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: HutredTheme.muted)),
        if (acc.isAdmin)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Center(
              child: Chip(
                avatar: Icon(Icons.shield_outlined, size: 16),
                label: Text('Админ'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          '${tracksWord(store.tracks.length)} · плейлистов: ${store.playlists.length}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: HutredTheme.muted),
        ),
        const SizedBox(height: 24),
        ListTile(
          leading: acc.syncing
              ? const SizedBox.square(
                  dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(acc.syncError == null ? Icons.cloud_done_outlined : Icons.cloud_off,
                  color: acc.syncError == null ? null : Theme.of(context).colorScheme.error),
          title: Text(status),
          trailing: TextButton(
            onPressed: acc.syncing ? null : acc.syncNow,
            child: const Text('Обновить'),
          ),
        ),
        Builder(builder: (context) {
          final settings = context.watch<SettingsStore>();
          final status = acc.uploading
              ? 'Загружается… осталось ${acc.uploadLeft}'
              : acc.uploadError ??
                  'В облаке ${acc.cloudFiles} из ${acc.localFiles} своих файлов';
          return SwitchListTile(
            secondary: acc.uploading
                ? const SizedBox.square(
                    dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_sync_outlined),
            title: const Text('Хранить свои файлы в облаке'),
            subtitle: Text('$status. Файлы будут на телефоне и не пропадут, '
                'даже если удалить их с компьютера (до 50 МБ на файл, всего 1 ГБ бесплатно)'),
            value: settings.cloudFiles,
            onChanged: (v) {
              settings.cloudFiles = v;
              if (v) acc.uploadLocalFiles();
            },
          );
        }),
        ListTile(
          leading: const Icon(Icons.move_down),
          title: const Text('Перенести треки, добавленные без входа'),
          onTap: () async {
            final n = await acc.importGuestLibrary();
            if (context.mounted) {
              AppActions.toast(context, n == 0 ? 'Нечего переносить' : 'Перенесено: ${tracksWord(n)}');
            }
          },
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            final ok = await AppActions.confirm(context,
                title: 'Выйти из аккаунта?',
                body: 'Медиатека останется в облаке и вернётся, когда ты снова войдёшь.',
                action: 'Выйти');
            if (ok) await acc.signOut();
          },
          icon: const Icon(Icons.logout),
          label: const Text('Выйти'),
        ),
      ],
    );
  }
}

Future<void> _pickAvatar(BuildContext context) async {
  final acc = context.read<AccountService>();
  final res = await FilePicker.platform.pickFiles(type: FileType.image);
  final path = res?.files.single.path;
  if (path == null) return;
  final err = await acc.uploadAvatar(path);
  if (context.mounted) AppActions.toast(context, err ?? 'Аватарка обновлена');
}

Future<void> _editUsername(BuildContext context) async {
  final acc = context.read<AccountService>();
  final ctrl = TextEditingController(text: acc.username ?? '');
  String? error;
  var busy = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        Future<void> save() async {
          setState(() => busy = true);
          final err = await acc.updateUsername(ctrl.text.trim());
          if (err == null) {
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } else {
            setState(() {
              error = err;
              busy = false;
            });
          }
        }

        return AlertDialog(
          title: const Text('Логин'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            onSubmitted: (_) => save(),
            decoration: InputDecoration(
              prefixText: '@',
              errorText: error,
              helperText: 'Латиница, цифры, точка и _ (3–24 символа)',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
            FilledButton(onPressed: busy ? null : save, child: const Text('Сохранить')),
          ],
        );
      },
    ),
  );
}
