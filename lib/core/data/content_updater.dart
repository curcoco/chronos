import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:chronos/core/data/content_store.dart';
import 'package:chronos/core/services/app_info.dart';
import 'package:chronos/core/services/app_log.dart';

/// 远程内容热更服务:小更新不换包。
///
/// 启动时从更新源同目录拉取 `content.json`(与 latest.json 同级),
/// 解析后写入 [ContentStore] 覆盖内置内容池;失败/离线时回退本地缓存,
/// 无缓存则继续用内置内容。内容形如:
/// {"quotes":["…"],"english":[{"en":"…","zh":"…"}],…}
class ContentUpdater {
  ContentUpdater._();
  static final ContentUpdater instance = ContentUpdater._();

  /// 拉取并应用远程内容(后台调用;任何失败静默,不影响启动)。
  Future<void> update() async {
    try {
      final url = await AppInfo.updateCheckUrl();
      final contentUrl = contentUrlFor(url);
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      String body;
      try {
        final req =
            await client.getUrl(Uri.parse(contentUrl)).timeout(const Duration(seconds: 6));
        final res = await req.close().timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) {
          AppLog.instance.e('内容热更下载失败:HTTP ${res.statusCode}');
          await _loadCache();
          return;
        }
        body = await res.transform(utf8.decoder).join();
      } finally {
        client.close(force: true);
      }

      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) {
        await _loadCache();
        return;
      }
      _apply(data);
      // 成功后写本地缓存,供离线启动使用。
      await _saveCache(body);
      AppLog.instance.i('内容热更已应用(${data.length} 个分组)');
    } catch (e) {
      AppLog.instance.e('内容热更失败,回退缓存:$e');
      await _loadCache();
    }
  }

  /// 由更新检查地址推导内容热更地址,兼容两种形态:
  /// - `.../latest.json` → 同目录 `.../content.json`;
  /// - 其它(直接填目录/文件名不同)→ 末尾补 `/content.json`。
  /// 此前只认 `latest.json` 结尾,用户自定义更新源(如 OSS 目录地址)时热更静默失效。
  static String contentUrlFor(String url) {
    final base = url.replaceFirst(RegExp(r'/latest\.json$'), '/content.json');
    if (base.endsWith('/content.json')) return base;
    return '${base.replaceAll(RegExp(r'/$'), '')}/content.json';
  }

  /// 解析 JSON 到 ContentStore(各字段按类型安全解析,缺省不覆盖)。
  void _apply(Map<String, dynamic> data) {
    final quotes = data['quotes'];
    if (quotes is List && quotes.isNotEmpty) {
      ContentStore.quotes = quotes.whereType<String>().toList();
    }
    final english = data['english'];
    if (english is List && english.isNotEmpty) {
      ContentStore.english = english
          .whereType<Map>()
          .map((e) => (
                en: (e['en'] ?? '') as String,
                zh: (e['zh'] ?? '') as String,
              ))
          .toList();
    }
    final autoTasks = data['auto_tasks'];
    if (autoTasks is List && autoTasks.isNotEmpty) {
      ContentStore.autoTasks = autoTasks
          .whereType<Map>()
          .map((e) => (
                title: (e['title'] ?? '') as String,
                category: (e['category'] ?? '学习') as String,
              ))
          .toList();
    }
    final weekPlans = data['week_plans'];
    if (weekPlans is List && weekPlans.isNotEmpty) {
      ContentStore.weekPlans = weekPlans
          .whereType<Map>()
          .map((e) => (
                title: (e['title'] ?? '') as String,
                detail: (e['detail'] ?? '') as String,
              ))
          .toList();
    }
    final longTerm = data['long_term_goals'];
    if (longTerm is List && longTerm.isNotEmpty) {
      ContentStore.longTermGoals = longTerm
          .whereType<Map>()
          .map((e) => (
                title: (e['title'] ?? '') as String,
                detail: (e['detail'] ?? '') as String,
              ))
          .toList();
    }
    final words = data['words'];
    if (words is List && words.isNotEmpty) {
      ContentStore.words = words
          .whereType<Map>()
          .map((e) => (
                w: (e['w'] ?? '') as String,
                p: (e['p'] ?? '') as String,
                m: (e['m'] ?? '') as String,
              ))
          .toList();
    }
    final readings = data['readings'];
    if (readings is List && readings.isNotEmpty) {
      ContentStore.readings = readings
          .whereType<Map>()
          .map((e) => (
                title: (e['title'] ?? '') as String,
                text: (e['text'] ?? '') as String,
              ))
          .toList();
    }
    final writings = data['writings'];
    if (writings is List && writings.isNotEmpty) {
      ContentStore.writings = writings.whereType<String>().toList();
    }
    final meals = data['meals'];
    if (meals is List && meals.isNotEmpty) {
      ContentStore.meals = meals
          .whereType<Map>()
          .map((e) => (
                name: (e['name'] ?? '') as String,
                kcal: ((e['kcal'] ?? 0) as num).toInt(),
                cost: ((e['cost'] ?? 0) as num).toDouble(),
              ))
          .toList();
    }
    final videos = data['videos'];
    if (videos is List && videos.isNotEmpty) {
      ContentStore.videos = videos
          .whereType<Map>()
          .map((e) => (
                title: (e['title'] ?? '') as String,
                min: ((e['min'] ?? 0) as num).toInt(),
              ))
          .toList();
    }
    final wishes = data['wishes'];
    if (wishes is List && wishes.isNotEmpty) {
      ContentStore.wishes = wishes
          .whereType<Map>()
          .map((e) => (
                title: (e['title'] ?? '') as String,
                cost: ((e['cost'] ?? 0) as num).toInt(),
              ))
          .toList();
    }
  }

  Future<String> _cachePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/content_cache.json';
  }

  Future<void> _saveCache(String body) async {
    try {
      final f = File(await _cachePath());
      await f.writeAsString(body, flush: true);
    } catch (e) {
      AppLog.instance.e('内容缓存写入失败:$e');
    }
  }

  /// 离线启动:读本地缓存并应用。
  Future<void> _loadCache() async {
    try {
      final f = File(await _cachePath());
      if (!await f.exists()) return;
      final data = jsonDecode(await f.readAsString());
      if (data is Map<String, dynamic>) {
        _apply(data);
        AppLog.instance.i('内容热更:已用本地缓存');
      }
    } catch (e) {
      AppLog.instance.e('内容缓存读取失败:$e');
    }
  }
}
