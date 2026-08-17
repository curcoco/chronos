import 'package:flutter/material.dart';

import 'package:student_workbench/features/health/models/workout.dart';
import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/core/utils/dates.dart';
import 'package:student_workbench/features/health/widgets/health_common.dart';

/// 健康「运动日历」Tab:月度热力图 + 运动统计。
class HealthHeatTab extends StatelessWidget {
  final List<Workout> workouts;

  const HealthHeatTab({super.key, required this.workouts});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, 1);
    final days = DateTime(now.year, now.month + 1, 0).day;
    final first = base.weekday % 7; // 0=周日
    final byDay = <String, int>{};
    for (final w in workouts) {
      byDay[w.date] = (byDay[w.date] ?? 0) + w.minutes;
    }
    int total = 0, count = 0;
    final cells = <Widget>[
      for (final w in ['日', '一', '二', '三', '四', '五', '六'])
        Center(
          child: Text(w, style: TextStyle(fontSize: 10, color: AppColors.textSub)),
        ),
      for (var i = 0; i < first; i++) const SizedBox(),
      for (var d = 1; d <= days; d++)
        Builder(builder: (context) {
          final key = dateKey(DateTime(now.year, now.month, d));
          final m = byDay[key] ?? 0;
          if (m > 0) {
            total += m;
            count++;
          }
          final level = m == 0
              ? null
              : m < 20
                  ? const Color(0xFFB3E5FC)
                  : m < 40
                      ? const Color(0xFF4FC3F7)
                      : m < 60
                          ? const Color(0xFF29B6F6)
                          : const Color(0xFF0288D1);
          return Container(
            decoration: BoxDecoration(
              color: level ?? const Color(0xFFE9F0F7),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Center(
              child: Text(
                '$d',
                style: TextStyle(
                  fontSize: 10,
                  color: level == const Color(0xFF0288D1) ||
                          level == const Color(0xFF29B6F6)
                      ? Colors.white
                      : AppColors.textMain,
                ),
              ),
            ),
          );
        }),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
            children: cells,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final c in [
              const Color(0xFFE9F0F7),
              const Color(0xFFB3E5FC),
              const Color(0xFF4FC3F7),
              const Color(0xFF29B6F6),
              const Color(0xFF0288D1),
            ]) ...[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: c, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 4),
            ],
            const SizedBox(width: 8),
            Text('时长越多颜色越深',
                style: TextStyle(fontSize: 10, color: AppColors.textSub)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            MetricCard(value: '$count', label: '运动天数'),
            const SizedBox(width: 10),
            MetricCard(value: '$total', label: '总时长(分)'),
            const SizedBox(width: 10),
            MetricCard(
                value: '${count > 0 ? (total / count).round() : 0}',
                label: '日均(分)'),
          ],
        ),
      ],
    );
  }
}
