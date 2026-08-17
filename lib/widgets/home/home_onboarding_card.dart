import 'package:flutter/material.dart';

import '../../theme.dart';
import '../section_card.dart';

/// 首页首次引导卡:离线功能开箱即用;联网功能(天气/AI 聊天/更新)需在
/// 「系统设置 → API 配置」填写 key。关闭后不再出现(存本地标记)。
class HomeOnboardingCard extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onOpenApiSettings;

  const HomeOnboardingCard({
    super.key,
    required this.onClose,
    required this.onOpenApiSettings,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '欢迎使用 Chronos',
      trailing: IconButton(
        onPressed: onClose,
        icon: Icon(Icons.close_rounded, size: 18, color: AppColors.textSub),
        tooltip: '关闭',
        visualDensity: VisualDensity.compact,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '计划 / 金币 / 灵感 / 记账等全部功能离线可用,数据只存本机。',
            style:
                TextStyle(fontSize: 13, height: 1.5, color: AppColors.textMain),
          ),
          const SizedBox(height: 6),
          Text(
            '天气与 AI 聊天需联网:在「系统设置 → API 配置」填入你的 key 即可。',
            style:
                TextStyle(fontSize: 12, height: 1.5, color: AppColors.textSub),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: AppColors.primaryLight,
                  foregroundColor: AppColors.primaryDark,
                ),
                onPressed: onOpenApiSettings,
                child: const Text('去配置 API'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onClose,
                child: Text('知道了',
                    style: TextStyle(color: AppColors.textSub)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
