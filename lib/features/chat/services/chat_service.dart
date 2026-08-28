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

  /// 会话文件夹列表(按名称排序)
  Future<List<SessionFolder>> folders() async {
    final db = await _db.database;
    final rows = await db.query('session_folders', orderBy: 'name ASC');
    return rows.map(SessionFolder.fromMap).toList();
  }

  /// 新建会话文件夹,返回新 id。
  Future<int> createFolder(String name) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert('session_folders', SessionFolder(
      name: name.trim(),
      createdAt: now,
    ).toMap());
  }

  /// 重命名文件夹。
  Future<void> renameFolder(int id, String name) async {
    final db = await _db.database;
    await db.update('session_folders', {'name': name.trim()},
        where: 'id = ?', whereArgs: [id]);
  }

  /// 删除文件夹(文件夹内的会话变为未归档,不删除会话)。
  Future<void> deleteFolder(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update('chat_sessions', {'folder_id': null},
          where: 'folder_id = ?', whereArgs: [id]);
      await txn.delete('session_folders', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// 把会话移动到指定文件夹(null = 移出到未归档)。
  Future<void> moveSession(int sessionId, int? folderId) async {
    final db = await _db.database;
    await db.update('chat_sessions', {'folder_id': folderId},
        where: 'id = ?', whereArgs: [sessionId]);
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

  /// 建立一个「分支」新会话:以既有的一串消息为新会话的初始历史,
  /// 以便在一个对话里从某条消息继续分叉,原会话保持不变。
  /// 消息按原 created_at 落库(保持顺序),新会话 updated_at 为当前。
  Future<int> branchSession({required List<ChatMessage> msgs, String? title}) async {
    if (msgs.isEmpty) return -1;
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction<int>((txn) async {
      final sid = await txn.insert('chat_sessions', ChatSession(
        title: (title == null || title.trim().isEmpty) ? '分支' : title.trim(),
        createdAt: now,
        updatedAt: now,
      ).toMap());
      for (final m in msgs) {
        await txn.insert('chat_messages', ChatMessage(
          sessionId: sid,
          role: m.role,
          content: m.content,
          imagePath: m.imagePath,
          reasoningContent: m.reasoningContent,
          createdAt: m.createdAt,
        ).toMap());
      }
      return sid;
    });
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
