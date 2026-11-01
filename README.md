# Hutred

Музыкальный плеер на Flutter для Android, iOS, Windows, macOS и Linux.

- **Треки из любых источников:** аудиофайлы, целые папки (на компьютере), YouTube и YouTube Music (видео и плейлисты), прямые ссылки на mp3 и потоки интернет-радио. Всё складывается в одну медиатеку и смешивается в плейлистах.
- **Поиск:** одновременно по своей медиатеке и по YouTube. Вставка ссылки в поиск добавляет трек или плейлист.
- **Текст как в Spotify:** текст подтягивается автоматически. Порядок поиска: синхронный текст в [LRCLIB](https://lrclib.net) → NetEase Music → субтитры клипа на YouTube (тоже по таймеру) → полный текст с [Genius](https://genius.com). Текущая строка заливается по словам в такт, список сам прокручивается, по строке можно нажать и перемотать. В меню «…» на экране текста можно взять текст из конкретного источника или вставить свой.
- **Обложки с Genius:** для треков без обложки ищутся автоматически, когда трек начинает играть; для любого трека — через меню «⋮ → Найти обложку на Genius».
- **Свои цвета:** во вкладке «Настройки» выбирается акцентный цвет (готовый или любой свой) и фон.
- Очередь с перетаскиванием, перемешивание, повтор, избранное, плейлисты, мини-плеер.
- На компьютере: боковая панель, текст справа от обложки, громкость, горячие клавиши (Ctrl+Пробел, Ctrl+←/→, Ctrl+L, медиаклавиши).

## Запуск

Нужен Flutter 3.27 или новее (`flutter --version`).

```bash
cd hutred
flutter create --org ru.hutred --platforms=android,ios,windows,macos,linux .
dart run tool/setup_platforms.dart
flutter pub get
dart run flutter_launcher_icons   # иконка приложения из assets/logo.png
flutter run            # или: flutter run -d windows / -d macos / -d linux
```

На Windows перед первой сборкой включи «Режим разработчика»: Параметры → Система → Для разработчиков.

`flutter create .` генерирует платформенные папки, а `setup_platforms.dart` дописывает в них разрешения: интернет на Android, сеть и выбор файлов на macOS, http-потоки радио на Android и iOS.

### Особенности платформ

- **Linux:** нужны `libmpv` и `zenity` (диалог выбора файлов): `sudo apt install libmpv-dev mpv zenity`.
- **Windows:** ничего ставить не нужно, библиотеки media_kit подтянутся при сборке.
- **Android/iOS:** выбранные файлы копируются в папку приложения, чтобы не пропасть из кэша.
- **Web** не поддерживается: браузер не даёт читать локальные пути и потоки YouTube.

### Сборка релиза

```bash
flutter build apk --release        # Android
flutter build windows --release    # Windows → build/windows/x64/runner/Release
flutter build macos --release
flutter build linux --release
flutter build ipa                  # iOS, нужен Mac и аккаунт Apple Developer
```

## Аккаунты и синхронизация

Чтобы у тебя и у друга были свои аккаунты, а медиатека была одинаковой на телефоне и компьютере, нужна бесплатная база Supabase (настраивается один раз, минут за 5):

1. Зарегистрируйся на https://supabase.com → **New project**. Придумай пароль базы, регион выбери Frankfurt (ближе всего).
2. Открой **SQL Editor → New query**, вставь целиком файл `supabase/schema.sql` и нажми **Run**. Появится таблица медиатеки, где каждый пользователь видит только свои треки.
3. **Project Settings → API**: скопируй **Project URL** и ключ **anon public** в `lib/config.dart`.
4. По желанию: **Authentication → Sign In / Providers → Email** — выключи «Confirm email», тогда можно входить сразу, без письма.
5. Пересобери приложение. В Настройках появится «Войти в аккаунт».

Ключ `anon public` можно спокойно встраивать в приложение: доступ к данным ограничен правилами из `schema.sql` (каждый видит только своё).

Что синхронизируется: треки, плейлисты, избранное, тексты, сдвиги текста. Треки с YouTube и SoundCloud играют на любом устройстве. Локальные файлы видны везде, но играют только там, где лежит сам файл. Настройки (цвета, ключи ИИ и Spotify) остаются на устройстве.

## Сборка для телефона

```bash
flutter build apk --release
```

Готовый файл: `build/app/outputs/flutter-apk/app-release.apk` — его можно скинуть другу и установить (на телефоне нужно разрешить установку из неизвестных источников).

На телефоне нет yt-dlp и Deno, поэтому часть видео с YouTube может не играть; SoundCloud и свои файлы работают как на компьютере.

## Устройство кода

```
lib/
  main.dart                    запуск, провайдеры
  models/                      Track, Playlist
  services/
    library_store.dart         медиатека и плейлисты (JSON в папке приложения)
    player_service.dart        очередь, перемешивание, повтор, just_audio
    youtube_source.dart        поиск, видео, плейлисты и аудиопотоки YouTube
    import_service.dart        файлы, папки, прямые ссылки
    lyrics_service.dart        парсер LRC и поиск текстов (LRCLIB → YouTube → Genius)
    genius_service.dart        поиск песен, текстов и обложек на Genius
    cover_service.dart         автоподбор обложек
    settings_store.dart        цвета и источники (settings.json)
    account_service.dart       аккаунты и синхронизация (Supabase)
    soundcloud_source.dart     поиск, плейлисты, скачивание SoundCloud
    wave_service.dart          «Моя волна»
    ai_sync_service.dart       ИИ-подгонка текста (Whisper)
  ui/
    home_shell.dart            навигация: боковая панель / нижняя панель
    screens/                   медиатека, поиск, плейлисты, плеер
    widgets/lyrics_view.dart   караоке-текст
```

Тесты парсера: `flutter test`.

## Что можно добавить дальше

- Фоновое воспроизведение и управление с экрана блокировки: пакет `just_audio_background` или `audio_service`.
- Чтение тегов и обложек из файлов (ID3, FLAC): пакет `metadata_god` или `audio_metadata_reader`.
- Новые источники (SoundCloud, Яндекс Музыка, подкасты по RSS): новый класс рядом с `youtube_source.dart` и новое значение в `TrackSource`.
- Синхронизация медиатеки между устройствами.

## Важно

Тексты с Genius берутся со страниц сайта, а не через официальный API, поэтому при изменении вёрстки Genius парсер может перестать находить текст — тогда поправь `parseLyricsHtml` в `genius_service.dart`. Приложение для личного использования; распространять чужие тексты нельзя.

Потоковое воспроизведение с YouTube идёт через неофициальную библиотеку `youtube_explode_dart`. Это нарушает условия использования YouTube, и YouTube периодически ломает такие библиотеки: если поиск или воспроизведение перестали работать, обнови пакет (`flutter pub upgrade youtube_explode_dart`). Для публикации в магазинах приложений этот источник лучше убрать.
