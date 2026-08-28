import 'package:sqflite/sqflite.dart';

import 'package:chronos/features/english/models/english_fav.dart';
import 'package:chronos/core/services/base_dao.dart';

/// 英文收藏服务(收藏的优质句/词/读/写)。
/// 继承 [BaseDao] 复用通用 CRUD;收藏切换等复杂逻辑自实现。
class EnglishService extends BaseDao<EnglishFav> {
  EnglishService();

  @override
  String get table => 'english_favs';

  @override
  EnglishFav fromMap(Map<String, Object?> map) => EnglishFav.fromMap(map);

  @override
  Map<String, Object?> toMap(EnglishFav entity) => entity.toMap();

  @override
  String? get defaultOrderBy => 'created_at DESC';

  /// 全部收藏(按收藏时间倒序)
  Future<List<EnglishFav>> favs() => queryAll();

  /// 是否已收藏(按 type + content 唯一)
  Future<bool> isFav(String type, String content) async {
    final rows = await queryWhere(
      'fav_type = ? AND content = ?',
      [type, content],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// 切换收藏,返回收藏后的状态。「查 + 删/插」在同一事务:
  /// 并发连点不会重复收藏(唯一约束 + ignore 兜底,不抛未处理异常)。
  Future<bool> toggle(String type, String title, String content) async {
    final db = await dbHelper.database;
    return db.transaction<bool>((txn) async {
      final rows = await txn.query('english_favs',
          where: 'fav_type = ? AND content = ?',
          whereArgs: [type, content], limit: 1);
      if (rows.isNotEmpty) {
        await txn.delete('english_favs',
            where: 'id = ?', whereArgs: [rows.first['id']]);
        return false;
      }
      await txn.insert('english_favs', EnglishFav(
        type: type,
        title: title,
        content: content,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ).toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
      return true;
    });
  }
}
