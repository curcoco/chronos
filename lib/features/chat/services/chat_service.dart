import 'package:characters/characters.dart';
import 'package:sqflite/sqflite.dart';

import 'package:chronos/core/services/db_helper.dart';
import 'package:chronos/features/chat/models/chat_session.dart';

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

  /// 会话标题:取首条消息前 12 个字符(按 grapheme,emoji/ZWJ 序列不会被切半)。
  static String _titleFrom(String? firstMessage) {
    if (firstMessage == null || firstMessage.trim().isEmpty) return '新对话';
    final text = firstMessage.trim().replaceAll('\n', ' ');
    final chars = text.characters;
    return chars.length <= 12 ? text : '${chars.take(12)}…';
  }

  /// 重命名会话
  Future<void> renameSession(int id, String title) async {
    final db = await _db.database;
    await db.update('chat_sessions',
        {'title': title.trim(), 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
  }

  /// 删除会话(连同其消息);两步删除在同一事务内,中途失败不留孤儿消息。
  Future<void> deleteSession(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('chat_messages',
          where: 'session_id = ?', whereArgs: [id]);
      await txn.delete('chat_sessions', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// 某会话的消息(按时间正序)
  Future<List<ChatMessage>> messages(int sessionId) async {
    final db = await _db.database;
    final rows = await db.query('chat_messages',
        where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'created_at ASC');
    return rows.map(ChatMessage.fromMap).toList();
  }

  /// 追加一条消息,返回新消息 id;消息插入与会话 updated_at 更新在同一事务。
  /// [imagePath]:用户发图的本地路径(v14 起持久化,历史消息可显示原图)。
  /// [reasoningContent]:AI 推理模型的思维链(v15 起持久化,回传要求)。
  Future<int> addMessage({
    required int sessionId,
    required String role,
    required String content,
    String? imagePath,
    String? reasoningContent,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction<int>((txn) async {
      final id = await txn.insert('chat_messages', ChatMessage(
        sessionId: sessionId,
        role: role,
        content: content,
        imagePath: imagePath,
        reasoningContent: reasoningContent,
        createdAt: now,
      ).toMap());
      await txn.update('chat_sessions', {'updated_at': now},
          where: 'id = ?', whereArgs: [sessionId]);
      return id;
    });
  }

  /// 清空某会话的全部消息(会话本身保留)。
  /// 返回被清空的消息列表,供「撤销」恢复。
  Future<List<ChatMessage>> clearMessages(int sessionId) async {
    final db = await _db.database;
    final rows = await db.query('chat_messages',
        where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'created_at ASC');
    final msgs = rows.map(ChatMessage.fromMap).toList();
    await db.delete('chat_messages',
        where: 'session_id = ?', whereArgs: [sessionId]);
    return msgs;
  }

  /// 撤销清空:把消息按原 id 插回(幂等:消息实际未被清空时跳过,不抛主键冲突)。
  Future<void> restoreMessages(List<ChatMessage> msgs) async {
    if (msgs.isEmpty) return;
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final m in msgs) {
        await txn.insert('chat_messages', m.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    await db.update('chat_sessions', {'updated_at': now},
        where: 'id = ?', whereArgs: [msgs.first.sessionId]);
  }
}
