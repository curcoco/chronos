/// 英文收藏条目
class EnglishFav {
  final int? id;
  /// quote / word / read / write
  final String type;
  final String title;
  final String content;
  final int createdAt;

  const EnglishFav({
    this.id,
    required this.type,
    required this.title,
    required this.content,
    required this.createdAt,
  });

  factory EnglishFav.fromMap(Map<String, Object?> map) => EnglishFav(
        id: map['id'] as int?,
        type: map['fav_type'] as String,
        title: map['title'] as String,
        content: map['content'] as String,
        createdAt: map['created_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'fav_type': type,
        'title': title,
        'content': content,
        'created_at': createdAt,
      };
}
