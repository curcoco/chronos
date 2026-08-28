import 'package:flutter/material.dart';

import 'package:chronos/core/services/key_store.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';

/// API 配置:搜索(Tavily) / 语音(elevenlabs) / 天气 / 外置记忆(Nocturne)。
/// 中转站与模型已由「设置 → 模型与服务」的提供商 / 模型页管理,不在本页。
/// 全部存本机安全存储,不入源码;密钥输入框默认遮显。
class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key});

  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  final Map<String, TextEditingController> _ctrls = {};
  final Set<String> _secret = {
    KeyStore.elevenApiKey,
    KeyStore.weatherApiKey,
    KeyStore.nocturneToken,
    KeyStore.tavilyApiKey,
    KeyStore.imageGenKey,
  };
  final Set<String> _revealed = {};

  /// 中转站相关键由「模型与服务 → 提供商」管理,本页不渲染。
  static const Set<String> _providerKeys = {
    KeyStore.llmBaseUrl,
    KeyStore.llmApiKey,
    KeyStore.llmModel,
    KeyStore.llmFastModel,
    KeyStore.llmOcrModel,
  };

  static const Map<String, String> _labels = {
    KeyStore.tavilyApiKey: 'Tavily API Key(联网搜索)',
    KeyStore.elevenApiKey: 'elevenlabs API Key',
    KeyStore.elevenVoiceId: '语音 ID',
    KeyStore.weatherApiKey: '心知天气 Key',
    KeyStore.nocturneUrl: '外置记忆地址',
    KeyStore.nocturneToken: '外置记忆 token',
    KeyStore.imageGenUrl: '生图模型地址',
    KeyStore.imageGenKey: '生图模型 Key',
    KeyStore.imageGenModel: '生图模型 ID',
  };

  static const Map<String, String> _hints = {
    KeyStore.tavilyApiKey: 'tvly-…(https://app.tavily.com 获取)',
    KeyStore.elevenApiKey: 'sk_…',
    KeyStore.elevenVoiceId: '如 BqljjWyTnrioXPCNkCd4',
    KeyStore.weatherApiKey: '心知天气私钥',
    KeyStore.nocturneUrl: 'http://host:8000/mcp(Nocturne MCP)',
    KeyStore.nocturneToken: 'MCP 访问鉴权 token',
    KeyStore.imageGenUrl: '如 https://中转站/v1(支持 /images/generations)',
    KeyStore.imageGenKey: '可复用中转站 Key',
    KeyStore.imageGenModel: '如 gpt-image-2',
  };

  @override
  void initState() {
    super.initState();
    for (final k in KeyStore.allKeys) {
      if (_providerKeys.contains(k)) continue;
      _ctrls[k] = TextEditingController();
      KeyStore.instance.get(k).then((v) {
        if (mounted) _ctrls[k]!.text = v;
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    for (final k in KeyStore.allKeys) {
      // 更新源地址由「系统设置」页单独编辑;这里不渲染也不写回,
      // 避免本页保存时用旧值覆盖用户刚改的更新源。
      if (k == KeyStore.updateCheckUrl) continue;
      if (_providerKeys.contains(k)) continue;
      await KeyStore.instance.set(k, _ctrls[k]!.text);
    }
    if (!mounted) return;
    showFrostedSnack(context, '配置已保存(仅存本机)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API 配置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '中转站与聊天/快速/OCR 模型请到「设置 → 模型与服务」配置。\n以下密钥仅存本机,字段默认遮显,可点眼睛查看。',
              style: TextStyle(fontSize: 12, color: Color(0xFFE65100), height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          for (final k in KeyStore.allKeys) ...[
            if (!_providerKeys.contains(k)) ...[
              _field(k),
              const SizedBox(height: 10),
            ],
          ],
          const SizedBox(height: 6),
          FilledButton(onPressed: _save, child: const Text('保存配置')),
        ],
      ),
    );
  }

  Widget _field(String key) {
    final secret = _secret.contains(key);
    final revealed = _revealed.contains(key);
    return TextField(
      controller: _ctrls[key],
      obscureText: secret && !revealed,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: _labels[key],
        hintText: _hints[key],
        isDense: true,
        suffixIcon: secret
            ? IconButton(
                icon: Icon(
                  revealed ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  size: 18,
                  color: AppColors.textSub,
                ),
                onPressed: () => setState(() {
                  if (revealed) {
                    _revealed.remove(key);
                  } else {
                    _revealed.add(key);
                  }
                }),
              )
            : null,
      ),
    );
  }
}
