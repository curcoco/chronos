import 'dart:convert';
import 'dart:io';

import 'key_store.dart';

/// 零时闲话铺 · 大模型对话(中转站 API,OpenAI 兼容)
/// 支持本地工具调用(函数调用):模型返回 tool_calls 时,由 [onTool] 执行后回传,
/// 循环最多 [maxRounds] 轮,直到模型给出正文回复。
/// 中转站地址/Key/模型在应用内「API 配置」填写,存本地。
class LlmService {
  LlmService._();
  static final LlmService instance = LlmService._();

  static const int maxRounds = 5;

  Future<bool> isConfigured() async {
    final s = KeyStore.instance;
    return (await s.get(KeyStore.llmBaseUrl)).isNotEmpty &&
        (await s.get(KeyStore.llmApiKey)).isNotEmpty &&
        (await s.get(KeyStore.llmModel)).isNotEmpty;
  }

  /// 发送对话历史,返回 AI 回复文本;失败抛异常
  ///
  /// [tools]: OpenAI 工具定义列表;模型需要时返回 tool_calls,
  /// [onTool] 负责执行工具并返回结果文本。
  Future<String> chat({
    required List<({String role, String content})> history,
    required String persona,
    List<Map<String, dynamic>>? tools,
    Future<String> Function(String name, Map<String, dynamic> args)? onTool,
  }) async {
    final s = KeyStore.instance;
    final baseUrl = await s.get(KeyStore.llmBaseUrl);
    final apiKey = await s.get(KeyStore.llmApiKey);
    final model = await s.get(KeyStore.llmModel);
    if (baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
      throw StateError('未配置中转站 API');
    }
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': persona},
      for (final m in history) {'role': m.role, 'content': m.content},
    ];

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      for (var round = 0; round < maxRounds; round++) {
        final req = await client
            .postUrl(Uri.parse('$base/chat/completions'))
            .timeout(const Duration(seconds: 10));
        req.headers.contentType = ContentType.json;
        req.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
        req.write(jsonEncode({
          'model': model,
          'messages': messages,
          'temperature': 0.7,
          'max_tokens': 800,
          'tools': ?tools,
        }));
        final res = await req.close().timeout(const Duration(seconds: 60));
        final body = await res.transform(utf8.decoder).join();
        if (res.statusCode != 200) {
          throw HttpException('服务返回 ${res.statusCode}');
        }
        final data = jsonDecode(body) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        final choice = (choices == null || choices.isEmpty)
            ? null
            : choices.first as Map<String, dynamic>;
        if (choice == null) throw HttpException('回复为空');
        final message = choice['message'] as Map<String, dynamic>;
        final toolCalls = message['tool_calls'] as List?;

        if (toolCalls == null || toolCalls.isEmpty) {
          final content = message['content'] as String?;
          if (content == null || content.trim().isEmpty) {
            throw HttpException('回复为空');
          }
          return content.trim();
        }

        // 工具调用:先追加带 tool_calls 的 assistant 消息,再执行各工具
        messages.add(message);
        for (final tc in toolCalls.cast<Map<String, dynamic>>()) {
          final id = (tc['id'] as String?) ?? '';
          final fn = ((tc['function'] as Map<String, dynamic>?)?['name']
                  as String?) ??
              '';
          final argsRaw = (tc['function'] as Map<String, dynamic>?)?['arguments']
                  as String? ??
              '{}';
          final args = jsonDecode(argsRaw) as Map<String, dynamic>;
          String result;
          if (onTool != null) {
            try {
              result = await onTool(fn, args);
            } catch (e) {
              result = '工具执行失败:$e';
            }
          } else {
            result = '未知工具:$fn';
          }
          messages.add({'role': 'tool', 'tool_call_id': id, 'content': result});
        }
      }
      throw HttpException('工具调用轮数过多');
    } finally {
      client.close(force: true);
    }
  }
}
