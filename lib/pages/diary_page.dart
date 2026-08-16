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

  final String _date = todayStr();
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

  void _openHistory(DiaryEntry e) {
    // 写作页固定当天,历史仅供查看:弹只读详情,不再载入编辑器改写过去。
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      fullDateTimeLabel(e.updatedAt),
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSub),
                    ),
                  ),
                  if (e.mood != null) MoodBadge(mood: e.mood),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                e.content,
                style: TextStyle(
                    fontSize: 15, height: 1.7, color: AppColors.textMain),
              ),
            ],
          ),
        );
      },
    );
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
        // 日记固定为「今天」,不提供选日期(避免回填/篡改历史)。
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.today_rounded,
                  size: 18, color: AppColors.primaryDark),
              const SizedBox(width: 8),
              Text(
                '${cur.year}年${cur.month}月${cur.day}日 · ${weekdayLabel(cur)}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
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
          color: selected ? AppColors.primary : AppColors.card,
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
                  // 正文在上:加粗、字号更大(与日期行的样式互换)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.5),
                        ),
                      ),
                      if (e.mood != null) ...[
                        const SizedBox(width: 8),
                        MoodBadge(mood: e.mood),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 日期在下:24 小时制、精确到分,细体小字
                  Text(
                    fullDateTimeLabel(e.updatedAt),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSub),
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
