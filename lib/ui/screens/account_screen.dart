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
import '../icons.dart';
import '../widgets/style_bits.dart';
import '../../services/friends_service.dart';

/// Вход, регистрация и состояние синхронизации.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccountService>();
    return Scaffold(
      appBar: AppBar(title: acc.signedIn ? null : const Text('Аккаунт')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: acc.signedIn ? 1100 : 440),
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
    void problem(String m) => setState(() {
          _message = m;
          _messageIsError = true;
        });
    if (_register && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return problem('Введи почту полностью, например name@mail.ru');
    }
    if (!_register && email.isEmpty) return problem('Введи почту или логин');
    if (_register) {
      final weak = AccountService.weakPassword(password);
      if (weak != null) return problem(weak);
    } else if (password.isEmpty) {
      return problem('Введи пароль');
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
        _message = 'Впиши почту (не логин) — на неё придёт ссылка для сброса. '
            'Открой письмо на этом же устройстве';
        _messageIsError = true;
      });
      return;
    }
    try {
      await context.read<AccountService>().resetPassword(email);
      setState(() {
        _message = 'Письмо отправлено на $email. Открой ссылку на этом устройстве — '
            'Hutred откроется и попросит новый пароль';
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
          autofillHints: _register
              ? const [AutofillHints.email]
              : const [AutofillHints.username, AutofillHints.email],
          decoration: InputDecoration(
              labelText: _register ? 'Почта' : 'Почта или логин',
              border: const OutlineInputBorder()),
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
          decoration: InputDecoration(
              labelText: 'Пароль',
              helperText: _register ? 'От 8 символов, буквы и цифры' : null,
              border: const OutlineInputBorder()),
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
    final friends = context.watch<FriendsService>();
    final st = HutredStyle.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final last = acc.lastSync;
    final status = acc.syncing
        ? 'Синхронизация…'
        : acc.syncError ??
            (last == null
                ? 'Ещё не синхронизировано'
                : 'Медиатека синхронизирована в ${last.hour.toString().padLeft(2, '0')}:'
                    '${last.minute.toString().padLeft(2, '0')}');
    final statusColor = acc.syncError != null
        ? Theme.of(context).colorScheme.error
        : acc.syncing
            ? Colors.amber
            : const Color(0xFF4ADE80);

    final avatar = Stack(clipBehavior: Clip.none, children: [
      Container(
        decoration: st.glass
            ? BoxDecoration(shape: BoxShape.circle, boxShadow: [
                BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 60, offset: const Offset(0, 20))
              ])
            : null,
        child: UserAvatar(radius: wide ? 66 : 48),
      ),
      Positioned(
        right: st.sharp ? -4 : 6,
        bottom: st.sharp ? -4 : 6,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: st.sharp ? BoxShape.rectangle : BoxShape.circle,
            color: statusColor,
            border: Border.all(color: Theme.of(context).canvasColor, width: 4),
          ),
        ),
      ),
    ]);

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StyleCaption('Аккаунт'),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => _editUsername(context),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(acc.username != null ? '@${acc.username}' : 'Задать логин',
                  overflow: TextOverflow.ellipsis, style: st.display(wide ? 56 : 32)),
            ),
            const SizedBox(width: 8),
            Icon(Ic.edit_outlined, size: 18, color: HutredTheme.muted),
          ]),
        ),
        const SizedBox(height: 4),
        Text(acc.email ?? '', style: const TextStyle(color: HutredTheme.muted)),
        const SizedBox(height: 6),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                  color: statusColor,
                  shape: st.sharp ? BoxShape.rectangle : BoxShape.circle)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(status, style: TextStyle(color: statusColor, fontSize: 13)),
          ),
          if (acc.isAdmin) ...[
            const SizedBox(width: 12),
            StyleChip(label: 'Админ', icon: Ic.shield_outlined),
          ],
        ]),
      ],
    );

    final buttons = Wrap(
      spacing: 10,
      runSpacing: 10,
      direction: wide ? Axis.vertical : Axis.horizontal,
      children: [
        StyleButton(
            label: 'Сменить аватарку', primary: false, onPressed: () => _pickAvatar(context)),
        StyleButton(
            label: 'Сменить логин', primary: false, onPressed: () => _editUsername(context)),
      ],
    );

    Widget stat(String n, String label) => Expanded(
          child: StylePanel(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n, style: st.display(30)),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: HutredTheme.muted, fontSize: 13)),
            ]),
          ),
        );

    final sync = StylePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StyleCaption('Синхронизация'),
          const SizedBox(height: 10),
          Text(
            'Медиатека, плейлисты и любимые одинаковые на всех устройствах, '
            'где ты вошёл в этот аккаунт.',
            style: TextStyle(color: HutredTheme.muted, height: 1.45),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            StyleButton(
              label: acc.syncing ? 'Синхронизация…' : 'Синхронизировать',
              icon: Ic.refresh,
              onPressed: acc.syncing ? null : acc.syncNow,
            ),
            StyleButton(
              label: 'Перенести треки без входа',
              primary: false,
              onPressed: () async {
                final n = await acc.importGuestLibrary();
                if (context.mounted) {
                  AppActions.toast(
                      context, n == 0 ? 'Нечего переносить' : 'Перенесено: ${tracksWord(n)}');
                }
              },
            ),
          ]),
        ],
      ),
    );

    final cloud = Builder(builder: (context) {
      final settings = context.watch<SettingsStore>();
      final total = acc.localFiles;
      final done = acc.cloudFiles;
      final cloudStatus = acc.uploading
          ? 'Загружается… осталось ${acc.uploadLeft}'
          : acc.uploadError ?? 'В облаке $done из $total своих файлов';
      return StylePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(child: StyleCaption('Облако')),
              Switch(
                value: settings.cloudFiles,
                onChanged: (v) {
                  settings.cloudFiles = v;
                  if (v) acc.uploadLocalFiles();
                },
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Свои файлы хранятся в облаке и есть на всех устройствах '
              '(до 50 МБ на файл, всего 1 ГБ бесплатно). $cloudStatus.',
              style: const TextStyle(color: HutredTheme.muted, height: 1.45),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(st.sharp ? 0 : 3),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
                minHeight: st.sharp ? 2 : 6,
                color: accent,
                backgroundColor: const Color(0xFF2A2A2A),
              ),
            ),
            const SizedBox(height: 18),
            StyleButton(
              label: 'Сменить пароль',
              icon: Ic.edit_outlined,
              primary: false,
              onPressed: () => showNewPasswordDialog(context),
            ),
            const SizedBox(height: 10),
            StyleButton(
              label: 'Выйти из аккаунта',
              icon: Ic.logout,
              primary: false,
              onPressed: () async {
                final ok = await AppActions.confirm(context,
                    title: 'Выйти из аккаунта?',
                    body: 'Медиатека останется в облаке и вернётся, когда ты снова войдёшь.',
                    action: 'Выйти');
                if (ok) await acc.signOut();
              },
            ),
          ],
        ),
      );
    });

    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 8, wide ? 32 : 20, 40),
      children: [
        if (wide)
          Row(children: [
            avatar,
            const SizedBox(width: 24),
            Expanded(child: info),
            buttons,
          ])
        else ...[
          Center(child: avatar),
          const SizedBox(height: 16),
          info,
          const SizedBox(height: 14),
          buttons,
        ],
        const SizedBox(height: 24),
        Row(children: [
          stat('${store.tracks.length}', 'треков в медиатеке'),
          const SizedBox(width: 12),
          stat('${store.favorites.length}', 'любимых'),
          const SizedBox(width: 12),
          stat('${store.playlists.length}', 'плейлистов'),
          if (wide) ...[
            const SizedBox(width: 12),
            stat('${friends.friends.length}', 'друзей'),
          ],
        ]),
        const SizedBox(height: 20),
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: sync),
            const SizedBox(width: 20),
            SizedBox(width: 380, child: cloud),
          ])
        else ...[
          sync,
          const SizedBox(height: 16),
          cloud,
        ],
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


/// Окно нового пароля: после ссылки «сбросить пароль» или из аккаунта.
Future<void> showNewPasswordDialog(BuildContext context, {bool recovery = false}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !recovery,
    builder: (_) => _NewPasswordDialog(recovery: recovery),
  );
}

class _NewPasswordDialog extends StatefulWidget {
  const _NewPasswordDialog({required this.recovery});
  final bool recovery;

  @override
  State<_NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends State<_NewPasswordDialog> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final weak = AccountService.weakPassword(_p1.text);
    if (weak != null) return setState(() => _error = weak);
    if (_p1.text != _p2.text) return setState(() => _error = 'Пароли не совпадают');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AccountService>().changePassword(_p1.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      AppActions.toast(context, 'Пароль изменён');
    } catch (e) {
      if (mounted) setState(() => _error = AccountService.authError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.recovery ? 'Придумай новый пароль' : 'Сменить пароль'),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _p1,
            obscureText: true,
            autofocus: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(
                labelText: 'Новый пароль',
                helperText: 'От 8 символов, буквы и цифры',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _p2,
            obscureText: true,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
                labelText: 'Ещё раз', border: OutlineInputBorder()),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ]),
      ),
      actions: [
        if (!widget.recovery)
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
