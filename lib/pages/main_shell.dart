import 'package:flutter/material.dart';

import '../routes.dart';
import '../theme.dart';
import '../widgets/app_drawer.dart';
import '../widgets/bottom_nav.dart';
import 'chat_page.dart';
import 'coin_center_page.dart';
import 'diary_page.dart';
import 'home_page.dart';
import 'knowledge_page.dart';
import 'ledger_page.dart';
import 'life_page.dart';
import 'plan_page.dart';
import 'quick_note_page.dart';

/// 主框架:底部 5 Tab 导航(首页/计划/+ /知识/生活)+ 左侧抽屉(设置 / 版本更新)。
/// 侧边栏见 [AppDrawer],底部导航见 [BottomNav],快捷菜单在本文件内。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  /// 中间「+」快捷菜单:一处直达常用功能,减少层层点击。
  void _openQuickMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        Widget item(IconData icon, String label, String sub, VoidCallback go) {
          return ListTile(
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primaryLight.withValues(alpha: 0.5),
              child: Icon(icon, size: 20, color: AppColors.primaryDark),
            ),
            title: Text(label,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            subtitle: Text(sub,
                style: TextStyle(fontSize: 12, color: AppColors.textSub)),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              go();
            },
          );
        }

        void push(Widget page, {bool dialog = false}) {
          AppRoutes.push(context, page, dialog: dialog);
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                  child: Row(
                    children: [
                      Text('快捷菜单',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMain)),
                    ],
                  ),
                ),
                item(Icons.edit_note_rounded, '灵感速记', '随手记录一条灵感',
                    () => push(const QuickNotePage(), dialog: true)),
                item(Icons.smart_toy_rounded, 'AI 对话', '和掌柜聊聊',
                    () => push(const ChatPage())),
                item(Icons.menu_book_rounded, '写日记', '记录今天的心情',
                    () => push(const DiaryPage())),
                item(Icons.account_balance_wallet_rounded, '记一笔', '快速记账',
                    () => push(const LedgerPage())),
                item(Icons.monetization_on_rounded, '金币中心', '查看金币与心愿',
                    () => push(const CoinCenterPage())),
              ],
            ),
          ),
        );
      },
    );
  }

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
        2 => const KnowledgePage(),
        _ => const LifePage(),
      },
      bottomNavigationBar: BottomNav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
        onPlus: _openQuickMenu,
      ),
    );
  }
}
