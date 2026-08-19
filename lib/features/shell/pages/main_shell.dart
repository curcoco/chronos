import 'package:flutter/material.dart';

import 'package:student_workbench/features/shell/widgets/app_drawer.dart';
import 'package:student_workbench/features/shell/widgets/bottom_nav.dart';
import 'package:student_workbench/features/chat/pages/chat_page.dart';
import 'package:student_workbench/features/home/pages/home_page.dart';
import 'package:student_workbench/features/ledger/pages/ledger_page.dart';
import 'package:student_workbench/features/notes/pages/quick_note_page.dart';
import 'package:student_workbench/features/tasks/pages/plan_page.dart';

/// 主框架:底部 5 Tab 导航(首页 / 计划 / 灵感速记 / 记账 / 闲话铺)。
/// 侧边栏见 [AppDrawer],底部导航见 [BottomNav];
/// 其它模块入口(英文/健康/复盘/日记/金币中心等)收进侧边栏「功能模块」区。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 右滑开侧边栏:热区放宽到屏幕左侧约 160px,不必贴着边缘
      drawerEdgeDragWidth: 160,
      drawer: AppDrawer(
        currentIndex: _index,
        onSelectTab: (i) {
          setState(() => _index = i);
          Navigator.of(context).pop(); // 关闭抽屉
        },
      ),
      body: switch (_index) {
        0 => HomePage(onGoPlan: () => setState(() => _index = 1)),
        1 => const PlanPage(),
        2 => const QuickNotePage(),
        3 => const LedgerPage(),
        _ => const ChatPage(),
      },
      bottomNavigationBar: BottomNav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
