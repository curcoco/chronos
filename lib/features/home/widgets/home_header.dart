import 'dart:io';

import 'package:flutter/material.dart';

import 'package:student_workbench/core/theme.dart';

/// 首页头部:日期 + 星期 + 金句 + 用户头像(点击开侧边栏)。
/// [avatarPath] 非空时显示头像图片,否则显示昵称首字。
class HomeHeader extends StatelessWidget {
  final String dateLabel;
  final String week;
  final String quote;
  final String nickname;
  final String avatarPath;
  final VoidCallback onOpenDrawer;

  const HomeHeader({
    super.key,
    required this.dateLabel,
    required this.week,
    required this.quote,
    required this.nickname,
    required this.avatarPath,
    required this.onOpenDrawer,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$dateLabel $week',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMain,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '「$quote」',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: AppColors.primaryDark.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        // 用户头像(点击开侧边栏;支持自定义头像图片)
        GestureDetector(
          onTap: onOpenDrawer,
          child: CircleAvatar(
            radius: 19,
            backgroundColor: AppColors.primaryLight,
            foregroundImage: avatarPath.isNotEmpty
                ? FileImage(File(avatarPath), scale: 1.0)
                : null,
            child: avatarPath.isEmpty
                ? Text(
                    nickname.isEmpty ? '?' : nickname.substring(0, 1),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
