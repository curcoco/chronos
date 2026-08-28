import 'package:flutter/material.dart';

import 'package:chronos/core/services/ai_provider.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/widgets/app_text_field.dart';
import 'package:chronos/core/widgets/confirm_dialog.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';
import 'package:chronos/core/widgets/section_card.dart';

import 'package:chronos/features/settings/widgets/model_picker_sheet.dart';

/// 提供商详情:连接配置(名称/地址/Key/启用/测试) + 模型列表管理。
/// 保存/删除后返回列表页刷新。
class ProviderDetailPage extends StatefulWidget {
  final AiProvider provider;
  const ProviderDetailPage({super.key, required this.provider});

  @override
  State<ProviderDetailPage> createState() => _ProviderDetailPageState();
}

class _ProviderDetailPageState extends State<ProviderDetailPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _modelCtrl;
  late bool _enabled;
  late List<String> _models;
  bool _testing = false;
  bool _fetching = false;
  bool _dirty = false; // 是否有未保存的修改(返回前拦截提示)

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void initState() {
    super.initState();
    final p = widget.provider;
    _nameCtrl = TextEditingController(text: p.name);
    _urlCtrl = TextEditingController(text: p.baseUrl);
    _keyCtrl = TextEditingController(text: p.apiKey);
    _modelCtrl = TextEditingController();
    _enabled = p.enabled;
    _models = List.of(p.models);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (name.isEmpty || url.isEmpty || key.isEmpty) {
      showFrostedSnack(context, '名称/地址/Key 都不能为空');
      return;
    }
    final list = await AiProviders.load();
    final updated = widget.provider.copyWith(
      name: name,
      baseUrl: url,
      apiKey: key,
      enabled: _enabled,
      models: _models,
    );
    await AiProviders.save([
      for (final p in list) p.id == updated.id ? updated : p,
    ]);
    if (!mounted) return;
    _dirty = false;
    showFrostedSnack(context, '已保存');
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: '删除提供商?',
      message: '「${widget.provider.name}」的配置将被删除,正在使用它的模型需要重新选择。',
      confirmText: '删除',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final list = await AiProviders.load();
    await AiProviders.save(
        [for (final p in list) if (p.id != widget.provider.id) p]);
    if (!mounted) return;
    showFrostedSnack(context, '已删除');
    Navigator.of(context).pop();
  }

  /// 测试连接:向 /chat/completions 发一个最小请求,看是否 200/可解析。
  Future<void> _testConnection() async {
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (url.isEmpty || key.isEmpty) {
      showFrostedSnack(context, '先填地址和 Key');
      return;
    }
    setState(() => _testing = true);
    try {
      final ok = await AiProviders.testConnection(url: url, apiKey: key);
      if (!mounted) return;
      showFrostedSnack(
          context, ok ? '连接正常' : '连接失败:请检查地址 / Key 或网络');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _addModel() {
    final m = _modelCtrl.text.trim();
    if (m.isEmpty) return;
    if (_models.contains(m)) {
      showFrostedSnack(context, '模型已存在');
      return;
    }
    setState(() {
      _models.add(m);
      _modelCtrl.clear();
    });
    _markDirty();
  }

  /// 从服务商拉取模型列表 → 弹选择器(搜索/勾选/全选)加入(参考 RikkaHub ModelPicker)。
  Future<void> _pickModels() async {
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (url.isEmpty || key.isEmpty) {
      showFrostedSnack(context, '先填地址和 Key');
      return;
    }
    setState(() => _fetching = true);
    try {
      final all = await AiProviders.fetchModels(url: url, apiKey: key);
      if (!mounted) return;
      if (all.isEmpty) {
        showFrostedSnack(context, '未获取到模型(该服务商可能不支持 /models 接口,可手填)');
        return;
      }
      final picked = await showModalBottomSheet<Set<String>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => ModelPickerSheet(
          allModels: all,
          existing: _models.toSet(),
        ),
      );
      if (picked == null || !mounted) return;
      var added = 0;
      setState(() {
        for (final m in picked) {
          if (!_models.contains(m)) {
            _models.add(m);
            added++;
          }
        }
      });
      if (added > 0) _markDirty();
      showFrostedSnack(context, '已添加 $added 个模型');
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 有未保存修改时拦截返回,确认后才离开。
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!mounted) return;
        final leave = await showConfirmDialog(
          this.context,
          title: '有未保存的修改',
          message: '当前改动还没保存,确定离开?',
          confirmText: '离开',
        );
        if (leave == true && mounted) {
          _dirty = false;
          Navigator.of(this.context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(title: Text(widget.provider.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SectionCard(
            title: '连接配置',
            child: Column(
              children: [
                AppTextField(
                  controller: _nameCtrl,
                  hintText: '名称',
                  maxLines: 1,
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 10),
                AppTextField(
                  controller: _urlCtrl,
                  hintText: '地址,如 https://api.xxx.com/v1',
                  maxLines: 1,
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 10),
                AppTextField(
                  controller: _keyCtrl,
                  hintText: 'API Key',
                  maxLines: 1,
                  obscureText: true,
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('启用',
                        style: TextStyle(
                            fontSize: 14, color: AppColors.textMain)),
                    const Spacer(),
                    Switch(
                      value: _enabled,
                      onChanged: (v) {
                        setState(() => _enabled = v);
                        _markDirty();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      foregroundColor: AppColors.primaryDark,
                      side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _testing ? null : _testConnection,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bolt_rounded, size: 18),
                    label: Text(_testing ? '测试中…' : '测试连接'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: '模型',
            child: Column(
              children: [
                for (final m in _models)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(Icons.extension_rounded,
                            size: 16, color: AppColors.textSub),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(m,
                              style: const TextStyle(fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() => _models.remove(m));
                            _markDirty();
                          },
                          icon: const Icon(Icons.close_rounded,
                              size: 18, color: Colors.grey),
                          tooltip: '移除模型',
                        ),
                      ],
                    ),
                  ),
                if (_models.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('还没有模型,可点下方按钮从服务商拉取,或手填',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSub)),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(42),
                      foregroundColor: AppColors.primaryDark,
                      side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _fetching ? null : _pickModels,
                    icon: _fetching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download_outlined, size: 18),
                    label: Text(_fetching ? '获取中…' : '从服务商添加模型'),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _modelCtrl,
                        hintText: '模型 ID,如 deepseek-chat',
                        maxLines: 1,
                        onSubmit: _addModel,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _addModel,
                      icon: const Icon(Icons.add_rounded, size: 20),
                      tooltip: '添加模型',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _save,
              child: const Text('保存'),
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('删除提供商'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
      ),
    );
  }
}
