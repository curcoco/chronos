import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:chronos/core/services/db_helper.dart';
import 'package:chronos/core/utils/dates.dart';
import 'package:chronos/features/coins/services/coin_service.dart';
import 'package:chronos/features/health/services/screen_time_service.dart';

/// 屏幕时间服务:分类优先级、用量统计(娱乐/总时长/热力图/排行)、
/// 金币联动(昨日达标发 2、不重复、超预算/无数据不发)、无原生通道时降级。
/// 用 sqflite_common_ffi 在真实 SQLite 上跑;通道调用在测试环境
/// 抛 MissingPluginException,服务的降级路径应返回空/false 而不崩。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // flutter test 默认并发跑多个测试文件;auto_memory_test / db_migration_test
    // 等套件共用默认目录下的 student_workbench.db(各自 setUp 删库重建)。
    // 本套件指到独立临时目录,彻底避开与其他套件的文件级竞争。
    final dir =
        Directory.systemTemp.createTempSync('chronos_screen_time_test');
    await databaseFactoryFfi.setDatabasesPath(dir.path);
  });

  setUp(() async {
    // 每个测试用全新库:关闭单例连接并删除 db(含 wal/shm),避免残留。
    await DbHelper.instance.close();
    final dir = await databaseFactory.getDatabasesPath();
    for (final name in [
      'student_workbench.db',
      'student_workbench.db-wal',
      'student_workbench.db-shm',
    ]) {
      final f = File(p.join(dir, name));
      if (await f.exists()) await f.delete();
    }
  });

  final service = ScreenTimeService.instance;

  /// 直接往 screen_usage 写一行(绕过通道,模拟已同步的数据)。
  Future<void> insertUsage(
      String day, String pkg, String category, int seconds) async {
    final db = await DbHelper.instance.database;
    await db.insert('screen_usage', {
      'day': day,
      'package': pkg,
      'category': category,
      'seconds': seconds,
    });
  }

  test('categoryOf:用户覆盖 > 内置预设 > 默认工具', () {
    expect(service.categoryOf('com.ss.android.ugc.aweme', {}),
        ScreenTimeService.catEntertainment); // 内置娱乐
    expect(service.categoryOf('com.unknown.app', {}), ScreenTimeService.catTool); // 默认
    expect(
        service.categoryOf('com.ss.android.ugc.aweme',
            {'com.ss.android.ugc.aweme': ScreenTimeService.catTool}),
        ScreenTimeService.catTool); // 覆盖:抖音标成工具
    expect(
        service.categoryOf('com.unknown.app', {'com.unknown.app': 'study'}),
        ScreenTimeService.catStudy); // 覆盖:未知 app 标成学习
  });

  test('分类持久化:setCategory / categories / 清除恢复默认', () async {
    await DbHelper.instance.database; // 建表
    await service.setCategory('com.a.b', 'study');
    expect((await service.categories())['com.a.b'], 'study');
    await service.setCategory('com.a.b', null); // 清除
    expect((await service.categories()).containsKey('com.a.b'), isFalse);
  });

  test('用量统计:娱乐/总时长/热力图分钟/排行与显示名回退', () async {
    await DbHelper.instance.database;
    final today = dateKey(DateTime.now());
    await insertUsage(
        today, 'com.ss.android.ugc.aweme', 'entertainment', 1800);
    await insertUsage(today, 'tv.danmaku.bili', 'entertainment', 600);
    await insertUsage(today, 'com.chronos.workbench', 'tool', 300);

    expect(await service.entertainmentSeconds(today), 2400);
    expect(await service.totalSeconds(today), 2700);

    final heat = await service.entertainmentMinutesByDay(7);
    expect(heat[today], 40); // 2400 秒 = 40 分钟

    final top =
        await service.topApps(today, category: ScreenTimeService.catEntertainment);
    expect(top.length, 2);
    expect(top.first.packageName, 'com.ss.android.ugc.aweme'); // 按秒数降序
    expect(top.first.minutes, 30);
    // 显示名回退链:已装 app 名(无通道为空)> 内置预设名 > 包名
    expect(top.first.label, '抖音');
    expect(top.last.label, '哔哩哔哩');
  });

  test('金币联动:昨日未超预算发 2,当天不重复发', () async {
    await DbHelper.instance.database;
    final yesterday =
        dateKey(DateTime.now().subtract(const Duration(days: 1)));
    final today = dateKey(DateTime.now());
    await insertUsage(
        yesterday, 'com.ss.android.ugc.aweme', 'entertainment', 1800);
    await insertUsage(yesterday, 'com.chronos.workbench', 'tool', 600);

    expect(await service.maybeRewardYesterday(budgetMinutes: 120), 2);

    final coins = await CoinService.instance.records();
    expect(
        coins.any((c) =>
            c.type == 'screen' && c.amount == 2 && c.date == today),
        isTrue);

    // 第二次调用(同一天)不重复发
    expect(await service.maybeRewardYesterday(budgetMinutes: 120), 0);
  });

  test('金币联动:昨日超预算不发', () async {
    await DbHelper.instance.database;
    final yesterday =
        dateKey(DateTime.now().subtract(const Duration(days: 1)));
    await insertUsage(
        yesterday, 'com.ss.android.ugc.aweme', 'entertainment', 200 * 60);
    expect(await service.maybeRewardYesterday(budgetMinutes: 120), 0);
  });

  test('金币联动:昨日无数据(未授权/未同步)不发', () async {
    await DbHelper.instance.database;
    expect(await service.maybeRewardYesterday(budgetMinutes: 120), 0);
  });

  test('recentEntertainmentByDay:按天分组、天内按秒降序、只含娱乐', () async {
    await DbHelper.instance.database;
    final today = dateKey(DateTime.now());
    final yesterday = dateKey(DateTime.now().subtract(const Duration(days: 1)));
    await insertUsage(today, 'com.ss.android.ugc.aweme', 'entertainment', 1200);
    await insertUsage(today, 'tv.danmaku.bili', 'entertainment', 2400);
    await insertUsage(yesterday, 'tv.danmaku.bili', 'entertainment', 600);
    await insertUsage(today, 'com.chronos.workbench', 'tool', 300); // 非娱乐不计

    final data = await service.recentEntertainmentByDay(7);
    expect(data[today]!.length, 2);
    expect(data[today]!.first.packageName, 'tv.danmaku.bili'); // 天内降序
    expect(data[today]!.first.label, '哔哩哔哩'); // 显示名回退内置预设
    expect(data[today]!.last.minutes, 20);
    expect(data[yesterday]!.single.minutes, 10);
  });

  test('降级:无原生通道时 syncRecent 返回 false 且不动已有数据', () async {
    await DbHelper.instance.database;
    final today = dateKey(DateTime.now());
    await insertUsage(
        today, 'com.ss.android.ugc.aweme', 'entertainment', 100);
    expect(await service.syncRecent(days: 3), isFalse);
    expect(await service.entertainmentSeconds(today), 100); // 数据未被动过
  });
}
