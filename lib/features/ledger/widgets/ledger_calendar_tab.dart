import 'package:flutter/material.dart';

import 'package:chronos/features/ledger/models/ledger_txn.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/utils/dates.dart';
import 'package:chronos/features/ledger/widgets/ledger_format.dart';

/// 记账「日历」Tab:按月展示每日支出热力 + 点选某天看当日流水。
class LedgerCalendarTab extends StatefulWidget {
  final List<LedgerTxn> txns;

  const LedgerCalendarTab({super.key, required this.txns});

  @override
  State<LedgerCalendarTab> createState() => _LedgerCalendarTabState();
}

class _LedgerCalendarTabState extends State<LedgerCalendarTab> {
  int _offset = 0;
  String? _dayKey;

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
    final expenseByDay = <String, double>{};
    for (final t in widget.txns
        .where((t) => t.type == 'expense' && t.date.startsWith(mk))) {
      expenseByDay[t.date] = (expenseByDay[t.date] ?? 0) + t.amount;
    }
    final firstWeekday = base.weekday % 7; // 0=周日
    final daysInMonth = DateTime(base.year, base.month + 1, 0).day;
    final todayKey = dateKey(DateTime.now());

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

    final cells = <Widget>[
      for (final w in ['日', '一', '二', '三', '四', '五', '六'])
        Center(
          child: Text(w,
              style: TextStyle(fontSize: 11, color: AppColors.textSub)),
        ),
      for (var i = 0; i < firstWeekday; i++) const SizedBox(),
      for (var d = 1; d <= daysInMonth; d++)
        _calCell(d, mk, expenseByDay['$mk-${d.toString().padLeft(2, '0')}'],
            '$mk-${d.toString().padLeft(2, '0')}' == todayKey),
    ];

    final dayTxns = _dayKey == null
        ? null
        : widget.txns.where((t) => t.date == _dayKey).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            children: cells,
          ),
        ),
        if (dayTxns != null) ...[
          const SizedBox(height: 12),
          Text(
            _dayKey!.isEmpty ? '' : _dateLabel(_dayKey!),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          if (dayTxns.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('当天没有记录',
                  style: TextStyle(fontSize: 12, color: AppColors.textSub)),
            )
          else
            for (final t in dayTxns) _txnRow(t),
        ],
      ],
    );
  }

  Widget _calCell(int day, String mk, double? expense, bool isToday) {
    final key = '$mk-${day.toString().padLeft(2, '0')}';
    final selected = key == _dayKey;
    return InkWell(
      onTap: () => setState(() => _dayKey = key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryLight
              : isToday
                  ? AppColors.primaryLight.withValues(alpha: 0.5)
                  : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$day',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400)),
            if (expense != null && expense > 0)
              Text(
                expense.round().toString(),
                style: const TextStyle(
                    fontSize: 9, color: Color(0xFFE53935)),
              )
            else
              const SizedBox(height: 12),
          ],
        ),
      ),
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
