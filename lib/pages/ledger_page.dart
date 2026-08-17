import 'package:flutter/material.dart';

import '../models/ledger_txn.dart';
import '../services/coin_service.dart';
import '../services/ledger_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/frosted_snack.dart';

/// 生活记账:余额 / 明细 / 日历 / 图表 / 预算 / 分类(纯本地)
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
  int _detailOffset = 0;
  int _calOffset = 0;
  String? _calDayKey;

  /// 明细 Tab 分批渲染:一次最多构建这么多行,底部「加载更多」递增。
  /// 记账流水会逐年累积,避免一次性构建全部行导致长列表卡顿。
  int _detailLimit = 50;
  final TextEditingController _catCtrl = TextEditingController();
  final TextEditingController _startCtrl = TextEditingController();
  final TextEditingController _budgetCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _catCtrl.dispose();
    _startCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
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
      _startCtrl.text = _start.toStringAsFixed(0);
      _budgetCtrl.text = _budget.toStringAsFixed(0);
      _loading = false;
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  String _money(double v) =>
      '¥${v.toStringAsFixed(2)}';

  String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  double _sumOf(List<LedgerTxn> list, String type) =>
      list.where((t) => t.type == type).fold(0.0, (s, t) => s + t.amount);

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
                  0 => _buildDetail(),
                  1 => _buildCalendar(),
                  2 => _buildChart(),
                  _ => _buildCats(),
                },
              ],
            ),
    );
  }

  // ---------- 头部 ----------
  Widget _buildHero() {
    final balance = _service.balanceOf(_txns, _start);
    final now = DateTime.now();
    final mk = _monthKey(now);
    final monthTx = _txns.where((t) => t.date.startsWith(mk)).toList();
    final mIncome = _sumOf(monthTx, 'income');
    final mExpense = _sumOf(monthTx, 'expense');
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
            '余额(起始 ${_money(_start)})',
            style: const TextStyle(
                fontSize: 12, color: Color(0xFFE3F4FF)),
          ),
          const SizedBox(height: 2),
          Text(
            _money(balance),
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
                  '本月收入  ${_money(mIncome)}',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFFE3F4FF)),
                ),
              ),
              Expanded(
                child: Text(
                  '本月支出  ${_money(mExpense)}',
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
                    '月度预算 ${_money(_budget)}',
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
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.35),
                color: over ? const Color(0xFFFFCDD2) : Colors.white,
              ),
            ),
          ] else
            const Text(
              '未设置月度预算,去「分类」页设置',
              style: TextStyle(fontSize: 11, color: Color(0xFFE3F4FF)),
            ),
        ],
      ),
    );
  }

  // ---------- 分段 ----------
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

  // ---------- 明细 ----------
  Widget _buildDetail() {
    final base = DateTime(DateTime.now().year, DateTime.now().month + _detailOffset, 1);
    final mk = _monthKey(base);
    final list = _txns.where((t) => t.date.startsWith(mk)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final header = Row(
      children: [
        IconButton(
          onPressed: () => setState(() => _detailOffset--),
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
          onPressed: () => setState(() => _detailOffset++),
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

    // 分批渲染:先构建前 _detailLimit 行,超出部分由「加载更多」递增。
    final rows = <Widget>[header];
    var shown = 0;
    outer:
    for (final entry in groups.entries) {
      if (shown >= _detailLimit) break;
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
        if (shown >= _detailLimit) break outer;
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
            onPressed: () => setState(() => _detailLimit += 50),
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

  String _dateLabel(String d) {
    final dt = DateTime.tryParse('${d}T00:00:00');
    if (dt == null) return d;
    return '${dt.year}年${dt.month}月${dt.day}日';
  }

  Widget _txnRow(LedgerTxn t) {
    final up = t.type == 'income';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
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
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSub),
                ),
              ],
            ),
          ),
          Text(
            '${up ? '+' : '-'}${_money(t.amount)}',
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

  // ---------- 日历 ----------
  Widget _buildCalendar() {
    final base = DateTime(DateTime.now().year, DateTime.now().month + _calOffset, 1);
    final mk = _monthKey(base);
    final expenseByDay = <String, double>{};
    for (final t in _txns.where((t) => t.type == 'expense' && t.date.startsWith(mk))) {
      expenseByDay[t.date] = (expenseByDay[t.date] ?? 0) + t.amount;
    }
    final firstWeekday = base.weekday % 7; // 0=周日
    final daysInMonth = DateTime(base.year, base.month + 1, 0).day;
    final todayKey = dateKey(DateTime.now());

    final header = Row(
      children: [
        IconButton(
          onPressed: () => setState(() => _calOffset--),
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
          onPressed: () => setState(() => _calOffset++),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );

    final cells = <Widget>[
      for (final w in ['日', '一', '二', '三', '四', '五', '六'])
        Center(
          child: Text(w,
              style: TextStyle(
                  fontSize: 11, color: AppColors.textSub)),
        ),
      for (var i = 0; i < firstWeekday; i++) const SizedBox(),
      for (var d = 1; d <= daysInMonth; d++)
        _calCell(d, mk, expenseByDay['$mk-${d.toString().padLeft(2, '0')}'],
            '$mk-${d.toString().padLeft(2, '0')}' == todayKey),
    ];

    final dayTxns = _calDayKey == null
        ? null
        : _txns.where((t) => t.date == _calDayKey).toList();

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
            _calDayKey!.isEmpty ? '' : _dateLabel(_calDayKey!),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700),
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
    final selected = key == _calDayKey;
    return InkWell(
      onTap: () => setState(() => _calDayKey = key),
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

  // ---------- 图表 ----------
  Widget _buildChart() {
    final days = <({String label, double income, double expense})>[];
    for (var i = 6; i >= 0; i--) {
      final d = DateTime.now().subtract(Duration(days: i));
      final key = dateKey(d);
      final dayTx = _txns.where((t) => t.date == key).toList();
      days.add((
        label: i == 0 ? '今天' : i == 1 ? '昨天' : '${d.month}/${d.day}',
        income: _sumOf(dayTx, 'income'),
        expense: _sumOf(dayTx, 'expense'),
      ));
    }
    final maxV = days.fold<double>(
        1, (m, d) => [m, d.income, d.expense].reduce((a, b) => a > b ? a : b));

    final now = DateTime.now();
    final mk = _monthKey(now);
    final monthTx = _txns.where((t) => t.date.startsWith(mk)).toList();
    final mIncome = _sumOf(monthTx, 'income');
    final mExpense = _sumOf(monthTx, 'expense');

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
                                height: (d.income / maxV * 100).clamp(1.0, 110.0),
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
            _Legend(color: Color(0xFF2E7D32), label: '收入'),
            SizedBox(width: 16),
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
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('本月收入  ${_money(mIncome)}',
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF2E7D32))),
              const SizedBox(height: 4),
              Text('本月支出  ${_money(mExpense)}',
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFFE53935))),
              const SizedBox(height: 4),
              Text('本月结余  ${_money(mIncome - mExpense)}',
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

  // ---------- 分类 / 设置 ----------
  Widget _buildCats() {
    final allCats = [...LedgerService.presetExpense, ...LedgerService.presetIncome];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('预设分类',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in allCats)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.line),
                ),
                child: Text(c, style: const TextStyle(fontSize: 13)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('自定义分类',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_customCats.isEmpty)
              Text('暂无自定义分类',
                  style: TextStyle(fontSize: 12, color: AppColors.textSub))
            else
              for (final c in _customCats)
                InputChip(
                  label: Text(c, style: const TextStyle(fontSize: 13)),
                  onDeleted: () => _removeCustomCat(c),
                  deleteIconColor: AppColors.textSub,
                ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _catCtrl,
                onSubmitted: (v) => _addCustomCat(),
                decoration: const InputDecoration(
                  hintText: '新分类名称',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: _addCustomCat,
              child: const Text('添加'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('起始余额',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _startCtrl,
                keyboardType: TextInputType.number,
                onSubmitted: (v) => _saveStart(),
                decoration: const InputDecoration(hintText: '起始余额', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: _saveStart,
              child: const Text('保存'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('月度预算',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _budgetCtrl,
                keyboardType: TextInputType.number,
                onSubmitted: (v) => _saveBudget(),
                decoration: const InputDecoration(hintText: '预算金额(0 取消)', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: _saveBudget,
              child: const Text('保存'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('超支会在首页余额卡上预警',
            style: TextStyle(fontSize: 11, color: AppColors.textSub)),
      ],
    );
  }

  Future<void> _addCustomCat() async {
    final name = _catCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('请输入分类名称');
      return;
    }
    await _service.addCustomCat(name);
    final cats = await _service.customCats();
    if (!mounted) return;
    _catCtrl.clear();
    setState(() => _customCats = cats);
    _showSnack('已添加分类');
  }

  Future<void> _removeCustomCat(String name) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这个分类?',
      message: '「$name」将不再出现在记一笔的分类里。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _service.removeCustomCat(name);
    final cats = await _service.customCats();
    if (!mounted) return;
    setState(() => _customCats = cats);
    _showSnack('已删除分类');
  }

  Future<void> _saveStart() async {
    final val = double.tryParse(_startCtrl.text);
    if (val == null || val < 0) {
      _showSnack('请输入有效金额');
      return;
    }
    await _service.setStartBalance(val);
    if (!mounted) return;
    setState(() => _start = val);
    _showSnack('起始余额已保存');
  }

  Future<void> _saveBudget() async {
    final val = double.tryParse(_budgetCtrl.text);
    if (val == null || val < 0) {
      _showSnack('请输入有效金额');
      return;
    }
    await _service.setBudget(val);
    if (!mounted) return;
    setState(() => _budget = val);
    _showSnack(val > 0 ? '预算已设置为 ${_money(val)}' : '已取消预算');
  }

  // ---------- 记一笔 ----------
  Future<void> _openEntry() async {
    final result = await showModalBottomSheet<({String type, double amount, String category, String note, String date})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EntrySheet(customCats: _customCats),
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

/// 「记一笔」底部弹层
class _EntrySheet extends StatefulWidget {
  final List<String> customCats;
  const _EntrySheet({required this.customCats});

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  bool _isExpense = true;
  String _category = '餐饮';
  String _date = todayStr();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  List<String> get _cats => _isExpense
      ? [...LedgerService.presetExpense, ...widget.customCats]
      : [...LedgerService.presetIncome, ...widget.customCats];

  void _setType(bool expense) {
    setState(() {
      _isExpense = expense;
      _category = _cats.first;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse('${_date}T00:00:00') ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = dateKey(picked));
  }

  void _submit() {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      showFrostedSnack(context, '请输入有效金额');
      return;
    }
    Navigator.of(context).pop((
      type: _isExpense ? 'expense' : 'income',
      amount: double.parse(amount.toStringAsFixed(2)),
      category: _category,
      note: _noteCtrl.text.trim(),
      date: _date,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              '记一笔',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _typeBtn(true, '支出'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _typeBtn(false, '收入'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText: '金额',
              hintText: '0.00',
              prefixText: '¥ ',
            ),
          ),
          const SizedBox(height: 12),
          const Text('分类',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _cats)
                InkWell(
                  onTap: () => setState(() => _category = c),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 6),
                    decoration: BoxDecoration(
                      color: _category == c
                          ? AppColors.primary
                          : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _category == c
                            ? AppColors.primary
                            : AppColors.line,
                      ),
                    ),
                    child: Text(
                      c,
                      style: TextStyle(
                        fontSize: 13,
                        color: _category == c
                            ? Colors.white
                            : AppColors.textSub,
                        fontWeight:
                            _category == c ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text(_date,
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    hintText: '备注(选填)',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _submit, child: const Text('保存')),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSub,
              side: BorderSide(color: AppColors.line),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _typeBtn(bool expense, String label) {
    final selected = _isExpense == expense;
    return InkWell(
      onTap: () => _setType(expense),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight.withValues(alpha: 0.5) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.primaryDark : AppColors.textSub,
            ),
          ),
        ),
      ),
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
