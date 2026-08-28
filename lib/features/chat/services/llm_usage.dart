/// 一次请求的 token 用量(来自响应里的 usage 字段;部分中转站不回传,可能为 null)。
class LlmUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  /// 缓存命中的上游 token(prompt 部分;用于展示缓存命中率)。
  final int cachedTokens;

  const LlmUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    required this.cachedTokens,
  });

  /// 解析一个响应对象(含 usage 字段);无 usage 或格式不符返回 null。
  static LlmUsage? fromResponse(Map<String, dynamic>? data) {
    if (data == null) return null;
    final usage = data['usage'];
    if (usage is! Map) return null;
    return fromJson(usage.cast<String, dynamic>());
  }

  /// 解析 usage JSON;无有效字段返回 null。
  static LlmUsage? fromJson(Map<String, dynamic>? usage) {
    if (usage == null) return null;
    final prompt = (usage['prompt_tokens'] as num?)?.toInt() ?? 0;
    final completion = (usage['completion_tokens'] as num?)?.toInt() ?? 0;
    final total =
        (usage['total_tokens'] as num?)?.toInt() ?? (prompt + completion);
    // 缓存命中:优先 prompt_tokens_details.cached_tokens,兼容 OpenRouter 的
    // prompt_cache_hit_tokens;都没有则记 0。
    var cached = 0;
    final details = usage['prompt_tokens_details'];
    if (details is Map) {
      cached = (details['cached_tokens'] as num?)?.toInt() ?? 0;
    }
    if (cached == 0) {
      cached = (usage['prompt_cache_hit_tokens'] as num?)?.toInt() ?? 0;
    }
    return LlmUsage(
      promptTokens: prompt,
      completionTokens: completion,
      totalTokens: total,
      cachedTokens: cached,
    );
  }
}
