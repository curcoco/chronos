import 'package:student_workbench/features/tasks/models/plan_item.dart';
import 'package:student_workbench/core/services/db_helper.dart';

/// 计划服务:本周计划 / 长期目标(本地 SQLite;完成态、排序、截止日期)
class PlanService {
  PlanService._();
  static final PlanService instance = PlanService._();
  DbHelper get _db => DbHelper.instance;

  /// 按 scope 列出:未完成在前,其次按 sort_order、创建时间。
  Future<List<PlanItem>> list(String scope) async {
    final db = await _db.database;
    final rows = await db.query(
      'plan_items',
      where: 'scope = ?',
      whereArgs: [scope],
      orderBy: 'done ASC, sort_order ASC, created_at ASC',
    );
    return rows.map(PlanItem.fromMap).toList();
  }

  Future<int> add({
    required String scope,
    required String title,
    String detail = '',
    String? dueDate,
  }) async {
    final db = await _db.database;
    final text = title.trim();
    if (text.isEmpty) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert('plan_items', PlanItem(
      scope: scope,
      title: text,
      detail: detail.trim(),
      dueDate: (dueDate?.isEmpty ?? true) ? null : dueDate,
      sortOrder: now ~/ 1000,
      createdAt: now,
      updatedAt: now,
    ).toMap());
  }

  Future<void> update(PlanItem item) async {
    final db = await _db.database;
    await db.update(
      'plan_items',
      item.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch).toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> toggle(PlanItem item) async {
    final db = await _db.database;
    await db.update(
      'plan_items',
      {
        'done': item.done ? 0 : 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.delete('plan_items', where: 'id = ?', whereArgs: [id]);
  }
}
