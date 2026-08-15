/// 金币收支记录模型
class CoinRecord {
  final int? id;
  /// 正数=收入,负数=支出
  final int amount;
  final String reason;
  /// task=完成任务 bonus=全部完成奖励 redeem=心愿兑换
  final String type;
  /// 关联的任务 id(取消完成时用于精确收回)
  final int? taskId;
  /// 记录日期 yyyy-MM-dd(用于每日上限统计)
  final String date;
  final int createdAt;

  const CoinRecord({
    this.id,
    required this.amount,
    required this.reason,
    required this.type,
    this.taskId,
    required this.date,
    required this.createdAt,
  });

  factory CoinRecord.fromMap(Map<String, Object?> map) => CoinRecord(
        id: map['id'] as int?,
        amount: map['amount'] as int,
        reason: map['reason'] as String,
        type: map['type'] as String,
        taskId: map['task_id'] as int?,
        date: map['rec_date'] as String,
        createdAt: map['created_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'amount': amount,
        'reason': reason,
        'type': type,
        if (taskId != null) 'task_id': taskId,
        'rec_date': date,
        'created_at': createdAt,
      };
}
