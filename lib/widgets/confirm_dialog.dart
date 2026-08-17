import 'package:flutter/material.dart';

/// 统一的确认弹窗。收敛全 App 分散重复的删除/清空确认对话框。
///
/// 返回 true 表示用户确认;取消或点外部关闭返回 false。
/// [destructive] 为 true 时确认按钮用红色(删除类危险操作)。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmText = '确认',
  String cancelText = '取消',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null
          ? null
          : Text(message, style: const TextStyle(height: 1.6)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelText),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935))
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return ok ?? false;
}
