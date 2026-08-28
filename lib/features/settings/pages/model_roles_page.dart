import 'package:flutter/material.dart';

import 'package:chronos/core/services/ai_provider.dart';
import 'package:chronos/core/services/key_store.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';

/// 分用途选模型(RikkaHub 式):聊天 / 快速 / OCR / 翻译 / 标题 各自
/// 从所有提供商的模型里选择。快速/OCR 等留空时按各自约定回退。
class ModelRolesPage extends StatefulWidget {
  const ModelRolesPage({super.key});

  @override
  State<ModelRolesPage> createState() => _ModelRolesPageState();
}

class _ModelRolesPageState extends State<ModelRolesPage> {
  late Future<Map<String, String>> _refsFuture;

  @override
  void initState() {
    super.initState();
    _refsFuture = _loadRefs();
  }

  Future<Map<String, String>> _loadRefs() async {
    return {
      'chat': await AiProviders.chatModelRef(),
      'fast': await AiProviders.fastModelRef(),
      'ocr': await AiProviders.ocrModelRef(),
      'translate': await AiProviders.translateModelRef(),
      'title': await AiProviders.titleModelRef(),
    };
  }

  /// 全部「provider · model」选项(只取启用且非空的提供商)。
  List<({String ref, String label})> _allOptions(
      List<AiProvider> providers) {
    return [
      for (final p in providers)
        if (p.enabled)
          for (final m in p.models)
            (ref: ModelRef(p.id, m).ref, label: '${p.name} · $m'),
    ];
  }

  /// 选项里显示的名字(找得到返回 provider·model,找不到返回原文)。
  String _labelOf(Map<String, String> refs, String key, List<AiProvider> ps) {
    final ref = refs[key] ?? '';
    final r = ModelRef.parse(ref);
    if (r == null || r.modelId.isEmpty) return '未设置';
    for (final p in ps) {
      if (p.id == r.providerId) return '${p.name} · ${r.modelId}';
    }
    return r.modelId;
  }

  Future<void> _pick(
      String key, String title, List<AiProvider> providers) async {
    final options = _allOptions(providers);
    if (options.isEmpty) {
      showFrostedSnack(context, '还没有可选的模型,先到「提供商」添加');
      return;
    }
    final current = (await _loadRefs())[key] ?? '';
    if (!mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    ListTile(
                      leading: Icon(
                        o.ref == current
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color: o.ref == current
                            ? AppColors.primaryDark
                            : AppColors.textSub,
                      ),
                      title: Text(o.label,
                          style: const TextStyle(fontSize: 14)),
                      onTap: () => Navigator.of(ctx).pop(o.ref),
                    ),
                ],
              ),
            ),
            if (key != 'chat')
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(''),
                  child: Text('清除(回退默认)',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSub)),
                ),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final k = switch (key) {
      'chat' => AiProviders.chatModelKey,
      'fast' => AiProviders.fastModelKey,
      'ocr' => AiProviders.ocrModelKey,
      'translate' => AiProviders.translateModelKey,
      _ => AiProviders.titleModelKey,
    };
    await KeyStore.instance.set(k, selected);
    setState(() => _refsFuture = _loadRefs());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模型与服务')),
      body: FutureBuilder<Map<String, String>>(
        future: _refsFuture,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final refs = snap.data!;
          return FutureBuilder<List<AiProvider>>(
            future: AiProviders.load(),
            builder: (context, psnap) {
              final ps = psnap.data ?? const <AiProvider>[];
              Widget item(String key, String title, String desc) {
                return ListTile(
                  leading: Icon(Icons.smart_toy_outlined,
                      size: 22, color: AppColors.primaryDark),
                  title: Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  subtitle: Text(desc,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSub)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          _labelOf(refs, key, ps),
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSub),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          size: 20, color: Colors.grey),
                    ],
                  ),
                  onTap: () => _pick(key, title, ps),
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Card(
                    child: Column(
                      children: [
                        item('chat', '聊天模型', '闲话铺对话使用的模型'),
                        FutureBuilder<String>(
                          future: KeyStore.instance
                              .get(KeyStore.llmSupports1m),
                          builder: (context, snap) => SwitchListTile(
                            contentPadding:
                                const EdgeInsets.only(left: 56, right: 8),
                            dense: true,
                            title: const Text(
                              '该聊天模型支持 1M 上下文',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '勾选:上下文预算 100 万 token;不勾选:20 万',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textSub),
                            ),
                            value: snap.data == '1',
                            onChanged: (v) async {
                              await KeyStore.instance.set(
                                  KeyStore.llmSupports1m, v ? '1' : '');
                              if (!context.mounted) return;
                              showFrostedSnack(context,
                                  v ? '已按 1M 上下文档位' : '已按默认档位');
                            },
                          ),
                        ),
                        const Divider(height: 1, indent: 56),
                        item('fast', '快速模型', '记忆提炼 / 上下文摘要,留空复用聊天模型'),
                        const Divider(height: 1, indent: 56),
                        item('ocr', 'OCR 模型', '图片识别,发图时聊天模型不支持则回退'),
                        const Divider(height: 1, indent: 56),
                        item('translate', '翻译模型', '长按消息翻译,留空复用聊天模型'),
                        const Divider(height: 1, indent: 56),
                        item('title', '标题模型', '会话标题生成,留空复用聊天模型'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '模型来自「提供商」里添加的模型列表;未配置时聊天不可用。',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSub, height: 1.5),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
