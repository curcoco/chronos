import 'package:sqflite/sqflite.dart';

import '../models/kitchen_item.dart';
import '../models/workout.dart';
import 'db_helper.dart';

/// 健康管理服务:厨房秘籍 / 运动记录 / 身体数据设置(纯本地)
class HealthService {
  HealthService();
  DbHelper get _db => DbHelper.instance;

  // ---------- 厨房秘籍 ----------
  Future<List<KitchenItem>> kitchenItems() async {
    final db = await _db.database;
    final rows = await db.query('kitchen_items', orderBy: 'created_at DESC');
    return rows.map(KitchenItem.fromMap).toList();
  }

  Future<void> addKitchenItem({
    required String cat,
    required String name,
    required int cal,
    required double price,
    required String link,
  }) async {
    final db = await _db.database;
    await db.insert('kitchen_items', KitchenItem(
      cat: cat,
      name: name,
      cal: cal,
      price: price,
      link: link,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ).toMap());
  }

  Future<void> deleteKitchenItem(int id) async {
    final db = await _db.database;
    await db.delete('kitchen_items', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- 运动记录 ----------
  Future<List<Workout>> workouts() async {
    final db = await _db.database;
    final rows = await db.query('workouts', orderBy: 'created_at DESC');
    return rows.map(Workout.fromMap).toList();
  }

  Future<void> addWorkout({
    required String type,
    required int minutes,
    required String date,
  }) async {
    final db = await _db.database;
    await db.insert('workouts', Workout(
      type: type,
      minutes: minutes,
      date: date,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ).toMap());
  }

  // ---------- 身体数据(设置) ----------
  Future<String?> _get(String key) async {
    final db = await _db.database;
    final rows = await db.query('health_settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> _set(String key, String value) async {
    final db = await _db.database;
    await db.insert('health_settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 身体数据:身高/体重/年龄/性别(m/f)/活动系数
  Future<({double height, double weight, int age, String sex, double activity})?>
      bodyData() async {
    final h = await _get('height');
    final w = await _get('weight');
    final a = await _get('age');
    if (h == null || w == null || a == null) return null;
    return (
      height: double.tryParse(h) ?? 0,
      weight: double.tryParse(w) ?? 0,
      age: int.tryParse(a) ?? 0,
      sex: await _get('sex') ?? 'm',
      activity: double.tryParse(await _get('activity') ?? '') ?? 1.2,
    );
  }

  Future<void> saveBodyData({
    required double height,
    required double weight,
    required int age,
    required String sex,
    required double activity,
  }) async {
    await _set('height', '$height');
    await _set('weight', '$weight');
    await _set('age', '$age');
    await _set('sex', sex);
    await _set('activity', '$activity');
  }

  /// 计算 BMI 与 TDEE(Mifflin-St Jeor);未录入返回 null
  Future<({double bmi, String bmiLabel, int tdee})?> calcMetrics() async {
    final b = await bodyData();
    if (b == null || b.height <= 0 || b.weight <= 0 || b.age <= 0) return null;
    final hm = b.height / 100;
    final bmi = b.weight / (hm * hm);
    final bmr = 10 * b.weight + 6.25 * b.height - 5 * b.age +
        (b.sex == 'm' ? 5 : -161);
    final tdee = (bmr * b.activity).round();
    return (
      bmi: bmi,
      bmiLabel: bmi < 18.5
          ? '偏瘦'
          : bmi < 24
              ? '正常'
              : bmi < 28
                  ? '偏胖'
                  : '肥胖',
      tdee: tdee,
    );
  }
}
