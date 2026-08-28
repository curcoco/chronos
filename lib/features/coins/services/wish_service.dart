import 'package:sqflite/sqflite.dart';

import 'package:chronos/features/coins/models/wish.dart';
import 'package:chronos/core/services/base_dao.dart';

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

  /// 添加心愿;入口校验:名称非空、金币数非负且有上限(防负数穿透兑换逻辑)。
  Future<void> addWish({required String title, required int cost}) async {
    final name = title.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(title, 'title', '心愿名称不能为空');
    }
    if (cost < 0 || cost > 100000) {
      throw ArgumentError.value(cost, 'cost', '金币数必须在 0 ~ 100000 之间');
    }
    await insert(Wish(
      title: name,
      cost: cost,
      redeemed: false,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// 未兑换在前,新加的在前
  Future<List<Wish>> wishes() => queryAll();

  /// 删除心愿(仅删除清单条目,不影响已产生的金币收支记录)
  Future<void> deleteWish(int id) => deleteById(id);

  /// 撤销删除:按原 id 插回(幂等,行实际未被删除时跳过,不抛主键冲突)。
  Future<int> restore(Wish wish) =>
      insert(wish, conflictAlgorithm: ConflictAlgorithm.ignore);
}
