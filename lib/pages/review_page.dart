import 'package:flutter/material.dart';

import '../models/review.dart';
import '../services/review_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import '../widgets/frosted_snack.dart';
import '../widgets/section_card.dart';

/// 每日复盘:今日完成进度 / 问题卡点 / 明日方案 + 历史复盘列表
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final ReviewService _service = ReviewService();
  final TextEditingController _doneCtrl = TextEditingController();
  final TextEditingController _problemCtrl = TextEditingController();
  final TextEditingController _planCtrl = TextEditingController();

  bool _loading = true;
  List<Review> _reviews = [];
  int _progress = 100;

  static const List<int> _progressValues = [100, 75, 50, 25, 0];
  static const List<String> _progressLabels = ['全部完成', '大部分', '一半', '少部分', '未开始'];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _doneCtrl.dispose();
    _problemCtrl.dispose();
    _planCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final results =
        await Future.wait([_service.all(), _service.reviewFor(todayStr())]);
    if (!mounted) return;
    final today = results[1] as Review?;
    _doneCtrl.text = today?.done ?? '';
    _problemCtrl.text = today?.problem ?? '';
    _planCtrl.text = today?.plan ?? '';
    setState(() {
      _reviews = results[0] as List<Review>;
      _progress = today?.progress ?? 100;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final done = _doneCtrl.text.trim();
    final problem = _problemCtrl.text.trim();
    final plan = _planCtrl.text.trim();
    if (done.isEmpty && problem.isEmpty && plan.isEmpty) {
      _showSnack('写点什么再保存吧');
      return;
    }
    await _service.save(todayStr(),
        progress: _progress, done: done, problem: problem, plan: plan);
    await _init();
    _showSnack('已保存今日复盘');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('每日复盘')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                SectionCard(
                  title: '今日完成进度',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < _progressValues.length; i++)
                            _progressChip(_progressValues[i], _progressLabels[i]),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _doneCtrl,
                        maxLines: 2,
                        maxLength: 200,
                        decoration: const InputDecoration(
                          hintText: '今天完成了什么…',
                          counterText: '',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: '遇到的问题卡点',
                  child: TextField(
                    controller: _problemCtrl,
                    maxLines: 2,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      hintText: '卡在哪里…',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: '明日优化调整方案',
                  child: TextField(
                    controller: _planCtrl,
                    maxLines: 2,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      hintText: '明天怎么调整…',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _save, child: const Text('保存今日复盘')),
                const SizedBox(height: 20),
                Text(
                  '历史复盘',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain),
                ),
                const SizedBox(height: 10),
                if (_reviews.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('还没有复盘记录',
                          style: TextStyle(color: AppColors.textSub)),
                    ),
                  )
                else
                  for (final r in _reviews) _historyCard(r),
              ],
            ),
    );
  }

  Widget _progressChip(int value, String label) {
    final selected = _progress == value;
    return InkWell(
      onTap: () => setState(() => _progress = value),
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

  Widget _historyCard(Review r) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  r.date,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '完成度 ${r.progress}%',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSub),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: r.progress / 100,
                minHeight: 6,
                backgroundColor: AppColors.line,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 6),
              dense: true,
              title: Text(
                '展开详情',
                style: TextStyle(fontSize: 12, color: AppColors.textSub),
              ),
              children: [
                _detailLine('完成', r.done),
                _detailLine('卡点', r.problem),
                _detailLine('明日方案', r.plan),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSub),
            ),
          ),
          Expanded(
            child: Text(value.isEmpty ? '—' : value,
                style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
