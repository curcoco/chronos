import 'package:flutter/material.dart';

import 'package:student_workbench/core/services/key_store.dart';
import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/core/widgets/frosted_snack.dart';

/// API 配置:中转站 / elevenlabs / 心知天气 / Supabase 的地址与密钥。
/// 全部存本机(SharedPreferences),不入源码;密钥输入框默认遮显。
class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key});

  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  final Map<String, TextEditingController> _ctrls = {};
  final Set<String> _secret = {
    KeyStore.llmApiKey,
    KeyStore.elevenApiKey,
    KeyStore.weatherApiKey,
    KeyStore.supabaseAnonKey,
  };
  final Set<String> _revealed = {};

  static const Map<String, String> _labels = {
    KeyStore.llmBaseUrl: '中转站地址',
    KeyStore.llmApiKey: '中转站 API Key',
    KeyStore.llmModel: '对话模型',
    KeyStore.llmFastModel: '快速模型(记忆提炼)',
    KeyStore.elevenApiKey: 'elevenlabs API Key',
    KeyStore.elevenVoiceId: '语音 ID',
    KeyStore.weatherApiKey: '心知天气 Key',
    KeyStore.supabaseUrl: 'Supabase 地址',
    KeyStore.supabaseAnonKey: 'Supabase anon key',
  };

  static const Map<String, String> _hints = {
    KeyStore.llmBaseUrl: 'https://…/v1',
    KeyStore.llmApiKey: 'sk-…',
    KeyStore.llmModel: '如 deepseek-chat / gpt-4o-mini',
    KeyStore.llmFastModel: '如 deepseek-chat(留空则复用对话模型)',
    KeyStore.elevenApiKey: 'sk_…',
    KeyStore.elevenVoiceId: '如 BqljjWyTnrioXPCNkCd4',
    KeyStore.weatherApiKey: '心知天气私钥',
    KeyStore.supabaseUrl: 'https://….supabase.co',
    KeyStore.supabaseAnonKey: 'eyJ…(anon public key)',
  };

  @override
  void initState() {
    super.initState();
    for (final k in KeyStore.allKeys) {
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
              '所有密钥仅保存在本机,不会写入源码或上传。'
              '含密钥的字段输入时默认遮显,点眼睛可查看。',
              style: TextStyle(fontSize: 12, color: Color(0xFFE65100), height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          for (final k in KeyStore.allKeys) ...[
            _field(k),
            const SizedBox(height: 10),
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
