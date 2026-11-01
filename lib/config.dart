/// Настройки облака Hutred (Supabase).
/// В репозитории ключей нет: при облачной сборке они подставляются из
/// секретов GitHub (SUPABASE_URL и SUPABASE_KEY) через --dart-define.
/// На своём компьютере можно вписать значения прямо сюда (этот файл у тебя
/// локально и так заполнен) или запускать с --dart-define.
/// Пока строки пустые, приложение работает без входа: медиатека только на устройстве.
class HutredConfig {
  /// Project URL, например https://abcdxyz.supabase.co
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Publishable-ключ проекта (его можно встраивать в приложение).
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_KEY');

  static bool get cloudEnabled =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
