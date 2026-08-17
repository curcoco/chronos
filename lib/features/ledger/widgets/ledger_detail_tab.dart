import 'package:flutter/material.dart';

import 'package:student_workbench/features/ledger/models/ledger_txn.dart';
import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/core/utils/dates.dart';
import 'package:student_workbench/features/ledger/widgets/ledger_format.dart';

/// 记账「明细」Tab:按月翻页 + 按日分组展示流水。
/// 分批渲染:一次最多构建 [_detailLimit] 行,超出部分由底部「加载更多」递增,
/// 避免记账流水逐年累积后一次性构建全部行导致卡顿。
class LedgerDetailTab extends StatefulWidget {
  final List<LedgerTxn> txns;

  const LedgerDetailTab({super.key, required this.txns});

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
    return Padding(
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
  }
}
