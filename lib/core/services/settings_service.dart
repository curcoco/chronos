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
  static const String _kAvatarPath = 'avatar_path';
  static const String _kPalette = 'theme_palette';
  static const String _kBackgroundEnabled = 'bg_enabled';
  static const String _kBackgroundOpacity = 'bg_opacity';
  static const String _kBackgroundPath = 'bg_path';
  static const String _kBackgroundBlur = 'bg_blur';
  static const String _kBackgroundNotify = 'bg_notify';
  static const String _kAutoBackup = 'auto_backup';
  static const String _kAutoMemory = 'auto_memory';
  static const String _kScreenBudget = 'screen_budget_minutes';

  /// 全局主题模式通知源:切换后 MaterialApp 监听并即时重建(无需重启)。
  final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  /// 主题色板 id(见 core/theme.dart kAppPalettes):切换后即时换肤。
  final ValueNotifier<String> palette = ValueNotifier<String>('blue');

  /// 背景图是否启用(启用后全 App 页面背景透出背景图)。
  final ValueNotifier<bool> backgroundEnabled = ValueNotifier<bool>(false);

  /// 后台生成通知是否启用(闲话铺退后台继续生成 + 完成通知;默认开)。
  final ValueNotifier<bool> backgroundNotify = ValueNotifier<bool>(true);

  /// Auto Memory 是否启用(AI 在对话中自主写/改/删「关于用户的认知档案」;默认开)。
  final ValueNotifier<bool> autoMemory = ValueNotifier<bool>(true);

  /// 每日娱乐时长预算(分钟;防沉迷「屏幕时间」用,超了变红、影响昨日金币奖励)。
  final ValueNotifier<int> screenBudgetMinutes = ValueNotifier<int>(120);

  /// 背景图透明度(0.3 ~ 1.0)。
  final ValueNotifier<double> backgroundOpacity = ValueNotifier<double>(0.85);

  /// 背景图高斯模糊度(0 ~ 30,0 = 不模糊)。
  final ValueNotifier<double> backgroundBlur = ValueNotifier<double>(0);

  /// 背景图本地文件路径(空 = 未设置)。
  final ValueNotifier<String> backgroundPath = ValueNotifier<String>('');

  /// 头像变更通知:侧边栏改头像后自增,首页等监听刷新头像显示。
  final ValueNotifier<int> avatarVersion = ValueNotifier<int>(0);

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

  /// 启动时载入全部视觉设置:主题模式 + 色板 + 背景图(供 MaterialApp 初始化)。
  Future<void> loadVisualSettings() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode.value = _decodeThemeMode(prefs.getString(_kThemeMode));
    palette.value = prefs.getString(_kPalette) ?? 'blue';
    backgroundEnabled.value = prefs.getBool(_kBackgroundEnabled) ?? false;
    backgroundNotify.value =
        prefs.getBool(_kBackgroundNotify) ?? true;
    autoMemory.value = prefs.getBool(_kAutoMemory) ?? true;
    screenBudgetMinutes.value = prefs.getInt(_kScreenBudget) ?? 120;
    backgroundOpacity.value = (prefs.getDouble(_kBackgroundOpacity) ?? 0.85)
        .clamp(0.3, 1.0);
    backgroundPath.value = prefs.getString(_kBackgroundPath) ?? '';
    backgroundBlur.value =
        (prefs.getDouble(_kBackgroundBlur) ?? 0).clamp(0.0, 30.0);
  }

  /// 切换主题色板:即时生效并持久化。
  Future<void> setPalette(String id) async {
    palette.value = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPalette, id);
  }

  /// 背景图开关:即时生效并持久化。
  Future<void> setBackgroundEnabled(bool value) async {
    backgroundEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBackgroundEnabled, value);  }

  /// 后台生成通知开关:即时生效并持久化。
  Future<void> setBackgroundNotify(bool value) async {
    backgroundNotify.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBackgroundNotify, value);  }

  /// Auto Memory 开关:即时生效并持久化。
  Future<void> setAutoMemory(bool value) async {
    autoMemory.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoMemory, value);  }

  /// 每日娱乐预算(分钟,30~300):即时生效并持久化。
  Future<void> setScreenBudgetMinutes(int value) async {
    final v = value.clamp(30, 300);
    screenBudgetMinutes.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kScreenBudget, v);
  }

  /// 背景图透明度(0.3~1.0):即时生效并持久化。
  Future<void> setBackgroundOpacity(double value) async {
    final v = value.clamp(0.3, 1.0);
    backgroundOpacity.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kBackgroundOpacity, v);
  }

  /// 背景图路径(空 = 清除):即时生效并持久化。
  Future<void> setBackgroundPath(String path) async {
    backgroundPath.value = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBackgroundPath, path);
  }

  /// 背景图高斯模糊度(0~30):即时生效并持久化。
  Future<void> setBackgroundBlur(double value) async {
    final v = value.clamp(0.0, 30.0);
    backgroundBlur.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kBackgroundBlur, v);
  }

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

  /// 用户头像图片的本地文件路径(空 = 未设置,显示昵称首字)。
  Future<String> avatarPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAvatarPath) ?? '';
  }

  Future<void> setAvatarPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAvatarPath, path);
    avatarVersion.value++;
  }

  /// 自动备份开关(开启后:启动时距上次备份超过 7 天则静默导出一次)。
  Future<bool> isAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoBackup) ?? false;
  }

  Future<void> setAutoBackupEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoBackup, value);
  }
}
