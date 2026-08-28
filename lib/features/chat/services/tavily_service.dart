import 'package:chronos/core/services/http_json.dart';
import 'package:chronos/core/services/key_store.dart';

/// 搜索服务(Tavily,默认且暂不开放自定义服务商)。
/// API Key 在「系统设置 → API 配置」填写(存本机);未配置时返回提示文本,
/// 不抛错打断聊天。
class TavilyService {
  TavilyService._();
  static final TavilyService instance = TavilyService._();

  static const String _endpoint = 'https://api.tavily.com/search';

  Future<bool> isConfigured() async {
    final key = await KeyStore.instance.get(KeyStore.tavilyApiKey);
    return key.isNotEmpty;
  }

  /// 搜索 [query],返回可直接喂给模型的文本结果(最多 [maxResults] 条)。
  /// 未配置 Key 时返回「未配置」提示(由调用方/工具层展示)。
  Future<String> search(String query, {int maxResults = 4}) async {
    final key = await KeyStore.instance.get(KeyStore.tavilyApiKey);
    if (key.isEmpty) {
      return '搜索服务未配置:请先配置 Tavily API Key,或直接告诉用户无法联网搜索。';
    }
    try {
      final data = await HttpJson.postJson(
        _endpoint,
        body: {
          'api_key': key,
          'query': query,
          'max_results': maxResults,
          'search_depth': 'basic',
        },
        ioTimeout: const Duration(seconds: 30),
      );
      final results = (data['results'] as List?) ?? const [];
      if (results.isEmpty) return '没有搜到相关内容。';
      final buf = StringBuffer('搜索结果:\n');
      var i = 0;
      for (final r in results.cast<Map<String, dynamic>>()) {
        if (i >= maxResults) break;
        i++;
        final title = (r['title'] as String?)?.trim() ?? '';
        final content = (r['content'] as String?)?.trim() ?? '';
        final url = (r['url'] as String?)?.trim() ?? '';
        buf.writeln('$i. $title');
        if (content.isNotEmpty) buf.writeln(content);
        if (url.isNotEmpty) buf.writeln('来源:$url');
        buf.writeln();
      }
      return buf.toString().trim();
    } catch (e) {
      return '联网搜索失败:$e';
    }
  }
}
