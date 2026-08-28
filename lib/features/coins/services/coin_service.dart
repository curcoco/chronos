import 'package:sqflite/sqflite.dart';

import 'package:chronos/features/coins/models/coin_record.dart';
import 'package:chronos/features/tasks/models/student_task.dart';
import 'package:chronos/features/coins/models/wish.dart';
import 'package:chronos/core/services/db_helper.dart';

/// 兑换冲突信号:心愿已在事务之外被标记为已兑换(并发/重复兑换)。
/// 仅用于 [CoinService.redeemWish] 内部「抛异常回滚扣款,外层转 false」。
class _RedeemConflict implements Exception {
  const _RedeemConflict();
}

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

  /// 纯函数:在每日上限约束下,计算实际应发放的金币数。
  /// [earned] 当日已赚,[amount] 本次拟发放。返回值 = min(amount, 剩余额度) 且不为负。
  /// 抽出为静态纯函数便于单元测试(奖励发放的核心不变量)。
  static int grantable({
    required int earned,
    required int amount,
    int cap = dailyCap,
  }) {
    final remaining = cap - earned;
    if (remaining <= 0 || amount <= 0) return 0;
    return remaining < amount ? remaining : amount;
  }

  /// 余额;调用方可传事务 [executor] 使查询并入同一事务(如兑换校验)。
  Future<int> balance({DatabaseExecutor? executor}) async {
    final db = executor ?? await _db.database;
    final v = Sqflite.firstIntValue(await db
        .rawQuery('SELECT COALESCE(SUM(amount), 0) FROM coin_records'));
    return v ?? 0;
  }

  /// 当日已赚金币(只统计正数)
  Future<int> earnedToday(String date, {DatabaseExecutor? executor}) async {
    final db = executor ?? await _db.database;
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
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _db.database;
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
  /// 授予量不超过剩余额度,避免超额(如剩 0/1 枚时只发 0/1)。
  /// 「查额度 + 发放」在事务内执行;传入 [executor](如外层事务)时并入其中。
  Future<int> rewardTask(StudentTask task, String date,
      {DatabaseExecutor? executor}) async {
    if (executor != null) {
      return _rewardTaskInner(executor, task, date);
    }
    final db = await _db.database;
    return db.transaction((txn) => _rewardTaskInner(txn, task, date));
  }

  Future<int> _rewardTaskInner(
      DatabaseExecutor db, StudentTask task, String date) async {
    final grant = grantable(
      earned: await earnedToday(date, executor: db),
      amount: taskReward,
    );
    if (grant <= 0) return 0;
    await addRecord(
      amount: grant,
      reason: '完成今日任务:${task.title}',
      type: 'task',
      date: date,
      taskId: task.id,
      executor: db,
    );
    return grant;
  }

  /// 当日全部任务完成奖励(每天仅一次),返回实际获得金币数
  /// 「查重 + 发放」在同一事务内:并发/连点不会重复发 bonus。
  Future<int> rewardAllDone(String date, {DatabaseExecutor? executor}) async {
    if (executor != null) {
      return _rewardAllDoneInner(executor, date);
    }
    final db = await _db.database;
    return db.transaction((txn) => _rewardAllDoneInner(txn, date));
  }

  Future<int> _rewardAllDoneInner(DatabaseExecutor db, String date) async {
    final exists = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM coin_records WHERE rec_date = ? AND type = 'bonus'",
            [date])) ??
        0;
    if (exists > 0) return 0;

    final grant = grantable(
      earned: await earnedToday(date, executor: db),
      amount: bonusReward,
    );
    if (grant <= 0) return 0;

    await addRecord(
      amount: grant,
      reason: '今日任务全部完成奖励',
      type: 'bonus',
      date: date,
      executor: db,
    );
    return grant;
  }

  /// 兑换心愿:扣金币并标记已兑换;余额不足/已兑换返回 false。
  /// 余额检查、扣款、标记「已兑换」在同一个事务里:并发/重复兑换不会超扣,
  /// 也不会出现「币已扣但心愿未标记」的跨表不一致。
  Future<bool> redeemWish(Wish wish, String date) async {
    if (wish.redeemed) return false;
    final db = await _db.database;
    try {
      return await db.transaction<bool>((txn) async {
        final bal = Sqflite.firstIntValue(await txn.rawQuery(
                'SELECT COALESCE(SUM(amount), 0) FROM coin_records')) ??
            0;
        if (bal < wish.cost) return false;
        await txn.insert('coin_records', CoinRecord(
          amount: -wish.cost,
          reason: '兑换心愿:${wish.title}',
          type: 'redeem',
          taskId: null,
          date: date,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ).toMap());
        // 心愿已在本事务之外被兑换(竞态):抛异常回滚扣款,外层转 false。
        final updated = await txn.update('wishes', {'redeemed': 1},
            where: 'id = ? AND redeemed = 0', whereArgs: [wish.id]);
        if (updated == 0) throw const _RedeemConflict();
        return true;
      });
    } on _RedeemConflict {
      return false;
    }
  }

  /// 取消完成任务:删除该任务当日已获得的完成奖励记录,返回收回数量
  /// (旧版本记录无 task_id,按 reason 兜底匹配)
  Future<int> revokeTask(StudentTask task, String date,
      {DatabaseExecutor? executor}) async {
    final db = executor ?? await _db.database;
    final deleted = await db.delete(
      'coin_records',
      where: "rec_date = ? AND type = 'task' AND "
          "(task_id = ? OR (task_id IS NULL AND reason = ?))",
      whereArgs: [date, task.id, '完成今日任务:${task.title}'],
    );
    return deleted > 0 ? taskReward : 0;
  }

  /// 收回当日全部完成奖励(取消勾选破坏全完成状态时调用),返回收回数量。
  /// 逐条删除在同一个事务内:失败整体回滚,不会只收回一半。
  Future<int> revokeAllDone(String date, {DatabaseExecutor? executor}) async {
    if (executor != null) {
      return _revokeAllDoneInner(executor, date);
    }
    final db = await _db.database;
    return db.transaction((txn) => _revokeAllDoneInner(txn, date));
  }

  Future<int> _revokeAllDoneInner(DatabaseExecutor db, String date) async {
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

  /// 当日某类型已获得金币(0 或正数;用于判断当日是否已打卡)
  Future<int> earnedOfType(String date, String type) async {
    final db = await _db.database;
    final v = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COALESCE(SUM(amount),0) FROM coin_records WHERE rec_date = ? AND type = ?',
            [date, type])) ??
        0;
    return v;
  }

  /// 每日打卡奖励(英文/记账/运动/视频等),每天每类一次,受每日上限约束。
  /// 授予量限制在剩余额度内:如已赚 9 枚、打卡 +2 时,只发 1 枚(不会超 10)。
  /// 「查重 + 发放」在同一事务内:并发/连点不会重复发放。
  Future<int> rewardDaily({
    required String type,
    required String reason,
    required int amount,
    required String date,
    DatabaseExecutor? executor,
  }) async {
    if (executor != null) {
      return _rewardDailyInner(executor,
          type: type, reason: reason, amount: amount, date: date);
    }
    final db = await _db.database;
    return db.transaction((txn) => _rewardDailyInner(txn,
        type: type, reason: reason, amount: amount, date: date));
  }

  Future<int> _rewardDailyInner(
    DatabaseExecutor db, {
    required String type,
    required String reason,
    required int amount,
    required String date,
  }) async {
    final exists = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM coin_records WHERE rec_date = ? AND type = ?',
            [date, type])) ??
        0;
    if (exists > 0) return 0;
    final grant = grantable(
      earned: await earnedToday(date, executor: db),
      amount: amount,
    );
    if (grant <= 0) return 0;
    await addRecord(amount: grant, reason: reason, type: type, date: date, executor: db);
    return grant;
  }

  /// 英文学习打卡奖励(每日一次)
  Future<int> rewardEnglish(String date) => rewardDaily(
      type: 'english', reason: '英文学习打卡', amount: 2, date: date);

  /// 记账打卡奖励(每日一次)
  Future<int> rewardLedgerCheckin(String date) =>
      rewardDaily(type: 'ledger', reason: '记账打卡', amount: 1, date: date);

  /// 运动打卡奖励(每日一次)
  Future<int> rewardWorkout(String date) =>
      rewardDaily(type: 'workout', reason: '运动打卡', amount: 1, date: date);

  /// 视频跟练打卡奖励(每日一次)
  Future<int> rewardVideo(String date) =>
      rewardDaily(type: 'video', reason: '视频跟练打卡', amount: 1, date: date);

  Future<List<CoinRecord>> records() async {
    final db = await _db.database;
    final rows = await db.query('coin_records', orderBy: 'created_at DESC');
    return rows.map(CoinRecord.fromMap).toList();
  }
}
