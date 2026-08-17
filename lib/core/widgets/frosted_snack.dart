import 'package:flutter/material.dart';

import 'package:student_workbench/core/widgets/overlay_toast.dart';

/// 磨砂玻璃提示条(转发到自绘 Overlay 实现,见 overlay_toast.dart)。
///
/// 保持历史函数签名不变,所有调用点无需改动:
/// - 入场上滑 + 淡入,退场下滑 + 淡出(替代 SnackBar 默认动画);
/// - 不排队:显示前先移除当前提示,多次触发始终只展示最新一条;
/// - 磨砂玻璃样式(半透明 + BackdropFilter 模糊)随明暗主题适配。
void showFrostedSnack(BuildContext context, String message) {
  OverlayToast.instance.show(context, message: message);
}

/// 带「撤销」按钮的磨砂提示条。用于删除/清空等可撤销操作:
/// 先执行操作,再弹出提示;用户点「撤销」时回调 [onUndo]。
void showUndoSnack(
  BuildContext context,
  String message, {
  required VoidCallback onUndo,
  String actionLabel = '撤销',
}) {
  OverlayToast.instance.show(
    context,
    message: message,
    duration: const Duration(milliseconds: 4000),
    actionLabel: actionLabel,
    onUndo: onUndo,
  );
}
