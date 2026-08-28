import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:chronos/routes.dart';
import 'package:chronos/core/services/app_info.dart';
import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/services/backup_service.dart';
import 'package:chronos/core/services/key_store.dart';
import 'package:chronos/core/services/settings_service.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/widgets/confirm_dialog.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';
import 'package:chronos/core/widgets/section_card.dart';
import 'package:chronos/core/widgets/update_download_button.dart';
import 'package:chronos/features/settings/pages/api_settings_page.dart';
import 'package:chronos/features/settings/pages/chat_files_page.dart';
import 'package:chronos/features/settings/pages/extension_service_page.dart';
import 'package:chronos/features/settings/pages/model_roles_page.dart';
import 'package:chronos/features/settings/pages/provider_list_page.dart';
import 'package:chronos/features/shell/pages/splash_page.dart';

/// 系统设置:关于(应用名、简介)+ 版本号与更新状态
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _version = '';
  UpdateStatus? _status; // null = 检查中/未检查
  String? _lastBackupAt; // 上次成功导出备份的时间

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final v = await AppInfo.installedVersion();
    final lastBackup = await SettingsService.instance.lastBackupAt();
    if (!mounted) return;
    setState(() {
      _version = v;
      _lastBackupAt = lastBackup;
    });
    await _check();
  }

  Future<void> _check() async {
    setState(() => _status = null);
    final s = await AppInfo.checkUpdate(_version);
    if (!mounted) return;
    setState(() => _status = s);
  }

  /// 编辑更新源地址(留空 = 使用默认阿里云服务器)。
  Future<void> _editUpdateSource() async {
    final current = await KeyStore.instance.get(KeyStore.updateCheckUrl);
    if (!mounted) return;
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('更新源地址'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://…/latest.json(留空用默认)',
            helperText: '默认:${AppInfo.defaultUpdateCheckUrl}',
            helperMaxLines: 2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    await KeyStore.instance.set(KeyStore.updateCheckUrl, result);
    if (!mounted) return;
    showFrostedSnack(context,
        result.isEmpty ? '已恢复默认更新源' : '更新源已保存,重新检查试试');
    await _check();
  }

  bool _exporting = false;
  bool _restoring = false;

  /// 导出诊断包(数据库 + 日志 + 设置,不含密钥),用于问题复现排查。
  Future<void> _exportDiagnostic() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final path = await BackupService.instance.exportDiagnosticZip();
      if (!mounted) return;
      showFrostedSnack(context, '诊断包已导出,可发送给开发者排查问题');
      await Share.shareXFiles([XFile(path)], subject: 'Chronos 诊断包');
    } catch (e) {
      AppLog.instance.e('导出诊断包失败:$e');
      if (!mounted) return;
      showFrostedSnack(context, '导出失败,请重试');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportData() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final path = await BackupService.instance.exportZip();
      // 记录上次备份时间,用于「上次备份于 X 天前」提醒。
      final now = DateTime.now();
      await SettingsService.instance.markBackupExported(now);
      if (!mounted) return;
      setState(() => _lastBackupAt = now.toIso8601String());
      showFrostedSnack(context, '已导出备份到:$path');
      // 顺手唤起系统分享,方便直接发送/另存到网盘或换机
      await Share.shareXFiles([XFile(path)], subject: 'Chronos 数据备份');
    } catch (e) {
      AppLog.instance.e('导出备份失败:$e');
      if (!mounted) return;
      showFrostedSnack(context, '导出失败,请重试');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _restoreData() async {
    if (_restoring) return;
    // 先选文件,再二次确认(覆盖是数据敏感操作)。
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: false,
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    final confirm = await showConfirmDialog(
      context,
      title: '用备份覆盖当前数据?',
      message: '用备份覆盖当前全部本地数据,恢复前自动保留副本。'
          '\n\nAPI 密钥不受影响。',
      confirmText: '覆盖恢复',
      destructive: true,
    );
    if (!confirm || !mounted) return;

    setState(() => _restoring = true);
    try {
      final result = await BackupService.instance.restoreFromZip(path);
      if (!mounted) return;
      // 备份里的主题模式等设置已写回 prefs,但内存中的 themeMode 仍是旧值,
      // 重新载入让主题与恢复后的数据一致。
      await SettingsService.instance.loadThemeMode();
      if (!mounted) return;
      showFrostedSnack(context,
          '恢复完成:数据库 + ${result.prefsRestored} 项设置,即将重启…');
      // 恢复后重建到启动页,让所有页面用新数据重新加载(等提示看得见再跳)。
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      AppRoutes.pushAndRemoveUntil(context, const SplashPage());
    } catch (e) {
      AppLog.instance.e('恢复备份失败:$e');
      if (!mounted) return;
      // zip 解析类错误(选错文件等)给出具体原因,其余给友好文案。
      final msg = e is FormatException ? e.message : '恢复失败,请重试';
      showFrostedSnack(context, msg);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('系统设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          SectionCard(
            title: '关于',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 连点 7 下此图标 → 输入 6 位密码进入拓展服务页(隐藏入口)
                    SecretUnlockTap(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.primaryLight, AppColors.primarySoft],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.school_rounded,
                          size: 30,
                          color: AppColors.onPrimarySoft,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chronos',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textMain,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '学生日常计划与金币激励应用\n灵感速记 · 每日任务 · 金币心愿',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color:
                                  AppColors.textSub.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                _infoRow(Icons.info_outline_rounded, '当前版本',
                    _version.isEmpty ? '版本 未知' : '版本 $_version'),
                const SizedBox(height: 10),
                _infoRow(
                    Icons.system_update_alt_rounded,
                    '最新版本',
                    status == null
                        ? '检查中…'
                        : '版本 ${status.latestVersion}'),
                const SizedBox(height: 12),
                _buildStatusChip(status),
                if (status != null &&
                    status.updateAvailable &&
                    status.note != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '更新说明:${status.note}',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSub),
                  ),
                ],
                if (status != null &&
                    status.updateAvailable &&
                    status.apkUrl != null) ...[
                  const SizedBox(height: 12),
                  UpdateDownloadButton(apkUrl: status.apkUrl!),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      foregroundColor: AppColors.primaryDark,
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: status == null ? null : _check,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('重新检查更新'),
                  ),
                ),
                const SizedBox(height: 10),
                // 更新源配置:默认阿里云服务器,可改为自己的 OSS/静态托管地址。
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link_rounded,
                      size: 20, color: AppColors.primaryDark),
                  title: const Text(
                    '更新源地址',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '默认阿里云,可改自己的静态地址',
                    style: TextStyle(fontSize: 11, color: AppColors.textSub),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded,
                      size: 20, color: AppColors.textSub),
                  onTap: _editUpdateSource,
                ),
                const SizedBox(height: 10),
                Text(
                  '纯本地存储,仅更新检查需联网',
                  style: TextStyle(fontSize: 12, color: AppColors.textSub),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: '外观',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '主题模式',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '深色适合夜间;跟随系统自动切换',
                  style: TextStyle(fontSize: 12, color: AppColors.textSub),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: SettingsService.instance.themeMode,
                  builder: (context, mode, _) {
                    return SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_rounded, size: 18),
                          label: Text('浅色'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_rounded, size: 18),
                          label: Text('深色'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto_rounded, size: 18),
                          label: Text('跟随'),
                        ),
                      ],
                      selected: {mode},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) =>
                          SettingsService.instance.setThemeMode(s.first),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  '主题配色',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '六套浅色主题,切换即时生效',
                  style: TextStyle(fontSize: 12, color: AppColors.textSub),
                ),
                const SizedBox(height: 10),
                _paletteSelector(),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  '背景图片',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '选一张图铺满全部页面背景,可调透明度',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSub, height: 1.5),
                ),
                const SizedBox(height: 6),
                ValueListenableBuilder<bool>(
                  valueListenable: SettingsService.instance.backgroundEnabled,
                  builder: (context, enabled, _) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '启用背景图',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    value: enabled,
                    onChanged: (v) =>
                        SettingsService.instance.setBackgroundEnabled(v),
                  ),
                ),
                _backgroundPicker(),
                ValueListenableBuilder<double>(
                  valueListenable:
                      SettingsService.instance.backgroundOpacity,
                  builder: (context, opacity, _) => Row(
                    children: [
                      Text('透明度',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSub)),
                      Expanded(
                        child: Slider(
                          value: opacity,
                          min: 0.3,
                          max: 1.0,
                          onChanged: (v) => SettingsService.instance
                              .setBackgroundOpacity(v),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text('${(opacity * 100).round()}%',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSub)),
                      ),
                    ],
                  ),
                ),
                // 背景图高斯模糊度:0 = 不模糊。
                ValueListenableBuilder<double>(
                  valueListenable: SettingsService.instance.backgroundBlur,
                  builder: (context, blur, _) => Row(
                    children: [
                      Text('模糊度',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSub)),
                      Expanded(
                        child: Slider(
                          value: blur,
                          min: 0,
                          max: 30,
                          divisions: 30,
                          onChanged: (v) =>
                              SettingsService.instance.setBackgroundBlur(v),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(blur == 0 ? '无' : '${blur.round()}',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSub)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: '模型与服务',
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.dns_outlined,
                      size: 22, color: AppColors.primaryDark),
                  title: const Text(
                    '提供商',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '多个中转站,各自 地址/Key/模型',
                    style: TextStyle(fontSize: 12, color: AppColors.textSub),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded,
                      size: 20, color: AppColors.textSub),
                  onTap: () =>
                      AppRoutes.push(context, const ProviderListPage()),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.smart_toy_outlined,
                      size: 22, color: AppColors.primaryDark),
                  title: const Text(
                    '模型',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '聊天/快速/OCR/翻译/标题 各选模型',
                    style: TextStyle(fontSize: 12, color: AppColors.textSub),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded,
                      size: 20, color: AppColors.textSub),
                  onTap: () => AppRoutes.push(context, const ModelRolesPage()),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.vpn_key_rounded,
                      size: 22, color: AppColors.primaryDark),
                  title: const Text(
                    'API 配置',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '语音 / 天气 / 搜索 / 外置记忆(密钥仅存本机)',
                    style: TextStyle(fontSize: 12, color: AppColors.textSub),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded,
                      size: 20, color: AppColors.textSub),
                  onTap: () => AppRoutes.push(context, const ApiSettingsPage()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: '数据设置',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_lastBackupAt != null) ...[
                  _backupTimeRow(_lastBackupAt!),
                  const SizedBox(height: 12),
                ],
                Text(
                  '导出本地数据',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '全部本地数据与设置打包成 zip,便于备份/换机。不含密钥。',
                  style: TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.5),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(46),
                    ),
                    onPressed: _exporting ? null : _exportData,
                    icon: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.archive_rounded, size: 18),
                    label: Text(_exporting ? '正在导出…' : '导出为 zip 备份'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '从备份恢复',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '选择备份 zip 覆盖当前数据(换机时用),自动保留副本',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSub, height: 1.5),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      foregroundColor: AppColors.primaryDark,
                      side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _restoring ? null : _restoreData,
                    icon: _restoring
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.restore_rounded, size: 18),
                    label: Text(_restoring ? '正在恢复…' : '从 zip 恢复'),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 4),
                FutureBuilder<bool>(
                  future: SettingsService.instance.isAutoBackupEnabled(),
                  builder: (context, snap) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      '自动备份(每周)',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '启动时距上次备份超 7 天,自动静默导出一份',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textSub),
                    ),
                    value: snap.data ?? false,
                    onChanged: (v) async {
                      await SettingsService.instance.setAutoBackupEnabled(v);
                      if (!context.mounted) return;
                      showFrostedSnack(context,
                          v ? '已开启自动备份(每周)' : '已关闭自动备份');
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      foregroundColor: AppColors.textSub,
                      side: BorderSide(color: AppColors.line),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _exporting ? null : _exportDiagnostic,
                    icon: const Icon(Icons.bug_report_outlined, size: 18),
                    label: const Text('导出诊断包(日志 + 数据库)'),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.photo_library_outlined,
                      size: 22, color: AppColors.primaryDark),
                  title: const Text(
                    '聊天图片',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '闲话铺发过的图片,可查看 / 删除 / 清空',
                    style: TextStyle(fontSize: 12, color: AppColors.textSub),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded,
                      size: 20, color: AppColors.textSub),
                  onTap: () => AppRoutes.push(context, const ChatFilesPage()),
                ),
                const SizedBox(height: 4),
                // 后台生成通知:闲话铺退后台继续生成并弹完成通知(默认开)。
                ValueListenableBuilder<bool>(
                  valueListenable: SettingsService.instance.backgroundNotify,
                  builder: (context, v, _) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      '后台生成通知',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '掌柜生成回复时退到后台也能继续,完成后通知你',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.textSub),
                    ),
                    value: v,
                    onChanged: (nv) async {
                      await SettingsService.instance.setBackgroundNotify(nv);
                      if (!context.mounted) return;
                      showFrostedSnack(context,
                          nv ? '已开启后台生成通知' : '已关闭后台生成通知');
                    },
                  ),
                ),
                const SizedBox(height: 4),
                // Auto Memory:掌柜在对话中自主写/改/删「关于用户的档案」(默认开)。
                ValueListenableBuilder<bool>(
                  valueListenable: SettingsService.instance.autoMemory,
                  builder: (context, v, _) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'AI 记忆档案(Auto Memory)',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '允许掌柜在对话中自主写入/更新/删除关于你的档案,可在「AI 长期记忆」页管理',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.textSub),
                    ),
                    value: v,
                    onChanged: (nv) async {
                      await SettingsService.instance.setAutoMemory(nv);
                      if (!context.mounted) return;
                      showFrostedSnack(context,
                          nv ? '已开启 Auto Memory' : '已关闭 Auto Memory');
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 「上次备份于 X 天前」提醒行:数据是用户的心血,让备份入口看得见。
  Widget _backupTimeRow(String iso) {
    final time = DateTime.tryParse(iso);
    if (time == null) return const SizedBox.shrink();
    final days = DateTime.now().difference(time).inDays;
    final String label = switch (days) {
      < 1 => '上次备份:今天',
      == 1 => '上次备份:昨天',
      _ => '上次备份:$days 天前',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 16, color: AppColors.primaryDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              days >= 7 ? '$label,建议尽快导出一次' : label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 六套主题配色选择器(色点 + 名称,选中高亮)。
  Widget _paletteSelector() {
    const labels = {
      'blue': '蓝色',
      'pink': '粉色',
      'green': '绿色',
      'yellow': '黄色',
      'black': '黑色',
      'white': '白色',
    };
    return ValueListenableBuilder<String>(
      valueListenable: SettingsService.instance.palette,
      builder: (context, current, _) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final entry in kAppPalettes.entries)
            _paletteChip(
              id: entry.key,
              palette: entry.value,
              label: labels[entry.key] ?? entry.key,
              selected: current == entry.key,
            ),
        ],
      ),
    );
  }

  Widget _paletteChip({
    required String id,
    required AppPalette palette,
    required String label,
    required bool selected,
  }) {
    return InkWell(
      onTap: () => SettingsService.instance.setPalette(id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: palette.primaryLight.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? palette.primary : AppColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: palette.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textMain,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 背景图选择区:缩略图 + 选择/移除。
  Widget _backgroundPicker() {
    return ValueListenableBuilder<String>(
      valueListenable: SettingsService.instance.backgroundPath,
      builder: (context, path, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: path.isNotEmpty
                  ? Image.file(File(path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                          Icons.image_outlined,
                          size: 22,
                          color: Colors.grey))
                  : const Icon(Icons.image_outlined,
                      size: 22, color: Colors.grey),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                  foregroundColor: AppColors.primaryDark,
                  side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _pickBackground,
                icon: const Icon(Icons.add_photo_alternate_outlined,
                    size: 18),
                label: Text(path.isEmpty ? '选择背景图片' : '更换背景图片',
                    style: const TextStyle(fontSize: 13)),
              ),
            ),
            if (path.isNotEmpty) ...[
              const SizedBox(width: 6),
              IconButton(
                onPressed: () async {
                  await SettingsService.instance.setBackgroundPath('');
                  if (!context.mounted) return;
                  showFrostedSnack(context, '已移除背景图');
                },
                icon: Icon(Icons.delete_outline_rounded,
                    size: 20, color: AppColors.textSub),
                tooltip: '移除背景图',
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 选择背景图:压缩后复制到应用文档目录持久化(备份 zip 会带上)。
  Future<void> _pickBackground() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = picked.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final dest = File('${dir.path}/background.$ext');
      await File(picked.path).copy(dest.path);
      await SettingsService.instance.setBackgroundPath(dest.path);
      if (!mounted) return;
      showFrostedSnack(context, '背景图已设置,可调透明度');
    } catch (_) {
      if (!mounted) return;
      showFrostedSnack(context, '背景图设置失败,请重试');
    }
  }

  Widget _buildStatusChip(UpdateStatus? status) {
    late final Color bg;
    late final Color fg;
    late final IconData icon;
    late final String text;
    if (status == null) {
      bg = AppColors.primaryLight.withValues(alpha: 0.35);
      fg = AppColors.primaryDark;
      icon = Icons.hourglass_top_rounded;
      text = '正在检查更新…';
    } else if (status.updateAvailable) {
      bg = const Color(0xFFFFF3E0);
      fg = const Color(0xFFE65100);
      icon = Icons.system_update_alt_rounded;
      text = '发现新版本 ${status.latestVersion},请下载最新 APK 覆盖更新';
    } else if (status.reachable) {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
      icon = Icons.check_circle_rounded;
      text = '已是最新版本';
    } else {
      bg = AppColors.line;
      fg = AppColors.textSub;
      icon = Icons.cloud_off_rounded;
      text = '无法连接更新服务器,请检查网络';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textSub),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSub,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
          ),
        ),
      ],
    );
  }
}
