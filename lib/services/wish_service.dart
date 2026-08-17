import '../models/wish.dart';
import 'base_dao.dart';

/// 心愿清单服务。CRUD 复用 [BaseDao]。
class WishService extends BaseDao<Wish> {
  WishService();

  @override
  String get table => 'wishes';

  @override
  Wish fromMap(Map<String, Object?> map) => Wish.fromMap(map);

  @override
  Map<String, Object?> toMap(Wish entity) => entity.toMap();

  @override
  String get defaultOrderBy => 'redeemed ASC, created_at DESC';

  Future<void> addWish({required String title, required int cost}) async {
    await insert(Wish(
      title: title,
      cost: cost,
      redeemed: false,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// 未兑换在前,新加的在前
  Future<List<Wish>> wishes() => queryAll();

  /// 删除心愿(仅删除清单条目,不影响已产生的金币收支记录)
  Future<void> deleteWish(int id) => deleteById(id);
}
