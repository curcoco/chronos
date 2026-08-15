import 'package:sqflite/sqflite.dart';

import '../data/daily_content.dart';
import '../models/student_task.dart';
import 'coin_service.dart';
import 'db_helper.dart';

/// 任务切换结果
class ToggleResult {
  final int coin;
  final int bonus;
  const ToggleResult({required this.coin, required this.bonus});
  int get total => coin + bonus;
}

/// 每日计划任务中心服务
class TaskService {
  TaskService();
  DbHelper get _db => DbHelper.instance;

  static void sortTasks(List<StudentTask> tasks) {
    tasks.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1; // 未完成在前
      if (a.priority != b.priority) return a.priority.compareTo(b.priority); // 高优先级在前
      return a.createdAt.compareTo(b.createdAt);
    });
  }

  /// 取某日任务;若当日尚无任何任务,按日期自动生成 3 条
  Future<List<StudentTask>> todayTasks(String date) async {
    await ensureDailyTasks(date);
    final db = await _db.database;
    final rows = await db.query('tasks',
        where: 'task_date = ?', whereArgs: [date]);
    final tasks = rows.map(StudentTask.fromMap).toList();
    sortTasks(tasks);
    return tasks;
  }

  Future<void> ensureDailyTasks(String date) async {
    final db = await _db.database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM tasks WHERE task_date = ?', [date])) ??
        0;
    if (count > 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final t in DailyContent.autoTasksFor(date)) {
      await db.insert('tasks', StudentTask(
        title: t.title,
        category: t.category,
        priority: 1, // 默认中优先级
        done: false,
        date: date,
        auto: true,
        createdAt: now,
      ).toMap());
    }
  }

  Future<StudentTask> addTask({
    required String title,
    required String category,
    required int priority,
    required String date,
    bool auto = false,
  }) async {
    final db = await _db.database;
    final id = await db.insert('tasks', StudentTask(
      title: title,
      category: category,
      priority: priority,
      done: false,
      date: date,
      auto: auto,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ).toMap());
    return StudentTask(
      id: id,
      title: title,
      category: category,
      priority: priority,
      done: false,
      date: date,
      auto: auto,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> deleteTask(int id) async {
    final db = await _db.database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  /// 勾选/取消勾选任务;勾选时发金币并检查全部完成奖励,
  /// 取消勾选时收回对应金币(任务奖励 + 全部完成奖励)。
  /// 返回值为正=获得,负=收回。
  Future<ToggleResult> toggleTask(StudentTask task, String date) async {
    final db = await _db.database;
    if (task.done) {
      // 取消完成:收回该任务奖励;若当日不再全部完成,再收回全部完成奖励
      await db.update('tasks', {'done': 0},
          where: 'id = ?', whereArgs: [task.id]);
      final revokedTask = await CoinService.instance.revokeTask(task, date);
      final revokedBonus = await CoinService.instance.revokeAllDone(date);
      return ToggleResult(coin: -revokedTask, bonus: -revokedBonus);
    }
    await db.update('tasks', {'done': 1},
        where: 'id = ?', whereArgs: [task.id]);

    final coin = await CoinService.instance.rewardTask(task, date);
    var bonus = 0;
    if (await isAllDone(date)) {
      bonus = await CoinService.instance.rewardAllDone(date);
    }
    return ToggleResult(coin: coin, bonus: bonus);
  }

  Future<bool> isAllDone(String date) async {
    final db = await _db.database;
    final total = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM tasks WHERE task_date = ?', [date])) ??
        0;
    if (total == 0) return false;
    final done = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM tasks WHERE task_date = ? AND done = 1',
            [date])) ??
        0;
    return done == total;
  }
}
