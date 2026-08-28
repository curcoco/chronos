import 'package:flutter/material.dart';

import 'package:chronos/features/tasks/models/student_task.dart';
import 'package:chronos/features/coins/services/coin_service.dart';

/// 勾选 / 取消勾选任务前的确认弹窗。返回 true 表示用户确认执行。
/// - 完成:提示可领取的金币;若已到每日上限则提示不再得币。
/// - 取消完成:精确提示将收回的任务奖励与全部完成奖励。
Future<bool> confirmTaskToggle(
  BuildContext context,
  StudentTask task,
  String date,
) async {
  final isComplete = !task.done;
  String message;
  if (isComplete) {
    final capped =
        await CoinService.instance.earnedToday(date) >= CoinService.dailyCap;
    message = '「${task.title}」\n'
        '完成可领取 +${CoinService.taskReward} 金币。'
        '${capped ? '\n(今日已达每日上限,完成不再获得金币)' : ''}';
  } else {
    final taskReward =
        await CoinService.instance.taskRewardEarned(task, date);
    final bonus = await CoinService.instance.bonusEarned(date);
    final parts = <String>[
      if (taskReward > 0) '任务奖励 $taskReward 枚',
      if (bonus > 0) '全部完成奖励 $bonus 枚',
    ];
    message = '「${task.title}」\n'
        '取消完成将收回:${parts.isEmpty ? '无可收回的金币' : parts.join('、')}。';
  }

  if (!context.mounted) return false;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(isComplete ? '确认完成?' : '确认取消完成?'),
      content: Text(message, style: const TextStyle(height: 1.6)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('再想想'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(isComplete ? '确认完成' : '确认取消'),
        ),
      ],
    ),
  );
  return result ?? false;
}
