import 'package:flutter/material.dart';

import 'package:student_workbench/features/ledger/services/ledger_service.dart';
import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/core/widgets/confirm_dialog.dart';
import 'package:student_workbench/core/widgets/frosted_snack.dart';
import 'package:student_workbench/features/ledger/widgets/ledger_format.dart';

/// 记账「分类 / 设置」Tab:预设分类展示、自定义分类增删、起始余额、月度预算。
class LedgerCatsTab extends StatefulWidget {
  final LedgerService service;
  final List<String> customCats;
  final double start;
  final double budget;

  /// 数据变更(增删分类 / 改余额 / 改预算)后通知父级刷新。
  final VoidCallback onChanged;

  const LedgerCatsTab({
    super.key,
    required this.service,
    required this.customCats,
    required this.start,
    required this.budget,
    required this.onChanged,
  });

  @override
  State<LedgerCatsTab> createState() => _LedgerCatsTabState();
}

class _LedgerCatsTabState extends State<LedgerCatsTab> {
  final TextEditingController _catCtrl = TextEditingController();
  late final TextEditingController _startCtrl =
      TextEditingController(text: widget.start.toStringAsFixed(0));
  late final TextEditingController _budgetCtrl =
      TextEditingController(text: widget.budget.toStringAsFixed(0));

  @override
  void dispose() {
    _catCtrl.dispose();
    _startCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  Future<void> _addCustomCat() async {
    final name = _catCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('请输入分类名称');
      return;
    }
    await widget.service.addCustomCat(name);
    _catCtrl.clear();
    widget.onChanged();
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
    await widget.service.removeCustomCat(name);
    widget.onChanged();
    _showSnack('已删除分类');
  }

  Future<void> _saveStart() async {
    final val = double.tryParse(_startCtrl.text);
    if (val == null || val < 0) {
      _showSnack('请输入有效金额');
      return;
    }
    await widget.service.setStartBalance(val);
    widget.onChanged();
    _showSnack('起始余额已保存');
  }

  Future<void> _saveBudget() async {
    final val = double.tryParse(_budgetCtrl.text);
    if (val == null || val < 0) {
      _showSnack('请输入有效金额');
      return;
    }
    await widget.service.setBudget(val);
    widget.onChanged();
    _showSnack(val > 0 ? '预算已设置为 ${money(val)}' : '已取消预算');
  }

  @override
  Widget build(BuildContext context) {
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
            if (widget.customCats.isEmpty)
              Text('暂无自定义分类',
                  style: TextStyle(fontSize: 12, color: AppColors.textSub))
            else
              for (final c in widget.customCats)
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
                decoration:
                    const InputDecoration(hintText: '起始余额', isDense: true),
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
                decoration: const InputDecoration(
                    hintText: '预算金额(0 取消)', isDense: true),
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
}
