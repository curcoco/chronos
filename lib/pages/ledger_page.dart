import 'package:flutter/material.dart';

import '../models/ledger_txn.dart';
import '../services/coin_service.dart';
import '../services/ledger_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import '../widgets/frosted_snack.dart';
import '../widgets/ledger/ledger_calendar_tab.dart';
import '../widgets/ledger/ledger_cats_tab.dart';
import '../widgets/ledger/ledger_chart_tab.dart';
import '../widgets/ledger/ledger_detail_tab.dart';
import '../widgets/ledger/ledger_entry_sheet.dart';
import '../widgets/ledger/ledger_format.dart';

/// 生活记账:余额 / 明细 / 日历 / 图表 / 预算 / 分类(纯本地)。
/// 各 Tab 内容拆到 widgets/ledger/ 下的独立组件,本页只负责
/// 数据加载、头部(余额卡/预算预警)、记一笔入口与 Tab 切换。
class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key});

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  final LedgerService _service = LedgerService();

  List<LedgerTxn> _txns = [];
  double _start = 0;
  double _budget = 0;
  List<String> _customCats = [];
  bool _loading = true;
  int _tab = 0; // 0明细 1日历 2图表 3分类

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _service.txns(),
      _service.startBalance(),
      _service.budget(),
      _service.customCats(),
    ]);
    if (!mounted) return;
    setState(() {
      _txns = results[0] as List<LedgerTxn>;
      _start = results[1] as double;
      _budget = results[2] as double;
      _customCats = results[3] as List<String>;
      _loading = false;
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('生活记账')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                _buildHero(),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _openEntry,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('记一笔'),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    '今日记任意一笔支出或收入,自动完成记账打卡(+1 金币,每日一次)',
                    style: TextStyle(fontSize: 11, color: AppColors.textSub),
                  ),
                ),
                const SizedBox(height: 14),
                _buildSeg(),
                const SizedBox(height: 10),
                switch (_tab) {
                  0 => LedgerDetailTab(txns: _txns),
                  1 => LedgerCalendarTab(txns: _txns),
                  2 => LedgerChartTab(txns: _txns),
                  _ => LedgerCatsTab(
                      service: _service,
                      customCats: _customCats,
                      start: _start,
                      budget: _budget,
                      onChanged: _load,
                    ),
                },
              ],
            ),
    );
  }

  // ---------- 头部 ----------
  Widget _buildHero() {
    final balance = _service.balanceOf(_txns, _start);
    final now = DateTime.now();
    final mk = monthKey(now);
    final monthTx = _txns.where((t) => t.date.startsWith(mk)).toList();
    final mIncome = sumOf(monthTx, 'income');
    final mExpense = sumOf(monthTx, 'expense');
    final pct = _budget > 0 ? (mExpense / _budget * 100).round() : 0;
    final over = _budget > 0 && pct >= 100;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryLight, AppColors.primary],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '余额(起始 ${money(_start)})',
            style: const TextStyle(fontSize: 12, color: Color(0xFFE3F4FF)),
          ),
          const SizedBox(height: 2),
          Text(
            money(balance),
            style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '本月收入  ${money(mIncome)}',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFFE3F4FF)),
                ),
              ),
              Expanded(
                child: Text(
                  '本月支出  ${money(mExpense)}',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFFE3F4FF)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_budget > 0) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '月度预算 ${money(_budget)}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFE3F4FF)),
                  ),
                ),
                Text(
                  over ? '已超支!' : '已用 $pct%',
                  style: TextStyle(
                      fontSize: 11,
                      color: over ? const Color(0xFFFFCDD2) : Colors.white,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (over) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '⚠ 本月已超预算,注意控制支出',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSeg() {
    const labels = ['明细', '日历', '图表', '分类'];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _tab = i),
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _tab == i ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: _tab == i ? Colors.white : AppColors.textSub,
                      fontWeight:
                          _tab == i ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- 记一笔 ----------
  Future<void> _openEntry() async {
    final result = await showModalBottomSheet<
        ({String type, double amount, String category, String note, String date})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => LedgerEntrySheet(customCats: _customCats),
    );
    if (result == null || !mounted) return;
    await _service.addTxn(
      type: result.type,
      amount: result.amount,
      category: result.category,
      note: result.note,
      date: result.date,
    );
    await _load();
    // 当天记一笔 → 自动完成记账打卡(每日一次,受金币上限约束)
    if (result.date == todayStr()) {
      final coin = await CoinService.instance.rewardLedgerCheckin(todayStr());
      if (!mounted) return;
      _showSnack(coin > 0 ? '已记一笔,记账打卡成功,金币 +$coin' : '已记一笔');
    } else {
      _showSnack('已记一笔');
    }
  }
}
