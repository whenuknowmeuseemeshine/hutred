import '../config.dart';

/// Облачный ретранслятор Hutred (функция `spotify` в Supabase): через него
/// ходим к Spotify и ИИ (Groq), если напрямую они не пускают (например, из России).
class CloudRelay {
  static bool get available => HutredConfig.cloudEnabled;

  static Uri wrap(Uri target) => Uri.parse('${HutredConfig.supabaseUrl}/functions/v1/spotify')
      .replace(queryParameters: {'u': target.toString()});

  /// Заголовки для запроса через ретранслятор: ключ облака — свой,
  /// а ключ сервиса передаём отдельным заголовком.
  static Map<String, String> headers(Map<String, String> original) {
    final out = Map<String, String>.of(original);
    final auth = out.remove('Authorization') ?? out.remove('authorization');
    out['apikey'] = HutredConfig.supabaseAnonKey;
    if (auth != null) out['x-spotify-auth'] = auth;
    return out;
  }
}
