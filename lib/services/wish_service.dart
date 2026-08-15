import '../models/wish.dart';
import 'db_helper.dart';

/// 心愿清单服务
class WishService {
  WishService();
  DbHelper get _db => DbHelper.instance;

  Future<void> addWish({required String title, required int cost}) async {
    final db = await _db.database;
    await db.insert('wishes', Wish(
      title: title,
      cost: cost,
      redeemed: false,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ).toMap());
  }

  /// 未兑换在前,新加的在前
  Future<List<Wish>> wishes() async {
    final db = await _db.database;
    final rows = await db.query('wishes',
        orderBy: 'redeemed ASC, created_at DESC');
    return rows.map(Wish.fromMap).toList();
  }
}
