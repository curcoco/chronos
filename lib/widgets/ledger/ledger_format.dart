/// 记账模块共享的格式化与聚合小工具(供明细/日历/图表 Tab 复用)。
library;

import '../../models/ledger_txn.dart';

String money(double v) => '¥${v.toStringAsFixed(2)}';

String monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

double sumOf(List<LedgerTxn> list, String type) =>
    list.where((t) => t.type == type).fold(0.0, (s, t) => s + t.amount);
