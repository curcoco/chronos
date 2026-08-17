import 'package:flutter/material.dart';

import 'package:student_workbench/routes.dart';
import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/core/widgets/module_card.dart';
import 'package:student_workbench/features/chat/pages/chat_page.dart';
import 'package:student_workbench/features/health/pages/health_page.dart';
import 'package:student_workbench/features/ledger/pages/ledger_page.dart';
import 'package:student_workbench/features/review/pages/review_page.dart';

/// 生活 Tab:第二批模块入口(每日复盘 / 生活记账等)
class LifePage extends StatelessWidget {
  const LifePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              '生活',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textMain,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              '记录与规划',
              style: TextStyle(fontSize: 13, color: AppColors.textSub),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                ModuleCard(
                  icon: Icons.favorite_rounded,
                  title: '健康管理',
                  desc: '厨房秘籍 / 智能食谱 / 运动打卡 / 热力图',
                  onTap: () => AppRoutes.push(context, const HealthPage()),
                ),
                const SizedBox(height: 12),
                ModuleCard(
                  icon: Icons.task_alt_rounded,
                  title: '每日复盘',
                  desc: '完成进度 / 问题卡点 / 明日方案,历史复盘留存',
                  onTap: () => AppRoutes.push(context, const ReviewPage()),
                ),
                const SizedBox(height: 12),
                ModuleCard(
                  icon: Icons.forum_rounded,
                  title: '零时闲话铺',
                  desc: '和 AI 掌柜聊天,可语音朗读(需配置 API)',
                  onTap: () => AppRoutes.push(context, const ChatPage()),
                ),
                const SizedBox(height: 12),
                ModuleCard(
                  icon: Icons.account_balance_wallet_rounded,
                  title: '生活记账',
                  desc: '收支流水 / 日历 / 图表 / 预算,纯本地',
                  onTap: () => AppRoutes.push(context, const LedgerPage()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
