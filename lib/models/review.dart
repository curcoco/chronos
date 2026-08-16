/// 每日复盘记录
class Review {
  final int? id;
  /// 日期 yyyy-MM-dd(每天一条,upsert)
  final String date;
  /// 完成度 0-100
  final int progress;
  final String done;
  final String problem;
  final String plan;
  final int createdAt;

  const Review({
    this.id,
    required this.date,
    required this.progress,
    required this.done,
    required this.problem,
    required this.plan,
    required this.createdAt,
  });

  factory Review.fromMap(Map<String, Object?> map) => Review(
        id: map['id'] as int?,
        date: map['review_date'] as String,
        progress: map['progress'] as int,
        done: map['done'] as String,
        problem: map['problem'] as String,
        plan: map['plan'] as String,
        createdAt: map['created_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'review_date': date,
        'progress': progress,
        'done': done,
        'problem': problem,
        'plan': plan,
        'created_at': createdAt,
      };
}
