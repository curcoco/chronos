import '../models/english_fav.dart';
import 'base_dao.dart';

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

  /// 切换收藏,返回收藏后的状态
  Future<bool> toggle(String type, String title, String content) async {
    final rows = await queryWhere(
      'fav_type = ? AND content = ?',
      [type, content],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      await deleteById(rows.first.id!);
      return false;
    }
    await insert(EnglishFav(
      type: type,
      title: title,
      content: content,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    return true;
  }
}
