import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chronos/core/services/key_store.dart';

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
  static String imageEndpointFor(String url) {
    var b = url.replaceAll(RegExp(r'/$'), '');
    if (b.endsWith('/images/generations')) return b;
    if (!b.endsWith('/v1')) b = '$b/v1';
    return '$b/images/generations';
  }

  /// 生图(OpenAI 兼容 `/images/generations`):文字提示 → 图片字节。
  /// 返回解码后的 (图片字节, mime);失败/服务商不支持返回 null。
  static Future<({Uint8List bytes, String mime})?> generateImage({
    required String url,
    required String apiKey,
    required String model,
    required String prompt,
  }) async {
    final endpoint = imageEndpointFor(url);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client
          .postUrl(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 15));
      req.headers.contentType = ContentType.json;
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      req.write(jsonEncode({'model': model, 'prompt': prompt}));
      final res = await req.close().timeout(const Duration(seconds: 90));
      final body =
          await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 90));
      if (res.statusCode != HttpStatus.ok) return null;
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) return null;
      final list = data['data'];
      if (list is! List || list.isEmpty) return null;
      final item = list.first;
      if (item is! Map<String, dynamic>) return null;
      // b64_json 优先(多数中转站),其次 url(需下载)。
      final b64 = item['b64_json'] as String?;
      if (b64 != null && b64.isNotEmpty) {
        return (bytes: base64Decode(b64), mime: 'image/png');
      }
      final urlStr = item['url'] as String?;
      if (urlStr != null && urlStr.isNotEmpty) {
        final imgReq =
            await client.getUrl(Uri.parse(urlStr)).timeout(const Duration(seconds: 20));
        final imgRes = await imgReq.close().timeout(const Duration(seconds: 90));
        final bytes = await imgRes
            .fold<List<int>>(<int>[], (a, b) => a..addAll(b))
            .timeout(const Duration(seconds: 90));
        if (bytes.isEmpty) return null;
        return (bytes: Uint8List.fromList(bytes), mime: 'image/png');
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
