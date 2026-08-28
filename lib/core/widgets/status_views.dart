import 'package:flutter/material.dart';

import 'package:chronos/core/theme.dart';

/// 页面「加载 / 错误 / 空」三态共享组件:各页面不再各写一套,
/// 保持视觉一致(浅蓝极简)并收敛文案样式。
/// 用法:数据未就绪返回 [LoadingView];加载失败返回 [ErrorView];
/// 列表为空返回 [EmptyView]。

/// 加载中:居中转圈 + 可选说明文字。
class LoadingView extends StatelessWidget {
  final String? hint;
  const LoadingView({super.key, this.hint});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (hint != null) ...[
            const SizedBox(height: 12),
            Text(hint!,
                style: TextStyle(fontSize: 12, color: AppColors.textSub)),
          ],
        ],
      ),
    );
  }
}

/// 加载失败:图标 + 文案 + 重试按钮。
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 42, color: AppColors.textSub),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSub),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}

/// 空状态:图标 + 文案(可带提示)。
class EmptyView extends StatelessWidget {
  final IconData icon;
  final String message;
  const EmptyView({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: AppColors.primaryLight),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: AppColors.textSub)),
        ],
      ),
    );
  }
}
