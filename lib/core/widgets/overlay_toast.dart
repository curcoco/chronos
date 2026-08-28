import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:chronos/core/theme.dart';

/// 全局底部提示条管理器(自绘 Overlay 版本)。
///
/// 相比 ScaffoldMessenger / SnackBar:
/// - 入场:上滑 + 淡入;退场:下滑 + 淡出(自绘动画,替换 SnackBar 默认动画);
/// - 不排队:新提示出现时立即移除旧提示,始终只显示最新一条;
/// - 保留磨砂玻璃样式与「撤销」按钮能力(磨砂样式原在 frosted_snack.dart,
///   随实现一并迁移到这里,`frosted_snack.dart` 仅保留转发函数)。
class OverlayToast {
  OverlayToast._();
  static final OverlayToast instance = OverlayToast._();

  static OverlayEntry? _current;

  /// 显示一条提示。同一时刻只保留一条(新提示顶掉旧提示)。
  /// [actionLabel] 与 [onUndo] 同时提供时,右侧显示操作按钮(如「撤销」)。
  void show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(milliseconds: 2700),
    String? actionLabel,
    VoidCallback? onUndo,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    // 不排队:先移除旧提示,让最新一条即时显示。
    _current?.remove();
    final media = MediaQuery.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _OverlayToastView(
        message: message,
        actionLabel: actionLabel,
        onUndo: onUndo,
        displayDuration: duration,
        bottomInset: media.padding.bottom,
        onDone: () {
          if (identical(_current, entry)) _current = null;
          entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

/// 提示条本体:入场动画 → 停留 → 退场动画 → 移除。
class _OverlayToastView extends StatefulWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onUndo;
  final Duration displayDuration;

  /// 屏幕底部安全区高度(导航条等),提示条悬浮其上。
  final double bottomInset;

  /// 退场动画完成后的回调(移除 OverlayEntry)。
  final VoidCallback onDone;

  const _OverlayToastView({
    required this.message,
    this.actionLabel,
    this.onUndo,
    required this.displayDuration,
    required this.bottomInset,
    required this.onDone,
  });

  @override
  State<_OverlayToastView> createState() => _OverlayToastViewState();
}

class _OverlayToastViewState extends State<_OverlayToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.25),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  ));

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      // 入场动画结束后开始停留计时,到时触发退场。
      _timer = Timer(widget.displayDuration, _dismiss);
    });
  }

  /// 立即开始退场(撤销按钮点击 / 停留时间到)。
  void _dismiss() {
    _timer?.cancel();
    _controller.reverse().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color glass = dark
        ? const Color(0xFF243342).withValues(alpha: 0.72)
        : Colors.white.withValues(alpha: 0.55);
    // 描边一律用中性灰(不随主题色),避免「彩色下划线」观感。
    final Color borderColor = dark
        ? const Color(0xFF3A4654).withValues(alpha: 0.7)
        : const Color(0x2E1F2D3D);
    final Color textColor =
        dark ? const Color(0xFFE7EEF5) : const Color(0xFF1F2D3D);
    // 动作色(如「撤销」)浅色跟随当前色板;深色用固定浅蓝保证深底可读。
    final Color actionColor =
        dark ? const Color(0xFF4FC3F7) : AppColors.primaryDark;

    final hasAction = widget.actionLabel != null && widget.onUndo != null;
    return Positioned(
      left: 20,
      right: 20,
      bottom: widget.bottomInset + 16,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: EdgeInsets.fromLTRB(16, 8, hasAction ? 8 : 16, 8),
                decoration: BoxDecoration(
                  color: glass,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.message,
                        // 无操作按钮时文字居中;带「撤销」等按钮时保持左对齐,按钮靠右。
                        textAlign:
                            hasAction ? TextAlign.left : TextAlign.center,
                        style: TextStyle(fontSize: 13, color: textColor),
                      ),
                    ),
                    if (hasAction)
                      TextButton(
                        onPressed: () {
                          widget.onUndo!.call();
                          _dismiss();
                        },
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                        ),
                        child: Text(
                          widget.actionLabel!,
                          style: TextStyle(
                            fontSize: 13,
                            color: actionColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
