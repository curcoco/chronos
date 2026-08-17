import '../models/review.dart';
import 'base_dao.dart';

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

  /// 保存(当天已存在则更新)
  Future<void> save(
    String date, {
    required int progress,
    required String done,
    required String problem,
    required String plan,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await reviewFor(date);
    if (existing == null) {
      await insert(Review(
        date: date,
        progress: progress,
        done: done,
        problem: problem,
        plan: plan,
        createdAt: now,
      ));
    } else {
      await updateById(existing.id!, {
        'progress': progress,
        'done': done,
        'problem': problem,
        'plan': plan,
      });
    }
  }

  /// 全部复盘,按日期倒序
  Future<List<Review>> all() => queryAll();
}
