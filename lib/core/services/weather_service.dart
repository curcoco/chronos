import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:student_workbench/core/services/key_store.dart';
import 'package:student_workbench/core/services/settings_service.dart';

/// 天气 · 心知天气(now 实时天气;Key 存本地,城市应用内选择)
/// 带本地缓存:同城市 [_cacheTtl] 内直接返回缓存,减少请求与流量。
class WeatherService {
  WeatherService._();
  static final WeatherService instance = WeatherService._();

  /// 缓存有效期:天气分钟级变化不大,30 分钟足够。
  static const Duration _cacheTtl = Duration(minutes: 30);
  static const String _kCacheCity = 'weather_cache_city';
  static const String _kCacheText = 'weather_cache_text';
  static const String _kCacheTemp = 'weather_cache_temp';
  static const String _kCacheAt = 'weather_cache_at';

  Future<bool> isConfigured() async =>
      (await KeyStore.instance.get(KeyStore.weatherApiKey)).isNotEmpty;

  /// 返回 (城市, 天气, 温度℃);失败抛异常
  /// 城市:应用内选择优先,未选择则返回提示。
  /// [forceRefresh] 为 true 时跳过缓存强制拉取(如用户手动切城市)。
  Future<({String city, String text, String temp})> now(
      {bool forceRefresh = false}) async {
    final saved = await SettingsService.instance.weatherCity();
    if (saved.isEmpty) throw StateError('未选择城市');
    if (!forceRefresh) {
      final cached = await _readCache(saved);
      if (cached != null) return cached;
    }
    final result = await fetchCity(saved);
    await _writeCache(result);
    return result;
  }

  /// 读取新鲜缓存(城市匹配且未过期);无有效缓存返回 null。
  Future<({String city, String text, String temp})?> _readCache(
      String city) async {
    final prefs = await SharedPreferences.getInstance();
    final at = prefs.getInt(_kCacheAt) ?? 0;
    final cachedCity = prefs.getString(_kCacheCity) ?? '';
    if (at == 0 || cachedCity != city) return null;
    final age = DateTime.now().millisecondsSinceEpoch - at;
    if (age > _cacheTtl.inMilliseconds) return null;
    return (
      city: cachedCity,
      text: prefs.getString(_kCacheText) ?? '',
      temp: prefs.getString(_kCacheTemp) ?? '',
    );
  }

  Future<void> _writeCache(
      ({String city, String text, String temp}) w) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCacheCity, w.city);
    await prefs.setString(_kCacheText, w.text);
    await prefs.setString(_kCacheTemp, w.temp);
    await prefs.setInt(_kCacheAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// 按指定城市查询(供 AI 工具调用;支持拼音/城市 ID)
  Future<({String city, String text, String temp})> fetchCity(
      String location) async {
    final key = await KeyStore.instance.get(KeyStore.weatherApiKey);
    if (key.isEmpty) throw StateError('未配置天气服务');
    if (location.trim().isEmpty) throw StateError('城市为空');
    final uri = Uri.parse('https://api.seniverse.com/v3/weather/now.json')
        .replace(queryParameters: {
      'key': key,
      'location': location.trim(),
      'language': 'zh-Hans',
      'unit': 'c',
    });
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      final res = await req.close().timeout(const Duration(seconds: 8));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        throw HttpException('天气服务返回 ${res.statusCode}');
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) {
        throw HttpException('天气数据为空');
      }
      final r = results.first as Map<String, dynamic>;
      final loc = r['location'] as Map<String, dynamic>?;
      final now = r['now'] as Map<String, dynamic>?;
      return (
        city: (loc?['name'] as String?) ?? location,
        text: (now?['text'] as String?) ?? '',
        temp: (now?['temperature'] as String?) ?? '',
      );
    } finally {
      client.close(force: true);
    }
  }
}
