import 'package:flutter/material.dart';

import 'package:chronos/core/theme.dart';
import 'package:chronos/features/chat/services/llm_usage.dart';

/// 聊天页顶部的 Token 仪表盘条:最近一次请求用量 + 缓存命中 + 本会话累计。
/// 纯展示组件,数据由调用方传入;未产生任何用量且未在生成时不显示。
class ChatTokenBar extends StatelessWidget {
  final bool sending;
  final LlmUsage? usage;
  final int sessionPromptTokens;
  final int sessionCompletionTokens;
  final int sessionCachedTokens;

  const ChatTokenBar({
    super.key,
    required this.sending,
    required this.usage,
    required this.sessionPromptTokens,
    required this.sessionCompletionTokens,
    required this.sessionCachedTokens,
  });

  @override
  Widget build(BuildContext context) {
    if (!sending && usage == null) return const SizedBox.shrink();
    final Color sub = AppColors.textSub;
    if (sending) {
      return _strip([
        Text('生成中…', style: TextStyle(fontSize: 11, color: sub)),
      ]);
    }
    final u = usage!;
    final cachePct = u.promptTokens > 0
        ? ((u.cachedTokens / u.promptTokens) * 100).round()
        : 0;
    final session = sessionPromptTokens + sessionCompletionTokens;
    return _strip([
      Text(
        '${u.promptTokens}+${u.completionTokens}=${u.totalTokens}',
        style: TextStyle(fontSize: 11, color: sub),
      ),
      if (u.cachedTokens > 0) ...[
        const SizedBox(width: 8),
        Icon(Icons.bolt_rounded, size: 12, color: const Color(0xFF43A047)),
        Text('缓存命中 ${u.cachedTokens}($cachePct%)',
            style: TextStyle(
                fontSize: 11,
                color: const Color(0xFF43A047),
                fontWeight: FontWeight.w600)),
      ],
      const Spacer(),
      Text(
        sessionCachedTokens > 0
            ? '本会话 $session tokens · 缓存 $sessionCachedTokens'
            : '本会话 $session tokens',
        style: TextStyle(fontSize: 11, color: sub),
      ),
    ]);
  }

  Widget _strip(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      color: AppColors.card.withValues(alpha: 0.6),
      child: Row(
        children: [
          Icon(Icons.data_usage_rounded, size: 13, color: AppColors.textSub),
          const SizedBox(width: 6),
          ...children,
        ],
      ),
    );
  }
}
