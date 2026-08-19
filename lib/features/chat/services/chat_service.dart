import 'package:student_workbench/core/services/db_helper.dart';
import 'package:student_workbench/features/chat/models/chat_session.dart';

/// 闲话铺会话管理:多会话(聊天窗口)、按会话保存消息。
/// v12 起取消「零点万事清零」,聊天记录长期保存在 SQLite。
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  DbHelper get _db => DbHelper.instance;

  /// 会话列表(最近更新在前)
  Future<List<ChatSession>> sessions() async {
    final db = await _db.database;
    final rows =
        await db.query('chat_sessions', orderBy: 'updated_at DESC');
    return rows.map(ChatSession.fromMap).toList();
  }

  /// 新建会话,返回新会话 id。
  /// [firstMessage] 非空时,会话标题取该消息截断(如「闲聊」)。
  Future<int> createSession({String? firstMessage}) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final title = _titleFrom(firstMessage);
    return db.insert('chat_sessions', ChatSession(
      title: title,
      createdAt: now,
      updatedAt: now,
    ).toMap());
  }

  /// 会话标题:取首条消息前 12 字;没有则「新对话」。
  static String _titleFrom(String? firstMessage) {
    if (firstMessage == null || firstMessage.trim().isEmpty) return '新对话';
    final text = firstMessage.trim().replaceAll('\n', ' ');
    return text.length <= 12 ? text : '${text.substring(0, 12)}…';
  }

  /// 重命名会话
  Future<void> renameSession(int id, String title) async {
    final db = await _db.database;
    await db.update('chat_sessions',
        {'title': title.trim(), 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
  }

  /// 删除会话(连同其消息)
  Future<void> deleteSession(int id) async {
    final db = await _db.database;
    await db.delete('chat_messages', where: 'session_id = ?', whereArgs: [id]);
    await db.delete('chat_sessions', where: 'id = ?', whereArgs: [id]);
  }

  /// 某会话的消息(按时间正序)
  Future<List<ChatMessage>> messages(int sessionId) async {
    final db = await _db.database;
    final rows = await db.query('chat_messages',
        where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'created_at ASC');
    return rows.map(ChatMessage.fromMap).toList();
  }

  /// 追加一条消息,返回新消息 id
  Future<int> addMessage({
    required int sessionId,
    required String role,
    required String content,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('chat_messages', ChatMessage(
      sessionId: sessionId,
      role: role,
      content: content,
      createdAt: now,
    ).toMap());
    await db.update('chat_sessions', {'updated_at': now},
        where: 'id = ?', whereArgs: [sessionId]);
    return id;
  }
}
