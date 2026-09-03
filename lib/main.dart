import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:chronos/features/shell/pages/splash_page.dart';
import 'package:chronos/core/services/ai_provider.dart';
import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/services/backup_service.dart';
import 'package:chronos/core/services/key_store.dart';
import 'package:chronos/core/services/notification_service.dart';
import 'package:chronos/core/services/settings_service.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/widgets/overlay_toast.dart';

/// 全局根导航 Key:供全局错误兜底随时取得界面上下文以弹出提示。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 安装全局错误兜底。
///
/// 把「未捕获异常」与「Flutter 框架错误」统一接住:记入 [AppLog] 可回溯,
/// 并通过底部提示条给用户一句话反馈,避免异常发生时**无反馈的白屏/卡死**。
/// - 异步/事件回调里未捕获的错误经 [PlatformDispatcher.onError] 回到这里,
///   返回 `true` 表示已处理,应用不会因此被终止;
/// - 框架构建/布局错误经 [FlutterError.onError] 回到这里,同时保留
///   [FlutterError.presentError],让 debug 控制台仍能看到现场。
/// 提示条做节流(1.5s),防止循环报错刷屏;整体 try/finally 防二次进入。
void _installGlobalErrorHandlers() {
  bool reporting = false;
  DateTime lastToast = DateTime.fromMillisecondsSinceEpoch(0);

  void report(String what) {
    if (reporting) return;
    reporting = true;
    try {
      AppLog.instance.e(what);
      final now = DateTime.now();
      if (now.difference(lastToast).inMilliseconds < 1500) return;
      lastToast = now;
      // 等当前帧渲染完再弹,避免在构建/布局出错时触碰 Overlay。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = appNavigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        try {
          OverlayToast.instance.show(ctx, message: '遇到了一点问题,已记入日志');
        } catch (_) {}
      });
    } finally {
      reporting = false;
    }
  }

  FlutterError.onError = (details) {
    report('框架错误:${details.exceptionAsString()}');
    try {
      FlutterError.presentError(details);
    } catch (_) {}
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    report('未捕获异常:$error\n$stack');
    return true;
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installGlobalErrorHandlers();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // 启动前载入视觉设置(主题模式 / 色板 / 背景图),避免首帧闪烁。
  await SettingsService.instance.loadVisualSettings();
  AppLog.instance.init();
  // 本地通知(后台生成完成通知 + 前台服务渠道)。
  await NotificationService.instance.init();
  // 旧版单中转站配置 → 提供商结构迁移(幂等)。
  await AiProviders.migrateLegacyIfNeeded();
  AppLog.instance.i('App 启动,主题模式 ${SettingsService.instance.themeMode.value},'
      '色板 ${SettingsService.instance.palette.value}');
  // 配置摘要(只记布尔,不含任何密钥):排障第一眼就知道哪些服务已配置。
  AppLog.instance.i('API 配置摘要:${await _configSummary()}');
  // 自动备份(可选,默认关):距上次备份超过 7 天时静默导出一次。
  _maybeAutoBackup();
  runApp(const StudentWorkbenchApp());
}

/// 自动备份:开启且距上次备份 ≥7 天时,延迟数秒后台静默导出一次。
Future<void> _maybeAutoBackup() async {
  try {
    if (!await SettingsService.instance.isAutoBackupEnabled()) return;
    final last = await SettingsService.instance.lastBackupAt();
    if (last != null) {
      final t = DateTime.tryParse(last);
      if (t != null && DateTime.now().difference(t).inDays < 7) return;
    }
    // 延迟执行,避免与启动加载抢资源。
    await Future<void>.delayed(const Duration(seconds: 8));
    final path = await BackupService.instance.exportZip();
    await SettingsService.instance.markBackupExported(DateTime.now());
    AppLog.instance.i('自动备份完成:$path');
  } catch (e) {
    AppLog.instance.e('自动备份失败:$e');
  }
}

/// 各联网服务是否已配置的布尔摘要(不含密钥本身)。
/// 用户反馈「配置完不回复」时,先看这一行就知道是不是缺配置。
Future<String> _configSummary() async {
  final s = KeyStore.instance;
  final buf = StringBuffer();
  buf.write('聊天服务:${await AiProviders.isChatConfigured()}');
  buf.write(', 快速模型:${(await AiProviders.fastModelRef()).isNotEmpty}');
  buf.write(', OCR模型:${(await AiProviders.ocrModelRef()).isNotEmpty}');
  buf.write(', 搜索Tavily:${(await s.get(KeyStore.tavilyApiKey)).isNotEmpty}');
  buf.write(', 语音:${(await s.get(KeyStore.elevenApiKey)).isNotEmpty && (await s.get(KeyStore.elevenVoiceId)).isNotEmpty}');
  buf.write(', 天气:${(await s.get(KeyStore.weatherApiKey)).isNotEmpty}');
  buf.write(', 外置记忆:${(await s.get(KeyStore.nocturneUrl)).isNotEmpty && (await s.get(KeyStore.nocturneToken)).isNotEmpty}');
  return buf.toString();
}

class StudentWorkbenchApp extends StatelessWidget {
  const StudentWorkbenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 监听主题模式 / 色板 / 背景图,任一变化即重建整个 MaterialApp。
    return ListenableBuilder(
      listenable: Listenable.merge([
        SettingsService.instance.themeMode,
        SettingsService.instance.palette,
        SettingsService.instance.backgroundEnabled,
        SettingsService.instance.backgroundOpacity,
        SettingsService.instance.backgroundBlur,
        SettingsService.instance.backgroundPath,
      ]),
      builder: (context, _) {
        return MaterialApp(
          title: 'Chronos',
          debugShowCheckedModeBanner: false,
          navigatorKey: appNavigatorKey,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: SettingsService.instance.themeMode.value,
          // 主题切换动画设为 0:Theme.of 的过渡默认有 ~200ms 渐变,而 AppColors
          // 运行时取值是瞬时翻转的,两者不一致会让部分模块看起来「慢半拍」。
          // 取消渐变后所有模块同步瞬时切换,消除刷新延迟观感。
          themeAnimationDuration: Duration.zero,
          // 每帧根据真正生效的主题亮度同步 AppColors 的运行时取值,
          // 保证「跟随系统」下 AppColors.* 与实际显示一致;
          // 启用背景图时,在 Navigator 之下垫一层全局背景图。
          builder: (context, child) {
            syncAppBrightness(Theme.of(context).brightness);
            final SettingsService s = SettingsService.instance;
            final bgPath = s.backgroundPath.value;
            final bgOn = s.backgroundEnabled.value && bgPath.isNotEmpty;
            // 全局字号阶梯缩放:大号调小、正文略小、最小字号不变。
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const _StepTextScaler()),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 兜底底色:任何情况下窗口背景都是主题色,
                  // 杜绝「透明脚手架 + 背景图未渲染 → 黑屏」。
                  ColoredBox(
                    color: AppColors.background,
                    child: const SizedBox.expand(),
                  ),
                  // 背景图固定在最底层(所有子页面共用,不随页面切换重新加载):
                  // RepaintBoundary 隔离重绘,透明度/模糊度/路径变化才重绘。
                  if (bgOn)
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: _buildBackground(s, bgPath),
                      ),
                    ),
                  child ?? const SizedBox.shrink(),
                ],
              ),
            );
          },
          home: const SplashPage(),
        );
      },
    );
  }
}

/// 构建背景图层:透明度 + 高斯模糊。
/// 模糊度 > 0 时套 [ImageFiltered](ImageFilter.blur);模糊度为 0 时不套,
/// 避免无谓的 GPU 模糊开销。图片本身走 FileImage 缓存,不重复解码。
Widget _buildBackground(SettingsService s, String bgPath) {
  final blur = s.backgroundBlur.value.clamp(0.0, 30.0);
  Widget img = Opacity(
    opacity: s.backgroundOpacity.value.clamp(0.1, 1.0),
    child: Image.file(
      File(bgPath),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    ),
  );
  if (blur > 0.5) {
    img = ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: img,
    );
  }
  return img;
}

/// 全局字号阶梯缩放(用户要求:最大字号调小、整体略小、最小字号不变):
/// - ≥18px 的大号(计时器/启动页/金额/标题) ×0.85 明显调小;
/// - 13~18px 正文按线性过渡(13 → ×1.0 递减到 18 → ×0.85)整体略小;
/// - ≤13px 的最小辅助字号保持不变。
/// 返回**缩放后的字号**;分段线性保证单调递增,不会「大字比小字还小」。
/// 顶层公开函数,便于单测覆盖([_StepTextScaler] 直接调用)。
double stepTextScale(double fontSize) {
  if (fontSize <= 13) return fontSize;
  if (fontSize >= 18) return fontSize * 0.85;
  return fontSize * (1.0 - (fontSize - 13) * 0.03);
}

class _StepTextScaler extends TextScaler {
  const _StepTextScaler();

  @override
  double scale(double fontSize) => stepTextScale(fontSize);

  @override
  double get textScaleFactor => 1.0;

  @override
  TextScaler clamp({double? minScaleFactor, double? maxScaleFactor}) => this;
}
