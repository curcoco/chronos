import 'package:sqflite/sqflite.dart';

import '../models/coin_record.dart';
import '../models/student_task.dart';
import '../models/wish.dart';
import 'db_helper.dart';

/// 金币激励系统:赚币(带每日上限)、消费、余额、收支历史
class CoinService {
  CoinService._();
  static final CoinService instance = CoinService._();

  /// 每日赚币上限
  static const int dailyCap = 10;
  /// 完成单个任务奖励
  static const int taskReward = 1;
  /// 当日全部任务完成奖励
  static const int bonusReward = 3;

  DbHelper get _db => DbHelper.instance;

  Future<int> balance() async {
    final db = await _db.database;
    final v = Sqflite.firstIntValue(await db
        .rawQuery('SELECT COALESCE(SUM(amount), 0) FROM coin_records'));
    return v ?? 0;
  }

  /// 当日已赚金币(只统计正数)
  Future<int> earnedToday(String date) async {
    final db = await _db.database;
    final v = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) FROM coin_records WHERE rec_date = ? AND amount > 0',
        [date]));
    return v ?? 0;
  }

  Future<void> addRecord({
    required int amount,
    required String reason,
    required String type,
    required String date,
    int? taskId,
  }) async {
    final db = await _db.database;
    await db.insert('coin_records', CoinRecord(
      amount: amount,
      reason: reason,
      type: type,
      taskId: taskId,
      date: date,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ).toMap());
  }

  /// 完成任务奖励,受每日上限约束;返回实际获得金币数
  Future<int> rewardTask(StudentTask task, String date) async {
    if (await earnedToday(date) >= dailyCap) return 0;
    await addRecord(
      amount: taskReward,
      reason: '完成今日任务:${task.title}',
      type: 'task',
      date: date,
      taskId: task.id,
    );
    return taskReward;
  }

  /// 当日全部任务完成奖励(每天仅一次),返回实际获得金币数
  Future<int> rewardAllDone(String date) async {
    final db = await _db.database;
    final exists = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM coin_records WHERE rec_date = ? AND type = 'bonus'",
        [date])) ??
        0;
    if (exists > 0) return 0;

    final earned = await earnedToday(date);
    final remaining = dailyCap - earned;
    if (remaining <= 0) return 0;
    final grant = remaining < bonusReward ? remaining : bonusReward;
    if (grant <= 0) return 0;

    await addRecord(
      amount: grant,
      reason: '今日任务全部完成奖励',
      type: 'bonus',
      date: date,
    );
    return grant;
  }

  /// 兑换心愿:扣金币并标记已兑换;余额不足返回 false
  Future<bool> redeemWish(Wish wish, String date) async {
    if (wish.redeemed) return false;
    if (await balance() < wish.cost) return false;

    await addRecord(
      amount: -wish.cost,
      reason: '兑换心愿:${wish.title}',
      type: 'redeem',
      date: date,
    );
    final db = await _db.database;
    await db.update('wishes', {'redeemed': 1},
        where: 'id = ?', whereArgs: [wish.id]);
    return true;
  }

  /// 取消完成任务:删除该任务当日已获得的完成奖励记录,返回收回数量
  /// (旧版本记录无 task_id,按 reason 兜底匹配)
  Future<int> revokeTask(StudentTask task, String date) async {
    final db = await _db.database;
    final deleted = await db.delete(
      'coin_records',
      where: "rec_date = ? AND type = 'task' AND "
          "(task_id = ? OR (task_id IS NULL AND reason = ?))",
      whereArgs: [date, task.id, '完成今日任务:${task.title}'],
    );
    return deleted > 0 ? taskReward : 0;
  }

  /// 收回当日全部完成奖励(取消勾选破坏全完成状态时调用),返回收回数量
  Future<int> revokeAllDone(String date) async {
    final db = await _db.database;
    final rows = await db.query('coin_records',
        where: "rec_date = ? AND type = 'bonus'", whereArgs: [date]);
    var revoked = 0;
    for (final row in rows) {
      revoked += CoinRecord.fromMap(row).amount;
      await db.delete('coin_records', where: 'id = ?', whereArgs: [row['id']]);
    }
    return revoked;
  }

  /// 该任务当日已获得的完成奖励(用于取消弹窗提示收回数额)
  Future<int> taskRewardEarned(StudentTask task, String date) async {
    final db = await _db.database;
    final v = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COALESCE(SUM(amount),0) FROM coin_records WHERE rec_date = ? AND type = 'task' AND (task_id = ? OR (task_id IS NULL AND reason = ?))",
      [date, task.id, '完成今日任务:${task.title}'],
    ));
    return v ?? 0;
  }

  /// 当日全部完成奖励数额(用于取消弹窗提示收回数额)
  Future<int> bonusEarned(String date) async {
    final db = await _db.database;
    final v = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COALESCE(SUM(amount),0) FROM coin_records WHERE rec_date = ? AND type = 'bonus'",
      [date],
    ));
    return v ?? 0;
  }

  Future<List<CoinRecord>> records() async {
    final db = await _db.database;
    final rows = await db.query('coin_records', orderBy: 'created_at DESC');
    return rows.map(CoinRecord.fromMap).toList();
  }
}
