# Hutred

Музыкальный плеер в духе Spotify: Windows, Android и iPhone.

- Своя медиатека из любых источников: файлы, SoundCloud, YouTube, Spotify, ссылки и радио.
- «Моя волна» и умное перемешивание с рекомендациями.
- Тексты песен караоке-строкой, обложки и сведения о треках.
- Плейлисты с подпиской, друзья, синхронизация между устройствами.
- Загрузки для прослушивания без интернета.

## Скачать

Последняя версия — на странице [Releases](../../releases/latest):
`Hutred-Setup.exe` (Windows), `Hutred.apk` (Android), `Hutred.ipa` (iPhone, через SideStore/iloader).

## Сборка

```
flutter pub get
flutter run
```

Ключи облака передаются при сборке (`--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_KEY=…`) и в репозитории не хранятся.

Проект для личного использования.
