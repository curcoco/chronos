import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 轻量设置:昵称(必填,首次随机生成)、问候语、主题模式等(本地持久化,重启不丢)
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const String _kNickname = 'nickname';
  static const String _kNicknameSet = 'nickname_set';
  static const String _kWeatherCity = 'weather_city';
  static const String _kGreeting = 'greeting';
  static const String _kThemeMode = 'theme_mode';
  static const String _kOnboardingDone = 'onboarding_done';
  static const String _kLastBackupAt = 'last_backup_at';

  /// 全局主题模式通知源:切换后 MaterialApp 监听并即时重建(无需重启)。
  final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  // 随机昵称池:两字形容词 + 的 + 名词
  static const List<String> _adjectives = [
    '开心', '元气', '认真', '温柔', '勇敢', '好奇',
    '安静', '活泼', '机灵', '淡定', '早起', '爱笑',
  ];
  static const List<String> _nouns = [
    '鲸鱼', '云朵', '星星', '月亮', '小猫', '狐狸',
    '松果', '竹笛', '纸鸢', '海浪', '柠檬', '布丁',
  ];

  /// 昵称:首次访问自动随机生成并保存(默认昵称,不代表用户设定)
  Future<String> nickname() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kNickname);
    if (saved != null && saved.trim().isNotEmpty) return saved;
    final name = _randomNickname();
    await prefs.setString(_kNickname, name);
    return name;
  }

  /// 昵称是否为用户主动设定(设定后才在欢迎界面显示昵称)
  Future<bool> isNicknameSet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kNicknameSet) ?? false;
  }

  Future<void> setNickname(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNickname, value.trim());
    await prefs.setBool(_kNicknameSet, true);
  }

  static String _randomNickname() =>
      '${_adjectives[Random().nextInt(_adjectives.length)]}'
      '的${_nouns[Random().nextInt(_nouns.length)]}';

  /// 天气城市(用户应用内选择;为空时回退到配置文件)
  Future<String> weatherCity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kWeatherCity) ?? '';
  }

  Future<void> setWeatherCity(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWeatherCity, value.trim());
  }

  Future<String> greeting() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kGreeting) ?? '嗨,同学';
  }

  Future<void> setGreeting(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kGreeting, value);
  }

  /// 主题模式:启动时读取本地持久化值并写入 [themeMode](供 MaterialApp 初始化)。
  Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = _decodeThemeMode(prefs.getString(_kThemeMode));
    themeMode.value = mode;
    return mode;
  }

  /// 切换主题模式:即时更新 [themeMode](界面立即重建)并持久化。
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, _encodeThemeMode(mode));
  }

  static ThemeMode _decodeThemeMode(String? v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _encodeThemeMode(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  /// 首次引导卡是否已展示(用户关闭后不再出现)。
  Future<bool> isOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingDone) ?? false;
  }

  Future<void> setOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingDone, true);
  }

  /// 上次成功导出备份的时间(ISO 8601);从未导出为 null。
  Future<String?> lastBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastBackupAt);
  }

  Future<void> markBackupExported(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastBackupAt, time.toIso8601String());
  }
}
