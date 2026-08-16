import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/splash_page.dart';
import 'services/settings_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // 启动前载入主题模式,避免首帧闪烁。
  await SettingsService.instance.loadThemeMode();
  runApp(const StudentWorkbenchApp());
}

class StudentWorkbenchApp extends StatelessWidget {
  const StudentWorkbenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 监听主题模式,切换时即时重建整个 MaterialApp。
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsService.instance.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Chronos',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          // 每帧根据真正生效的主题亮度同步 AppColors 的运行时取值,
          // 保证「跟随系统」下 AppColors.* 与实际显示一致。
          builder: (context, child) {
            syncAppBrightness(Theme.of(context).brightness);
            return child ?? const SizedBox.shrink();
          },
          home: const SplashPage(),
        );
      },
    );
  }
}
