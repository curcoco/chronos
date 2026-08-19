/// 用户自传的跟练视频条目。
class UserVideo {
  final int? id;
  final String title;
  final String path;
  final String note;
  final int createdAt;

  const UserVideo({
    this.id,
    required this.title,
    required this.path,
    required this.note,
    required this.createdAt,
  });

  factory UserVideo.fromMap(Map<String, Object?> map) => UserVideo(
        id: map['id'] as int?,
        title: map['title'] as String,
        path: map['path'] as String,
        note: map['note'] as String,
        createdAt: map['created_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'path': path,
        'note': note,
        'created_at': createdAt,
      };
}
