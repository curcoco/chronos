import 'dart:async';

import 'package:flutter/material.dart';

import 'package:student_workbench/core/data/health_content.dart';
import 'package:student_workbench/features/coins/services/coin_service.dart';
import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/core/utils/dates.dart';
import 'package:student_workbench/core/widgets/frosted_snack.dart';

/// 健康「视频跟练」Tab:内置计时器 + 跟练列表 + 打卡领金币。
/// 计时器状态在本组件内自持,切换 Tab 不重置(父级 TabBarView 缓存)。
class HealthVideoTab extends StatefulWidget {
  const HealthVideoTab({super.key});

  @override
  State<HealthVideoTab> createState() => _HealthVideoTabState();
}

class _HealthVideoTabState extends State<HealthVideoTab> {
  Timer? _timer;
  int _sec = 0;
  bool _on = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() => setState(() => _sec++);

  void _toggle() {
    setState(() => _on = !_on);
    if (_on) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      _timer?.cancel();
    }
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _on = false;
      _sec = 0;
    });
  }

  Future<void> _checkin() async {
    if (_sec <= 0) {
      showFrostedSnack(context, '先开始计时再打卡吧');
      return;
    }
    final coin = await CoinService.instance.rewardVideo(todayStr());
    if (!mounted) return;
    showFrostedSnack(
      context,
      coin > 0 ? '跟练完成,金币 +$coin(计时 ${_sec ~/ 60} 分钟)' : '今日已打过卡',
    );
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    final mm = (_sec ~/ 60).toString().padLeft(2, '0');
    final ss = (_sec % 60).toString().padLeft(2, '0');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryLight, AppColors.primary],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Text(
                '$mm:$ss',
                style: const TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.card,
                      foregroundColor: AppColors.primaryDark,
                    ),
                    onPressed: _toggle,
                    child: Text(_on ? '暂停' : '开始'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                    ),
                    onPressed: _reset,
                    child: const Text('重置'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                    ),
                    onPressed: _checkin,
                    child: const Text('打卡 +1'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final v in HealthContent.videos)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              children: [
                Icon(Icons.play_circle_outline_rounded,
                    size: 20, color: AppColors.primaryDark),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(v.title, style: const TextStyle(fontSize: 14)),
                ),
                Text('${v.min} 分钟',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textSub)),
              ],
            ),
          ),
      ],
    );
  }
}
