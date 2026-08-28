/// 日志脱敏:把密钥类内容(API Key / Bearer token / 查询参数中的 key)打码,
/// 避免错误响应体或请求摘要写进日志时泄露敏感信息。
class LogSanitize {
  LogSanitize._();

  /// 常见密钥模式,按顺序替换为掩码;捕获组 1 保留字段名/前缀。
  static final List<RegExp> _patterns = [
    // sk-xxx / sk_xxx / tvly-xxx 类 API Key
    RegExp(r'\b(?:sk|tvly)[-_][A-Za-z0-9_-]{6,}'),
    // Bearer / Basic 认证头
    RegExp(r'(Bearer)\s+[A-Za-z0-9._~+/-]{8,}'),
    RegExp(r'(Basic)\s+[A-Za-z0-9+/]{8,}'),
    // JSON 字段:api_key / token / key / secret / authorization
    RegExp(r'("(?:api_?key|token|secret|authorization|password)"\s*:\s*)"[^"]*"'),
    // 查询参数:key=xxx / token=xxx / apikey=xxx
    RegExp(r'([?&](?:api_?key|token|secret|key)=)[^&\s"]{4,}'),
    // 请求头样式 xi-api-key: xxx / Authorization: xxx(忽略大小写)
    RegExp(r'(xi-api-key|x-api-key|authorization)\s*[:=]\s*[^\s,;]+',
        caseSensitive: false),
  ];

  /// 对日志文本脱敏;输入为 null 时返回空串。
  static String mask(String? text) {
    if (text == null || text.isEmpty) return '';
    var out = text;
    for (final p in _patterns) {
      out = out.replaceAllMapped(p, _masked);
    }
    return out;
  }

  static String _masked(Match m) {
    // 保留字段名/前缀(如有),只打码值。
    final prefix = m.group(1) ?? '';
    return '$prefix***';
  }

  /// 压平换行并截断(用于错误响应体摘要,防刷屏)。
  static String brief(String text, {int max = 300}) {
    final flat = text.replaceAll('\n', ' ').trim();
    if (flat.length <= max) return flat;
    return '${flat.substring(0, max)}…';
  }
}
