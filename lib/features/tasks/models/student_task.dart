/// 今日任务模型
class StudentTask {
  final int? id;
  final String title;
  final String category;
  /// 优先级:0=高 1=中 2=低
  final int priority;
  final bool done;
  /// 所属日期 yyyy-MM-dd
  final String date;
  /// 是否为按日期自动生成的今日任务
  final bool auto;
  final int createdAt;

  const StudentTask({
    this.id,
    required this.title,
    required this.category,
    required this.priority,
    required this.done,
    required this.date,
    required this.auto,
    required this.createdAt,
  });

  factory StudentTask.fromMap(Map<String, Object?> map) => StudentTask(
        id: map['id'] as int?,
        title: map['title'] as String,
        category: map['category'] as String,
        priority: map['priority'] as int,
        done: (map['done'] as int) == 1,
        date: map['task_date'] as String,
        auto: (map['auto'] as int) == 1,
        createdAt: map['created_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'category': category,
        'priority': priority,
        'done': done ? 1 : 0,
        'task_date': date,
        'auto': auto ? 1 : 0,
        'created_at': createdAt,
      };

  StudentTask copyWith({bool? done}) => StudentTask(
        id: id,
        title: title,
        category: category,
        priority: priority,
        done: done ?? this.done,
        date: date,
        auto: auto,
        createdAt: createdAt,
      );
}
