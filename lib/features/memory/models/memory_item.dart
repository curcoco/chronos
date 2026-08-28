/// AI 长期记忆条目
class MemoryItem {
  final int? id;
  /// profile=画像 fact=事实 summary=摘要
  final String kind;
  final String content;
  /// manual=手动 chat=对话提炼
  final String source;
  /// 历史字段(原 Supabase 云同步标记;列保留兼容旧数据,不再使用)
  final bool cloudSynced;
  final int createdAt;
  final int updatedAt;

  /// 重要性(1~10,默认 5;越高越优先浮现)。
  final int importance;
  /// 置顶:常驻注入(score 视为 999,不参与衰减)。
  final bool pinned;
  /// 最近激活时间(衰减用;null 视为创建时间)。
  final int? lastActivated;
  /// 被检索/激活次数(浮现软饱和:次数越多越稳定,但不会无限放大)。
  final int activationCount;
  /// 是否已解决(已解决记忆衰减更快)。
  final bool resolved;
  /// public=注入+页可见;private=仅存不注入(用户不想让 AI 记住的)。
  final String visibility;
  /// 领域(可选,用于分类展示)。
  final String? domain;
  /// 标签(用于关键字匹配增强)。
  final List<String> tags;

  const MemoryItem({
    this.id,
    required this.kind,
    required this.content,
    required this.source,
    this.cloudSynced = false,
    required this.createdAt,
    required this.updatedAt,
    this.importance = 5,
    this.pinned = false,
    this.lastActivated,
    this.activationCount = 0,
    this.resolved = false,
    this.visibility = 'public',
    this.domain,
    this.tags = const [],
  });

  MemoryItem copyWith({
    String? content,
    int? importance,
    bool? pinned,
    bool? resolved,
    String? visibility,
    String? domain,
    List<String>? tags,
  }) =>
      MemoryItem(
        id: id,
        kind: kind,
        content: content ?? this.content,
        source: source,
        cloudSynced: cloudSynced,
        createdAt: createdAt,
        updatedAt: updatedAt,
        importance: importance ?? this.importance,
        pinned: pinned ?? this.pinned,
        lastActivated: lastActivated,
        activationCount: activationCount,
        resolved: resolved ?? this.resolved,
        visibility: visibility ?? this.visibility,
        domain: domain ?? this.domain,
        tags: tags ?? this.tags,
      );

  factory MemoryItem.fromMap(Map<String, Object?> map) => MemoryItem(
        id: map['id'] as int?,
        kind: map['kind'] as String,
        content: map['content'] as String,
        source: map['source'] as String,
        cloudSynced: (map['cloud_synced'] as int? ?? 0) == 1,
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
        importance: (map['importance'] as int? ?? 5).clamp(1, 10),
        pinned: (map['pinned'] as int? ?? 0) == 1,
        lastActivated: map['last_activated'] as int?,
        activationCount: map['activation_count'] as int? ?? 0,
        resolved: (map['resolved'] as int? ?? 0) == 1,
        visibility: map['visibility'] as String? ?? 'public',
        domain: map['domain'] as String?,
        tags: _decodeTags(map['tags'] as String?),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'kind': kind,
        'content': content,
        'source': source,
        'cloud_synced': cloudSynced ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'importance': importance,
        'pinned': pinned ? 1 : 0,
        if (lastActivated != null) 'last_activated': lastActivated,
        'activation_count': activationCount,
        'resolved': resolved ? 1 : 0,
        'visibility': visibility,
        if (domain != null) 'domain': domain,
        if (tags.isNotEmpty) 'tags': List<String>.from(tags).join('|'),
      };

  static List<String> _decodeTags(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return [for (final t in raw.split('|')) if (t.trim().isNotEmpty) t.trim()];
  }
}
