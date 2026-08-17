import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/app_info.dart';
import '../services/settings_service.dart';
import '../services/update_installer.dart';
import '../theme.dart';
import '../widgets/frosted_snack.dart';
import 'chat_page.dart';
import 'coin_center_page.dart';
import 'diary_page.dart';
import 'extension_service_page.dart';
import 'home_page.dart';
import 'knowledge_page.dart';
import 'ledger_page.dart';
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
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => page, fullscreenDialog: dialog),
          );
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
        onPlus: _openQuickMenu,
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
  String _nickname = '';
  UpdateStatus? _status; // null = 检查中/未检查

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final v = await AppInfo.installedVersion();
    final nickname = await SettingsService.instance.nickname();
    if (!mounted) return;
    setState(() {
      _version = v;
      _nickname = nickname;
    });
    await _check();
  }

  Future<void> _editNickname() async {
    final controller = TextEditingController(text: _nickname);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改昵称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '输入你的昵称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    if (result.isEmpty) {
      showFrostedSnack(context, '昵称不能为空');
      return;
    }
    await SettingsService.instance.setNickname(result);
    if (!mounted) return;
    setState(() => _nickname = result);
    showFrostedSnack(context, '昵称已更新');
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
    // 水玻璃侧边栏:整体半透明 + BackdropFilter 背景模糊,露出背后页面。
    // 明暗主题下用不同色调的半透明底色;子元素(导航按钮等)用更浅的
    // 磨砂玻璃层叠,形成层次。
    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ClipRRect(
        borderRadius:
            const BorderRadius.horizontal(right: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: isDarkMode
                  ? const Color(0xE6172330)
                  : const Color(0xE6FFFFFF),
              border: Border(
                right: BorderSide(
                  color: isDarkMode
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            // 应用信息头部(渐变随明暗主题切换,深色下用低亮度同色系)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDarkMode
                      ? const [Color(0xFF16222E), Color(0xFF1E3A4C)]
                      : const [Color(0xFFD6EDFF), Color(0xFFB3E5FC)],
                ),
              ),
              child: Row(
                children: [
                  // 连点 7 下此图标 → 输入 6 位密码进入拓展服务页(隐藏入口)
                  SecretUnlockTap(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.primaryLight, AppColors.primary],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.school_rounded,
                          size: 26,
                          color: isDarkMode
                              ? const Color(0xFF07222E)
                              : Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chronos',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textMain,
                        ),
                      ),
                      const SizedBox(height: 2),
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
            // 版本与更新(仅发现新版本时显示;点击整卡即可下载更新)
            if (_status != null && _status!.updateAvailable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: _UpdateBanner(
                  version: _status!.latestVersion,
                  note: _status!.note,
                  apkUrl: _status!.apkUrl,
                ),
              ),
            // 用户资料(昵称必填,点击修改)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Material(
                color: _glassColor(),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: _editNickname,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.primaryLight,
                          child: Text(
                            _nickname.isEmpty
                                ? '?'
                                : _nickname.substring(0, 1),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _nickname,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textMain,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '点击修改昵称',
                                style: TextStyle(
                                    fontSize: 11, color: AppColors.textSub),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.edit_rounded,
                            size: 16, color: AppColors.textSub),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Padding(
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
            ListTile(
              leading: Icon(Icons.edit_note_rounded,
                  size: 22, color: AppColors.textSub),
              title: Text(
                '灵感速记',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain),
              ),
              // 磨砂玻璃导航按钮
              tileColor: _glassColor(),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.of(context).pop(); // 先关抽屉
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const QuickNotePage(),
                    fullscreenDialog: true,
                  ),
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.settings_outlined,
                  size: 22, color: AppColors.textSub),
              title: Text(
                '系统设置',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain),
              ),
              trailing: Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textSub),
              // 磨砂玻璃导航按钮
              tileColor: _glassColor(),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onTap: _openSettings,
            ),
            const Spacer(),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                '纯本地存储,仅更新检查需联网',
                style: TextStyle(fontSize: 11, color: AppColors.textSub),
              ),
            ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  /// 磨砂玻璃底色:随明暗主题适配的半透明白/蓝灰,用于抽屉内卡片与导航按钮。
  Color _glassColor() => isDarkMode
      ? const Color(0xFF243342).withValues(alpha: 0.5)
      : Colors.white.withValues(alpha: 0.5);

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
      // 磨砂玻璃导航按钮:半透明底色,选中态用主题色提亮
      tileColor: _glassColor(),
      selectedTileColor: AppColors.primaryLight.withValues(alpha: 0.45),
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
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: const [
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
                  gradient: LinearGradient(
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

/// 侧边栏「发现新版本」横幅:显示新版本号 + 更新内容,点击整卡下载并安装
class _UpdateBanner extends StatefulWidget {
  final String version;
  final String? note;
  final String? apkUrl;

  const _UpdateBanner({
    required this.version,
    this.note,
    this.apkUrl,
  });

  @override
  State<_UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<_UpdateBanner> {
  double? _progress; // null = 未在下载
  String? _error;

  bool get _downloading => _progress != null;

  Future<void> _download() async {
    final url = widget.apkUrl;
    if (url == null) {
      showFrostedSnack(context, '更新文件暂不可用');
      return;
    }
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      final path = await UpdateInstaller.downloadApk(
        url,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      await UpdateInstaller.installApk(path);
      if (!mounted) return;
      setState(() => _progress = null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _progress = null;
        _error = '下载失败,点按重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      // 磨砂玻璃卡片:半透明白/蓝灰,与抽屉水玻璃背景层叠
      color: dark
          ? const Color(0xFF243342).withValues(alpha: 0.5)
          : Colors.white.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _downloading ? null : _download,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.system_update_alt_rounded,
                      size: 18, color: Color(0xFFE65100)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '发现新版本 ${widget.version}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE65100),
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.note != null && widget.note!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  widget.note!,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSub, height: 1.4),
                ),
              ],
              const SizedBox(height: 10),
              if (_downloading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 6,
                    backgroundColor: AppColors.line,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '正在下载 ${((_progress ?? 0) * 100).clamp(0, 100).round()}%…',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSub),
                ),
              ] else if (_error != null)
                Text(
                  _error!,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFFE65100)),
                )
              else
                Text(
                  '点击下载更新',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
