import 'package:flutter/material.dart';

import 'package:chronos/features/ledger/models/ledger_txn.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/utils/dates.dart';
import 'package:chronos/features/ledger/widgets/ledger_format.dart';

/// 记账「图表」Tab:近 7 天收支柱状图 + 本月汇总。
class LedgerChartTab extends StatelessWidget {
  final List<LedgerTxn> txns;

  const LedgerChartTab({super.key, required this.txns});

  @override
  Widget build(BuildContext context) {
    final days = <({String label, double income, double expense})>[];
    for (var i = 6; i >= 0; i--) {
      final d = DateTime.now().subtract(Duration(days: i));
      final key = dateKey(d);
      final dayTx = txns.where((t) => t.date == key).toList();
      days.add((
        label: i == 0 ? '今天' : i == 1 ? '昨天' : '${d.month}/${d.day}',
        income: sumOf(dayTx, 'income'),
        expense: sumOf(dayTx, 'expense'),
      ));
    }
    final maxV = days.fold<double>(
        1, (m, d) => [m, d.income, d.expense].reduce((a, b) => a > b ? a : b));

    final now = DateTime.now();
    final mk = monthKey(now);
    final monthTx = txns.where((t) => t.date.startsWith(mk)).toList();
    final mIncome = sumOf(monthTx, 'income');
    final mExpense = sumOf(monthTx, 'expense');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '近7天收支',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in days)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: 110,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                width: 9,
                                height:
                                    (d.income / maxV * 100).clamp(1.0, 110.0),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2E7D32),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3)),
                                ),
                              ),
                              const SizedBox(width: 3),
                              Container(
                                width: 9,
                                height:
                                    (d.expense / maxV * 100).clamp(1.0, 110.0),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(d.label,
                            style: TextStyle(
                                fontSize: 10, color: AppColors.textSub)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _Legend(color: const Color(0xFF2E7D32), label: '收入'),
            const SizedBox(width: 16),
            _Legend(color: AppColors.primary, label: '支出'),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('本月汇总',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('本月收入  ${money(mIncome)}',
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF2E7D32))),
              const SizedBox(height: 4),
              Text('本月支出  ${money(mExpense)}',
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFFE53935))),
              const SizedBox(height: 4),
              Text('本月结余  ${money(mIncome - mExpense)}',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textMain,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(fontSize: 11, color: AppColors.textSub)),
      ],
    );
  }
}
