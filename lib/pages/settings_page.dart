import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_info.dart';
import '../services/backup_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/frosted_snack.dart';
import '../widgets/section_card.dart';
import '../widgets/update_download_button.dart';
import 'api_settings_page.dart';
import 'extension_service_page.dart';

/// 系统设置:关于(应用名、简介)+ 版本号与更新状态
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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

  bool _exporting = false;
  bool _restoring = false;

  Future<void> _exportData() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final path = await BackupService.instance.exportZip();
      if (!mounted) return;
      showFrostedSnack(context, '已导出备份到:$path');
      // 顺手唤起系统分享,方便直接发送/另存到网盘或换机
      await Share.shareXFiles([XFile(path)], subject: 'Chronos 数据备份');
    } catch (e) {
      if (!mounted) return;
      showFrostedSnack(context, '导出失败:$e');
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
      message: '将用所选备份里的数据(任务 / 心愿 / 金币 / 日记 / 记忆 / 计划 / 记账等)'
          '覆盖当前全部本地数据,现有数据会被替换。恢复前会自动保留一份当前数据副本。'
          '\n\nAPI 密钥不受影响。',
      confirmText: '覆盖恢复',
      destructive: true,
    );
    if (!confirm || !mounted) return;

    setState(() => _restoring = true);
    try {
      final result = await BackupService.instance.restoreFromZip(path);
      if (!mounted) return;
      showFrostedSnack(context,
          '恢复完成:数据库已导入,设置项 ${result.prefsRestored} 项。重启应用后全部生效。');
    } catch (e) {
      if (!mounted) return;
      final msg = e is FormatException ? e.message : '$e';
      showFrostedSnack(context, '恢复失败:$msg');
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
                            colors: [AppColors.primaryLight, AppColors.primary],
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
                        child: const Icon(
                          Icons.school_rounded,
                          size: 30,
                          color: Colors.white,
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
                Text(
                  '纯本地存储,数据保存在设备上;仅版本更新检查需要联网。',
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
                  '深色模式适合夜间使用;跟随系统会随手机设置自动切换',
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
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: '数据备份',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  '把全部本地数据(任务 / 心愿 / 金币 / 日记 / 记忆 / 计划 / 记账等)'
                  '与个人设置打包成 zip 保存到本机,便于备份或更换设备。不含 API 密钥。',
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
                  '选择之前导出的 zip,用它覆盖当前全部本地数据(换新设备时用)。'
                  '覆盖前会自动保留一份当前数据副本;恢复后请重启应用生效。',
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
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: '联网服务',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.vpn_key_rounded,
                  size: 22, color: AppColors.primaryDark),
              title: const Text(
                'API 配置',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '中转站 / 语音 / 天气 / 云端同步(密钥仅存本机)',
                style: TextStyle(fontSize: 12, color: AppColors.textSub),
              ),
              trailing: Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textSub),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ApiSettingsPage()),
              ),
            ),
          ),
        ],
      ),
    );
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
