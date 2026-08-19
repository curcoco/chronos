import 'package:flutter/material.dart';

import 'package:student_workbench/features/health/models/kitchen_item.dart';
import 'package:student_workbench/features/health/models/user_video.dart';
import 'package:student_workbench/features/health/models/workout.dart';
import 'package:student_workbench/features/health/services/health_service.dart';
import 'package:student_workbench/features/health/widgets/health_heat_tab.dart';
import 'package:student_workbench/features/health/widgets/health_kitchen_tab.dart';
import 'package:student_workbench/features/health/widgets/health_video_tab.dart';
import 'package:student_workbench/features/health/widgets/health_workout_tab.dart';

/// 健康管理:厨房秘籍 / 运动记录 / 视频跟练(含用户自传视频)/ 运动日历。
/// (智能食谱已舍弃,原 5 Tab 减为 4。)
/// 各 Tab 内容拆到 widgets/health/ 下的独立组件,本页只负责
/// 数据加载、状态共享与 TabBar 组装。
class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  final HealthService _service = HealthService();

  List<KitchenItem> _kitchen = [];
  List<Workout> _workouts = [];
  List<UserVideo> _videos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _service.kitchenItems(),
      _service.workouts(),
      _service.userVideos(),
    ]);
    if (!mounted) return;
    setState(() {
      _kitchen = results[0] as List<KitchenItem>;
      _workouts = results[1] as List<Workout>;
      _videos = results[2] as List<UserVideo>;
      _loading = false;
    });
  }

  /// 各 Tab 增删/保存数据后统一刷新。
  Future<void> _reload() => _load();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('健康管理'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '厨房秘籍'),
              Tab(text: '运动记录'),
              Tab(text: '视频跟练'),
              Tab(text: '运动日历'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  HealthKitchenTab(
                    service: _service,
                    items: _kitchen,
                    onChanged: _reload,
                  ),
                  HealthWorkoutTab(
                    service: _service,
                    workouts: _workouts,
                    onChanged: _reload,
                  ),
                  HealthVideoTab(
                    service: _service,
                    videos: _videos,
                    onChanged: _reload,
                  ),
                  HealthHeatTab(workouts: _workouts),
                ],
              ),
      ),
    );
  }
}
