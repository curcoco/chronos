import '../models/diary_entry.dart';
import 'db_helper.dart';

/// 日记服务(按天一篇,upsert;本地存储)
class DiaryService {
  DiaryService._();
  static final DiaryService instance = DiaryService._();
  DbHelper get _db => DbHelper.instance;

  Future<DiaryEntry?> diaryFor(String date) async {
    final db = await _db.database;
    final rows = await db.query('diary_entries',
        where: 'entry_date = ?', whereArgs: [date], limit: 1);
    return rows.isEmpty ? null : DiaryEntry.fromMap(rows.first);
  }

  /// 保存(当天已存在则更新)
  Future<void> save(
    String date, {
    required String content,
    String? mood,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await diaryFor(date);
    if (existing == null) {
      await db.insert('diary_entries', DiaryEntry(
        content: content.trim(),
        mood: mood,
        date: date,
        createdAt: now,
        updatedAt: now,
      ).toMap());
    } else {
      await db.update('diary_entries', {
        'content': content.trim(),
        'mood': mood,
        'updated_at': now,
      }, where: 'id = ?', whereArgs: [existing.id]);
    }
  }

  /// 全部日记,按日期倒序
  Future<List<DiaryEntry>> all() async {
    final db = await _db.database;
    final rows = await db.query('diary_entries', orderBy: 'entry_date DESC');
    return rows.map(DiaryEntry.fromMap).toList();
  }

  Future<void> delete(String date) async {
    final db = await _db.database;
    await db.delete('diary_entries',
        where: 'entry_date = ?', whereArgs: [date]);
  }
}
