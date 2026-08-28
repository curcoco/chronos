import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chronos/core/services/ai_provider.dart';
import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/services/http_json.dart';
import 'package:chronos/core/services/key_store.dart';

/// 图片消息不被当前模型支持且没有可回退的 OCR 模型。
class LlmImageNotSupportedError implements Exception {
  const LlmImageNotSupportedError();
}

/// 中转站以 400/422 拒绝请求(常见于不支持 function calling / max_tokens /
/// 流式参数的模型或代理),由 [_complete] / [chatStream] 捕获后
/// 去掉工具参数降级重试一次。
class _ParamsRejectedError implements Exception {
  final String message;
  _ParamsRejectedError(this.message);

  @override
  String toString() => message;
}

/// SSE 流式请求一个事件都没收到:中转站忽略 `stream: true` 返回普通 JSON、
/// 或把 JSON 拆成多行、或以 200+error 事件返回错误时,当前解析器一行都收不到,
/// 若直接抛「回复为空」会把真实原因吞掉。由 [chatStream] 捕获后
/// 整段降级为非流式请求,保证「配置正确但回复为空」的中转站也能正常对话。
class _StreamNotSupportedError implements Exception {
  const _StreamNotSupportedError();
}

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
    final total = (usage['total_tokens'] as num?)?.toInt() ?? (prompt + completion);
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

/// 零时闲话铺 · 大模型对话(中转站 API,OpenAI 兼容)
/// 支持本地工具调用(函数调用):模型返回 tool_calls 时,由 [onTool] 执行后回传,
/// 循环最多 [maxRounds] 轮,直到模型给出正文回复。
/// 支持图文消息([chatWithImage]):最后一条用户消息带 base64 图片
/// (data URL),模型不支持图片时由调用方回退到 OCR 模型(见 chat_page)。
/// 支持流式输出([chatStream]):逐 token 产出,订阅方取消即停止生成。
/// 中转站地址/Key/模型在应用内「API 配置」填写,存本机安全存储。
class LlmService {
  LlmService._();
  static final LlmService instance = LlmService._();

  static const int maxRounds = 5;

  Future<bool> isConfigured() async {
    if (await AiProviders.isChatConfigured()) return true;
    // 迁移前的旧配置兜底(首次启动迁移后即为新结构)。
    final s = KeyStore.instance;
    return (await s.get(KeyStore.llmBaseUrl)).isNotEmpty &&
        (await s.get(KeyStore.llmApiKey)).isNotEmpty &&
        (await s.get(KeyStore.llmModel)).isNotEmpty;
  }

  /// 解析本次请求的端点:modelRef 为空时用「聊天模型」引用;
  /// 返回 (地址, Key, 模型名)。未配置/格式错误抛 StateError。
  Future<({String baseUrl, String apiKey, String model})> _endpoint(
      String? modelRef) async {
    final ref = (modelRef == null || modelRef.isEmpty)
        ? await AiProviders.chatModelRef()
        : modelRef;
    final ep = await AiProviders.resolve(ref);
    if (ep == null) throw StateError('未配置中转站 API');
    return ep;
  }

  /// 兼容两种填法:中转站地址只填根地址(如 `https://api.xxx.com/v1`),
  /// 或直接填完整 `/chat/completions` 端点;统一返回请求 URL。
  static String endpointFor(String base) {
    final b = base.replaceAll(RegExp(r'/$'), '');
    if (b.endsWith('/chat/completions')) return b;
    return '$b/chat/completions';
  }

  /// 发送纯文本对话历史,返回 AI 回复文本(非流式,整段返回);失败抛异常
  ///
  /// [tools]: OpenAI 工具定义列表;模型需要时返回 tool_calls,
  /// [onTool] 负责执行工具并返回结果文本。
  /// [modelRef]: 模型引用("提供商id|模型id",见 [AiProviders]);为空用聊天模型。
  Future<String> chat({
    required List<({String role, String content, String? reasoningContent})>
        history,
    required String persona,
    List<Map<String, dynamic>>? tools,
    Future<String> Function(String name, Map<String, dynamic> args)? onTool,
    String? modelRef,
    void Function(LlmUsage?)? onUsage,
  }) async {
    final ep = await _endpoint(modelRef);
    final baseUrl = ep.baseUrl;
    final apiKey = ep.apiKey;
    final modelName = ep.model;
    if (baseUrl.isEmpty || apiKey.isEmpty || modelName.isEmpty) {
      throw StateError('未配置中转站 API');
    }
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': persona},
      for (final m in history)
        if (m.role == 'assistant')
          {
            'role': 'assistant',
            'content': m.content,
            // 关键:DeepSeek V4 思考模式 + 请求带 tools 时,
            // 历史每条 assistant 都必须带 reasoning_content 字段,
            // 否则 400「must be passed back」。旧数据/无思考给空串兜底。
            'reasoning_content': m.reasoningContent ?? '',
          }
        else
          {'role': m.role, 'content': m.content},
    ];
    final r = await _complete(
        baseUrl: baseUrl, apiKey: apiKey, modelName: modelName,
        messages: messages, tools: tools, onTool: onTool);
    onUsage?.call(r.usage);
    return r.text;
  }

  /// 发送带图片的消息(最后一条用户消息为 文字 + 图片):
  /// 图片以 base64 data URL 形式传给模型(OpenAI 兼容多模态协议)。
  /// 模型不支持图片时抛异常,由调用方决定是否回退 OCR 模型。
  /// [modelRef]: 模型引用;为空用聊天模型(图片通常走多模态模型,
  /// 调用方可在模型不支持时以 OCR 模型引用重试)。
  Future<String> chatWithImage({
    required String text,
    required List<({String role, String content, String? reasoningContent})>
        history,
    required String persona,
    required String imageBase64,
    required String imageMime,
    List<Map<String, dynamic>>? tools,
    Future<String> Function(String name, Map<String, dynamic> args)? onTool,
    String? modelRef,
    void Function(LlmUsage?)? onUsage,
  }) async {
    final ep = await _endpoint(modelRef);
    final baseUrl = ep.baseUrl;
    final apiKey = ep.apiKey;
    final modelName = ep.model;
    if (baseUrl.isEmpty || apiKey.isEmpty || modelName.isEmpty) {
      throw StateError('未配置中转站 API');
    }
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': persona},
      for (final m in history)
        if (m.role == 'assistant')
          {
            'role': 'assistant',
            'content': m.content,
            // DeepSeek V4 思考模式 + 带 tools 请求:assistant 必须带
            // reasoning_content 字段(空串兜底),否则 400。
            'reasoning_content': m.reasoningContent ?? '',
          }
        else
          {'role': m.role, 'content': m.content},
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': text},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:$imageMime;base64,$imageBase64'},
          },
        ],
      },
    ];
    final r = await _complete(
        baseUrl: baseUrl, apiKey: apiKey, modelName: modelName,
        messages: messages, tools: tools, onTool: onTool);
    onUsage?.call(r.usage);
    return r.text;
  }

  /// 流式对话:逐段产出 (正文, 思维链) 增量(订阅方拼接显示,首字秒出)。
  /// 推理模型(如 DeepSeek-R1)的思维链走 `reasoning_content` 字段,
  /// 与正文分开产出;普通模型该字段恒为空。
  /// 工具调用在流内部处理:模型请求工具时先执行、再继续下一轮流式回复,
  /// 对订阅方透明(工具轮通常不产出文本)。
  /// 取消订阅即中断请求(停止生成)。
  Stream<({String text, String reasoning})> chatStream({
    required List<({String role, String content, String? reasoningContent})>
        history,
    required String persona,
    List<Map<String, dynamic>>? tools,
    Future<String> Function(String name, Map<String, dynamic> args)? onTool,
    String? modelRef,
    void Function(LlmUsage?)? onUsage,
  }) async* {
    final ep = await _endpoint(modelRef);
    final baseUrl = ep.baseUrl;
    final apiKey = ep.apiKey;
    final modelName = ep.model;
    if (baseUrl.isEmpty || apiKey.isEmpty || modelName.isEmpty) {
      throw StateError('未配置中转站 API');
    }
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': persona},
      for (final m in history)
        if (m.role == 'assistant')
          {
            'role': 'assistant',
            'content': m.content,
            // DeepSeek V4 思考模式 + 带 tools 请求:assistant 必须带
            // reasoning_content 字段(空串兜底),否则 400。
            'reasoning_content': m.reasoningContent ?? '',
          }
        else
          {'role': m.role, 'content': m.content},
    ];
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    for (var attempt = 0; attempt < 2; attempt++) {
      final useTools = attempt == 0 ? tools : null;
      try {
        yield* _streamRound(
          base: base,
          apiKey: apiKey,
          modelName: modelName,
          messages: messages,
          tools: useTools,
          onTool: onTool,
          onUsage: onUsage,
          degraded: attempt > 0,
        );
        return;
      } on _ParamsRejectedError catch (e) {
        if (attempt == 1 || useTools == null) rethrow;
        AppLog.instance
            .i('中转站拒绝了带工具参数的流式请求,降级为纯文本重试:$e');
      } on _StreamNotSupportedError {
        // 中转站没有按 SSE 返回(常见于忽略 stream 参数、返回普通 JSON):
        // 整段降级为非流式请求,回复一次性产出,保证「配置正确但回复为空」
        // 的中转站也能正常对话。
        AppLog.instance.i('SSE 未收到任何事件,降级为非流式对话');
        final r = await _complete(
          baseUrl: baseUrl,
          apiKey: apiKey,
          modelName: modelName,
          messages: messages,
          tools: tools,
          onTool: onTool,
        );
        // 降级路径也要产出思维链:调用方落库后,下一轮才能原样回传。
        yield (text: r.text, reasoning: r.reasoning);
        onUsage?.call(r.usage);
        return;
      }
    }
    throw HttpException('对话请求失败');
  }

  /// 非流式公共请求循环:发消息 → 有 tool_calls 则执行工具回传 → 直到模型给出正文。
  ///
  /// 健壮性(针对「配置完掌柜不回复」的常见根因):
  /// - 非 2xx 时把响应体片段带进异常(经 [HttpJson] 统一脱敏 + 日志),
  ///   错误原因(模型名写错/Key 无效/参数不被支持)能直接看到;
  /// - 400/422 视为「参数不被该中转站支持」(部分代理不支持 tools / max_tokens),
  ///   去掉 tools 与 max_tokens 后自动重试一次,保证基本对话可用;
  /// - 请求、响应体读取都有超时,任何一环卡住都会抛出而不是无限挂起。
  /// 返回 (正文, 思维链)——思维链供降级路径捕获并落库回传。
  Future<({String text, String reasoning, LlmUsage? usage})> _complete({
    required String baseUrl,
    required String apiKey,
    required String modelName,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Future<String> Function(String name, Map<String, dynamic> args)? onTool,
  }) async {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    for (var attempt = 0; attempt < 2; attempt++) {
      final useTools = attempt == 0 ? tools : null;
      try {
        return await _completeRound(
          base: base,
          apiKey: apiKey,
          modelName: modelName,
          messages: messages,
          tools: useTools,
          onTool: onTool,
          degraded: attempt > 0,
        );
      } on _ParamsRejectedError catch (e) {
        if (attempt == 1 || useTools == null) rethrow;
        AppLog.instance
            .i('中转站拒绝了带工具参数的请求,降级为纯文本重试:$e');
      }
    }
    throw HttpException('对话请求失败');
  }

  /// 非流式单次完整请求(含最多 [maxRounds] 轮工具调用循环)。
  /// 返回 (正文, 思维链, 用量)。
  Future<({String text, String reasoning, LlmUsage? usage})> _completeRound({
    required String base,
    required String apiKey,
    required String modelName,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Future<String> Function(String name, Map<String, dynamic> args)? onTool,
    bool degraded = false,
  }) async {
    for (var round = 0; round < maxRounds; round++) {
      final payload =
          _payload(modelName, messages, tools, stream: false, degraded: degraded);
      final data = await _post(
        base: base,
        apiKey: apiKey,
        payload: payload,
        tools: tools,
      );
      final choices = data['choices'] as List?;
      final choice = (choices == null || choices.isEmpty)
          ? null
          : choices.first as Map<String, dynamic>;
      if (choice == null) throw HttpException('回复为空');
      final message = choice['message'] as Map<String, dynamic>;
      final toolCalls = message['tool_calls'] as List?;
      final hasTools = toolCalls != null && toolCalls.isNotEmpty;

      if (!hasTools || tools == null) {
        final content = message['content'] as String?;
        if (content == null || content.trim().isEmpty) {
          throw HttpException('回复为空');
        }
        // 返回正文 + 思维链 + 用量(推理模型;非流式降级路径也要捕获,
        // 否则下一轮没有 reasoning_content 可回传,DeepSeek 直接报错)。
        return (
          text: content.trim(),
          reasoning:
              ((message['reasoning_content'] as String?) ?? '').trim(),
          usage: LlmUsage.fromResponse(data),
        );
      }

      messages.add(message);
      for (final tc in toolCalls.cast<Map<String, dynamic>>()) {
        messages.add({
          'role': 'tool',
          'tool_call_id': (tc['id'] as String?) ?? '',
          'content': await _runTool(tc, onTool),
        });
      }
    }
    throw HttpException('工具调用轮数过多');
  }

  /// 流式单轮:逐段产出 (正文, 思维链) 增量;模型请求工具时内部执行并继续下一轮。
  Stream<({String text, String reasoning})> _streamRound({
    required String base,
    required String apiKey,
    required String modelName,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Future<String> Function(String name, Map<String, dynamic> args)? onTool,
    void Function(LlmUsage?)? onUsage,
    bool degraded = false,
  }) async* {
    for (var round = 0; round < maxRounds; round++) {
      final payload =
          _payload(modelName, messages, tools, stream: true, degraded: degraded);
      final textBuf = StringBuffer();
      final reasoningBuf = StringBuffer(); // 思维链累积(工具调用续轮需原样回传)
      // index → 累积的工具调用(delta 按 index 拼接)
      final toolCalls = <int, ({String id, String name, String args})>{};
      var finishReason = '';
      LlmUsage? usage;
      // 成功解析出的事件数:为 0 说明中转站没有按 SSE 格式返回
      // (可能不支持流式、忽略 stream 参数返回普通 JSON),交给降级逻辑。
      var parsedEvents = 0;

      await for (final data in HttpJson.postSse(
        endpointFor(base),
        body: payload,
        headers: {HttpHeaders.authorizationHeader: 'Bearer $apiKey'},
      )) {
        final Map<String, dynamic> chunk;
        try {
          chunk = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          continue; // 非 JSON 行(如心跳),忽略
        }
        parsedEvents++;
        // 用量可能出现在任一 chunk(尤其收尾 choices 空的 usage 块)。
        final u = LlmUsage.fromResponse(chunk);
        if (u != null) usage = u;
        // 中转站以 200 + error 事件返回错误(如模型名/Key/参数不被支持):
        // 透出真实原因,避免被当成「回复为空」吞掉。
        final err = chunk['error'];
        if (err != null) {
          final msg = err is Map
              ? ((err['message'] as String?) ?? err.toString())
              : err.toString();
          AppLog.instance.e('流式对话服务端错误事件:$msg');
          throw HttpException('服务返回错误:$msg');
        }
        final choices = chunk['choices'] as List?;
        final choice = (choices == null || choices.isEmpty)
            ? null
            : choices.first as Map<String, dynamic>;
        if (choice == null) continue;
        finishReason = (choice['finish_reason'] as String?) ?? finishReason;
        final delta =
            choice['delta'] as Map<String, dynamic>? ?? const {};
        // 推理模型的思维链(reasoning_content,如 DeepSeek-R1):单独产出,
        // 与正文分开拼接,UI 以「思考过程」折叠块展示;普通模型恒为空。
        final reasoning = delta['reasoning_content'] as String?;
        if (reasoning != null && reasoning.isNotEmpty) {
          reasoningBuf.write(reasoning);
          yield (text: '', reasoning: reasoning);
        }
        final content = delta['content'] as String?;
        if (content != null && content.isNotEmpty) {
          textBuf.write(content);
          yield (text: content, reasoning: ''); // 增量输出给 UI
        }
        final tcs = delta['tool_calls'] as List?;
        if (tcs != null) {
          for (final tc in tcs.cast<Map<String, dynamic>>()) {
            final idx = (tc['index'] as num?)?.toInt() ?? 0;
            final fn = (tc['function'] as Map<String, dynamic>?)?['name']
                    as String? ??
                '';
            final argsDelta =
                (tc['function'] as Map<String, dynamic>?)?['arguments']
                        as String? ??
                    '';
            final id = (tc['id'] as String?) ?? '';
            final cur = toolCalls[idx] ?? (id: '', name: '', args: '');
            toolCalls[idx] = (
              id: id.isNotEmpty ? id : cur.id,
              name: fn.isNotEmpty ? fn : cur.name,
              args: cur.args + argsDelta,
            );
          }
        }
      }

      // 本轮结束:工具调用 → 执行后继续下一轮;正文 → 返回。
      if (finishReason == 'tool_calls' && toolCalls.isNotEmpty) {
        messages.add({
          'role': 'assistant',
          if (textBuf.isNotEmpty) 'content': textBuf.toString(),
          // 推理模型:工具调用续轮必须把本轮思维链原样带回,否则 API 拒绝。
          if (reasoningBuf.isNotEmpty)
            'reasoning_content': reasoningBuf.toString(),
          'tool_calls': [
            for (final e in toolCalls.entries)
              {
                'id': e.value.id,
                'type': 'function',
                'function': {
                  'name': e.value.name,
                  'arguments': e.value.args.isEmpty ? '{}' : e.value.args,
                },
              },
          ],
        });
        for (final e in toolCalls.entries) {
          messages.add({
            'role': 'tool',
            'tool_call_id': e.value.id,
            'content': await _runToolById(e.value, onTool),
          });
        }
        continue;
      }
      final reply = textBuf.toString().trim();
      if (reply.isEmpty) {
        if (parsedEvents == 0) {
          // 一个事件都没收到:不是「真的没回复」,而是中转站没按 SSE 返回,
          // 交给 chatStream 整段降级为非流式请求。
          throw const _StreamNotSupportedError();
        }
        throw HttpException('回复为空');
      }
      onUsage?.call(usage);
      return;
    }
    throw HttpException('工具调用轮数过多');
  }

  /// 统一请求体:流式时带 stream;降级轮(degraded)只保留最基础参数——
  /// 部分中转站/模型会拒绝 `temperature` 等附加参数(如 reasoning 模型),
  /// 去掉 tools / max_tokens / temperature 后保证基本对话可用。
  static Map<String, dynamic> _payload(
    String modelName,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools, {
    required bool stream,
    bool degraded = false,
  }) {
    final payload = <String, dynamic>{
      'model': modelName,
      'messages': messages,
      'stream': stream,
    };
    if (!degraded) {
      payload['temperature'] = 0.7;
      // 流式请求告诉上游回传 usage(供 Token 仪表盘统计缓存命中与消耗);
      // 部分中转站不支持该字段会 400,降级轮(degraded)已去掉它。
      if (stream) payload['stream_options'] = {'include_usage': true};
    }
    if (tools != null) {
      payload['tools'] = tools;
      payload['max_tokens'] = 800;
    }
    return payload;
  }

  /// POST 一次非流式请求;400/422 转 [_ParamsRejectedError](触发降级重试)。
  Future<Map<String, dynamic>> _post({
    required String base,
    required String apiKey,
    required Map<String, dynamic> payload,
    required List<Map<String, dynamic>>? tools,
  }) async {
    try {
      return await HttpJson.postJson(
        endpointFor(base),
        headers: {HttpHeaders.authorizationHeader: 'Bearer $apiKey'},
        body: payload,
      );
    } on HttpJsonException catch (e) {
      if (e.statusCode == 400 || e.statusCode == 422) {
        throw _ParamsRejectedError(e.message);
      }
      rethrow;
    }
  }

  /// 执行单个工具调用(非流式路径,按 OpenAI tool_call 结构)。
  Future<String> _runTool(
    Map<String, dynamic> tc,
    Future<String> Function(String name, Map<String, dynamic> args)? onTool,
  ) async {
    final fn =
        ((tc['function'] as Map<String, dynamic>?)?['name'] as String?) ?? '';
    final argsRaw =
        (tc['function'] as Map<String, dynamic>?)?['arguments'] as String? ??
            '{}';
    final Map<String, dynamic> args;
    try {
      args = jsonDecode(argsRaw) as Map<String, dynamic>;
    } catch (_) {
      return '工具参数解析失败';
    }
    if (onTool != null) {
      try {
        return await onTool(fn, args);
      } catch (e) {
        return '工具执行失败:$e';
      }
    }
    return '未知工具:$fn';
  }

  /// 执行流式累积出的工具调用(delta 拼接后的完整结构)。
  Future<String> _runToolById(
    ({String id, String name, String args}) t,
    Future<String> Function(String name, Map<String, dynamic> args)? onTool,
  ) async {
    if (onTool == null) return '未知工具:${t.name}';
    final Map<String, dynamic> args;
    try {
      args = jsonDecode(t.args.isEmpty ? '{}' : t.args) as Map<String, dynamic>;
    } catch (_) {
      return '工具参数解析失败';
    }
    try {
      return await onTool(t.name, args);
    } catch (e) {
      return '工具执行失败:$e';
    }
  }
}
