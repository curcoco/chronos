import 'package:student_workbench/features/health/models/kitchen_item.dart';
import 'package:student_workbench/features/health/models/user_video.dart';
import 'package:student_workbench/features/health/models/workout.dart';
import 'package:student_workbench/core/services/db_helper.dart';

/// 健康管理服务:厨房秘籍 / 运动记录 / 自传跟练视频(纯本地)
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

  // ---------- 用户自传跟练视频 ----------
  Future<List<UserVideo>> userVideos() async {
    final db = await _db.database;
    final rows = await db.query('user_videos', orderBy: 'created_at DESC');
    return rows.map(UserVideo.fromMap).toList();
  }

  Future<int> addUserVideo({
    required String title,
    required String path,
    String note = '',
  }) async {
    final db = await _db.database;
    return db.insert('user_videos', UserVideo(
      title: title,
      path: path,
      note: note,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ).toMap());
  }

  Future<void> deleteUserVideo(int id) async {
    final db = await _db.database;
    await db.delete('user_videos', where: 'id = ?', whereArgs: [id]);
  }
}
