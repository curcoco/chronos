import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/services/http_json.dart';
import 'package:chronos/core/services/key_store.dart';
import 'package:chronos/core/utils/log_sanitize.dart';

/// 一个 AI 提供商(中转站):独立地址 / Key / 启用开关 / 模型列表。
/// 由 [AiProviders] 整体序列化存于安全存储(含 API Key,Keystore 加密)。
class AiProvider {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final bool enabled;

  /// 该提供商可用的模型 ID 列表(手填,或从服务商拉取后保存)。
  final List<String> models;

  const AiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    this.enabled = true,
    this.models = const [],
  });

  AiProvider copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    bool? enabled,
    List<String>? models,
  }) {
    return AiProvider(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      enabled: enabled ?? this.enabled,
      models: models ?? this.models,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'enabled': enabled,
        'models': models,
      };

  factory AiProvider.fromJson(Map<String, dynamic> j) => AiProvider(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        baseUrl: (j['baseUrl'] as String?) ?? '',
        apiKey: (j['apiKey'] as String?) ?? '',
        enabled: (j['enabled'] as bool?) ?? true,
        models: [
          for (final m in (j['models'] as List?) ?? const [])
            if (m is String && m.isNotEmpty) m,
        ],
      );
}

/// 模型引用:「提供商id|模型id」(模型 id 可能含 `/` 等字符,故用 `|` 分隔)。
class ModelRef {
  final String providerId;
  final String modelId;

  const ModelRef(this.providerId, this.modelId);

  String get ref => '$providerId|$modelId';

  static ModelRef? parse(String? s) {
    if (s == null || s.isEmpty) return null;
    final i = s.indexOf('|');
    if (i <= 0 || i >= s.length - 1) return null;
    return ModelRef(s.substring(0, i), s.substring(i + 1));
  }
}

/// 常见服务商模板(非推广,官方 OpenAI 兼容端点):添加提供商时一键预填
/// 名称与地址,Key 留空由用户填写。
class RecommendedProvider {
  final String name;
  final String baseUrl;
  const RecommendedProvider(this.name, this.baseUrl);
}

const List<RecommendedProvider> recommendedAiProviders = [
  RecommendedProvider('DeepSeek', 'https://api.deepseek.com/v1'),
  RecommendedProvider('硅基流动', 'https://api.siliconflow.cn/v1'),
  RecommendedProvider('OpenRouter', 'https://openrouter.ai/api/v1'),
  RecommendedProvider('智谱 AI', 'https://open.bigmodel.cn/api/paas/v4'),
  RecommendedProvider('通义千问', 'https://dashscope.aliyuncs.com/compatible-mode/v1'),
  RecommendedProvider('Kimi(Moonshot)', 'https://api.moonshot.cn/v1'),
  RecommendedProvider('OpenAI', 'https://api.openai.com/v1'),
  RecommendedProvider('Google Gemini', 'https://generativelanguage.googleapis.com/v1beta/openai/'),
  RecommendedProvider('Ollama 本地', 'http://localhost:11434/v1'),
];

/// 提供商仓储:整体存取于安全存储(含 API Key)。
/// 首次启动把旧的单中转站配置(llm_base_url / llm_api_key / llm_model …)
/// 迁移为一个名为「默认中转」的提供商,并同步各用途模型引用。
class AiProviders {
  AiProviders._();

  static const String _key = 'ai_providers';

  /// 各用途模型引用键("providerId|modelId")。
  static const String chatModelKey = 'chat_model_ref';
  static const String fastModelKey = 'fast_model_ref';
  static const String ocrModelKey = 'ocr_model_ref';
  static const String translateModelKey = 'translate_model_ref';
  static const String titleModelKey = 'title_model_ref';

  static const List<String> modelRefKeys = [
    chatModelKey,
    fastModelKey,
    ocrModelKey,
    translateModelKey,
    titleModelKey,
  ];

  static Future<List<AiProvider>> load() async {
    final raw = await KeyStore.instance.get(_key);
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          if (e is Map<String, dynamic>) AiProvider.fromJson(e),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<AiProvider> list) => KeyStore.instance
      .set(_key, jsonEncode([for (final p in list) p.toJson()]));

  /// 按 id 查找;id 为空或找不到时回退到第一个启用的提供商。
  static Future<AiProvider?> find(String? providerId) async {
    final list = await load();
    if (providerId != null) {
      for (final p in list) {
        if (p.id == providerId) return p;
      }
    }
    for (final p in list) {
      if (p.enabled) return p;
    }
    return list.isEmpty ? null : list.first;
  }

  /// 解析模型引用 → (baseUrl, apiKey, modelId);未配置/格式错误返回 null。
  static Future<({String baseUrl, String apiKey, String model})?> resolve(
      String ref) async {
    final r = ModelRef.parse(ref);
    final p = await find(r?.providerId);
    if (p == null || p.baseUrl.trim().isEmpty || p.apiKey.isEmpty) return null;
    if (r == null || r.modelId.isEmpty) return null;
    return (baseUrl: p.baseUrl, apiKey: p.apiKey, model: r.modelId);
  }

  /// 旧版单中转站配置 → 默认提供商(幂等:providers 已有内容则跳过)。
  static Future<void> migrateLegacyIfNeeded() async {
    if ((await KeyStore.instance.get(_key)).isNotEmpty) return;
    final baseUrl = await KeyStore.instance.get(KeyStore.llmBaseUrl);
    if (baseUrl.isEmpty) return;
    final apiKey = await KeyStore.instance.get(KeyStore.llmApiKey);
    final chat = await KeyStore.instance.get(KeyStore.llmModel);
    final fast = await KeyStore.instance.get(KeyStore.llmFastModel);
    final ocr = await KeyStore.instance.get(KeyStore.llmOcrModel);
    const defId = 'default';
    final provider = AiProvider(
      id: defId,
      name: '默认中转',
      baseUrl: baseUrl,
      apiKey: apiKey,
      models: [
        if (chat.isNotEmpty) chat,
        if (fast.isNotEmpty && fast != chat) fast,
        if (ocr.isNotEmpty && ocr != chat && ocr != fast) ocr,
      ],
    );
    await save([provider]);
    if (chat.isNotEmpty) {
      await KeyStore.instance.set(chatModelKey, ModelRef(defId, chat).ref);
    }
    if (fast.isNotEmpty) {
      await KeyStore.instance.set(fastModelKey, ModelRef(defId, fast).ref);
    }
    if (ocr.isNotEmpty) {
      await KeyStore.instance.set(ocrModelKey, ModelRef(defId, ocr).ref);
    }
  }

  /// 各用途模型引用读取(空字符串 = 未配置)。
  static Future<String> chatModelRef() =>
      KeyStore.instance.get(chatModelKey);
  static Future<String> fastModelRef() =>
      KeyStore.instance.get(fastModelKey);
  static Future<String> ocrModelRef() => KeyStore.instance.get(ocrModelKey);
  static Future<String> translateModelRef() =>
      KeyStore.instance.get(translateModelKey);
  static Future<String> titleModelRef() =>
      KeyStore.instance.get(titleModelKey);

  /// 聊天是否已配置:聊天模型引用的提供商地址/Key/模型齐全。
  static Future<bool> isChatConfigured() async {
    final ref = await chatModelRef();
    final r = ModelRef.parse(ref);
    final p = await find(r?.providerId);
    if (p == null) return false;
    return p.baseUrl.trim().isNotEmpty &&
        p.apiKey.isNotEmpty &&
        (r?.modelId.isNotEmpty ?? false);
  }

  /// 从服务商拉取模型列表(OpenAI 兼容 `GET {baseUrl}/models`)。
  /// 返回模型 id 列表;接口不支持/网络失败返回空列表(由调用方提示)。
  static Future<List<String>> fetchModels({
    required String url,
    required String apiKey,
  }) async {
    var base = url.replaceAll(RegExp(r'/$'), '');
    if (base.endsWith('/chat/completions')) {
      base = base.substring(0, base.length - '/chat/completions'.length);
    }
    final endpoint = '$base/models';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client
          .getUrl(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 8));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      final res = await req.close().timeout(const Duration(seconds: 12));
      final body =
          await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
      if (res.statusCode != HttpStatus.ok) return const [];
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) return const [];
      final list = data['data'];
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map<String, dynamic> &&
              e['id'] is String &&
              (e['id'] as String).isNotEmpty)
            e['id'] as String,
      ];
    } catch (_) {
      return const [];
    } finally {
      client.close(force: true);
    }
  }

  /// 测试连接:向 `/chat/completions` 发一个最小请求,
  /// 拿到任何非空响应体(含 4xx 错误体)都视为端点连通。
  static Future<bool> testConnection({
    required String url,
    required String apiKey,
  }) async {
    final base = url.replaceAll(RegExp(r'/$'), '');
    final endpoint = base.endsWith('/chat/completions')
        ? base
        : '$base/chat/completions';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client
          .postUrl(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 8));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      req.write(jsonEncode({
        'model': 'gpt-3.5-turbo',
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
        'max_tokens': 1,
        'stream': false,
      }));
      final res = await req.close().timeout(const Duration(seconds: 12));
      final body =
          await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
      return res.statusCode >= 200 && res.statusCode < 500 && body.trim().isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// 生图端点(OpenAI 兼容 /images/generations):兼容根地址 / 带 /v1 / 已带完整端点。
  /// 与 [LlmService.endpointFor](只补 /chat/completions)不同:生图端点通常在
  /// `/v1` 之下,故对不含版本路径段的基础地址补 `/v1`。
  static String imageEndpointFor(String url) {
    var b = url.replaceAll(RegExp(r'/$'), '');
    if (b.endsWith('/images/generations')) return b;
    // 已含版本路径段(如 /v1、/openai/v1)不重复补。
    if (!RegExp(r'/(v\d+)$').hasMatch(b)) b = '$b/v1';
    return '$b/images/generations';
  }

  /// 生图(OpenAI 兼容 `/images/generations`):文字提示(可带底图/风格/尺寸/张数)
  /// → 图片字节列表。失败抛 [ImageGenException](带用户可读原因与状态码)。
  ///
  /// - 走统一 [HttpJson],连接池复用 + 失败日志脱敏 + 错误体透出;
  /// - 默认请求 `response_format: b64_json`(多数中转站支持,避免二次下载 url);
  /// - 兜底解析 `url`(经 [HttpJson.getBytes] 下载);
  /// - mime 按图片头字节判断,不写死。
  static Future<List<ImageGenResult>> generateImage({
    required String url,
    required String apiKey,
    required ImageGenOptions options,
  }) async {
    final endpoint = imageEndpointFor(url);
    final primary = options.toBody();

    // 部分模型/代理不支持 size/quality/style/n>1 等可选参数 → 400/422。
    // 此时去掉这些可选参数重试一次(只保留 model/prompt/n=1/response_format),
    // 保证「基本生图可用」,与聊天路径的 400/422 降级哲学一致。
    Map<String, dynamic> data;
    try {
      data = await _postGenSafe(endpoint, apiKey, primary);
    } on ImageGenException catch (e) {
      if ((e.statusCode == 400 || e.statusCode == 422) &&
          _hasOptionalParams(primary)) {
        data = await _postGenSafe(endpoint, apiKey, _reducedBody(primary));
      } else {
        rethrow;
      }
    }

    final list = data['data'];
    if (list is! List || list.isEmpty) {
      throw ImageGenException('生成图片失败:服务商未返回图片');
    }
    final results = <ImageGenResult>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final b64 = item['b64_json'] as String?;
      if (b64 != null && b64.isNotEmpty) {
        results.add(ImageGenResult(base64Decode(b64)));
        continue;
      }
      final urlStr = item['url'] as String?;
      if (urlStr != null && urlStr.isNotEmpty) {
        final bytes = await _downloadImage(urlStr);
        if (bytes != null) results.add(ImageGenResult(bytes));
      }
    }
    if (results.isEmpty) {
      throw ImageGenException('生成图片失败:服务商未返回图片');
    }
    return results;
  }

  /// 按图片头字节判断 mime(不写死;识别不了回退 png)。
  static String mimeForBytes(Uint8List b) {
    if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E &&
        b[3] == 0x47) {
      return 'image/png';
    }
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 &&
        b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 &&
        b[11] == 0x50) {
      return 'image/webp';
    }
    if (b.length >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 &&
        b[3] == 0x38) {
      return 'image/gif';
    }
    return 'image/png';
  }

  static Future<Uint8List?> _downloadImage(String url) async {
    try {
      final bytes = await HttpJson.getBytes(
        url,
        connectTimeout: const Duration(seconds: 20),
        ioTimeout: const Duration(seconds: 90),
      );
      if (bytes.isEmpty) return null;
      return Uint8List.fromList(bytes);
    } catch (e) {
      AppLog.instance.e('生图 URL 下载失败:${LogSanitize.mask(url)} $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> _postGen(
      String endpoint, String apiKey, Map<String, dynamic> body) {
    return HttpJson.postJson(
      endpoint,
      headers: {HttpHeaders.authorizationHeader: 'Bearer $apiKey'},
      body: body,
      connectTimeout: const Duration(seconds: 15),
      ioTimeout: const Duration(seconds: 120),
    );
  }

  /// 统一错误包装:网络/非 2xx 一律转成 [ImageGenException](带可读原因与状态码)。
  static Future<Map<String, dynamic>> _postGenSafe(
      String endpoint, String apiKey, Map<String, dynamic> body) async {
    try {
      return await _postGen(endpoint, apiKey, body);
    } on ImageGenException {
      rethrow;
    } on HttpJsonException catch (e) {
      throw ImageGenException(_friendlyGenError(e), statusCode: e.statusCode);
    } on Exception catch (e) {
      AppLog.instance.e('生图请求异常:${LogSanitize.mask(endpoint)} $e');
      throw ImageGenException('生成图片失败:网络异常,请稍后重试');
    }
  }

  /// 去可选参数的重试体:去掉 size/quality/style/negative_prompt,n 收敛为 1。
  static Map<String, dynamic> _reducedBody(Map<String, dynamic> body) {
    final m = Map<String, dynamic>.from(body)
      ..remove('size')
      ..remove('quality')
      ..remove('style')
      ..remove('negative_prompt');
    m['n'] = 1;
    return m;
  }

  /// 请求体是否含「可能不被支持」的可选参数(触发降级重试的条件)。
  static bool _hasOptionalParams(Map<String, dynamic> body) {
    return body.containsKey('size') ||
        body.containsKey('quality') ||
        body.containsKey('style') ||
        body.containsKey('negative_prompt') ||
        (body['n'] is int && (body['n'] as int) > 1);
  }

  static String _friendlyGenError(HttpJsonException e) {
    switch (e.statusCode) {
      case 400:
        return '生成失败:模型或参数不受支持(400),请换生图模型或调整参数';
      case 401:
      case 403:
        return '生成失败:密钥无效或无权限(${e.statusCode}),请检查生图模型 Key';
      case 402:
      case 429:
        return '生成失败:额度不足或请求太频繁(${e.statusCode}),请稍后再试';
      case 404:
        return '生成失败:生图端点不存在(404),请检查生图模型地址';
      case 422:
        return '生成失败:提示词或参数不合法(422),请调整后重试';
      default:
        return '生成失败:服务返回 ${e.statusCode}(${e.message}),请检查生图模型配置';
    }
  }
}

/// 生图请求参数(OpenAI 兼容 `/images/generations`)。
class ImageGenOptions {
  final String model;

  /// 正向提示词。非空必填。
  final String prompt;

  /// 负向提示词(部分模型支持,作为可选项;不支持时会 400,由调用方兜底)。
  final String? negativePrompt;

  /// 尺寸,如 `1024x1024` / `1792x1024` / `1024x1792`;null 由服务商默认。
  final String? size;

  /// 清晰度:`standard` / `hd`。
  final String? quality;

  /// 一次生成的张数(1~4)。默认 1。
  final int n;

  /// 响应格式:`b64_json` / `url`。默认 `b64_json`(避免二次下载)。
  final String? responseFormat;

  /// 风格(部分模型支持):`vivid` / `natural` 等。
  final String? style;

  /// 图生图/编辑底图(base64,不含 `data:` 前缀);null = 文生图。
  final String? imageBase64;

  const ImageGenOptions({
    required this.model,
    required this.prompt,
    this.negativePrompt,
    this.size,
    this.quality,
    this.n = 1,
    this.responseFormat = 'b64_json',
    this.style,
    this.imageBase64,
  });

  /// 发送到服务商的请求体(供单测校验参数是否按需带上)。
  Map<String, dynamic> toBody() {
    final body = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      'n': n,
      'response_format': responseFormat ?? 'b64_json',
    };
    if (size != null) body['size'] = size;
    if (quality != null) body['quality'] = quality;
    if (style != null) body['style'] = style;
    if (negativePrompt != null && negativePrompt!.isNotEmpty) {
      body['negative_prompt'] = negativePrompt;
    }
    if (imageBase64 != null && imageBase64!.isNotEmpty) {
      body['image'] = imageBase64;
    }
    return body;
  }
}

/// 生图结果:图片字节 + 按字节头推导的 mime/扩展名。
class ImageGenResult {
  final Uint8List bytes;
  ImageGenResult(this.bytes);

  String get mime => AiProviders.mimeForBytes(bytes);
  String get ext => switch (mime) {
        'image/jpeg' => 'jpg',
        'image/webp' => 'webp',
        'image/gif' => 'gif',
        _ => 'png',
      };
}

/// 生图失败(带用户可读原因与可选的 HTTP 状态码)。
class ImageGenException implements Exception {
  final String message;
  final int? statusCode;
  const ImageGenException(this.message, {this.statusCode});

  @override
  String toString() => message;
}
