import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:chronos/core/theme.dart';
import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/utils/dates.dart';
import 'package:chronos/core/widgets/confirm_dialog.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';
import 'package:chronos/core/widgets/status_views.dart';
import 'package:chronos/features/chat/services/llm_service.dart';
import 'package:chronos/features/memory/models/memory_item.dart';
import 'package:chronos/features/memory/services/memory_extractor.dart';
import 'package:chronos/features/memory/services/memory_service.dart';
import 'package:chronos/features/chat/services/chat_service.dart';

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
  String? _tagFilter; // 标签筛选(null = 全部)
  bool _loading = true;
  String? _loadError; // 记忆列表加载失败(渲染 ErrorView + 重试)
  bool _extracting = false;
  bool _selecting = false; // 批量管理模式
  final Set<int> _selected = {}; // 批量管理选中的 id

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final items = await _service.list();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      AppLog.instance.e('记忆列表加载失败:$e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '记忆加载失败,请重试';
      });
    }
  }

  Future<void> _reload() async {
    try {
      final items = await _service.list();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      AppLog.instance.e('记忆列表刷新失败:$e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  List<MemoryItem> get _display {
    var list = _kind == 'all'
        ? _items
        : _items.where((m) => m.kind == _kind).toList();
    if (_tagFilter != null) {
      list = list.where((m) => m.tags.contains(_tagFilter)).toList();
    }
    return list;
  }

  /// 所有记忆里出现过的标签(去重,用于筛选;无标签时整行隐藏)。
  List<String> get _allTags =>
      _items.expand((m) => m.tags).map((t) => t.trim()).toSet().toList();

  Future<void> _add() => _showEditor();

  Future<void> _edit(MemoryItem item) => _showEditor(item: item);

  /// 统一添加/编辑弹窗:支持类型、重要性(1~10)、置顶、可见性、标签。
  Future<void> _showEditor({MemoryItem? item}) async {
    final isEdit = item != null;
    final kindCtrl = ValueNotifier<String>(item?.kind ?? 'fact');
    final ctrl = TextEditingController(text: item?.content ?? '');
    final tagsCtrl = TextEditingController(
        text: item == null ? '' : item.tags.join(','));
    var importance = item?.importance ?? 5;
    var pinned = item?.pinned ?? false;
    var visibility = item?.visibility ?? 'public';

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(isEdit ? '编辑记忆' : '添加记忆'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 类型(仅添加时可改)
                if (!isEdit)
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
                  autofocus: !isEdit,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: '记忆内容,如:喜欢晚上学习'),
                ),
                const SizedBox(height: 12),
                // 重要性(1~10)
                Row(
                  children: [
                    const Text('重要性', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Slider(
                        value: importance.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        label: '$importance',
                        onChanged: (v) =>
                            setDialogState(() => importance = v.round()),
                      ),
                    ),
                    SizedBox(
                      width: 26,
                      child: Text('$importance',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                // 置顶 与 可见性
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('置顶', style: TextStyle(fontSize: 12)),
                      selected: pinned,
                      onSelected: (v) => setDialogState(() => pinned = v),
                    ),
                    const SizedBox(width: 8),
                    for (final v in const ['public', 'private'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            v == 'public' ? '公开(注入)' : '私有(不注入)',
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: visibility == v,
                          onSelected: (_) => setDialogState(() => visibility = v),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tagsCtrl,
                  decoration: const InputDecoration(
                      hintText: '标签,用逗号分隔(可选,用于语义匹配)',
                      prefixIcon: Icon(Icons.sell_outlined, size: 18)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;
    final content = ctrl.text.trim();
    if (content.isEmpty) {
      _showSnack('记忆内容不能为空');
      return;
    }
    final tags = _parseTags(tagsCtrl.text);
    try {
      if (isEdit) {
        await _service.update(item.id!, content,
            importance: importance,
            pinned: pinned,
            visibility: visibility,
            tags: tags);
        _showSnack('已更新');
      } else {
        await _service.add(
          kind: kindCtrl.value,
          content: content,
          importance: importance,
          pinned: pinned,
          visibility: visibility,
          tags: tags,
        );
        _showSnack('已保存记忆');
      }
      await _reload();
    } catch (e) {
      AppLog.instance.e('${isEdit ? '编辑' : '添加'}记忆失败:$e');
      _showSnack('保存失败,请重试');
    }
  }

  /// 解析标签:支持英文逗号/中文逗号/竖线/空白分隔,去重、去空。
  static List<String> _parseTags(String raw) {
    final parts = raw
        .split(RegExp(r'[,，|、\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.toSet().toList();
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
    try {
      await _service.delete(item.id!);
      await _reload();
      if (!mounted) return;
      showUndoSnack(
        context,
        '已删除记忆',
        onUndo: () async {
          try {
            await _service.restore(item);
            await _reload();
          } catch (e) {
            AppLog.instance.e('撤销删除记忆失败:$e');
          }
        },
      );
    } catch (e) {
      AppLog.instance.e('删除记忆失败:$e');
      _showSnack('删除失败,请重试');
    }
  }

  /// 手动提炼:从最近对话提取记忆(与聊天后的自动提炼同一逻辑)。
  Future<void> _extract() async {
    if (_extracting) return;
    if (!await LlmService.instance.isConfigured()) {
      _showSnack('聊天服务未配置,请先到 API 配置');
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
    } catch (e) {
      AppLog.instance.e('记忆提炼失败:$e');
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
        title: Text(_selecting ? '管理记忆' : 'AI 长期记忆'),
        actions: [
          IconButton(
            onPressed: _extracting || _selecting ? null : _extract,
            icon: _extracting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded, size: 20),
            tooltip: '从对话提炼记忆',
          ),
          IconButton(
            onPressed: () => setState(() {
              _selecting = !_selecting;
              if (!_selecting) _selected.clear();
            }),
            icon: Icon(
                _selecting ? Icons.check_rounded : Icons.checklist_rounded,
                size: 20),
            tooltip: _selecting ? '完成管理' : '批量管理',
          ),
        ],
      ),
      bottomNavigationBar: _selecting ? _selectionBar() : null,
      body: _loadError != null
          ? ErrorView(
              message: _loadError!,
              onRetry: () {
                setState(() {
                  _loadError = null;
                  _loading = true;
                });
                _init();
              },
            )
          : _loading
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
                    '记忆存在本机。掌柜会在对话中自主维护「关于你的档案」(标注 AI 档案),'
                    '聊天后也会自动提炼;也可手动添加。'
                    '外置记忆在「API 配置」里设置。',
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
                if (_allTags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  // 标签筛选(可选)
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final t in _allTags)
                        ChoiceChip(
                          label: Text(t, style: const TextStyle(fontSize: 12)),
                          selected: _tagFilter == t,
                          onSelected: (sel) => setState(() {
                            _tagFilter = sel ? t : null;
                          }),
                        ),
                    ],
                  ),
                ],
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
    final selected = _selected.contains(m.id);
    return InkWell(
      onTap: _selecting
          ? () => _toggleSelect(m.id)
          : null,
      onLongPress: _selecting ? null : () => _copyMemory(m.content),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
          color: selected
              ? AppColors.primaryLight.withValues(alpha: 0.30)
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selecting) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 6),
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected ? AppColors.primaryDark : AppColors.line,
                ),
              ),
            ],
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
                  Row(
                    children: [
                      // 重要性(1~10)
                      _stars(m.importance),
                      if (m.source == 'auto') ...[
                        _metaBadge('AI 档案', const Color(0xFF1565C0)),
                      ],
                      if (m.pinned) ...[
                        _metaBadge('置顶', AppColors.primaryDark),
                      ],
                      if (m.visibility == 'private') ...[
                        _metaBadge('私有', const Color(0xFF8E24AA)),
                      ],
                      if (m.tags.isNotEmpty) ...[
                        for (final t in m.tags.take(2))
                          _metaBadge(t, AppColors.textSub),
                      ],
                    ],
                  ),
                  Text(
                    fullDateTimeLabel(m.createdAt),
                    style: TextStyle(fontSize: 10, color: AppColors.textSub),
                  ),
                ],
              ),
            ),
            if (!_selecting) ...[
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
          ],
        ),
      ),
    );
  }

  /// 切换批量管理中某条记忆的选中状态。
  void _toggleSelect(int? id) {
    if (id == null) return;
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  /// 长按复制记忆内容。
  Future<void> _copyMemory(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    showFrostedSnack(context, '已复制');
  }

  /// 批量管理底栏:已选数量 + 删除选中 + 取消。
  Widget _selectionBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Text('已选 ${_selected.length} 条',
                style: TextStyle(fontSize: 13, color: AppColors.textSub)),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                _selecting = false;
                _selected.clear();
              }),
              child: const Text('取消'),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.card,
                foregroundColor: const Color(0xFFC62828),
                side: const BorderSide(color: Color(0xFFC62828)),
              ),
              onPressed: _selected.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('删除选中'),
            ),
          ],
        ),
      ),
    );
  }

  /// 批量删除选中的记忆,先确认后执行。
  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除所选 ${_selected.length} 条记忆?',
      message: '此操作不可撤销(可撤销),确认删除?',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      final items = _items.where((m) => _selected.contains(m.id)).toList();
      for (final m in items) {
        await _service.delete(m.id!);
      }
      if (!mounted) return;
      setState(() {
        _selecting = false;
        _selected.clear();
      });
      await _reload();
      if (!mounted) return;
      showFrostedSnack(context, '已删除 ${items.length} 条记忆');
    } catch (e) {
      AppLog.instance.e('批量删除记忆失败:$e');
      if (!mounted) return;
      _showSnack('删除失败,请重试');
    }
  }

  /// 重要性星星(黄/灰,最多 5 颗,按 /2 折算显示)。
  Widget _stars(int importance) {
    final n = ((importance + 1) ~/ 2).clamp(1, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            i < n ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 13,
            color: i < n ? const Color(0xFFF5B301) : AppColors.line,
          ),
      ],
    );
  }

  Widget _metaBadge(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Color _kindColor(String kind) => switch (kind) {
        'profile' => const Color(0xFF0288D1),
        'fact' => const Color(0xFF2E7D32),
        _ => const Color(0xFF7B1FA2),
      };
}
