/// 运动记录
class Workout {
  final int? id;
  final String type;
  final int minutes;
  /// 日期 yyyy-MM-dd
  final String date;
  final int createdAt;

  const Workout({
    this.id,
    required this.type,
    required this.minutes,
    required this.date,
    required this.createdAt,
  });

  factory Workout.fromMap(Map<String, Object?> map) => Workout(
        id: map['id'] as int?,
        type: map['type'] as String,
        minutes: map['minutes'] as int,
        date: map['work_date'] as String,
        createdAt: map['created_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'type': type,
        'minutes': minutes,
        'work_date': date,
        'created_at': createdAt,
      };
}
