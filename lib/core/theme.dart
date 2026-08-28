import 'package:flutter/material.dart';

import 'package:chronos/core/services/settings_service.dart';

/// 当前是否深色:由 [MaterialApp.builder] 在每帧根据解析后的主题写入,
/// [AppColors] 的各语义色 getter 据此返回浅色/深色取值。
/// 说明:因取值需随主题运行时切换,[AppColors] 字段为 getter(非 const),
/// 故引用处不能再放在 const 上下文里。
bool _isDark = false;

/// 供 MaterialApp.builder 同步当前亮度(浅/深)。
void syncAppBrightness(Brightness b) => _isDark = b == Brightness.dark;

bool get isDarkMode => _isDark;

/// 一套主题配色(浅色):8 个语义色 + 按钮前景色。
/// 深色模式全局共用一套低亮度同色系,不随主题色切换(本批 6 套均为浅色主题)。
class AppPalette {
  final Color primary;
  final Color primaryDark;
  final Color primaryLight;
  final Color background;
  final Color card;
  final Color textMain;
  final Color textSub;
  final Color line;

  /// FilledButton 等主按钮上的文字颜色(黄色系需深色文字保证对比度)。
  final Color onPrimary;

  const AppPalette({
    required this.primary,
    required this.primaryDark,
    required this.primaryLight,
    required this.background,
    required this.card,
    required this.textMain,
    required this.textSub,
    required this.line,
    required this.onPrimary,
  });
}

/// 主题色板注册表:id → 浅色板。默认蓝色(历史配色,老用户无感切换)。
const Map<String, AppPalette> kAppPalettes = {
  // 蓝色(默认,保持历史观感)
  'blue': AppPalette(
    primary: Color(0xFF29B6F6),
    primaryDark: Color(0xFF0288D1),
    primaryLight: Color(0xFFB3E5FC),
    background: Color(0xFFF1F8FE),
    card: Colors.white,
    textMain: Color(0xFF1F2D3D),
    textSub: Color(0xFF7B8C9D),
    line: Color(0xFFD6EAF9),
    onPrimary: Colors.white,
  ),
  // 粉色
  'pink': AppPalette(
    primary: Color(0xFFF06292),
    primaryDark: Color(0xFFC2185B),
    primaryLight: Color(0xFFF8BBD0),
    background: Color(0xFFFDF2F6),
    card: Colors.white,
    textMain: Color(0xFF3B2230),
    textSub: Color(0xFF9C6B7E),
    line: Color(0xFFF6DCE7),
    onPrimary: Colors.white,
  ),
  // 绿色
  'green': AppPalette(
    primary: Color(0xFF66BB6A),
    primaryDark: Color(0xFF2E7D32),
    primaryLight: Color(0xFFC8E6C9),
    background: Color(0xFFF2F9F1),
    card: Colors.white,
    textMain: Color(0xFF22332A),
    textSub: Color(0xFF6E8A74),
    line: Color(0xFFDCEEDD),
    onPrimary: Colors.white,
  ),
  // 黄色(按钮用深色文字保证可读性)
  'yellow': AppPalette(
    primary: Color(0xFFF9A825),
    primaryDark: Color(0xFFEF6C00),
    primaryLight: Color(0xFFFFE082),
    background: Color(0xFFFFFBF0),
    card: Colors.white,
    textMain: Color(0xFF3A3120),
    textSub: Color(0xFF8C7B5E),
    line: Color(0xFFF3E8CE),
    onPrimary: Color(0xFF3E2723),
  ),
  // 黑色(深灰,适应人眼不刺眼:浅灰纸面 + 深灰蓝文字)
  'black': AppPalette(
    primary: Color(0xFF546E7A),
    primaryDark: Color(0xFF37474F),
    primaryLight: Color(0xFFB0BEC5),
    background: Color(0xFFF4F5F7),
    card: Colors.white,
    textMain: Color(0xFF2B2F36),
    textSub: Color(0xFF6B7280),
    line: Color(0xFFE3E5E8),
    onPrimary: Colors.white,
  ),
  // 白色(柔和不刺眼:近白纸面 + 蓝灰中性文字)
  'white': AppPalette(
    primary: Color(0xFF78909C),
    primaryDark: Color(0xFF546E7A),
    primaryLight: Color(0xFFCFD8DC),
    background: Color(0xFFFDFDFD),
    card: Colors.white,
    textMain: Color(0xFF33373D),
    textSub: Color(0xFF7A8089),
    line: Color(0xFFECEEF0),
    onPrimary: Colors.white,
  ),
};

/// 当前选中的浅色板(跟随设置即时切换)。
AppPalette get _palette =>
    kAppPalettes[SettingsService.instance.palette.value] ??
    kAppPalettes['blue']!;

/// 深色模式统一使用的低亮度同色系(不随主题色切换)。
class _DarkColors {
  static const primary = Color(0xFF4FC3F7);
  static const primaryDark = Color(0xFF81D4FA);
  static const primaryLight = Color(0xFF1E3A4C);
  static const background = Color(0xFF0F1620);
  static const card = Color(0xFF1A2532);
  static const textMain = Color(0xFFE7EEF5);
  static const textSub = Color(0xFF93A6B8);
  static const line = Color(0xFF2B3947);
  static const onPrimary = Color(0xFF07222E);
}

/// 全局配色 —— 语义名不变,取值随「当前色板 × 亮度」切换。
class AppColors {
  static Color get primary => _isDark ? _DarkColors.primary : _palette.primary;
  static Color get primaryDark =>
      _isDark ? _DarkColors.primaryDark : _palette.primaryDark;
  static Color get primaryLight =>
      _isDark ? _DarkColors.primaryLight : _palette.primaryLight;
  /// 浅淡主色:大面积填充(聊天气泡 / 渐变卡末端)用的柔和浅色。
  /// 蓝/粉/绿/黄:在色板浅色(primaryLight,如天蓝 B3E5FC / 樱花粉 F8BBD0)
  /// 基础上再往白色方向浅一档(天蓝/樱花粉那档,用户确认满意);
  /// 黑/白两套「经典色」保持不变(直接用主色,不做浅化);
  /// 深色模式沿用 primary(深色下主色本就偏亮,不另做浅色)。
  static Color get primarySoft {
    if (_isDark) return _DarkColors.primary;
    final p = SettingsService.instance.palette.value;
    if (p == 'black' || p == 'white') return _palette.primary;
    return Color.lerp(_palette.primaryLight, Colors.white, 0.2)!;
  }

  /// 浅色底上的前景色(文字/图标):
  /// 蓝/粉/绿/黄浅色底 → 深色文字(primaryDark);
  /// 黑/白经典深灰底 → 白色文字(onPrimary,经典配法);
  /// 深色模式 → 深色 onPrimary。
  static Color get onPrimarySoft {
    if (_isDark) return _DarkColors.onPrimary;
    final p = SettingsService.instance.palette.value;
    return (p == 'black' || p == 'white')
        ? _palette.onPrimary
        : _palette.primaryDark;
  }
  static Color get background =>
      _isDark ? _DarkColors.background : _palette.background;
  static Color get card => _isDark ? _DarkColors.card : _palette.card;
  static Color get textMain =>
      _isDark ? _DarkColors.textMain : _palette.textMain;
  static Color get textSub =>
      _isDark ? _DarkColors.textSub : _palette.textSub;
  static Color get line => _isDark ? _DarkColors.line : _palette.line;
  static Color get onPrimary =>
      _isDark ? _DarkColors.onPrimary : _palette.onPrimary;
}

class AppTheme {
  /// ThemeData 缓存:同一「亮度 × 色板 × 背景图开关」复用同一实例,
  /// 切换色板/背景图时只有首次构建新 ThemeData,减少重复计算与重建开销。
  static final Map<String, ThemeData> _cache = {};

  static ThemeData light() => _get(Brightness.light);
  static ThemeData dark() => _get(Brightness.dark);

  static ThemeData _get(Brightness brightness) {
    final SettingsService settings = SettingsService.instance;
    final bool bgImageOn = settings.backgroundEnabled.value &&
        settings.backgroundPath.value.isNotEmpty;
    final key = '${brightness == Brightness.dark}:'
        '${settings.palette.value}:$bgImageOn';
    return _cache.putIfAbsent(key, () => _build(brightness));
  }

  static ThemeData _build(Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    // 构建 ThemeData 前先同步亮度,确保下方 AppColors getter 取到正确取值。
    syncAppBrightness(brightness);

    final Color bg = dark ? _DarkColors.background : _palette.background;
    final Color surface = dark ? _DarkColors.card : _palette.card;
    final Color primary = dark ? _DarkColors.primary : _palette.primary;
    final Color primaryDark =
        dark ? _DarkColors.primaryDark : _palette.primaryDark;
    final Color textMain =
        dark ? _DarkColors.textMain : _palette.textMain;
    final Color textSub = dark ? _DarkColors.textSub : _palette.textSub;
    final Color line = dark ? _DarkColors.line : _palette.line;

    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      secondary: primaryDark,
      surface: surface,
    );

    // 启用背景图且存在图片文件时,页面背景透明,让全局背景图透出
    // (与 main.dart builder 的判断保持一致;无图时保持不透明,避免黑屏)。
    final SettingsService settings = SettingsService.instance;
    final bool bgImageOn = settings.backgroundEnabled.value &&
        settings.backgroundPath.value.isNotEmpty;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bgImageOn ? Colors.transparent : bg,
      appBarTheme: AppBarTheme(
        // 背景图启用时顶栏半透明:背景图透出、标题仍清晰,滚动内容
        // 从顶栏下方滚过时被半透明层隔开(全透明会裸透重叠)。
        backgroundColor: bgImageOn ? surface.withValues(alpha: 0.62) : bg,
        foregroundColor: textMain,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textMain,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor:
              dark ? _DarkColors.onPrimary : _palette.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: textSub.withValues(alpha: 0.8)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          // 聚焦边框用中性灰蓝而非主题色:避免「彩线框」抢眼,
          // 契合浅淡极简的视觉基调(用户要求)。
          borderSide:
              BorderSide(color: textSub.withValues(alpha: 0.55), width: 1.4),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      dividerTheme: DividerThemeData(
          color: dark ? const Color(0xFF24303D) : const Color(0xFFEAF3FA)),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            dark ? const Color(0xFF243342) : const Color(0xFF2B3A4D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primaryDark,
        unselectedLabelColor: textSub,
        indicatorColor: primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle:
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    );
  }
}
