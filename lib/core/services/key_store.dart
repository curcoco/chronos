import 'package:shared_preferences/shared_preferences.dart';

/// API 密钥与连接配置:应用内设置,存本地(SharedPreferences)。
/// 源码与 APK 常量里不再有任何密钥明文;首次使用在「系统设置 → API 配置」填写。
class KeyStore {
  KeyStore._();
  static final KeyStore instance = KeyStore._();

  static const String llmBaseUrl = 'llm_base_url';
  static const String llmApiKey = 'llm_api_key';
  static const String llmModel = 'llm_model';
  static const String llmFastModel = 'llm_fast_model';
  static const String elevenApiKey = 'eleven_api_key';
  static const String elevenVoiceId = 'eleven_voice_id';
  static const String weatherApiKey = 'weather_api_key';
  static const String supabaseUrl = 'supabase_url';
  static const String supabaseAnonKey = 'supabase_anon_key';
  static const String nocturneUrl = 'nocturne_url';
  static const String nocturneToken = 'nocturne_token';

  static const List<String> allKeys = [
    llmBaseUrl,
    llmApiKey,
    llmModel,
    llmFastModel,
    elevenApiKey,
    elevenVoiceId,
    weatherApiKey,
    supabaseUrl,
    supabaseAnonKey,
    nocturneUrl,
    nocturneToken,
  ];

  Future<String> get(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('api_$key') ?? '';
  }

  Future<void> set(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_$key', value.trim());
  }
}
