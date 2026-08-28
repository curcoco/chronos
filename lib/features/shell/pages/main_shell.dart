import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chronos/routes.dart';
import 'package:chronos/core/services/ai_provider.dart';
import 'package:chronos/core/widgets/confirm_dialog.dart';
import 'package:chronos/features/shell/widgets/app_drawer.dart';
import 'package:chronos/features/shell/widgets/bottom_nav.dart';
import 'package:chronos/features/chat/pages/chat_page.dart';
import 'package:chronos/features/home/pages/home_page.dart';
import 'package:chronos/features/ledger/pages/ledger_page.dart';
import 'package:chronos/features/notes/pages/quick_note_page.dart';
import 'package:chronos/features/settings/pages/provider_list_page.dart';
import 'package:chronos/features/tasks/pages/plan_page.dart';

/// 主框架:底部 5 Tab 导航(首页 / 计划 / 灵感速记 / 记账 / 闲话铺)。
/// 侧边栏见 [AppDrawer],底部导航见 [BottomNav];
/// 其它模块入口(英文/健康/复盘/日记/金币中心等)收进侧边栏「功能模块」区。
///
/// 闲话铺为「启动器」Tab:点击后以全屏路由进入聊天页(不显示底部导航、
/// 直达最近会话),返回键回到本框架。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const String _kConfigGuideDone = 'config_guide_done_v1';

  @override
  void initState() {
    super.initState();
    _maybeShowConfigGuide();
  }

  /// 首次使用引导:全新安装且未配置聊天服务时,提示配置中转站的步骤。
  /// 只弹一次(prefs 标记),已配置(含旧版迁移)不打扰。
  Future<void> _maybeShowConfigGuide() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    if (await AiProviders.isChatConfigured()) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kConfigGuideDone) ?? false) return;
    await prefs.setBool(_kConfigGuideDone, true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开始使用 Chronos'),
        content: const Text(
          '计划 / 速记 / 日记 / 记账等离线功能开箱即用。\n\n'
          'AI 聊天等联网功能需要先配置模型服务:\n'
          '① 设置 → 模型与服务 → 提供商,添加你的中转站(地址 + API Key)\n'
          '② 在「模型」页选择聊天模型\n\n'
          '密钥只存本机,不会上传。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              AppRoutes.push(context, const ProviderListPage());
            },
            child: const Text('去配置'),
          ),
        ],
      ),
    );
  }

  void _onTapTab(int i) {
    if (i == 4) {
      // 闲话铺:全屏进入,隐藏底部导航(见 ChatPage 注释)。
      AppRoutes.push(context, const ChatPage());
      return;
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    // 主框架为导航栈根:按返回键先弹确认,避免误触直接退出应用。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final ok = await showConfirmDialog(
          context,
          title: '退出应用?',
          message: '确定要退出 Chronos 吗?',
          confirmText: '退出',
          destructive: true,
        );
        if (ok == true && mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        // 右滑开侧边栏:热区放宽到屏幕左侧约 160px,不必贴着边缘
        drawerEdgeDragWidth: 160,
        drawer: const AppDrawer(),
        body: switch (_index) {
          1 => const PlanPage(),
          2 => const QuickNotePage(),
          3 => const LedgerPage(),
          _ => HomePage(onGoPlan: () => setState(() => _index = 1)),
        },
        bottomNavigationBar: BottomNav(
          index: _index,
          onTap: _onTapTab,
        ),
      ),
    );
  }
}
