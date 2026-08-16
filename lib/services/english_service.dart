import '../models/english_fav.dart';
import 'db_helper.dart';

/// 英文收藏服务(收藏的优质句/词/读/写)
class EnglishService {
  EnglishService();
  DbHelper get _db => DbHelper.instance;

  Future<List<EnglishFav>> favs() async {
    final db = await _db.database;
    final rows = await db.query('english_favs', orderBy: 'created_at DESC');
    return rows.map(EnglishFav.fromMap).toList();
  }

  /// 是否已收藏(按 type + content 唯一)
  Future<bool> isFav(String type, String content) async {
    final db = await _db.database;
    final rows = await db.query('english_favs',
        where: 'fav_type = ? AND content = ?',
        whereArgs: [type, content],
        limit: 1);
    return rows.isNotEmpty;
  }

  /// 切换收藏,返回收藏后的状态
  Future<bool> toggle(String type, String title, String content) async {
    final db = await _db.database;
    final rows = await db.query('english_favs',
        where: 'fav_type = ? AND content = ?',
        whereArgs: [type, content],
        limit: 1);
    if (rows.isNotEmpty) {
      await db.delete('english_favs',
          where: 'id = ?', whereArgs: [rows.first['id']]);
      return false;
    }
    await db.insert('english_favs', EnglishFav(
      type: type,
      title: title,
      content: content,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ).toMap());
    return true;
  }
}
