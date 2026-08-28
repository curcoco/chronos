import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:chronos/routes.dart';
import 'package:chronos/core/services/app_info.dart';
import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/services/settings_service.dart';
import 'package:chronos/core/services/update_installer.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/features/settings/pages/extension_service_page.dart';
import 'package:chronos/features/settings/pages/settings_page.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';
import 'package:chronos/features/coins/pages/coin_center_page.dart';
import 'package:chronos/features/diary/pages/diary_page.dart';
import 'package:chronos/features/english/pages/english_page.dart';
import 'package:chronos/features/health/pages/health_page.dart';
import 'package:chronos/features/review/pages/review_page.dart';

/// 侧边栏:应用信息 + 版本与更新 + 系统设置入口 + 功能模块。
/// 水玻璃风格:整体半透明 + BackdropFilter 背景模糊,露出背后页面。
/// (底部导航已覆盖 5 个一级 Tab,侧边栏不再重复导航,专注二级模块与设置。)
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  String _version = '';
  String _nickname = '';
  String _avatarPath = ''; // 头像图片本地路径(空=未设置)
  UpdateStatus? _status; // null = 检查中/未检查

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final v = await AppInfo.installedVersion();
    final nickname = await SettingsService.instance.nickname();
    final avatar = await SettingsService.instance.avatarPath();
    if (!mounted) return;
    setState(() {
      _version = v;
      _nickname = nickname;
      _avatarPath = avatar;
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

  /// 编辑资料:弹底部菜单(改昵称 / 换头像 / 移除头像)。
  Future<void> _editProfile() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('修改昵称'),
              onTap: () => Navigator.of(sheetCtx).pop('nickname'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('更换头像'),
              onTap: () => Navigator.of(sheetCtx).pop('pick'),
            ),
            if (_avatarPath.isNotEmpty)
              ListTile(
                leading: Icon(Icons.person_off_outlined,
                    color: AppColors.textSub),
                title: const Text('移除头像'),
                onTap: () => Navigator.of(sheetCtx).pop('remove'),
              ),
            const Divider(height: 1),
            ListTile(
              title: Center(
                child: Text('取消',
                    style: TextStyle(color: AppColors.textSub)),
              ),
              onTap: () => Navigator.of(sheetCtx).pop(),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'nickname':
        await _editNickname();
      case 'pick':
        await _pickAvatar();
      case 'remove':
        await SettingsService.instance.setAvatarPath('');
        if (!mounted) return;
        setState(() => _avatarPath = '');
        showFrostedSnack(context, '已移除头像');
    }
  }

  /// 头像组件:有图显示图片,无图显示昵称首字。
  Widget _avatarWidget() {
    final path = _avatarPath;
    return CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.primaryLight,
      foregroundImage: path.isNotEmpty
          ? FileImage(File(path), scale: 1.0)
          : null,
      child: path.isEmpty
          ? Text(
              _nickname.isEmpty ? '?' : _nickname.substring(0, 1),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            )
          : null,
    );
  }

  /// 选择图片作为头像:复制到应用文档目录持久化。
  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    try {
      // 存到应用文档目录(备份 zip 也会带上,便于换机迁移)。
      final dir = await getApplicationDocumentsDirectory();
      final file = File(picked.path);
      final ext = picked.path.contains('.png') ? 'png' : 'jpg';
      final dest = File('${dir.path}/avatar.$ext');
      await file.copy(dest.path);
      await SettingsService.instance.setAvatarPath(dest.path);
      if (!mounted) return;
      setState(() => _avatarPath = dest.path);
      showFrostedSnack(context, '头像已更新');
    } catch (e) {
      AppLog.instance.e('设置头像失败:$e');
      if (!mounted) return;
      showFrostedSnack(context, '头像设置失败,请重试');
    }
  }

  Future<void> _check() async {
    setState(() => _status = null);
    final s = await AppInfo.checkUpdate(_version);
    if (!mounted) return;
    setState(() => _status = s);
  }

  void _openSettings() {
    Navigator.of(context).pop(); // 先关抽屉
    AppRoutes.push(context, const SettingsPage());
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
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
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
                            // 浅色跟随当前色板,换主题色系时抽屉头部同步变色。
                            : [AppColors.background, AppColors.primaryLight],
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
                                colors: [AppColors.primaryLight, AppColors.primarySoft],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.school_rounded,
                                size: 26,
                                color: AppColors.onPrimarySoft),
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
                      child: UpdateBanner(
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
                        onTap: _editProfile,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              _avatarWidget(),
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
                                      '点击编辑资料',
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
                      '功能模块',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSub),
                    ),
                  ),
                  // 其余模块入口(原知识/生活 Tab 的内容收进侧边栏)
                  _moduleTile(Icons.translate_rounded, '英文积累', const EnglishPage()),
                  _moduleTile(
                      Icons.favorite_rounded, '健康管理', const HealthPage()),
                  _moduleTile(Icons.task_alt_rounded, '每日复盘', const ReviewPage()),
                  _moduleTile(
                      Icons.menu_book_rounded, '写日记', const DiaryPage()),
                  _moduleTile(
                      Icons.monetization_on_rounded, '金币中心', const CoinCenterPage()),
                  const Spacer(),
                  // 系统设置:置于抽屉最底部。
                  _frostTile(
                    onTap: _openSettings,
                    child: ListTile(
                      leading: Icon(Icons.settings_outlined,
                          size: 22, color: AppColors.primaryDark),
                      title: Text(
                        '系统设置',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMain),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded,
                          size: 20, color: AppColors.textSub),
                    ),
                  ),
                  const SizedBox(height: 12),
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

  /// 磨砂玻璃列表按钮:圆角裁剪 + BackdropFilter 背景模糊 + 半透明底色,
  /// 在抽屉水玻璃背景之上再叠一层,每个按钮呈独立的毛玻璃块(不再只是半透明色)。
  Widget _frostTile({required VoidCallback onTap, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Material(
            color: _glassColor(),
            child: InkWell(
              onTap: onTap,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  /// 功能模块入口:关抽屉后 push 模块页。
  Widget _moduleTile(IconData icon, String label, Widget page) {
    return _frostTile(
      onTap: () {
        Navigator.of(context).pop(); // 先关抽屉
        AppRoutes.push(context, page);
      },
      child: ListTile(
        leading: Icon(icon, size: 22, color: AppColors.textSub),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textMain,
          ),
        ),
        trailing:
            Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textSub),
      ),
    );
  }
}

/// 侧边栏「发现新版本」横幅:显示新版本号 + 更新内容,点击整卡下载并安装
class UpdateBanner extends StatefulWidget {
  final String version;
  final String? note;
  final String? apkUrl;

  const UpdateBanner({
    super.key,
    required this.version,
    this.note,
    this.apkUrl,
  });

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
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
                  style: TextStyle(fontSize: 11, color: AppColors.textSub),
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
