import 'package:flutter/material.dart';

import '../theme.dart';

/// 通用卡片容器:标题行 + 内容
class SectionCard extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SectionCard({
    super.key,
    required this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// 分类彩色小标签
Color categoryColor(String category) {
  const palette = [
    Color(0xFF42A5F5),
    Color(0xFF66BB6A),
    Color(0xFFFFA726),
    Color(0xFFAB47BC),
    Color(0xFFEF5350),
    Color(0xFF26A69A),
    Color(0xFFEC407A),
    Color(0xFF7E57C2),
  ];
  return palette[category.hashCode.abs() % palette.length];
}

/// 优先级标签 0高 1中 2低
class PriorityTag extends StatelessWidget {
  final int priority;
  const PriorityTag({super.key, required this.priority});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (priority) {
      0 => ('高', const Color(0xFFEF5350)),
      1 => ('中', const Color(0xFFFFA726)),
      _ => ('低', const Color(0xFF66BB6A)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
