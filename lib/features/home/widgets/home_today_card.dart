import 'package:flutter/material.dart';

import 'package:chronos/features/tasks/models/student_task.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/widgets/section_card.dart';

/// 首页今日任务卡:进度条 + 任务清单。
/// 固定展示至多 3 条;溢出时卡片内部可上滑查看全部。
class HomeTodayCard extends StatelessWidget {
  final List<StudentTask> tasks;
  final VoidCallback? onGoPlan;

  /// 点击未完成任务(完成确认);已完成任务不支持任何操作(为 null)。
  final ValueChanged<StudentTask> onToggleTask;

  const HomeTodayCard({
    super.key,
    required this.tasks,
    required this.onToggleTask,
    this.onGoPlan,
  });

  int get _doneCount => tasks.where((t) => t.done).length;

  @override
  Widget build(BuildContext context) {
    final total = tasks.length;
    final done = _doneCount;
    final progress = total == 0 ? 0.0 : done / total;
    return SectionCard(
      title: '今日任务',
      trailing: TextButton(
        onPressed: onGoPlan,
        child: Text('查看全部 ›',
            style: TextStyle(fontSize: 13, color: AppColors.primaryDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '已完成 $done/$total',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.line,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          if (total == 0)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('今天还没有任务,去计划中心添加吧~',
                  style: TextStyle(color: AppColors.textSub)),
            )
          else ...[
            // 固定展示至多 3 条;溢出时卡片内部可上滑查看全部。
            if (tasks.length > 3)
              SizedBox(
                height: 120, // 3 行高度,溢出部分卡片内上滑查看
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [for (final task in tasks) _taskTile(task)],
                ),
              )
            else
              for (final task in tasks) _taskTile(task),
            if (done == total)
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('今日任务全部完成,太棒了!',
                    style: TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _taskTile(StudentTask task) {
    // 已完成的任务不支持任何操作:整行不可点击。
    return InkWell(
      onTap: task.done ? null : () => onToggleTask(task),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(
              task.done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: task.done ? AppColors.primary : const Color(0xFFB9CBD9),
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                task.title,
                style: TextStyle(
                  fontSize: 15,
                  color: task.done ? AppColors.textSub : AppColors.textMain,
                  decoration: task.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: categoryColor(task.category).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                task.category,
                style: TextStyle(
                  fontSize: 11,
                  color: categoryColor(task.category),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
