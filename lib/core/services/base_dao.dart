import 'package:sqflite/sqflite.dart';

import 'package:student_workbench/core/services/db_helper.dart';

/// 泛型数据访问基类。收敛 note / diary / wish 等「单例 + 简单 CRUD」
/// 服务的重复样板:子类只需给出表名、`fromMap` 与排序,即可复用增删查。
///
/// 说明:仅覆盖通用增删查;各业务特有的复杂查询(如金币的聚合统计、
/// 计划的 scope 过滤)仍由各自服务实现,不强行套入基类。
abstract class BaseDao<T> {
  /// 表名
  String get table;

  /// 行 → 实体
  T fromMap(Map<String, Object?> map);

  /// 实体 → 行(用于插入)
  Map<String, Object?> toMap(T entity);

  /// 默认排序(如 'created_at DESC'),null 表示不排序
  String? get defaultOrderBy => null;

  DbHelper get dbHelper => DbHelper.instance;

  Future<Database> get _db async => dbHelper.database;

  /// 插入一条,返回新行 id
  Future<int> insert(T entity) async {
    final db = await _db;
    return db.insert(table, toMap(entity));
  }

  /// 查全部(按 [defaultOrderBy] 或传入的 [orderBy] 排序)
  Future<List<T>> queryAll({String? orderBy}) async {
    final db = await _db;
    final rows = await db.query(table, orderBy: orderBy ?? defaultOrderBy);
    return rows.map(fromMap).toList();
  }

  /// 条件查询
  Future<List<T>> queryWhere(
    String where,
    List<Object?> whereArgs, {
    String? orderBy,
    int? limit,
  }) async {
    final db = await _db;
    final rows = await db.query(table,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy ?? defaultOrderBy,
        limit: limit);
    return rows.map(fromMap).toList();
  }

  /// 按 id 删除
  Future<int> deleteById(int id) async {
    final db = await _db;
    return db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  /// 按 id 集合批量删除
  Future<int> deleteByIds(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = await _db;
    final placeholders = List.filled(ids.length, '?').join(',');
    return db.delete(table, where: 'id IN ($placeholders)', whereArgs: ids);
  }

  /// 更新指定 id 的字段
  Future<int> updateById(int id, Map<String, Object?> values) async {
    final db = await _db;
    return db.update(table, values, where: 'id = ?', whereArgs: [id]);
  }
}
