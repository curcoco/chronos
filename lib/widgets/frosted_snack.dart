import 'dart:ui';

import 'package:flutter/material.dart';

/// 磨砂玻璃提示条:半透明 + 背景模糊(BackdropFilter),随明暗主题适配。
void showFrostedSnack(BuildContext context, String message) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  final Color glass = dark
      ? const Color(0xFF243342).withValues(alpha: 0.72)
      : Colors.white.withValues(alpha: 0.55);
  final Color borderColor = dark
      ? Colors.white.withValues(alpha: 0.18)
      : Colors.white.withValues(alpha: 0.7);
  final Color textColor =
      dark ? const Color(0xFFE7EEF5) : const Color(0xFF1F2D3D);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      // 展示时长:4 秒的 2/3(缩短三分之一)
      duration: const Duration(milliseconds: 2700),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      content: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: glass,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: textColor),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 带「撤销」按钮的磨砂提示条。用于删除/清空等可撤销操作:
/// 先执行操作,再弹出提示;用户点「撤销」时回调 [onUndo]。
void showUndoSnack(
  BuildContext context,
  String message, {
  required VoidCallback onUndo,
  String actionLabel = '撤销',
}) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  final Color glass = dark
      ? const Color(0xFF243342).withValues(alpha: 0.72)
      : Colors.white.withValues(alpha: 0.55);
  final Color borderColor = dark
      ? Colors.white.withValues(alpha: 0.18)
      : Colors.white.withValues(alpha: 0.7);
  final Color textColor =
      dark ? const Color(0xFFE7EEF5) : const Color(0xFF1F2D3D);
  final Color actionColor =
      dark ? const Color(0xFF4FC3F7) : const Color(0xFF0288D1);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      duration: const Duration(milliseconds: 4000),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      content: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            decoration: BoxDecoration(
              color: glass,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(fontSize: 13, color: textColor),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    messenger.hideCurrentSnackBar();
                    onUndo();
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  child: Text(
                    actionLabel,
                    style: TextStyle(
                        fontSize: 13,
                        color: actionColor,
                        fontWeight: FontWeight.w700),
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
