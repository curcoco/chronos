import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// API 密钥与连接配置:应用内设置,存本机安全存储(Android Keystore 加密)。
/// 源码与 APK 常量里不再有任何密钥明文;首次使用在「系统设置 → API 配置」填写。
///
/// 迁移:2.1.x 及更早版本把密钥明文存在 SharedPreferences(`api_` 前缀),
/// 这里在首次读取时自动迁入安全存储并删除旧值,调用方无感。
class KeyStore {
  KeyStore._();
  static final KeyStore instance = KeyStore._();

  static const String llmBaseUrl = 'llm_base_url';
  static const String llmApiKey = 'llm_api_key';
  static const String llmModel = 'llm_model';

  /// 聊天模型是否支持 1M 上下文('1' = 支持;空/其它 = 按默认 200k 档)。
  /// 影响闲话铺上下文 token 预算与预警线(见 core/utils/context_budget.dart)。
  /// 注意:刻意不放进 [allKeys](API 配置页以勾选框单独呈现,不渲染成文本框)。
  static const String llmSupports1m = 'llm_supports_1m';
  static const String llmFastModel = 'llm_fast_model';
  static const String llmOcrModel = 'llm_ocr_model';
  static const String tavilyApiKey = 'tavily_api_key';
  static const String elevenApiKey = 'eleven_api_key';
  static const String elevenVoiceId = 'eleven_voice_id';
  static const String weatherApiKey = 'weather_api_key';
  static const String nocturneUrl = 'nocturne_url';
  static const String nocturneToken = 'nocturne_token';
  static const String updateCheckUrl = 'update_check_url';

  /// 生图模型(GPT-image-2 等,OpenAI 兼容 /images/generations,独立于聊天模型)。
  static const String imageGenUrl = 'image_gen_url';
  static const String imageGenKey = 'image_gen_key';
  static const String imageGenModel = 'image_gen_model';

  /// 生图工作台选中的模型引用("providerId|modelId",见 AiProviders)。
  /// 刻意不放进 [allKeys](API 配置页以文本框渲染,生图模型选择在生图工作台内)。
  static const String imageGenRef = 'image_gen_ref';

  static const List<String> allKeys = [
    llmBaseUrl,
    llmApiKey,
    llmModel,
    llmFastModel,
    llmOcrModel,
    tavilyApiKey,
    elevenApiKey,
    elevenVoiceId,
    weatherApiKey,
    nocturneUrl,
    nocturneToken,
    updateCheckUrl,
    imageGenUrl,
    imageGenKey,
    imageGenModel,
  ];

  static const String _legacyPrefix = 'api_';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String> get(String key) async {
    final secure = await _storage.read(key: key);
    if (secure != null && secure.isNotEmpty) return secure;
    // 旧版本地迁移:SharedPreferences 里的 `api_<key>` 迁入安全存储后删除。
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString('$_legacyPrefix$key');
    if (legacy == null || legacy.isEmpty) return '';
    await _storage.write(key: key, value: legacy);
    await prefs.remove('$_legacyPrefix$key');
    return legacy;
  }

  Future<void> set(String key, String value) async {
    final v = value.trim();
    if (v.isEmpty) {
      await _storage.delete(key: key);
      return;
    }
    await _storage.write(key: key, value: v);
  }
}
