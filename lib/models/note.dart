/// 灵感速记模型
class Note {
  final int? id;
  final String content;
  final int createdAt;

  const Note({this.id, required this.content, required this.createdAt});

  factory Note.fromMap(Map<String, Object?> map) => Note(
        id: map['id'] as int?,
        content: map['content'] as String,
        createdAt: map['created_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'content': content,
        'created_at': createdAt,
      };
}
