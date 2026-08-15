import 'package:flutter/material.dart';

import '../services/app_info.dart';
import '../theme.dart';
import 'home_page.dart';
import 'knowledge_page.dart';
import 'life_page.dart';
import 'plan_page.dart';
import 'quick_note_page.dart';
import 'settings_page.dart';

/// 主框架:底部 5 Tab 导航(首页/计划/+ /知识/生活)+ 左侧抽屉(设置 / 版本更新)
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  void _openQuickNote() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const QuickNotePage(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _AppDrawer(
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
      bottomNavigationBar: _BottomNav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
        onPlus: _openQuickNote,
      ),
    );
  }
}

/// 侧边栏:应用信息 + 版本与更新 + 导航快捷 + 系统设置入口
class _AppDrawer extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onSelectTab;

  const _AppDrawer({required this.currentIndex, required this.onSelectTab});

  @override
  State<_AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<_AppDrawer> {
  String _version = '';
  UpdateStatus? _status; // null = 检查中/未检查

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final v = await AppInfo.installedVersion();
    if (!mounted) return;
    setState(() => _version = v);
    await _check();
  }

  Future<void> _check() async {
    setState(() => _status = null);
    final s = await AppInfo.checkUpdate(_version);
    if (!mounted) return;
    setState(() => _status = s);
  }

  void _openSettings() {
    Navigator.of(context).pop(); // 先关抽屉
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 应用信息头部
            Container(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFD6EDFF), Color(0xFFB3E5FC)],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primaryLight, AppColors.primary],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.school_rounded,
                        size: 26, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '学生学习工作台',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textMain,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '计划 · 金币 · 灵感',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSub),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 版本与更新
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: _buildVersionCard(),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 2),
              child: Text(
                '导航',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSub),
              ),
            ),
            _navTile(0, Icons.home_rounded, '首页'),
            _navTile(1, Icons.checklist_rounded, '计划'),
            _navTile(2, Icons.school_rounded, '知识'),
            _navTile(3, Icons.emoji_emotions_rounded, '生活'),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined,
                  size: 22, color: AppColors.textSub),
              title: const Text(
                '系统设置',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain),
              ),
              trailing: const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textSub),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onTap: _openSettings,
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                '纯本地存储,仅更新检查需联网',
                style: TextStyle(fontSize: 11, color: AppColors.textSub),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionCard() {
    final status = _status;
    final checking = status == null;
    final latest = status?.latestVersion ?? '…';
    // 状态配色与文案
    late final Color chipBg;
    late final Color chipFg;
    late final IconData chipIcon;
    late final String chipText;
    if (checking) {
      chipBg = const Color(0xFFE3F0FA);
      chipFg = AppColors.textSub;
      chipIcon = Icons.hourglass_top_rounded;
      chipText = '正在检查更新…';
    } else if (status.updateAvailable) {
      chipBg = const Color(0xFFFFF3E0);
      chipFg = const Color(0xFFE65100);
      chipIcon = Icons.system_update_alt_rounded;
      chipText = '发现新版本 $latest,请下载最新 APK 更新';
    } else if (status.reachable) {
      chipBg = const Color(0xFFE8F5E9);
      chipFg = const Color(0xFF2E7D32);
      chipIcon = Icons.check_circle_rounded;
      chipText = '已是最新版本';
    } else {
      chipBg = const Color(0xFFEEF2F6);
      chipFg = AppColors.textSub;
      chipIcon = Icons.cloud_off_rounded;
      chipText = '无法连接更新服务器,请检查网络';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 18, color: AppColors.primaryDark),
              const SizedBox(width: 8),
              const Text(
                '版本与更新',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain),
              ),
              const Spacer(),
              TextButton(
                onPressed: checking ? null : _check,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('重新检查',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                '当前版本',
                style: TextStyle(fontSize: 13, color: AppColors.textSub),
              ),
              const Spacer(),
              Text(
                _version.isEmpty ? '…' : _version,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                '最新版本',
                style: TextStyle(fontSize: 13, color: AppColors.textSub),
              ),
              const Spacer(),
              Text(
                latest,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(chipIcon, size: 16, color: chipFg),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    chipText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: chipFg,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!checking && status.updateAvailable && status.note != null) ...[
            const SizedBox(height: 8),
            Text(
              '更新说明:${status.note}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSub),
            ),
          ],
        ],
      ),
    );
  }

  Widget _navTile(int index, IconData icon, String label) {
    final selected = widget.currentIndex == index;
    return ListTile(
      leading: Icon(icon,
          size: 22,
          color: selected ? AppColors.primaryDark : AppColors.textSub),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? AppColors.primaryDark : AppColors.textMain,
        ),
      ),
      selected: selected,
      selectedTileColor: AppColors.primaryLight.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: () => widget.onSelectTab(index),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onPlus;

  const _BottomNav({
    required this.index,
    required this.onTap,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1429B6F6),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: '首页',
                selected: index == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.checklist_rounded,
                label: '计划',
                selected: index == 1,
                onTap: () => onTap(1),
              ),
              _PlusButton(onTap: onPlus),
              _NavItem(
                icon: Icons.school_rounded,
                label: '知识',
                selected: index == 2,
                onTap: () => onTap(2),
              ),
              _NavItem(
                icon: Icons.emoji_emotions_rounded,
                label: '生活',
                selected: index == 3,
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primaryDark : AppColors.textSub;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 中间的 + 号快捷键:比其它按钮大一圈、微微浮起、视觉突出
class _PlusButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PlusButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -14),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primaryLight, AppColors.primary],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.add_rounded, size: 32, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
