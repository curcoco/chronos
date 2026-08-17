/// 计划条目:本周计划(scope=week)/ 长期目标(scope=longterm)
class PlanItem {
  final int? id;

  /// week=本周计划 longterm=长期目标
  final String scope;
  final String title;
  final String detail;
  final bool done;

  /// 截止日期(可空;yyyy-MM-dd)
  final String? dueDate;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;

  const PlanItem({
    this.id,
    required this.scope,
    required this.title,
    this.detail = '',
    this.done = false,
    this.dueDate,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  static const String scopeWeek = 'week';
  static const String scopeLongTerm = 'longterm';

  PlanItem copyWith({
    String? title,
    String? detail,
    bool? done,
    String? dueDate,
    int? sortOrder,
    int? updatedAt,
  }) =>
      PlanItem(
        id: id,
        scope: scope,
        title: title ?? this.title,
        detail: detail ?? this.detail,
        done: done ?? this.done,
        dueDate: dueDate ?? this.dueDate,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory PlanItem.fromMap(Map<String, Object?> map) => PlanItem(
        id: map['id'] as int?,
        scope: map['scope'] as String,
        title: map['title'] as String,
        detail: (map['detail'] as String?) ?? '',
        done: (map['done'] as int? ?? 0) == 1,
        dueDate: map['due_date'] as String?,
        sortOrder: map['sort_order'] as int? ?? 0,
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'scope': scope,
        'title': title,
        'detail': detail,
        'done': done ? 1 : 0,
        'due_date': dueDate,
        'sort_order': sortOrder,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
