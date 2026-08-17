/// 健康模块共享的小组件与工具。
library;

import 'package:flutter/material.dart';

import 'package:student_workbench/core/theme.dart';

/// 分类/类型圆角胶囊选择器(厨房分类、运动类型复用)。
class CatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const CatChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : AppColors.textSub,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// 指标展示卡:大数字 + 小标签(BMI / TDEE / 运动统计复用)。
class MetricCard extends StatelessWidget {
  final String value;
  final String label;

  const MetricCard({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 11, color: AppColors.textSub)),
          ],
        ),
      ),
    );
  }
}

String money(double v) => '¥${v.toStringAsFixed(2)}';

String dateLabel(String d) {
  final dt = DateTime.tryParse('${d}T00:00:00');
  if (dt == null) return d;
  return '${dt.year}年${dt.month}月${dt.day}日';
}
