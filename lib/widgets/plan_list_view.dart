import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../data/daily_content.dart';
import '../models/plan_item.dart';
import '../services/plan_service.dart';
import '../theme.dart';
import 'frosted_snack.dart';
import 'section_card.dart';

/// 计划清单视图:本周计划 / 长期目标共用(scope 区分)。
/// 支持新增、勾选完成、编辑、删除;空态有引导文案。
class PlanListView extends StatefulWidget {
  final String scope;
  final String title;
  final String hint;
  final String emptyText;
  final IconData icon;

  const PlanListView({
    super.key,
    required this.scope,
    required this.title,
    required this.hint,
    required this.emptyText,
    required this.icon,
  });

  @override
  State<PlanListView> createState() => _PlanListViewState();
}

class _PlanListViewState extends State<PlanListView> {
  final PlanService _service = PlanService.instance;
  bool _loading = true;
  List<PlanItem> _items = [];

  int get _doneCount => _items.where((e) => e.done).length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _service.list(widget.scope);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  Future<void> _addOrEdit([PlanItem? existing]) async {
    final result = await showModalBottomSheet<({String title, String detail})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PlanEditSheet(
        title: widget.title,
        initialTitle: existing?.title ?? '',
        initialDetail: existing?.detail ?? '',
      ),
    );
    if (result == null || !mounted) return;
    if (existing == null) {
      await _service.add(
        scope: widget.scope,
        title: result.title,
        detail: result.detail,
      );
      _snack('已添加');
    } else {
      await _service.update(
        existing.copyWith(title: result.title, detail: result.detail),
      );
      _snack('已更新');
    }
    await _load();
  }

  Future<void> _toggle(PlanItem item) async {
    await _service.toggle(item);
    await _load();
  }

  /// 系统随机生成一条(排除已存在的标题,避免重复)
  Future<void> _generateRandom() async {
    final exclude = _items.map((e) => e.title).toSet();
    final isWeek = widget.scope == PlanItem.scopeWeek;
    final picked = isWeek
        ? DailyContent.randomWeekPlan(exclude: exclude)
        : DailyContent.randomLongTermGoal(exclude: exclude);
    await _service.add(
      scope: widget.scope,
      title: picked.title,
      detail: picked.detail,
    );
    await _load();
    _snack('已随机生成一条${widget.title}');
  }

  Future<void> _delete(PlanItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除该条目'),
        content: Text(item.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE53935)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.delete(item.id!);
    await _load();
    _snack('已删除');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final total = _items.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        SectionCard(
          title: widget.title,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (total > 0)
                Text(
                  '已完成 $_doneCount/$total',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              if (total > 0) const SizedBox(height: 8),
              Text(
                widget.hint,
                style: TextStyle(fontSize: 12, color: AppColors.textSub),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => _addOrEdit(),
                icon: const Icon(Icons.add_rounded),
                label: Text('添加${widget.title}'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: AppColors.primaryDark,
                  side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _generateRandom,
                icon: const Icon(Icons.casino_rounded, size: 20),
                label: const Text('随机生成'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (total == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(widget.icon, size: 46, color: AppColors.primaryLight),
                const SizedBox(height: 12),
                Text(
                  widget.emptyText,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSub, height: 1.5),
                ),
              ],
            ),
          )
        else
          for (final item in _items) _tile(item),
      ],
    );
  }

  Widget _tile(PlanItem item) {
    // 编辑/删除键默认隐藏,左滑(从右向左)显示操作按钮。
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Slidable(
        key: ValueKey(item.id),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: 0.5,
          children: [
            SlidableAction(
              onPressed: (_) => _addOrEdit(item),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: Icons.edit_outlined,
              label: '编辑',
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(18)),
            ),
            SlidableAction(
              onPressed: (_) => _delete(item),
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              icon: Icons.delete_outline_rounded,
              label: '删除',
              borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(18)),
            ),
          ],
        ),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: item.done,
                  activeColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5)),
                  onChanged: (_) => _toggle(item),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: item.done
                                ? AppColors.textSub
                                : AppColors.textMain,
                            decoration:
                                item.done ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (item.detail.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.detail,
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSub),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // 左滑提示:小箭头暗示可向左滑出操作
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Icon(Icons.swipe_left_alt_rounded,
                      size: 18,
                      color: AppColors.textSub.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 计划新增/编辑弹层:标题 + 备注
class _PlanEditSheet extends StatefulWidget {
  final String title;
  final String initialTitle;
  final String initialDetail;

  const _PlanEditSheet({
    required this.title,
    required this.initialTitle,
    required this.initialDetail,
  });

  @override
  State<_PlanEditSheet> createState() => _PlanEditSheetState();
}

class _PlanEditSheetState extends State<_PlanEditSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.initialTitle);
  late final TextEditingController _detail =
      TextEditingController(text: widget.initialDetail);

  @override
  void dispose() {
    _title.dispose();
    _detail.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _title.text.trim();
    if (t.isEmpty) {
      showFrostedSnack(context, '请填写标题');
      return;
    }
    Navigator.of(context).pop((title: t, detail: _detail.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.initialTitle.isEmpty ? '添加${widget.title}' : '编辑${widget.title}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textMain,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '标题',
              hintText: '想完成什么',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _detail,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '备注(可选)',
              hintText: '补充说明、拆解步骤等',
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _submit,
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
