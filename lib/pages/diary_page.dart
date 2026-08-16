import 'package:flutter/material.dart';

import '../models/diary_entry.dart';
import '../services/diary_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import '../widgets/frosted_snack.dart';
import '../widgets/mood_badge.dart';

/// 日记:按天一篇的长文本写作,可切换日期、可查看/回改历史
class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage>
    with SingleTickerProviderStateMixin {
  final DiaryService _service = DiaryService.instance;
  final TextEditingController _ctrl = TextEditingController();
  late final TabController _tabs = TabController(length: 2, vsync: this);

  String _date = todayStr();
  String? _mood;
  List<DiaryEntry> _entries = [];
  bool _loading = true;
  bool _saved = false;

  static const List<(String, String)> _moodOptions = [
    ('happy', '开心'),
    ('calm', '平静'),
    ('sad', '难过'),
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadList();
    await _loadCurrent();
  }

  Future<void> _loadList() async {
    final entries = await _service.all();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _loadCurrent() async {
    final e = await _service.diaryFor(_date);
    if (!mounted) return;
    _ctrl.text = e?.content ?? '';
    setState(() {
      _mood = e?.mood;
      _saved = e != null;
    });
  }

  Future<void> _save() async {
    final content = _ctrl.text.trim();
    if (content.isEmpty) {
      showFrostedSnack(context, '写点什么再保存吧');
      return;
    }
    await _service.save(_date, content: content, mood: _mood);
    setState(() => _saved = true);
    await _loadList();
    if (!mounted) return;
    showFrostedSnack(context, '日记已保存');
  }

  Future<void> _delete() async {
    if (!_saved) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这一天的日记?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE53935)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _service.delete(_date);
    _ctrl.clear();
    setState(() {
      _mood = null;
      _saved = false;
    });
    await _loadList();
    if (!mounted) return;
    showFrostedSnack(context, '已删除');
  }

  void _moveDate(int days) {
    final now = DateTime.now();
    final current = DateTime.tryParse('${_date}T00:00:00') ?? now;
    final target = current.add(Duration(days: days));
    if (target.isAfter(now)) return; // 不允许未来
    if (target.year < 2020) return;
    setState(() => _date = dateKey(target));
    _loadCurrent();
  }

  void _openHistory(DiaryEntry e) {
    setState(() => _date = e.date);
    _loadCurrent();
    _tabs.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cur = DateTime.tryParse('${_date}T00:00:00') ?? now;
    return Scaffold(
      appBar: AppBar(
        title: const Text('日记'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: '写作'), Tab(text: '历史')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildEditor(cur),
                _buildHistory(),
              ],
            ),
    );
  }

  // ---------- 写作 ----------
  Widget _buildEditor(DateTime cur) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => _moveDate(-1),
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: '前一天',
            ),
            Expanded(
              child: Text(
                '${cur.year}年${cur.month}月${cur.day}日',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              onPressed: () => _moveDate(1),
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: '后一天',
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            _moodChip(null, '无'),
            for (final m in _moodOptions) _moodChip(m.$1, m.$2),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: TextField(
            controller: _ctrl,
            minLines: 10,
            maxLines: null,
            maxLength: 5000,
            decoration: const InputDecoration(
              hintText: '写下今天的长篇日记…',
              border: InputBorder.none,
              counterText: '',
            ),
            style: const TextStyle(fontSize: 15, height: 1.7),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(onPressed: _save, child: const Text('保存日记')),
        const SizedBox(height: 8),
        if (_saved)
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFE53935),
              side: const BorderSide(color: Color(0xFFFFCDD2)),
            ),
            onPressed: _delete,
            child: const Text('删除这一天'),
          ),
      ],
    );
  }

  Widget _moodChip(String? value, String label) {
    final selected = _mood == value;
    return InkWell(
      onTap: () => setState(() => _mood = value),
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
          ),
        ),
      ),
    );
  }

  // ---------- 历史 ----------
  Widget _buildHistory() {
    if (_entries.isEmpty) {
      return Center(
        child: Text('还没有日记,去「写作」写一篇吧~',
            style: TextStyle(color: AppColors.textSub)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: _entries.length,
      itemBuilder: (context, i) {
        final e = _entries[i];
        final dt = DateTime.tryParse('${e.date}T00:00:00');
        final title = dt == null
            ? e.date
            : '${dt.year}年${dt.month}月${dt.day}日';
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _openHistory(e),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (e.mood != null) MoodBadge(mood: e.mood),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    e.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSub, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
