import 'package:flutter/material.dart';

import 'package:chronos/core/services/ai_provider.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/widgets/app_text_field.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';
import 'package:chronos/core/widgets/status_views.dart';
import 'package:chronos/features/settings/pages/provider_detail_page.dart';

/// 提供商管理(RikkaHub 式):多个中转站,各自独立 地址/Key/启用/模型列表。
/// 列表页:搜索 + 卡片(名称/地址/模型数/启用开关) + 添加。
class ProviderListPage extends StatefulWidget {
  const ProviderListPage({super.key});

  @override
  State<ProviderListPage> createState() => _ProviderListPageState();
}

class _ProviderListPageState extends State<ProviderListPage> {
  List<AiProvider> _providers = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AiProviders.load();
    if (!mounted) return;
    setState(() {
      _providers = list;
      _loading = false;
    });
  }

  Future<void> _save(List<AiProvider> list) async {
    await AiProviders.save(list);
    if (!mounted) return;
    setState(() => _providers = list);
  }

  /// 添加提供商:底部弹窗填 名称/地址/Key,保存后置顶。
  Future<void> _add() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加提供商'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('常用服务商(点选预填,再填 Key)',
                style: TextStyle(fontSize: 12, color: AppColors.textSub)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in recommendedAiProviders)
                  ActionChip(
                    label: Text(r.name,
                        style: const TextStyle(fontSize: 12)),
                    backgroundColor: AppColors.primaryLight
                        .withValues(alpha: 0.35),
                    side: BorderSide(color: AppColors.line),
                    onPressed: () {
                      nameCtrl.text = r.name;
                      urlCtrl.text = r.baseUrl;
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: nameCtrl,
              hintText: '名称,如:硅基流动 / 我的中转',
              maxLines: 1,
            ),
            const SizedBox(height: 10),
            AppTextField(
              controller: urlCtrl,
              hintText: '地址,如 https://api.xxx.com/v1',
              maxLines: 1,
            ),
            const SizedBox(height: 10),
            AppTextField(
              controller: keyCtrl,
              hintText: 'API Key',
              maxLines: 1,
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final url = urlCtrl.text.trim();
              final key = keyCtrl.text.trim();
              if (name.isEmpty || url.isEmpty || key.isEmpty) {
                showFrostedSnack(context, '名称/地址/Key 都不能为空');
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final name = nameCtrl.text.trim();
    final url = urlCtrl.text.trim();
    final key = keyCtrl.text.trim();
    final provider = AiProvider(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      baseUrl: url,
      apiKey: key,
    );
    await _save([provider, ..._providers]);
    if (!mounted) return;
    showFrostedSnack(context, '已添加提供商「$name」');
  }

  Future<void> _toggle(AiProvider p, bool enabled) async {
    await _save([
      for (final x in _providers) x.id == p.id ? x.copyWith(enabled: enabled) : x,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? _providers
        : [
            for (final p in _providers)
              if (p.name.toLowerCase().contains(_query.toLowerCase()) ||
                  p.baseUrl.toLowerCase().contains(_query.toLowerCase()))
                p,
          ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('提供商'),
        actions: [
          IconButton(
            onPressed: _add,
            icon: const Icon(Icons.add_rounded),
            tooltip: '添加提供商',
          ),
        ],
      ),
      body: _loading
          ? const LoadingView(hint: '加载中…')
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: '搜索提供商…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => setState(() => _query = ''),
                            ),
                      filled: true,
                      fillColor: AppColors.card,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            BorderSide(color: AppColors.primary, width: 1.6),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _providers.isEmpty
                      ? EmptyView(
                          icon: Icons.dns_outlined,
                          message: '还没有提供商\n点右上角 + 添加你的中转站\n(地址 + API Key + 模型)',
                        )
                      : filtered.isEmpty
                          ? const EmptyView(
                              icon: Icons.search_off_rounded,
                              message: '没有匹配的提供商\n换个关键词试试',
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final p = filtered[i];
                                return Material(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              ProviderDetailPage(provider: p),
                                        ),
                                      );
                                      _load();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          14, 10, 8, 10),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  AppColors.primaryLight,
                                                  AppColors.primarySoft,
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              p.name.isEmpty
                                                  ? '?'
                                                  : p.name.substring(0, 1),
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.primaryDark,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  p.name,
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight:
                                                        FontWeight.w700,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  p.baseUrl,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors.textSub,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${p.models.length} 个模型'
                                                  '${p.enabled ? '' : ' · 已停用'}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: p.enabled
                                                        ? AppColors.primaryDark
                                                        : AppColors.textSub,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Switch(
                                            value: p.enabled,
                                            onChanged: (v) => _toggle(p, v),
                                          ),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            size: 20,
                                            color: Colors.grey,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
    );
  }
}
