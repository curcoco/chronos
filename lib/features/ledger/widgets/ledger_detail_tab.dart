import 'package:flutter/material.dart';

import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/utils/dates.dart';
import 'package:chronos/core/widgets/confirm_dialog.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';
import 'package:chronos/features/ledger/models/ledger_txn.dart';
import 'package:chronos/features/ledger/services/ledger_service.dart';
import 'package:chronos/features/ledger/widgets/ledger_entry_sheet.dart';
import 'package:chronos/features/ledger/widgets/ledger_format.dart';

/// 记账「明细」Tab:按月翻页 + 按日分组展示流水。
/// 分批渲染:一次最多构建 [_detailLimit] 行,超出部分由底部「加载更多」递增,
/// 避免记账流水逐年累积后一次性构建全部行导致卡顿。
/// 交互:左滑一条记录可删除(确认弹窗 + 撤销提示)。删除时先通过 [onRemove]
/// 同步移除该行(满足 Dismissible「被删行必须立刻离开树」的约束),删除后
/// 通过 [onChanged] 通知父页刷新余额/日历/图表等联动数据(撤销时也会调用)。
class LedgerDetailTab extends StatefulWidget {
  final List<LedgerTxn> txns;
  final List<String> customCats;
  final ValueChanged<LedgerTxn>? onRemove;
  final VoidCallback? onChanged;

  const LedgerDetailTab({
    super.key,
    required this.txns,
    this.customCats = const [],
    this.onRemove,
    this.onChanged,
  });

  @override
  State<LedgerDetailTab> createState() => _LedgerDetailTabState();
}

class _LedgerDetailTabState extends State<LedgerDetailTab> {
  int _offset = 0;
  int _limit = 50;

  String _dateLabel(String d) {
    final dt = DateTime.tryParse('${d}T00:00:00');
    if (dt == null) return d;
    final now = DateTime.now();
    if (d == dateKey(now)) return '今天';
    if (d == dateKey(now.subtract(const Duration(days: 1)))) return '昨天';
    return '${dt.month}月${dt.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final base =
        DateTime(DateTime.now().year, DateTime.now().month + _offset, 1);
    final mk = monthKey(base);
    final list = widget.txns.where((t) => t.date.startsWith(mk)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final header = Row(
      children: [
        IconButton(
          onPressed: () => setState(() => _offset--),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            '${base.year}年${base.month}月',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          onPressed: () => setState(() => _offset++),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );

    if (list.isEmpty) {
      return Column(children: [
        header,
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Text('本月暂无记录', style: TextStyle(color: AppColors.textSub)),
        ),
      ]);
    }

    final groups = <String, List<LedgerTxn>>{};
    for (final t in list) {
      groups.putIfAbsent(t.date, () => []).add(t);
    }

    // 分批渲染:先构建前 _limit 行,超出部分由「加载更多」递增。
    final rows = <Widget>[header];
    rows.add(Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text(
        '点击记录可编辑,左滑可删除(可撤销)',
        style: TextStyle(fontSize: 11, color: AppColors.textSub),
      ),
    ));
    var shown = 0;
    outer:
    for (final entry in groups.entries) {
      if (shown >= _limit) break;
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(
          _dateLabel(entry.key),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSub),
        ),
      ));
      for (final t in entry.value) {
        if (shown >= _limit) break outer;
        rows.add(_txnRow(t));
        shown++;
      }
    }

    final remaining = list.length - shown;
    if (remaining > 0) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 10),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
              foregroundColor: AppColors.primaryDark,
              side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => setState(() => _limit += 50),
            child: Text('加载更多(剩余 $remaining 条)'),
          ),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  Widget _txnRow(LedgerTxn t) {
    final up = t.type == 'income';
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: up ? const Color(0xFF2E7D32) : const Color(0xFFE53935),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.note.isEmpty ? t.category : '${t.category} · ${t.note}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  up ? '收入' : '支出',
                  style: TextStyle(fontSize: 11, color: AppColors.textSub),
                ),
              ],
            ),
          ),
          Text(
            '${up ? '+' : '-'}${money(t.amount)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: up ? const Color(0xFF2E7D32) : const Color(0xFFE53935),
            ),
          ),
        ],
      ),
    );
    final id = t.id;
    if (id == null) return row; // 理论不可达(DB 行必有 id),兜底避免滑动无键。
    // 点击可编辑;左滑删除(先确认,删除类 destructive,删除后给撤销提示)。
    return Dismissible(
      key: ValueKey('ledger-txn-$id'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFE53935),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.white, size: 20),
      ),
      confirmDismiss: (_) => showConfirmDialog(
        context,
        title: '删除这条记录?',
        message: '${up ? '收入' : '支出'} ${money(t.amount)}'
            '(${t.category})${t.note.isEmpty ? '' : ' ${t.note}'}\n删除后可通过提示条撤销。',
        confirmText: '删除',
        destructive: true,
      ),
      onDismissed: (_) => _deleteAndUndo(t),
      child: InkWell(
        onTap: () => _editTxn(t),
        borderRadius: BorderRadius.circular(10),
        child: row,
      ),
    );
  }

  /// 点击记录 → 编辑弹层(预填)→ 保存后刷新。
  Future<void> _editTxn(LedgerTxn t) async {
    final result = await showModalBottomSheet<
        ({String type, double amount, String category, String note, String date})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) =>
          LedgerEntrySheet(customCats: widget.customCats, initial: t),
    );
    if (result == null || !mounted) return;
    try {
      await LedgerService().updateTxn(
        t.id!,
        type: result.type,
        amount: result.amount,
        category: result.category,
        note: result.note,
        date: result.date,
      );
      widget.onChanged?.call();
      if (!mounted) return;
      showFrostedSnack(context, '已更新');
    } catch (e) {
      AppLog.instance.e('更新流水失败:$e');
      if (!mounted) return;
      showFrostedSnack(context, '更新失败,请重试');
    }
  }

  /// 执行删除并弹出「撤销」:先同步移除行(满足 Dismissible 约束),
  /// 再做 DB 删除;失败则重载恢复真实数据。
  Future<void> _deleteAndUndo(LedgerTxn t) async {
    widget.onRemove?.call(t); // 父页 setState,该行立即离开 widget 树
    try {
      await LedgerService().deleteTxn(t.id!);
    } catch (_) {
      widget.onChanged?.call(); // 删除失败:整页重载恢复
      if (!mounted) return;
      showFrostedSnack(context, '删除失败,请重试');
      return;
    }
    if (!mounted) return;
    showUndoSnack(
      context,
      '已删除 ${t.category} ${money(t.amount)}',
      onUndo: () async {
        await LedgerService().restoreTxn(t);
        widget.onChanged?.call();
      },
    );
  }
}
