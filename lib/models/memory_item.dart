/// AI 长期记忆条目
class MemoryItem {
  final int? id;
  /// profile=画像 fact=事实 summary=摘要
  final String kind;
  final String content;
  /// manual=手动 chat=对话提炼
  final String source;
  /// 是否已同步到云端(Supabase)
  final bool cloudSynced;
  final int createdAt;
  final int updatedAt;

  const MemoryItem({
    this.id,
    required this.kind,
    required this.content,
    required this.source,
    this.cloudSynced = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MemoryItem.fromMap(Map<String, Object?> map) => MemoryItem(
        id: map['id'] as int?,
        kind: map['kind'] as String,
        content: map['content'] as String,
        source: map['source'] as String,
        cloudSynced: (map['cloud_synced'] as int? ?? 0) == 1,
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'kind': kind,
        'content': content,
        'source': source,
        'cloud_synced': cloudSynced ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
