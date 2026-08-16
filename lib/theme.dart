import 'package:flutter/material.dart';

/// 当前是否深色:由 [MaterialApp.builder] 在每帧根据解析后的主题写入,
/// [AppColors] 的各语义色 getter 据此返回浅色/深色取值。
/// 说明:因取值需随主题运行时切换,[AppColors] 字段为 getter(非 const),
/// 故引用处不能再放在 const 上下文里。
bool _isDark = false;

/// 供 MaterialApp.builder 同步当前亮度(浅/深)。
void syncAppBrightness(Brightness b) => _isDark = b == Brightness.dark;

bool get isDarkMode => _isDark;

/// 全局配色 —— 浅蓝色系(浅色)/ 同色系低亮度(深色)。
/// 语义名不变,取值随亮度切换。
class AppColors {
  static Color get primary =>
      _isDark ? const Color(0xFF4FC3F7) : const Color(0xFF29B6F6); // 主色
  static Color get primaryDark =>
      _isDark ? const Color(0xFF81D4FA) : const Color(0xFF0288D1);
  static Color get primaryLight =>
      _isDark ? const Color(0xFF1E3A4C) : const Color(0xFFB3E5FC);
  static Color get background =>
      _isDark ? const Color(0xFF0F1620) : const Color(0xFFF1F8FE); // 页面背景
  static Color get card =>
      _isDark ? const Color(0xFF1A2532) : Colors.white; // 卡片面
  static Color get textMain =>
      _isDark ? const Color(0xFFE7EEF5) : const Color(0xFF1F2D3D);
  static Color get textSub =>
      _isDark ? const Color(0xFF93A6B8) : const Color(0xFF7B8C9D);
  static Color get line =>
      _isDark ? const Color(0xFF2B3947) : const Color(0xFFD6EAF9);
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    // 构建 ThemeData 前先同步亮度,确保下方 AppColors getter 取到正确取值。
    syncAppBrightness(brightness);

    final Color bg = dark ? const Color(0xFF0F1620) : const Color(0xFFF1F8FE);
    final Color surface = dark ? const Color(0xFF1A2532) : Colors.white;
    final Color primary =
        dark ? const Color(0xFF4FC3F7) : const Color(0xFF29B6F6);
    final Color primaryDark =
        dark ? const Color(0xFF81D4FA) : const Color(0xFF0288D1);
    final Color textMain =
        dark ? const Color(0xFFE7EEF5) : const Color(0xFF1F2D3D);
    final Color textSub =
        dark ? const Color(0xFF93A6B8) : const Color(0xFF7B8C9D);
    final Color line = dark ? const Color(0xFF2B3947) : const Color(0xFFD6EAF9);

    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      secondary: primaryDark,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
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
          foregroundColor: dark ? const Color(0xFF07222E) : Colors.white,
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
          borderSide: BorderSide(color: primary, width: 1.6),
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
