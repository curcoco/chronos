import 'package:flutter/material.dart';

import 'package:student_workbench/core/data/health_content.dart';
import 'package:student_workbench/features/health/services/health_service.dart';
import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/core/widgets/frosted_snack.dart';
import 'package:student_workbench/core/widgets/section_card.dart';
import 'package:student_workbench/features/health/widgets/health_common.dart';

/// 健康「智能食谱」Tab:身体数据 → BMI/TDEE → 3 天食谱生成。
class HealthPlanTab extends StatefulWidget {
  final HealthService service;
  final ({double bmi, String bmiLabel, int tdee})? metrics;

  /// 保存身体数据后由父级刷新 metrics。
  final VoidCallback onChanged;

  const HealthPlanTab({
    super.key,
    required this.service,
    required this.metrics,
    required this.onChanged,
  });

  @override
  State<HealthPlanTab> createState() => _HealthPlanTabState();
}

class _HealthPlanTabState extends State<HealthPlanTab> {
  final TextEditingController _height = TextEditingController();
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _age = TextEditingController();
  final TextEditingController _budget = TextEditingController();
  String _sex = 'm';
  double _activity = 1.2;
  String _mealsHtml = '';

  @override
  void initState() {
    super.initState();
    _initForm();
  }

  Future<void> _initForm() async {
    final body = await widget.service.bodyData();
    if (!mounted || body == null) return;
    setState(() {
      _height.text = body.height.toStringAsFixed(0);
      _weight.text = body.weight.toStringAsFixed(0);
      _age.text = '${body.age}';
      _sex = body.sex;
      _activity = body.activity;
    });
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _age.dispose();
    _budget.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  Future<void> _saveBody() async {
    final h = double.tryParse(_height.text);
    final w = double.tryParse(_weight.text);
    final a = int.tryParse(_age.text);
    if (h == null || w == null || a == null || h <= 0 || w <= 0 || a <= 0) {
      _showSnack('请完整填写身体数据');
      return;
    }
    await widget.service.saveBodyData(
        height: h, weight: w, age: a, sex: _sex, activity: _activity);
    widget.onChanged();
    _showSnack('已计算 BMI 与 TDEE');
  }

  void _genMeals() {
    final budget = double.tryParse(_budget.text);
    if (budget == null || budget <= 0) {
      _showSnack('请输入每日预算');
      return;
    }
    final sb = StringBuffer();
    for (var d = 1; d <= 3; d++) {
      double cost = 0;
      int kcal = 0;
      final rows = HealthContent.mealTags.map((tag) {
        final m = HealthContent.randomMeal();
        cost += m.cost;
        kcal += m.kcal;
        return (tag: tag, m: m);
      }).toList();
      final over = cost > budget;
      sb.write('<day $d>');
      sb.write(rows
          .map((r) => '${r.tag}:${r.m.name}(${r.m.kcal}kcal/${money(r.m.cost)})')
          .join(' | '));
      sb.write(' 合计 ${kcal}kcal/${money(cost)}${over ? '[超预算]' : ''};');
      sb.write('</day>');
    }
    setState(() => _mealsHtml = sb.toString());
    _showSnack('已生成 3 天食谱');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        SectionCard(
          title: '身体数据',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _height,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '身高(cm)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _weight,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '体重(kg)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _age,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '年龄'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _sex = 'm'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor:
                            _sex == 'm' ? AppColors.primaryLight : Colors.white,
                        foregroundColor: _sex == 'm'
                            ? AppColors.primaryDark
                            : AppColors.textSub,
                        side: BorderSide(
                          color: _sex == 'm'
                              ? AppColors.primary
                              : AppColors.line,
                        ),
                      ),
                      child: const Text('男'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _sex = 'f'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor:
                            _sex == 'f' ? AppColors.primaryLight : Colors.white,
                        foregroundColor: _sex == 'f'
                            ? AppColors.primaryDark
                            : AppColors.textSub,
                        side: BorderSide(
                          color: _sex == 'f'
                              ? AppColors.primary
                              : AppColors.line,
                        ),
                      ),
                      child: const Text('女'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<double>(
                initialValue: _activity,
                decoration: const InputDecoration(labelText: '活动量'),
                items: const [
                  DropdownMenuItem(value: 1.2, child: Text('久坐(几乎不运动)')),
                  DropdownMenuItem(value: 1.375, child: Text('轻度(每周1-3次)')),
                  DropdownMenuItem(value: 1.55, child: Text('中度(每周3-5次)')),
                  DropdownMenuItem(value: 1.725, child: Text('高强度(每周6-7次)')),
                ],
                onChanged: (v) => setState(() => _activity = v ?? 1.2),
              ),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: _saveBody, child: const Text('计算 BMI / TDEE')),
            ],
          ),
        ),
        if (widget.metrics != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              MetricCard(
                  value: widget.metrics!.bmi.toStringAsFixed(1),
                  label: 'BMI(${widget.metrics!.bmiLabel})'),
              const SizedBox(width: 10),
              MetricCard(value: '${widget.metrics!.tdee}', label: 'TDEE(kcal/天)'),
            ],
          ),
        ],
        const SizedBox(height: 12),
        SectionCard(
          title: '3 天食谱',
          child: Column(
            children: [
              TextField(
                controller: _budget,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: '每日预算(元)', isDense: true),
              ),
              const SizedBox(height: 10),
              FilledButton(
                  onPressed: _genMeals, child: const Text('生成 3 天食谱')),
              if (_mealsHtml.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _mealsHtml
                      .replaceAll('<day', '\n[第 ')
                      .replaceAll('>', ' 天]')
                      .replaceAll('</day>', ''),
                  style: const TextStyle(fontSize: 12, height: 1.7),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
