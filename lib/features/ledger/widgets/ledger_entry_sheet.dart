import 'package:flutter/material.dart';

import 'package:chronos/features/ledger/models/ledger_txn.dart';
import 'package:chronos/features/ledger/services/ledger_service.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/utils/dates.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';

/// 「记一笔 / 编辑记录」底部弹层:类型(支出/收入)+ 金额 + 分类 + 备注 + 日期。
/// 返回 `(type, amount, category, note, date)`;取消返回 null。
/// 传 [initial] 时为编辑模式(字段预填,标题显示「编辑记录」)。
class LedgerEntrySheet extends StatefulWidget {
  final List<String> customCats;
  final LedgerTxn? initial;

  const LedgerEntrySheet({super.key, required this.customCats, this.initial});

  @override
  State<LedgerEntrySheet> createState() => _LedgerEntrySheetState();
}

class _LedgerEntrySheetState extends State<LedgerEntrySheet> {
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  bool _isExpense = true;
  String _category = '餐饮';
  String _date = todayStr();

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    if (t != null) {
      _isExpense = t.type == 'expense';
      _category = t.category;
      _date = t.date;
      _amountCtrl.text =
          t.amount == t.amount.roundToDouble() ? t.amount.toStringAsFixed(0) : '$t.amount';
      _noteCtrl.text = t.note;
    }
  }

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
    if (amount > 99999999) {
      showFrostedSnack(context, '金额过大');
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
          Center(
            child: Text(
              _editing ? '编辑记录' : '记一笔',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _typeBtn(true, '支出')),
              const SizedBox(width: 10),
              Expanded(child: _typeBtn(false, '收入')),
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
                      color: _category == c ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _category == c ? AppColors.primary : AppColors.line,
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
                  label: Text(_date, style: const TextStyle(fontSize: 13)),
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
          color: selected
              ? AppColors.primaryLight.withValues(alpha: 0.5)
              : Colors.white,
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
