import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import 'package:chronos/core/services/db_helper.dart';
import 'package:chronos/core/utils/dates.dart';
import 'package:chronos/features/coins/services/coin_service.dart';

/// 一个 app 在某天的使用情况(秒)。
class ScreenAppUsage {
  final String packageName;
  final String label; // 显示名:已装 app 名 > 内置预设名 > 包名
  final int seconds;
  final String category; // entertainment / study / tool

  const ScreenAppUsage({
    required this.packageName,
    required this.label,
    required this.seconds,
    required this.category,
  });

  int get minutes => seconds ~/ 60;
}

/// 防沉迷「屏幕时间」:读系统 UsageStats 聚合每日各 app 前台时长,
/// 按用户分类算「娱乐时长」,供健康页展示与金币奖励。
///
/// 设计:不做常驻后台监控——系统一直在记账,打开页面时查最近几天回填 DB,
/// 省电且纯本地。原生侧见 `ScreenTimePlugin.kt`(通道 `app/screen_time`)。
class ScreenTimeService {
  ScreenTimeService._();
  static final ScreenTimeService instance = ScreenTimeService._();

  static const MethodChannel _channel = MethodChannel('app/screen_time');

  static const String catEntertainment = 'entertainment';
  static const String catStudy = 'study';
  static const String catTool = 'tool';

  /// 内置常见娱乐 app 预设(包名 → 显示名)。用户可在分类页覆盖;
  /// 清单外的 app 默认「工具」,想算娱乐去分类页手动标。
  static const Map<String, String> builtinEntertainment = {
    'com.ss.android.ugc.aweme': '抖音',
    'com.ss.android.ugc.aweme.lite': '抖音极速版',
    'com.smile.gifmaker': '快手',
    'com.kuaishou.nebula': '快手极速版',
    'tv.danmaku.bili': '哔哩哔哩',
    'com.sina.weibo': '微博',
    'com.xingin.xhs': '小红书',
    'com.dragon.read': '番茄小说',
    'com.qidian.QDReader': '起点读书',
    'com.tencent.tmgp.sgame': '王者荣耀',
    'com.tencent.tmgp.pubgmhd': '和平精英',
    'com.miHoYo.Yuanshen': '原神',
    'com.happyelements.AndroidAnimal': '开心消消乐',
    'com.ss.android.article.news': '今日头条',
    'com.netease.cloudmusic': '网易云音乐',
    'com.tencent.qqmusic': 'QQ音乐',
    'com.kugou.android': '酷狗音乐',
    'com.tencent.qqlive': '腾讯视频',
    'com.qiyi.video': '爱奇艺',
    'com.youku.phone': '优酷视频',
    'com.hunantv.imgo.activity': '芒果TV',
    'air.tv.douyu.android': '斗鱼',
    'com.duowan.kiwi': '虎牙直播',
    'com.zhiliaoapp.musically': 'TikTok',
    'com.google.android.youtube': 'YouTube',
    'com.twitter.android': 'X(Twitter)',
    'com.instagram.android': 'Instagram',
    'com.reddit.frontpage': 'Reddit',
  };

  DbHelper get _db => DbHelper.instance;

  /// app 显示名缓存(首次成功取已装 app 后驻留内存;测试环境无通道时为空)。
  Map<String, String>? _labelCache;

  /// 「使用情况访问」权限是否已授予(特殊权限,app 无法代点)。
  Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 跳系统「使用情况访问权限」设置页(用户手动授予)。
  Future<void> openPermissionSettings() async {
    try {
      await _channel.invokeMethod<void>('openPermissionSettings');
    } on MissingPluginException {
      // 无原生实现(测试/桌面):静默
    }
  }

  /// 查询 [begin, end) 内各 app 前台秒数。无通道/失败返回空。
  Future<Map<String, int>> _usageSince(DateTime begin, DateTime end) async {
    try {
      final rows = await _channel.invokeListMethod<Map>('queryUsage', {
        'begin': begin.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
      });
      if (rows == null) return const {};
      return {
        for (final r in rows)
          if (r['package'] is String) r['package'] as String: (r['seconds'] as num?)?.toInt() ?? 0,
      };
    } on MissingPluginException {
      return const {};
    } on PlatformException {
      return const {};
    }
  }

  /// 已装 app 的「包名 → 显示名」(失败/无通道时为空,展示回退包名或预设名)。
  Future<Map<String, String>> appLabels({bool refresh = false}) async {
    if (!refresh && _labelCache != null) return _labelCache!;
    try {
      final rows = await _channel
          .invokeListMethod<Map>('installedApps');
      if (rows == null) return _labelCache ?? const {};
      _labelCache = {
        for (final r in rows)
          if (r['package'] is String)
            r['package'] as String: (r['label'] as String?) ?? r['package'] as String,
      };
      return _labelCache!;
    } on MissingPluginException {
      return _labelCache ?? const {};
    } on PlatformException {
      return _labelCache ?? const {};
    }
  }

  /// 用户手动分类(包名 → 分类;DB 覆盖,优先于内置预设)。
  Future<Map<String, String>> categories() async {
    final db = await _db.database;
    final rows = await db.query('screen_app_categories');
    return {
      for (final r in rows) r['package'] as String: r['category'] as String,
    };
  }

  /// 设置/清除单个 app 的自定义分类([category] 传 null 删除,回到预设/默认)。
  Future<void> setCategory(String packageName, String? category) async {
    final db = await _db.database;
    if (category == null) {
      await db.delete('screen_app_categories',
          where: 'package = ?', whereArgs: [packageName]);
      return;
    }
    await db.insert(
      'screen_app_categories',
      {
        'package': packageName,
        'category': category,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 有效分类 = 用户覆盖 > 内置娱乐预设 > 工具(默认)。
  String categoryOf(String packageName, Map<String, String> overrides) {
    final o = overrides[packageName];
    if (o == catEntertainment || o == catStudy || o == catTool) {
      return o!;
    }
    if (builtinEntertainment.containsKey(packageName)) return catEntertainment;
    return catTool;
  }

  /// 同步最近 [days] 天(含今天)的用量到 DB。
  /// 每天一次通道查询(整天窗口;今天截至当前时刻),当天数据整体重写。
  /// 某天查询为空(系统已清理过期数据)则跳过,不动已有记录。
  /// 返回是否成功(权限/通道不可用返回 false)。
  Future<bool> syncRecent({int days = 8}) async {
    if (!await hasPermission()) return false;
    final overrides = await categories();
    final db = await _db.database;
    final now = DateTime.now();
    for (var i = days - 1; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day - i);
      final end = i == 0 ? now : DateTime(day.year, day.month, day.day + 1);
      final usage = await _usageSince(day, end);
      if (usage.isEmpty) continue;
      final key = dateKey(day);
      await db.transaction((txn) async {
        await txn
            .delete('screen_usage', where: 'day = ?', whereArgs: [key]);
        final batch = txn.batch();
        for (final e in usage.entries) {
          if (e.value <= 0) continue;
          batch.insert('screen_usage', {
            'day': key,
            'package': e.key,
            'category': categoryOf(e.key, overrides),
            'seconds': e.value,
          });
        }
        await batch.commit(noResult: true);
      });
    }
    return true;
  }

  /// 某天某分类(或不限分类)的总秒数。
  Future<int> secondsOf(String day, {String? category}) async {
    final db = await _db.database;
    final where = category == null ? 'day = ?' : 'day = ? AND category = ?';
    final args = category == null ? [day] : [day, category];
    final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(seconds), 0) FROM screen_usage WHERE $where', args);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// 某天的娱乐总秒数。
  Future<int> entertainmentSeconds(String day) =>
      secondsOf(day, category: catEntertainment);

  /// 某天的全部屏幕总秒数(不分分类;含 Chronos 自己)。
  Future<int> totalSeconds(String day) => secondsOf(day);

  /// 近 [days] 天的「天 → 娱乐分钟数」(热力图数据;无记录的天不在 map 里)。
  Future<Map<String, int>> entertainmentMinutesByDay(int days) async {
    final db = await _db.database;
    final since = dateKey(DateTime.now().subtract(Duration(days: days - 1)));
    final rows = await db.rawQuery(
      "SELECT day, CAST(SUM(seconds)/60 AS INTEGER) AS m FROM screen_usage "
      "WHERE category = ? AND day >= ? GROUP BY day",
      [catEntertainment, since],
    );
    return {
      for (final r in rows) r['day'] as String: (r['m'] as num?)?.toInt() ?? 0,
    };
  }

  /// 某天用量排行(可按分类过滤),带显示名。
  Future<List<ScreenAppUsage>> topApps(String day,
      {String? category, int limit = 5}) async {
    final db = await _db.database;
    final where = category == null ? 'day = ?' : 'day = ? AND category = ?';
    final args = category == null ? [day] : [day, category];
    final rows = await db.query('screen_usage',
        where: where, whereArgs: args, orderBy: 'seconds DESC', limit: limit);
    if (rows.isEmpty) return const [];
    final labels = await appLabels();
    return [
      for (final r in rows)
        ScreenAppUsage(
          packageName: r['package'] as String,
          label: labels[r['package']] ??
              builtinEntertainment[r['package']] ??
              (r['package'] as String),
          seconds: (r['seconds'] as num?)?.toInt() ?? 0,
          category: r['category'] as String,
        ),
    ];
  }

  /// 近 [days] 天每天的娱乐 app 明细(天 → 按秒降序的 app 列表)。
  /// 趋势图用:细看「哪几天飘了、是哪个 app 干的」。
  Future<Map<String, List<ScreenAppUsage>>> recentEntertainmentByDay(
      int days) async {
    final db = await _db.database;
    final since = dateKey(DateTime.now().subtract(Duration(days: days - 1)));
    final rows = await db.query('screen_usage',
        where: 'category = ? AND day >= ?',
        whereArgs: [catEntertainment, since],
        orderBy: 'day, seconds DESC');
    if (rows.isEmpty) return const {};
    final labels = await appLabels();
    final byDay = <String, List<ScreenAppUsage>>{};
    for (final r in rows) {
      final pkg = r['package'] as String;
      byDay.putIfAbsent(r['day'] as String, () => []).add(ScreenAppUsage(
            packageName: pkg,
            label:
                labels[pkg] ?? builtinEntertainment[pkg] ?? pkg,
            seconds: (r['seconds'] as num?)?.toInt() ?? 0,
            category: r['category'] as String,
          ));
    }
    return byDay;
  }

  /// 昨日娱乐未超预算则发 2 金币(每天至多一次;受每日赚币上限约束)。
  /// 昨日完全没有数据(未授权/未同步)时不发,避免误奖。
  /// 返回实际发放数量(0 = 未发)。
  Future<int> maybeRewardYesterday({required int budgetMinutes}) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final key = dateKey(yesterday);
    final total = await totalSeconds(key);
    if (total <= 0) return 0;
    final ent = await entertainmentSeconds(key);
    if (ent > budgetMinutes * 60) return 0;
    return CoinService.instance.rewardScreen(dateKey(DateTime.now()));
  }
}
