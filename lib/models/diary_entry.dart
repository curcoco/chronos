/// 日记条目(按天一篇,可长文本)
class DiaryEntry {
  final int? id;
  final String content;
  /// happy=开心 calm=平静 sad=难过,null=无
  final String? mood;
  /// 日期 yyyy-MM-dd
  final String date;
  final int createdAt;
  final int updatedAt;

  const DiaryEntry({
    this.id,
    required this.content,
    this.mood,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DiaryEntry.fromMap(Map<String, Object?> map) => DiaryEntry(
        id: map['id'] as int?,
        content: map['content'] as String,
        mood: map['mood'] as String?,
        date: map['entry_date'] as String,
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'content': content,
        if (mood != null) 'mood': mood,
        'entry_date': date,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
