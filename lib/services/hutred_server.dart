import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Функции сервера Hutred (supabase/functions/hutred): вход по логину,
/// токен Spotify и ИИ. Ключи админа остаются на сервере.
class HutredServer {
  HutredServer._();

  static Uri fn(String path) =>
      Uri.parse('${HutredConfig.supabaseUrl}/functions/v1/hutred/$path');

  /// Токен вошедшего пользователя или null.
  static String? get userToken {
    if (!HutredConfig.cloudEnabled) return null;
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> headers({bool json = false}) {
    final t = userToken;
    return {
      'apikey': HutredConfig.supabaseAnonKey,
      if (t != null) 'Authorization': 'Bearer $t',
      if (json) 'Content-Type': 'application/json',
    };
  }

  /// Текст ошибки из ответа функции.
  static String errorOf(String body, int code) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is String) return j['error'] as String;
    } catch (_) {}
    if (code == 401) return 'Войди в аккаунт';
    if (code == 429) return 'Слишком часто — подожди немного';
    return 'Сервер Hutred ответил $code';
  }
}
