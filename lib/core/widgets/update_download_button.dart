import 'dart:io';

import 'package:flutter/material.dart';

import 'package:chronos/core/services/update_installer.dart';
import 'package:chronos/core/theme.dart';

/// 「下载并更新」按钮:下载 APK(带进度)→ 调起系统安装器。
/// 状态:idle → downloading(百分比) → 打开安装页;失败可重试。
class UpdateDownloadButton extends StatefulWidget {
  final String apkUrl;

  const UpdateDownloadButton({super.key, required this.apkUrl});

  @override
  State<UpdateDownloadButton> createState() => _UpdateDownloadButtonState();
}

class _UpdateDownloadButtonState extends State<UpdateDownloadButton> {
  double? _progress; // null = 未在下载
  String? _error;

  bool get _downloading => _progress != null;

  Future<void> _start() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      final path = await UpdateInstaller.downloadApk(
        widget.apkUrl,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      // 下载完成,调起系统安装器;装完/取消由系统处理,这里静默返回
      await UpdateInstaller.installApk(path);
      if (!mounted) return;
      setState(() => _progress = null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _progress = null;
        _error = e is HttpException && e.message.isNotEmpty
            ? '下载失败:${e.message}'
            : '下载失败,请检查网络后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_downloading) {
      final p = _progress ?? 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '正在下载更新 ${(p * 100).clamp(0, 100).toStringAsFixed(0)}%…',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 6,
              backgroundColor: const Color(0xFFE3F0FA),
              color: AppColors.primary,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            onPressed: _start,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('下载并更新'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 14, color: Color(0xFFE65100)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _error!,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFFE65100)),
                ),
              ),
              TextButton(
                onPressed: _start,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('重试', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
