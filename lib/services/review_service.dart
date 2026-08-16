import '../models/review.dart';
import 'db_helper.dart';

/// 每日复盘服务(每天一条,upsert)
class ReviewService {
  ReviewService();
  DbHelper get _db => DbHelper.instance;

  /// 取某日复盘(没有则 null)
  Future<Review?> reviewFor(String date) async {
    final db = await _db.database;
    final rows = await db.query('reviews',
        where: 'review_date = ?', whereArgs: [date], limit: 1);
    if (rows.isEmpty) return null;
    return Review.fromMap(rows.first);
  }

  /// 保存(当天已存在则更新)
  Future<void> save(
    String date, {
    required int progress,
    required String done,
    required String problem,
    required String plan,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await reviewFor(date);
    if (existing == null) {
      await db.insert('reviews', Review(
        date: date,
        progress: progress,
        done: done,
        problem: problem,
        plan: plan,
        createdAt: now,
      ).toMap());
    } else {
      await db.update('reviews', {
        'progress': progress,
        'done': done,
        'problem': problem,
        'plan': plan,
      }, where: 'id = ?', whereArgs: [existing.id]);
    }
  }

  /// 全部复盘,按日期倒序
  Future<List<Review>> all() async {
    final db = await _db.database;
    final rows = await db.query('reviews', orderBy: 'review_date DESC');
    return rows.map(Review.fromMap).toList();
  }
}
