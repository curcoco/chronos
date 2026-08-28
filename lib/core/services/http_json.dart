import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/utils/log_sanitize.dart';

/// 非 2xx 响应异常:带状态码与脱敏后的响应体摘要,
/// 调用方可按状态码分流处理(如 400/422 → 降级重试)。
class HttpJsonException implements Exception {
  final int statusCode;
  final String message;
  const HttpJsonException(this.statusCode, this.message);

  @override
  String toString() => message;
}

/// 统一 JSON HTTP 客户端:收拢全 App 散落的 HttpClient,保证:
/// - 统一的连接 / 读写超时(不再出现某一路「无限挂起」);
/// - 非 2xx 时抛 [HttpJsonException](带脱敏后的响应体片段)并写日志;
/// - **常驻连接池复用**:单例 HttpClient 跨请求 keep-alive,避免每次重复
///   TCP/TLS 握手(「模型回复慢」在连接建立慢时明显改善);
/// - SSE 流式接口([postSse] 返回 [Stream],订阅方取消即中断,供聊天流式输出)。
///
/// 约定:更新源(app_info / content_updater)保持独立实现,不经过这里。
class HttpJson {
  HttpJson._();

  static const Duration defaultConnectTimeout = Duration(seconds: 10);
  static const Duration defaultIoTimeout = Duration(seconds: 60);
  static const Duration defaultIdleTimeout = Duration(seconds: 30);

  /// 常驻 HTTP 客户端:跨请求复用连接池,不 `close(force)`(否则连接池失效)。
  /// `idleTimeout` 让超时空闲连接被自动回收;流式取消会断开该次连接并从池中移除。
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = defaultConnectTimeout
    ..idleTimeout = const Duration(seconds: 45);

  /// GET 并解析 JSON;非 2xx 抛 [HttpException](带脱敏后的响应体片段)。
  static Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String>? headers,
    Duration? connectTimeout,
    Duration? ioTimeout,
  }) async {
    final body = await _send(
      method: 'GET',
      url: url,
      headers: headers,
      connectTimeout: connectTimeout ?? defaultConnectTimeout,
      ioTimeout: ioTimeout ?? defaultIoTimeout,
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// POST JSON 并解析 JSON;非 2xx 抛 [HttpException](带脱敏后的响应体片段)。
  static Future<Map<String, dynamic>> postJson(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    Duration? connectTimeout,
    Duration? ioTimeout,
  }) async {
    final text = await postText(
      url,
      headers: headers,
      body: body,
      connectTimeout: connectTimeout,
      ioTimeout: ioTimeout,
    );
    return jsonDecode(text) as Map<String, dynamic>;
  }

  /// POST JSON,返回响应体原文。
  static Future<String> postText(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    Duration? connectTimeout,
    Duration? ioTimeout,
  }) =>
      _send(
        method: 'POST',
        url: url,
        headers: headers,
        body: body,
        connectTimeout: connectTimeout ?? defaultConnectTimeout,
        ioTimeout: ioTimeout ?? defaultIoTimeout,
      );

  /// POST JSON,返回原始响应体字节(如 elevenlabs 音频)。
  static Future<List<int>> postBytes(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    Duration? connectTimeout,
    Duration? ioTimeout,
  }) async {
    final req = await _client
        .postUrl(Uri.parse(url))
        .timeout(connectTimeout ?? defaultConnectTimeout);
    req.headers.contentType = ContentType.json;
    headers?.forEach(req.headers.set);
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close().timeout(ioTimeout ?? defaultIoTimeout);
    final bytes = <int>[];
    await for (final chunk in res.timeout(ioTimeout ?? defaultIoTimeout)) {
      bytes.addAll(chunk);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final brief = LogSanitize.mask(LogSanitize.brief(utf8.decode(bytes, allowMalformed: true)));
      AppLog.instance.e('HTTP POST ${LogSanitize.mask(url)} → ${res.statusCode}: $brief');
      throw HttpJsonException(res.statusCode, '服务返回 ${res.statusCode}: $brief');
    }
    return bytes;
  }

  /// POST JSON,SSE 流式:逐条 `data:` 负载产出到返回的 [Stream]。
  /// - 订阅方 cancel 会关闭底层连接(停止生成);
  /// - 相邻两条事件超过 [idleTimeout] 抛 [TimeoutException];
  /// - 非 2xx 抛 [HttpException](带脱敏后的响应体片段)。
  static Stream<String> postSse(
    String url, {
    required Map<String, dynamic> body,
    Map<String, String>? headers,
    Duration? connectTimeout,
    Duration? idleTimeout,
  }) async* {
    final req = await _client
        .postUrl(Uri.parse(url))
        .timeout(connectTimeout ?? defaultConnectTimeout);
    req.headers.contentType = ContentType.json;
    req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    headers?.forEach(req.headers.set);
    req.write(jsonEncode(body));
    final res = await req.close().timeout(defaultIoTimeout);
    if (res.statusCode != 200) {
      final errBody = await res
          .transform(utf8.decoder)
          .join()
          .timeout(defaultIoTimeout);
      final brief = LogSanitize.mask(LogSanitize.brief(errBody));
      AppLog.instance.e('HTTP SSE ${LogSanitize.mask(url)} → ${res.statusCode}: $brief');
      throw HttpJsonException(res.statusCode, '服务返回 ${res.statusCode}: $brief');
    }
      // 诊断:中转站可能不支持流式(忽略 stream 参数,返回普通 JSON)。
      // 记录 Content-Type,配合 LLM 层「SSE 零事件 → 降级非流式」的兜底。
      final mime = res.headers.contentType?.mimeType ?? '';
      if (!mime.contains('text/event-stream')) {
        AppLog.instance.i(
            'SSE 端点返回 Content-Type=$mime,可能不支持流式,将由调用方降级');
      }
      final lines = res
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final raw in lines.timeout(idleTimeout ?? defaultIdleTimeout)) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith(':')) continue; // 空行/心跳注释
        if (!line.startsWith('data:')) continue; // 忽略 event:/id:/retry:
        final data = line.substring(5).trim();
        if (data == '[DONE]') break;
        if (data.isEmpty) continue;
        yield data;
      }
      // 流结束/订阅取消:连接由常驻 _client 管理(取消会断开该次连接并回收)。
  }

  static Future<String> _send({
    required String method,
    required String url,
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    required Duration connectTimeout,
    required Duration ioTimeout,
  }) async {
    final uri = Uri.parse(url);
    final req = await (method == 'GET'
            ? _client.getUrl(uri)
            : _client.postUrl(uri))
        .timeout(connectTimeout);
    req.headers.contentType = ContentType.json;
    headers?.forEach(req.headers.set);
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close().timeout(ioTimeout);
    final text = await res.transform(utf8.decoder).join().timeout(ioTimeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final brief =
          LogSanitize.mask(LogSanitize.brief(text));
      AppLog.instance.e('HTTP $method ${LogSanitize.mask(url)} → ${res.statusCode}: $brief');
      throw HttpJsonException(res.statusCode, '服务返回 ${res.statusCode}: $brief');
    }
    return text;
  }
}
