/// 闲话铺会话(聊天窗口)。
class ChatSession {
  final int? id;
  final String title;
  final int createdAt;
  final int updatedAt;

  const ChatSession({
    this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatSession.fromMap(Map<String, Object?> map) => ChatSession(
        id: map['id'] as int?,
        title: map['title'] as String,
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

/// 会话内消息。
class ChatMessage {
  final int? id;
  final int sessionId;
  final String role; // user / assistant
  final String content;
  final int createdAt;

  const ChatMessage({
    this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessage.fromMap(Map<String, Object?> map) => ChatMessage(
        id: map['id'] as int?,
        sessionId: map['session_id'] as int,
        role: map['role'] as String,
        content: map['content'] as String,
        createdAt: map['created_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'role': role,
        'content': content,
        'created_at': createdAt,
      };
}
