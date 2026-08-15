import 'package:shared_preferences/shared_preferences.dart';

/// 轻量设置:问候语等(本地持久化,重启不丢)
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const String _kGreeting = 'greeting';

  Future<String> greeting() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kGreeting) ?? '嗨,同学';
  }

  Future<void> setGreeting(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kGreeting, value);
  }
}
