import 'package:flutter/material.dart';

import 'package:student_workbench/features/tasks/models/plan_item.dart';
import 'package:student_workbench/features/tasks/models/student_task.dart';
import 'package:student_workbench/features/tasks/services/task_service.dart';
import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/core/utils/dates.dart';
import 'package:student_workbench/features/tasks/widgets/add_task_sheet.dart';
import 'package:student_workbench/core/widgets/confirm_dialog.dart';
import 'package:student_workbench/core/widgets/frosted_snack.dart';
import 'package:student_workbench/features/tasks/widgets/plan_list_view.dart';
import 'package:student_workbench/features/tasks/widgets/random_task_sheet.dart';
import 'package:student_workbench/core/widgets/section_card.dart';
import 'package:student_workbench/features/tasks/widgets/task_confirm_dialog.dart';

/// 每日计划任务中心:今日清单 + 本周计划 + 长期目标(均可交互)
class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  final TaskService _taskService = TaskService();

  bool _loading = true;
  List<StudentTask> _tasks = [];

  int get _doneCount => _tasks.where((t) => t.done).length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await _taskService.todayTasks(todayStr());
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  Future<void> _addTask() async {
    final result = await showModalBottomSheet<AddTaskResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const AddTaskSheet(),
    );
    if (result == null || !mounted) return;
    await _taskService.addTask(
      title: result.title,
      category: result.category,
      priority: result.priority,
      date: todayStr(),
    );
    await _load();
  }

  /// 随机任务:新增一条,不影响手动添加流程与每日自动生成的 3 条
  Future<void> _addRandomTask() async {
    final result = await showModalBottomSheet<AddTaskResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) =>
          RandomTaskSheet(excludeTitles: _tasks.map((t) => t.title).toSet()),
    );
    if (result == null || !mounted) return;
    await _taskService.addTask(
      title: result.title,
      category: result.category,
      priority: result.priority,
      date: todayStr(),
      auto: true,
    );
    await _load();
    _showSnack('已添加随机任务');
  }

  Future<void> _toggleTask(StudentTask task) async {
    final ok = await confirmTaskToggle(context, task, todayStr());
    if (!ok || !mounted) return;
    final r = await _taskService.toggleTask(task, todayStr());
    await _load();
    if (r.total != 0) {
      _showSnack(r.total > 0
          ? '金币 +${r.total}${r.bonus > 0 ? '(含全部完成奖励)' : ''}'
          : '已收回金币 ${-r.total}');
    }
  }

  /// 取消任务:从今日清单移除(不再展示)。已完成的任务不支持任何操作,
  /// 因此这里只处理未完成任务。取消后不保留历史记录。
  Future<void> _confirmCancelTask(StudentTask task) async {
    final ok = await showConfirmDialog(
      context,
      title: '取消该任务?',
      message: '「${task.title}」将从今日清单移除,不再展示。',
      confirmText: '取消任务',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _taskService.deleteTask(task.id!);
    await _load();
    _showSnack('已取消该任务');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '计划中心',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMain,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: Icon(Icons.menu_rounded,
                      size: 22, color: AppColors.textSub),
                  tooltip: '菜单',
                ),
              ],
            ),
          ),
          DefaultTabController(
            length: 3,
            child: Expanded(
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: '今日清单'),
                      Tab(text: '本周计划'),
                      Tab(text: '长期目标'),
                    ],
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : TabBarView(
                            children: [
                              _buildTodayList(),
                              const PlanListView(
                                scope: PlanItem.scopeWeek,
                                title: '本周计划',
                                icon: Icons.calendar_month_rounded,
                                hint: '把本周想推进的事列出来,完成后勾选',
                                emptyText: '本周还没有计划\n点上方按钮添加第一条',
                              ),
                              const PlanListView(
                                scope: PlanItem.scopeLongTerm,
                                title: '长期目标',
                                icon: Icons.flag_rounded,
                                hint: '记录更长远的目标,拆成可执行的小步',
                                emptyText: '还没有长期目标\n点上方按钮立个小目标吧',
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayList() {
    final total = _tasks.length;
    final done = _doneCount;
    final progress = total == 0 ? 0.0 : done / total;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        SectionCard(
          title: '今日进度',
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
              const SizedBox(height: 10),
              Text(
                '完成单个任务 +1 金币,全部完成额外 +3 金币(每日最多 10 枚)',
                style: TextStyle(fontSize: 12, color: AppColors.textSub),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: _addTask,
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加今日任务'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: AppColors.primaryDark,
            side: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.5),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: _addRandomTask,
          icon: const Icon(Icons.casino_rounded, size: 20),
          label: const Text('随机任务'),
        ),
        const SizedBox(height: 14),
        if (total == 0)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text('今天还没有任务,点上方按钮添加吧~',
                  style: TextStyle(color: AppColors.textSub)),
            ),
          )
        else
          for (final task in _tasks) _taskTile(task),
        if (total > 0 && done == total)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Center(
              child: Text('今日任务全部完成!',
                  style: TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }

  Widget _taskTile(StudentTask task) {
    // 已完成的任务不支持任何操作:勾选禁用、不显示取消按钮。
    final completed = task.done;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
        child: Row(
          children: [
            Checkbox(
              value: task.done,
              activeColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5)),
              // 已完成 → 禁用,不可取消完成
              onChanged: completed ? null : (_) => _toggleTask(task),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color:
                          task.done ? AppColors.textSub : AppColors.textMain,
                      decoration: task.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              categoryColor(task.category).withValues(alpha: 0.12),
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
                      const SizedBox(width: 6),
                      PriorityTag(priority: task.priority),
                      if (task.auto) ...[
                        const SizedBox(width: 6),
                        Text(
                          '自动生成',
                          style: TextStyle(
                              fontSize: 10, color: AppColors.textSub),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (!completed)
              IconButton(
                onPressed: () => _confirmCancelTask(task),
                icon: Icon(Icons.close_rounded,
                    size: 20, color: AppColors.textSub),
                tooltip: '取消任务',
              ),
          ],
        ),
      ),
    );
  }
}
