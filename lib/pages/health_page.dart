import 'dart:async';

import 'package:flutter/material.dart';

import '../data/health_content.dart';
import '../models/kitchen_item.dart';
import '../models/workout.dart';
import '../services/coin_service.dart';
import '../services/health_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/frosted_snack.dart';
import '../widgets/section_card.dart';

/// 健康管理:厨房秘籍 / 智能食谱 / 运动记录 / 视频跟练 / 运动日历
class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  final HealthService _service = HealthService();
  final TextEditingController _kcName = TextEditingController();
  final TextEditingController _kcCal = TextEditingController();
  final TextEditingController _kcPrice = TextEditingController();
  final TextEditingController _kcLink = TextEditingController();
  final TextEditingController _wkMin = TextEditingController();
  final TextEditingController _bpHeight = TextEditingController();
  final TextEditingController _bpWeight = TextEditingController();
  final TextEditingController _bpAge = TextEditingController();
  final TextEditingController _bpBudget = TextEditingController();

  List<KitchenItem> _kitchen = [];
  List<Workout> _workouts = [];
  String _kcCat = '菜品';
  String _kcNewCat = '菜品';
  String _wkType = '跑步';
  String _sex = 'm';
  double _activity = 1.2;
  ({double bmi, String bmiLabel, int tdee})? _metrics;
  String _mealsHtml = '';
  bool _loading = true;

  // 计时器
  Timer? _timer;
  int _tmrSec = 0;
  bool _tmrOn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [
      _kcName, _kcCal, _kcPrice, _kcLink, _wkMin,
      _bpHeight, _bpWeight, _bpAge, _bpBudget,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _service.kitchenItems(),
      _service.workouts(),
      _service.bodyData(),
    ]);
    if (!mounted) return;
    final body = results[2] as ({double height, double weight, int age, String sex, double activity})?;
    if (body != null) {
      _bpHeight.text = body.height.toStringAsFixed(0);
      _bpWeight.text = body.weight.toStringAsFixed(0);
      _bpAge.text = '${body.age}';
      _sex = body.sex;
      _activity = body.activity;
    }
    setState(() {
      _kitchen = results[0] as List<KitchenItem>;
      _workouts = results[1] as List<Workout>;
      _loading = false;
    });
    _metrics = await _service.calcMetrics();
    if (mounted) setState(() {});
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  String _money(double v) => '¥${v.toStringAsFixed(2)}';

  // ================= 厨房秘籍 =================
  Future<void> _saveKitchen() async {
    final name = _kcName.text.trim();
    if (name.isEmpty) {
      _showSnack('请输入名称');
      return;
    }
    await _service.addKitchenItem(
      cat: _kcNewCat,
      name: name,
      cal: int.tryParse(_kcCal.text) ?? 0,
      price: double.tryParse(_kcPrice.text) ?? 0,
      link: _kcLink.text.trim(),
    );
    _kcName.clear();
    _kcCal.clear();
    _kcPrice.clear();
    _kcLink.clear();
    if (!mounted) return;
    Navigator.of(context).pop();
    final items = await _service.kitchenItems();
    if (!mounted) return;
    setState(() => _kitchen = items);
    _showSnack('已添加');
  }

  Future<void> _deleteKitchen(KitchenItem item) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这条记录?',
      message: '「${item.name}」',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _service.deleteKitchenItem(item.id!);
    final items = await _service.kitchenItems();
    if (!mounted) return;
    setState(() => _kitchen = items);
  }

  // ================= 智能食谱 =================
  Future<void> _saveBody() async {
    final h = double.tryParse(_bpHeight.text);
    final w = double.tryParse(_bpWeight.text);
    final a = int.tryParse(_bpAge.text);
    if (h == null || w == null || a == null || h <= 0 || w <= 0 || a <= 0) {
      _showSnack('请完整填写身体数据');
      return;
    }
    await _service.saveBodyData(
        height: h, weight: w, age: a, sex: _sex, activity: _activity);
    final m = await _service.calcMetrics();
    if (!mounted) return;
    setState(() => _metrics = m);
    _showSnack('已计算 BMI 与 TDEE');
  }

  void _genMeals() {
    final budget = double.tryParse(_bpBudget.text);
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
      sb.write(rows.map((r) => '${r.tag}:${r.m.name}(${r.m.kcal}kcal/${_money(r.m.cost)})').join(' | '));
      sb.write(' 合计 ${kcal}kcal/${_money(cost)}${over ? '[超预算]' : ''};');
      sb.write('</day>');
    }
    setState(() {
      _mealsHtml = sb.toString();
    });
    _showSnack('已生成 3 天食谱');
  }

  // ================= 运动记录 =================
  Future<void> _saveWorkout() async {
    final min = int.tryParse(_wkMin.text);
    if (min == null || min <= 0) {
      _showSnack('请输入时长');
      return;
    }
    await _service.addWorkout(
        type: _wkType, minutes: min, date: todayStr());
    _wkMin.clear();
    if (!mounted) return;
    Navigator.of(context).pop();
    final list = await _service.workouts();
    if (!mounted) return;
    setState(() => _workouts = list);
    _showSnack('已记录');
  }

  Future<void> _workoutCheckin() async {
    final coin = await CoinService.instance.rewardWorkout(todayStr());
    if (!mounted) return;
    _showSnack(coin > 0 ? '运动打卡成功,金币 +$coin' : '今日已打过卡');
  }

  // ================= 视频跟练 =================
  void _tmrTick() {
    setState(() => _tmrSec++);
  }

  void _tmrToggle() {
    setState(() => _tmrOn = !_tmrOn);
    if (_tmrOn) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tmrTick());
    } else {
      _timer?.cancel();
    }
  }

  void _tmrReset() {
    _timer?.cancel();
    setState(() {
      _tmrOn = false;
      _tmrSec = 0;
    });
  }

  Future<void> _videoCheckin() async {
    if (_tmrSec <= 0) {
      _showSnack('先开始计时再打卡吧');
      return;
    }
    final coin = await CoinService.instance.rewardVideo(todayStr());
    if (!mounted) return;
    _showSnack(coin > 0
        ? '跟练完成,金币 +$coin(计时 ${_tmrSec ~/ 60} 分钟)'
        : '今日已打过卡');
    _tmrReset();
  }

  // ================= 构建 =================
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('健康管理'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '厨房秘籍'),
              Tab(text: '智能食谱'),
              Tab(text: '运动记录'),
              Tab(text: '视频跟练'),
              Tab(text: '运动日历'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildKitchen(),
                  _buildPlan(),
                  _buildWorkout(),
                  _buildVideo(),
                  _buildHeat(),
                ],
              ),
      ),
    );
  }

  // ---------- 厨房秘籍 ----------
  Widget _buildKitchen() {
    final list = _kitchen.where((k) => k.cat == _kcCat).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final c in HealthContent.kitchenCats)
              _catChip(c, c == _kcCat, () => setState(() => _kcCat = c)),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.card,
            foregroundColor: AppColors.primaryDark,
            side: BorderSide(color: AppColors.primary),
          ),
          onPressed: _openKitchenSheet,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('添加条目'),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text('这个分类还没有内容',
                  style: TextStyle(color: AppColors.textSub)),
            ),
          )
        else
          for (final k in list) _kitchenTile(k),
      ],
    );
  }

  Widget _kitchenTile(KitchenItem k) {
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
                Text(k.name, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  '${k.cal > 0 ? '约 ${k.cal} kcal' : '无卡路里'}'
                  '${k.link.isNotEmpty ? ' · 视频链接' : ''}',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSub),
                ),
              ],
            ),
          ),
          Text(_money(k.price),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSub)),
          IconButton(
            onPressed: () => _deleteKitchen(k),
            icon: Icon(Icons.close_rounded,
                size: 18, color: AppColors.textSub),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  void _openKitchenSheet() {
    _kcNewCat = _kcCat;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
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
              child: Text('添加条目',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _kcName,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final c in HealthContent.kitchenCats)
                  _catChip(c, c == _kcNewCat,
                      () => setState(() => _kcNewCat = c)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _kcCal,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '卡路里(kcal/份)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _kcPrice,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '价格(元)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _kcLink,
              decoration: const InputDecoration(
                  labelText: '教程视频链接(选填)'),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _saveKitchen, child: const Text('保存')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catChip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : AppColors.textSub,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  // ---------- 智能食谱 ----------
  Widget _buildPlan() {
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
                      controller: _bpHeight,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: '身高(cm)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _bpWeight,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: '体重(kg)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _bpAge,
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
                        backgroundColor: _sex == 'm'
                            ? AppColors.primaryLight
                            : Colors.white,
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
                        backgroundColor: _sex == 'f'
                            ? AppColors.primaryLight
                            : Colors.white,
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
                onChanged: (v) =>
                    setState(() => _activity = v ?? 1.2),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _saveBody, child: const Text('计算 BMI / TDEE')),
            ],
          ),
        ),
        if (_metrics != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              _metric(_metrics!.bmi.toStringAsFixed(1),
                  'BMI(${_metrics!.bmiLabel})'),
              const SizedBox(width: 10),
              _metric('${_metrics!.tdee}', 'TDEE(kcal/天)'),
            ],
          ),
        ],
        const SizedBox(height: 12),
        SectionCard(
          title: '3 天食谱',
          child: Column(
            children: [
              TextField(
                controller: _bpBudget,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: '每日预算(元)', isDense: true),
              ),
              const SizedBox(height: 10),
              FilledButton(onPressed: _genMeals, child: const Text('生成 3 天食谱')),
              if (_mealsHtml.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _mealsHtml.replaceAll('<day', '\n[第 ').replaceAll('>', ' 天]').replaceAll('</day>', ''),
                  style: const TextStyle(fontSize: 12, height: 1.7),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _metric(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSub)),
          ],
        ),
      ),
    );
  }

  // ---------- 运动记录 ----------
  Widget _buildWorkout() {
    final groups = <String, List<Workout>>{};
    final sorted = [..._workouts]..sort((a, b) => b.date.compareTo(a.date));
    for (final w in sorted) {
      groups.putIfAbsent(w.date, () => []).add(w);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.card,
            foregroundColor: AppColors.primaryDark,
            side: BorderSide(color: AppColors.primary),
          ),
          onPressed: _openWorkoutSheet,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('添加运动'),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _workoutCheckin,
            child: const Text('今日运动打卡 +1 金币',
                style: TextStyle(fontSize: 12)),
          ),
        ),
        if (groups.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text('还没有运动记录',
                  style: TextStyle(color: AppColors.textSub)),
            ),
          )
        else
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text(
                _dateLabel(entry.key),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSub),
              ),
            ),
            for (final w in entry.value)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${w.type}  ${w.minutes} 分钟',
                          style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              ),
          ],
      ],
    );
  }

  void _openWorkoutSheet() {
    _wkType = '跑步';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
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
              child: Text('添加运动',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (final t in HealthContent.workoutTypes)
                  _catChip(t, t == _wkType, () => setState(() => _wkType = t)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _wkMin,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: '时长(分钟)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '日期:${todayStr()}',
                    style: TextStyle(fontSize: 13, color: AppColors.textSub),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _saveWorkout, child: const Text('保存')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(String d) {
    final dt = DateTime.tryParse('${d}T00:00:00');
    if (dt == null) return d;
    return '${dt.year}年${dt.month}月${dt.day}日';
  }

  // ---------- 视频跟练 ----------
  Widget _buildVideo() {
    final mm = (_tmrSec ~/ 60).toString().padLeft(2, '0');
    final ss = (_tmrSec % 60).toString().padLeft(2, '0');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryLight, AppColors.primary],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Text(
                '$mm:$ss',
                style: const TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.card,
                      foregroundColor: AppColors.primaryDark,
                    ),
                    onPressed: _tmrToggle,
                    child: Text(_tmrOn ? '暂停' : '开始'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                    ),
                    onPressed: _tmrReset,
                    child: const Text('重置'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                    ),
                    onPressed: _videoCheckin,
                    child: const Text('打卡 +1'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final v in HealthContent.videos)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              children: [
                Icon(Icons.play_circle_outline_rounded,
                    size: 20, color: AppColors.primaryDark),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(v.title,
                      style: const TextStyle(fontSize: 14)),
                ),
                Text('${v.min} 分钟',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSub)),
              ],
            ),
          ),
      ],
    );
  }

  // ---------- 运动日历 ----------
  Widget _buildHeat() {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, 1);
    final days = DateTime(now.year, now.month + 1, 0).day;
    final first = base.weekday % 7; // 0=周日
    final byDay = <String, int>{};
    for (final w in _workouts) {
      byDay[w.date] = (byDay[w.date] ?? 0) + w.minutes;
    }
    int total = 0, count = 0;
    final cells = <Widget>[
      for (final w in ['日', '一', '二', '三', '四', '五', '六'])
        Center(
          child: Text(w,
              style: TextStyle(
                  fontSize: 10, color: AppColors.textSub)),
        ),
      for (var i = 0; i < first; i++) const SizedBox(),
      for (var d = 1; d <= days; d++)
        Builder(builder: (context) {
          final key = dateKey(DateTime(now.year, now.month, d));
          final m = byDay[key] ?? 0;
          if (m > 0) {
            total += m;
            count++;
          }
          final level = m == 0
              ? null
              : m < 20
                  ? const Color(0xFFB3E5FC)
                  : m < 40
                      ? const Color(0xFF4FC3F7)
                      : m < 60
                          ? const Color(0xFF29B6F6)
                          : const Color(0xFF0288D1);
          return Container(
            decoration: BoxDecoration(
              color: level ?? const Color(0xFFE9F0F7),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Center(
              child: Text(
                '$d',
                style: TextStyle(
                  fontSize: 10,
                  color: level == const Color(0xFF0288D1) ||
                          level == const Color(0xFF29B6F6)
                      ? Colors.white
                      : AppColors.textMain,
                ),
              ),
            ),
          );
        }),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
            children: cells,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final c in [
              const Color(0xFFE9F0F7),
              const Color(0xFFB3E5FC),
              const Color(0xFF4FC3F7),
              const Color(0xFF29B6F6),
              const Color(0xFF0288D1),
            ]) ...[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: c, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 4),
            ],
            const SizedBox(width: 8),
            Text('时长越多颜色越深',
                style: TextStyle(fontSize: 10, color: AppColors.textSub)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _metric('$count', '运动天数'),
            const SizedBox(width: 10),
            _metric('$total', '总时长(分)'),
            const SizedBox(width: 10),
            _metric('${count > 0 ? (total / count).round() : 0}', '日均(分)'),
          ],
        ),
      ],
    );
  }
}
