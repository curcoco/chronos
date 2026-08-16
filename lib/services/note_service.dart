import '../models/note.dart';
import 'db_helper.dart';

/// 灵感速记服务(同步到「灵感专区」)
class NoteService {
  NoteService();
  DbHelper get _db => DbHelper.instance;

  Future<void> addNote(String content, {String? mood}) async {
    final text = content.trim();
    if (text.isEmpty) return;
    final db = await _db.database;
    await db.insert('notes', Note(
      content: text,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      mood: mood,
    ).toMap());
  }

  /// 最新在前
  Future<List<Note>> notes() async {
    final db = await _db.database;
    final rows = await db.query('notes', orderBy: 'created_at DESC');
    return rows.map(Note.fromMap).toList();
  }

  Future<void> deleteNote(int id) async {
    final db = await _db.database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  /// 批量删除
  Future<void> deleteNotes(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _db.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete('notes',
        where: 'id IN ($placeholders)', whereArgs: ids);
  }

  /// 收藏 / 取消收藏
  Future<void> setFavorite(int id, bool favorite) async {
    final db = await _db.database;
    await db.update('notes', {'favorite': favorite ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }
}
