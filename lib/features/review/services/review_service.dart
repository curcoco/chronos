import 'package:chronos/features/review/models/review.dart';
import 'package:chronos/core/services/base_dao.dart';

/// 每日复盘服务(每天一条,upsert)。
/// 继承 [BaseDao] 复用通用 CRUD;按日 upsert 逻辑自实现。
class ReviewService extends BaseDao<Review> {
  ReviewService();

  @override
  String get table => 'reviews';

  @override
  Review fromMap(Map<String, Object?> map) => Review.fromMap(map);

  @override
  Map<String, Object?> toMap(Review entity) => entity.toMap();

  @override
  String? get defaultOrderBy => 'review_date DESC';

  /// 取某日复盘(没有则 null)
  Future<Review?> reviewFor(String date) async {
    final rows =
        await queryWhere('review_date = ?', [date], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// 保存(当天已存在则更新)。「查 + 写(insert/update)」在同一事务:
  /// 并发保存同一天不会重复插入(reviews.review_date 有 UNIQUE,竞态会抛
  /// 唯一约束异常,这里用事务串行化消除)。
  Future<void> save(
    String date, {
    required int progress,
    required String done,
    required String problem,
    required String plan,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      final rows = await txn.query('reviews',
          where: 'review_date = ?', whereArgs: [date], limit: 1);
      if (rows.isEmpty) {
        await txn.insert('reviews', Review(
          date: date,
          progress: progress,
          done: done,
          problem: problem,
          plan: plan,
          createdAt: now,
        ).toMap());
      } else {
        await txn.update('reviews', {
          'progress': progress,
          'done': done,
          'problem': problem,
          'plan': plan,
        }, where: 'id = ?', whereArgs: [rows.first['id']]);
      }
    });
  }

  /// 全部复盘,按日期倒序
  Future<List<Review>> all() => queryAll();
}
