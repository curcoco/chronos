import 'package:flutter/material.dart';

import '../services/app_info.dart';
import '../theme.dart';
import '../widgets/section_card.dart';
import '../widgets/update_download_button.dart';

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
                    Container(
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
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
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
                    style: const TextStyle(
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
                const Text(
                  '纯本地存储,数据保存在设备上;仅版本更新检查需要联网。',
                  style: TextStyle(fontSize: 12, color: AppColors.textSub),
                ),
              ],
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
      bg = const Color(0xFFE3F0FA);
      fg = AppColors.textSub;
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
      bg = const Color(0xFFEEF2F6);
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
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSub,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
          ),
        ),
      ],
    );
  }
}
