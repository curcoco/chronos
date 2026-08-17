import 'package:flutter/material.dart';

import '../../data/health_content.dart';
import '../../models/workout.dart';
import '../../services/coin_service.dart';
import '../../services/health_service.dart';
import '../../theme.dart';
import '../../utils/dates.dart';
import '../frosted_snack.dart';
import 'health_common.dart';

/// 健康「运动记录」Tab:添加运动、今日打卡、按日分组展示记录。
class HealthWorkoutTab extends StatefulWidget {
  final HealthService service;
  final List<Workout> workouts;

  /// 添加记录后由父级刷新数据。
  final VoidCallback onChanged;

  const HealthWorkoutTab({
    super.key,
    required this.service,
    required this.workouts,
    required this.onChanged,
  });

  @override
  State<HealthWorkoutTab> createState() => _HealthWorkoutTabState();
}

class _HealthWorkoutTabState extends State<HealthWorkoutTab> {
  final TextEditingController _min = TextEditingController();
  String _type = '跑步';

  @override
  void dispose() {
    _min.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  Future<void> _save() async {
    final min = int.tryParse(_min.text);
    if (min == null || min <= 0) {
      _showSnack('请输入时长');
      return;
    }
    await widget.service.addWorkout(
        type: _type, minutes: min, date: todayStr());
    _min.clear();
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onChanged();
    _showSnack('已记录');
  }

  Future<void> _checkin() async {
    final coin = await CoinService.instance.rewardWorkout(todayStr());
    if (!mounted) return;
    _showSnack(coin > 0 ? '运动打卡成功,金币 +$coin' : '今日已打过卡');
  }

  void _openSheet() {
    _type = '跑步';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
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
              child: Text('添加运动',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (final t in HealthContent.workoutTypes)
                  CatChip(
                    label: t,
                    selected: t == _type,
                    onTap: () => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _min,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '时长(分钟)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '日期:${todayStr()}',
                    style: TextStyle(fontSize: 13, color: AppColors.textSub),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('保存')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Workout>>{};
    final sorted = [...widget.workouts]..sort((a, b) => b.date.compareTo(a.date));
    for (final w in sorted) {
      groups.putIfAbsent(w.date, () => []).add(w);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.card,
            foregroundColor: AppColors.primaryDark,
            side: BorderSide(color: AppColors.primary),
          ),
          onPressed: _openSheet,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('添加运动'),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _checkin,
            child: const Text('今日运动打卡 +1 金币',
                style: TextStyle(fontSize: 12)),
          ),
        ),
        if (groups.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text('还没有运动记录',
                  style: TextStyle(color: AppColors.textSub)),
            ),
          )
        else
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text(
                dateLabel(entry.key),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSub),
              ),
            ),
            for (final w in entry.value)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${w.type}  ${w.minutes} 分钟',
                          style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              ),
          ],
      ],
    );
  }
}
