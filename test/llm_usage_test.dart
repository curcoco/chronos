import 'package:flutter_test/flutter_test.dart';
import 'package:chronos/features/chat/services/llm_usage.dart';

void main() {
  test('LlmUsage.fromJson:解析标准 OpenAI usage(含缓存命中)', () {
    final u = LlmUsage.fromJson({
      'prompt_tokens': 100,
      'completion_tokens': 20,
      'total_tokens': 120,
      'prompt_tokens_details': {'cached_tokens': 60},
    });
    expect(u, isNotNull);
    expect(u!.promptTokens, 100);
    expect(u.completionTokens, 20);
    expect(u.totalTokens, 120);
    expect(u.cachedTokens, 60);
  });

  test('LlmUsage.fromJson:无缓存字段时 cached=0', () {
    final u = LlmUsage.fromJson({
      'prompt_tokens': 5,
      'completion_tokens': 3,
      'total_tokens': 8,
    });
    expect(u!.cachedTokens, 0);
  });

  test('LlmUsage.fromJson:兼容 OpenRouter 的 prompt_cache_hit_tokens', () {
    final u = LlmUsage.fromJson({
      'prompt_tokens': 100,
      'completion_tokens': 10,
      'prompt_cache_hit_tokens': 90,
    });
    expect(u!.cachedTokens, 90);
  });

  test('LlmUsage.fromResponse:无 usage 字段返回 null', () {
    expect(LlmUsage.fromResponse({'choices': []}), isNull);
    expect(LlmUsage.fromResponse(null), isNull);
    expect(LlmUsage.fromResponse({'usage': 'not-a-map'}), isNull);
  });

  test('LlmUsage.fromResponse:total_tokens 缺失时按 prompt+completion 兜底', () {
    final u = LlmUsage.fromResponse({
      'usage': {'prompt_tokens': 7, 'completion_tokens': 6},
    });
    expect(u!.totalTokens, 13);
  });
}
