import '../config.dart';
import 'relay.dart';

/// Облачный ретранслятор Hutred: свой сервер-посредник (если админ его
/// настроил) или функция `spotify` в Supabase. Через него ходим к Spotify
/// и ИИ (Groq), если напрямую они не пускают (например, из России).
class CloudRelay {
  static bool get available => HutredRelay.available || HutredConfig.cloudEnabled;

  static Uri wrap(Uri target) => HutredRelay.available
      ? HutredRelay.wrap(target)
      : Uri.parse('${HutredConfig.supabaseUrl}/functions/v1/spotify')
          .replace(queryParameters: {'u': target.toString()});

  /// Заголовки для запроса через ретранслятор: ключ облака — свой,
  /// а ключ сервиса передаём отдельным заголовком.
  static Map<String, String> headers(Map<String, String> original) {
    if (HutredRelay.available) return HutredRelay.headers(original);
    final out = Map<String, String>.of(original);
    final auth = out.remove('Authorization') ?? out.remove('authorization');
    out['apikey'] = HutredConfig.supabaseAnonKey;
    if (auth != null) out['x-spotify-auth'] = auth;
    return out;
  }
}
