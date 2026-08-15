import '../models/note.dart';
import 'db_helper.dart';

/// 灵感速记服务(同步到「灵感专区」)
class NoteService {
  NoteService();
  DbHelper get _db => DbHelper.instance;

  Future<void> addNote(String content) async {
    final text = content.trim();
    if (text.isEmpty) return;
    final db = await _db.database;
    await db.insert('notes', Note(
      content: text,
      createdAt: DateTime.now().millisecondsSinceEpoch,
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
}
