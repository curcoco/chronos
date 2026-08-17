import 'package:flutter/material.dart';

import 'package:student_workbench/features/diary/models/diary_entry.dart';
import 'package:student_workbench/features/diary/services/diary_service.dart';
import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/core/utils/dates.dart';
import 'package:student_workbench/core/widgets/app_text_field.dart';
import 'package:student_workbench/core/widgets/confirm_dialog.dart';
import 'package:student_workbench/core/widgets/frosted_snack.dart';
import 'package:student_workbench/core/widgets/mood_badge.dart';

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
  bool _saving = false;

  static const List<(String, String)> _moodOptions = [
    ('happy', '开心'),
    ('calm', '平静'),
    ('sad', '难过'),
  ];

  @override
  void initState() {
    super.initState();
    _loadList();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadList() async {
    final entries = await _service.all();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final content = _ctrl.text.trim();
    if (content.isEmpty) {
      showFrostedSnack(context, '写点什么再保存吧');
      return;
    }
    setState(() => _saving = true);
    try {
      // 一天可多篇、无上限:每次保存都新增一篇。
      await _service.add(_date, content: content, mood: _mood);
      _ctrl.clear();
      setState(() => _mood = null);
      await _loadList();
      if (!mounted) return;
      showFrostedSnack(context, '日记已保存');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 清空当前草稿(仅清空输入框,不影响已保存的日记)
  Future<void> _clearDraft() async {
    if (_ctrl.text.trim().isEmpty && _mood == null) return;
    final ok = await showConfirmDialog(
      context,
      title: '清空草稿?',
      message: '将清空当前未保存的内容,已保存的日记不受影响。',
      confirmText: '清空',
      destructive: true,
    );
    if (!ok || !mounted) return;
    _ctrl.clear();
    setState(() => _mood = null);
    showFrostedSnack(context, '已清空草稿');
  }

  /// 删除某一篇已保存的日记(支持撤销)
  Future<void> _deleteEntry(DiaryEntry e) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这篇日记?',
      message: '删除后可在提示内撤销。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || e.id == null || !mounted) return;
    final removed = e;
    await _service.deleteById(e.id!);
    await _loadList();
    if (!mounted) return;
    showUndoSnack(
      context,
      '已删除',
      onUndo: () async {
        await _service.restore(removed);
        await _loadList();
      },
    );
  }

  void _openHistory(DiaryEntry e) {
    // 历史仅供查看:弹只读详情,展示完整正文;可从菜单删除。
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
                  if (e.mood != null) ...[
                    MoodBadge(mood: e.mood),
                    const SizedBox(width: 4),
                  ],
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 20, color: Color(0xFFE53935)),
                    tooltip: '删除这篇',
                    onPressed: () {
                      Navigator.of(context).pop();
                      _deleteEntry(e);
                    },
                  ),
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
          child: AppTextField(
            controller: _ctrl,
            minLines: 10,
            maxLines: null,
            maxLength: 5000,
            hintText: '写下此刻的日记…一天可记多篇',
            border: InputBorder.none,
            submitOnEnter: false, // 长文本:回车正常换行
            style: const TextStyle(fontSize: 15, height: 1.7),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('保存日记'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFE53935),
            side: const BorderSide(color: Color(0xFFFFCDD2)),
          ),
          onPressed: _clearDraft,
          child: const Text('清空草稿'),
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
      return _EmptyHint(
        icon: Icons.auto_stories_rounded,
        title: '还没有日记',
        subtitle: '切到「写作」写下第一篇吧~\n一天可以记很多篇',
      );
    }
    // 按日期分组(同一天多篇聚在一起),日期倒序、组内按时间倒序。
    final groups = <String, List<DiaryEntry>>{};
    for (final e in _entries) {
      groups.putIfAbsent(e.date, () => []).add(e);
    }
    final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: dates.length,
      itemBuilder: (context, i) {
        final date = dates[i];
        final items = groups[date]!
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 日期分组标题:某天 · N 篇
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 13, color: AppColors.primaryDark),
                  const SizedBox(width: 6),
                  Text(
                    _dateHeader(date),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark),
                  ),
                  const SizedBox(width: 6),
                  Text('· ${items.length} 篇',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSub)),
                ],
              ),
            ),
            for (final e in items) _historyCard(e),
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }

  /// 「2026年8月15日 · 星期六」分组标题
  String _dateHeader(String date) {
    final d = DateTime.tryParse('${date}T00:00:00');
    if (d == null) return date;
    return '${d.year}年${d.month}月${d.day}日 · ${weekdayLabel(d)}';
  }

  Widget _historyCard(DiaryEntry e) {
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
              Row(
                children: [
                  Text(
                    fullDateTimeLabel(e.updatedAt),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSub),
                  ),
                  const Spacer(),
                  // UX:明确「可点开看全文」的引导
                  Text('查看全文 ›',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 通用空状态提示:图标 + 标题 + 副标题,降低新用户上手门槛。
class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyHint({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.6, color: AppColors.textSub),
            ),
          ],
        ),
      ),
    );
  }
}
