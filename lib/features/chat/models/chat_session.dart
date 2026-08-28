/// 闲话铺会话(聊天窗口)。
class ChatSession {
  final int? id;
  final String title;
  /// 所属会话文件夹 id(v17 起;null = 未归档)。
  final int? folderId;
  final int createdAt;
  final int updatedAt;

  const ChatSession({
    this.id,
    required this.title,
    this.folderId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatSession.fromMap(Map<String, Object?> map) => ChatSession(
        id: map['id'] as int?,
        title: map['title'] as String,
        folderId: map['folder_id'] as int?,
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        if (folderId != null) 'folder_id': folderId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

/// 会话文件夹(给会话分组用;v17 起)。
class SessionFolder {
  final int? id;
  final String name;
  final int createdAt;

  const SessionFolder({this.id, required this.name, required this.createdAt});

  factory SessionFolder.fromMap(Map<String, Object?> map) => SessionFolder(
        id: map['id'] as int?,
        name: map['name'] as String,
        createdAt: map['created_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'created_at': createdAt,
      };
}

/// 会话内消息。
class ChatMessage {
  final int? id;
  final int sessionId;
  final String role; // user / assistant
  final String content;

  /// 图片本地路径(v14 起持久化;旧消息为 null)。用户消息可能有,AI 消息恒为 null。
  final String? imagePath;

  /// 推理模型的思维链(v15 起持久化;旧消息为 null)。
  /// DeepSeek 等推理模型要求多轮对话时把上一轮 reasoning_content 原样带回。
  final String? reasoningContent;
  final int createdAt;

  const ChatMessage({
    this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    this.imagePath,
    this.reasoningContent,
    required this.createdAt,
  });

  factory ChatMessage.fromMap(Map<String, Object?> map) => ChatMessage(
        id: map['id'] as int?,
        sessionId: map['session_id'] as int,
        role: map['role'] as String,
        content: map['content'] as String,
        imagePath: map['image_path'] as String?,
        reasoningContent: map['reasoning_content'] as String?,
        createdAt: map['created_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'role': role,
        'content': content,
        if (imagePath != null) 'image_path': imagePath,
        if (reasoningContent != null) 'reasoning_content': reasoningContent,
        'created_at': createdAt,
      };
}
