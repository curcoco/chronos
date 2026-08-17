import 'dart:math';

import 'package:flutter/material.dart';

import 'package:student_workbench/core/data/daily_content.dart';
import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/features/tasks/widgets/add_task_sheet.dart' show AddTaskResult;
import 'package:student_workbench/core/widgets/section_card.dart' show categoryColor;

enum _PriorityScheme { user, random }

/// 「随机任务」弹层:从任务池随机取一条加入今日清单(新增,不替换手动流程)。
/// 优先级两种方案可选:「我来自选」或「系统随机」。
class RandomTaskSheet extends StatefulWidget {
  /// 今日已存在的任务标题,随机时尽量避开重复
  final Set<String> excludeTitles;

  const RandomTaskSheet({super.key, this.excludeTitles = const {}});

  @override
  State<RandomTaskSheet> createState() => _RandomTaskSheetState();
}

class _RandomTaskSheetState extends State<RandomTaskSheet> {
  _PriorityScheme _scheme = _PriorityScheme.random; // 默认系统随机
  int _priority = 1; // 我来自选时的默认中
  late ({String title, String category}) _task;

  @override
  void initState() {
    super.initState();
    _task = DailyContent.randomAutoTask(exclude: widget.excludeTitles);
  }

  void _reroll() {
    setState(() {
      _task = DailyContent.randomAutoTask(exclude: widget.excludeTitles);
    });
  }

  void _submit() {
    Navigator.of(context).pop(AddTaskResult(
      title: _task.title,
      category: _task.category,
      priority: _scheme == _PriorityScheme.random
          ? Random().nextInt(3)
          : _priority,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              '随机任务',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              '从任务池随机取一条加入今日清单,不影响每日自动生成的 3 条',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSub),
            ),
          ),
          const SizedBox(height: 16),
          _buildPreview(),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _reroll,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('换一条'),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '优先级方案',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _schemeChip(_PriorityScheme.user, '我来自选', Icons.tune_rounded),
              const SizedBox(width: 10),
              _schemeChip(
                  _PriorityScheme.random, '系统随机', Icons.casino_rounded),
            ],
          ),
          if (_scheme == _PriorityScheme.user) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _priorityChip(0, '高', const Color(0xFFEF5350)),
                const SizedBox(width: 10),
                _priorityChip(1, '中', const Color(0xFFFFA726)),
                const SizedBox(width: 10),
                _priorityChip(2, '低', const Color(0xFF66BB6A)),
              ],
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submit,
            child: const Text('添加到今日清单'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryLight),
      ),
      child: Row(
        children: [
          Icon(Icons.casino_rounded,
              color: AppColors.primaryDark, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _task.title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: categoryColor(_task.category)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _task.category,
                    style: TextStyle(
                      fontSize: 11,
                      color: categoryColor(_task.category),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_scheme == _PriorityScheme.random)
            Text(
              '优先级随机',
              style: TextStyle(fontSize: 11, color: AppColors.textSub),
            ),
        ],
      ),
    );
  }

  Widget _schemeChip(_PriorityScheme value, String label, IconData icon) {
    final selected = _scheme == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _scheme = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryLight.withValues(alpha: 0.5)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.line,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected ? AppColors.primaryDark : AppColors.textSub),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.primaryDark : AppColors.textSub,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _priorityChip(int value, String label, Color color) {
    final selected = _priority == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _priority = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.14) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : AppColors.line,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? color : AppColors.textSub,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
