/// 灵感速记模型(随笔已合并进来,可带心情标记)
class Note {
  final int? id;
  final String content;
  final int createdAt;
  /// 是否收藏(详情页菜单可切换,灵感专区置顶显示)
  final bool favorite;
  /// 心情标记:happy=开心 calm=平静 sad=难过,null=无
  final String? mood;

  const Note({
    this.id,
    required this.content,
    required this.createdAt,
    this.favorite = false,
    this.mood,
  });

  factory Note.fromMap(Map<String, Object?> map) => Note(
        id: map['id'] as int?,
        content: map['content'] as String,
        createdAt: map['created_at'] as int,
        favorite: (map['favorite'] as int? ?? 0) == 1,
        mood: map['mood'] as String?,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'content': content,
        'created_at': createdAt,
        'favorite': favorite ? 1 : 0,
        if (mood != null) 'mood': mood,
      };

  Note copyWith({bool? favorite, String? mood}) => Note(
        id: id,
        content: content,
        createdAt: createdAt,
        favorite: favorite ?? this.favorite,
        mood: mood ?? this.mood,
      );
}
