import 'package:flutter/material.dart';

import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/core/utils/dates.dart';
import 'package:student_workbench/core/widgets/confirm_dialog.dart';
import 'package:student_workbench/core/widgets/frosted_snack.dart';
import 'package:student_workbench/features/chat/services/llm_service.dart';
import 'package:student_workbench/features/memory/models/memory_item.dart';
import 'package:student_workbench/features/memory/services/memory_extractor.dart';
import 'package:student_workbench/features/memory/services/memory_service.dart';
import 'package:student_workbench/features/chat/services/chat_service.dart';

/// AI 长期记忆面板(RikkaHub 式内置记忆):
/// 查看 / 添加 / 编辑 / 删除;聊天后自动提炼,也可手动提炼。
/// 记忆全部存本地 SQLite;外置记忆服务见「系统设置 → API 配置」。
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key});

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  final MemoryService _service = MemoryService.instance;

  List<MemoryItem> _items = [];
  String _kind = 'all';
  bool _loading = true;
  bool _extracting = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final items = await _service.list();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _reload() async {
    final items = await _service.list();
    if (!mounted) return;
    setState(() => _items = items);
  }

  void _showSnack(String msg) => showFrostedSnack(context, msg);

  List<MemoryItem> get _display =>
      _kind == 'all' ? _items : _items.where((m) => m.kind == _kind).toList();

  Future<void> _add() async {
    final kindCtrl = ValueNotifier<String>('fact');
    final ctrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加记忆'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final k in MemoryService.kinds)
                  ValueListenableBuilder<String>(
                    valueListenable: kindCtrl,
                    builder: (context, v, _) => ChoiceChip(
                      label: Text(MemoryService.kindLabels[k] ?? k,
                          style: const TextStyle(fontSize: 12)),
                      selected: v == k,
                      onSelected: (_) => kindCtrl.value = k,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(hintText: '记忆内容,如:喜欢晚上学习'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != true || !mounted) return;
    final content = ctrl.text.trim();
    if (content.isEmpty) {
      _showSnack('记忆内容不能为空');
      return;
    }
    await _service.add(kind: kindCtrl.value, content: content);
    await _reload();
    _showSnack('已保存记忆');
  }

  Future<void> _edit(MemoryItem item) async {
    final ctrl = TextEditingController(text: item.content);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑记忆'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '记忆内容'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    await _service.update(item.id!, result);
    await _reload();
    _showSnack('已更新');
  }

  Future<void> _delete(MemoryItem item) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这条记忆?',
      message: item.content,
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _service.delete(item.id!);
    await _reload();
    _showSnack('已删除');
  }

  /// 手动提炼:从最近对话提取记忆(与聊天后的自动提炼同一逻辑)。
  Future<void> _extract() async {
    if (_extracting) return;
    if (!await LlmService.instance.isConfigured()) {
      _showSnack('聊天服务未配置,请先到 系统设置 → API 配置 填写');
      return;
    }
    final sessions = await ChatService.instance.sessions();
    if (sessions.isEmpty) {
      _showSnack('还没有对话,先去聊几句吧');
      return;
    }
    // 取最近一个会话的全部消息。
    final msgs = await ChatService.instance.messages(sessions.first.id!);
    if (msgs.isEmpty) {
      _showSnack('还没有对话,先去聊几句吧');
      return;
    }
    final history = [
      for (final m in msgs) (role: m.role, content: m.content),
    ];
    setState(() => _extracting = true);
    _showSnack('正在提炼记忆…');
    try {
      final result =
          await MemoryExtractor.instance.extractFrom(history);
      await _reload();
      if (!mounted) return;
      _showSnack(result.added > 0 ? '已提炼 ${result.added} 条记忆' : '本次没有提炼到新记忆');
    } catch (_) {
      if (!mounted) return;
      _showSnack('提炼失败,请检查网络或配置');
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final display = _display;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 长期记忆'),
        actions: [
          IconButton(
            onPressed: _extracting ? null : _extract,
            icon: _extracting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded, size: 20),
            tooltip: '从对话提炼记忆',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Text(
                    '记忆全部保存在本机(SQLite)。聊天后小掌柜会自动提炼'
                    '画像 / 事实 / 摘要;也可手动添加或编辑。'
                    '如需接外置记忆服务,见「系统设置 → API 配置 → 外置记忆」。',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSub,
                        height: 1.5),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.card,
                          foregroundColor: AppColors.primaryDark,
                          side: BorderSide(color: AppColors.primary),
                        ),
                        onPressed: _add,
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text('添加记忆'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 类型筛选
                Wrap(
                  spacing: 8,
                  children: [
                    for (final k in ['all', ...MemoryService.kinds])
                      ChoiceChip(
                        label: Text(
                          k == 'all' ? '全部' : (MemoryService.kindLabels[k] ?? k),
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: _kind == k,
                        onSelected: (_) => setState(() => _kind = k),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (display.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(
                      child: Text('还没有记忆。可手动添加,或聊天后自动提炼',
                          style: TextStyle(color: AppColors.textSub)),
                    ),
                  )
                else
                  for (final m in display) _memoryTile(m),
              ],
            ),
    );
  }

  Widget _memoryTile(MemoryItem m) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _kindColor(m.kind).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              MemoryService.kindLabels[m.kind] ?? m.kind,
              style: TextStyle(
                  fontSize: 11,
                  color: _kindColor(m.kind),
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.content,
                    style: const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 3),
                Text(
                  fullDateTimeLabel(m.createdAt),
                  style: TextStyle(fontSize: 10, color: AppColors.textSub),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _edit(m),
            icon: Icon(Icons.edit_outlined,
                size: 16, color: AppColors.textSub),
            visualDensity: VisualDensity.compact,
            tooltip: '编辑',
          ),
          IconButton(
            onPressed: () => _delete(m),
            icon: Icon(Icons.close_rounded,
                size: 18, color: AppColors.textSub),
            visualDensity: VisualDensity.compact,
            tooltip: '删除',
          ),
        ],
      ),
    );
  }

  Color _kindColor(String kind) => switch (kind) {
        'profile' => const Color(0xFF0288D1),
        'fact' => const Color(0xFF2E7D32),
        _ => const Color(0xFF7B1FA2),
      };
}
