import 'package:flutter/material.dart';

import 'package:chronos/features/health/widgets/health_screen_time_tab.dart';

/// 屏幕时间(防沉迷)独立页面。
///
/// 入口在侧边栏「功能模块」区(与健康管理平级),不在健康页内——健康页
/// 回归纯粹的「吃 + 运动」四件事。内容复用 [HealthScreenTimeTab]:权限门 →
/// 今日娱乐/预算卡 → 热力图 → 今日排行 → 分类管理,数据打开时从系统
/// UsageStats 同步(无常驻后台)。
class ScreenTimePage extends StatelessWidget {
  const ScreenTimePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('屏幕时间')),
      body: const HealthScreenTimeTab(),
    );
  }
}
