import 'package:flutter/material.dart';

import '../data/daily_content.dart';
import '../models/note.dart';
import '../models/student_task.dart';
import '../services/coin_service.dart';
import '../services/note_service.dart';
import '../services/settings_service.dart';
import '../services/task_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import '../widgets/section_card.dart';
import '../widgets/task_confirm_dialog.dart';
import 'coin_center_page.dart';

/// 首页仪表盘:今日任务概览 / 灵感快捷速记 / 每日英语一句 / 金币入口
class HomePage extends StatefulWidget {
  final VoidCallback? onGoPlan;

  const HomePage({super.key, this.onGoPlan});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TaskService _taskService = TaskService();
  final NoteService _noteService = NoteService();
  final TextEditingController _noteCtrl = TextEditingController();

  bool _loading = true;
  List<StudentTask> _tasks = [];
  List<Note> _notes = [];
  int _coin = 0;
  int _todayEarned = 0;
  String _greeting = '嗨,同学';
  String _quote = '';
  String _dateLabel = '';
  String _week = '';
  ({String en, String zh}) _english = (en: '', zh: '');

  int get _doneCount => _tasks.where((t) => t.done).length;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final now = DateTime.now();
    final date = todayStr();
    final results = await Future.wait<Object>([
      _taskService.todayTasks(date),
      CoinService.instance.balance(),
      CoinService.instance.earnedToday(date),
      SettingsService.instance.greeting(),
      _noteService.notes(),
    ]);
    if (!mounted) return;
    setState(() {
      _tasks = results[0] as List<StudentTask>;
      _coin = results[1] as int;
      _todayEarned = results[2] as int;
      _greeting = results[3] as String;
      _notes = (results[4] as List<Note>).take(3).toList();
      _quote = DailyContent.quoteFor(date);
      _english = DailyContent.englishFor(now);
      _dateLabel = monthDayLabel(now);
      _week = weekdayLabel(now);
      _loading = false;
    });
  }

  Future<void> _reload() async {
    final date = todayStr();
    final tasks = await _taskService.todayTasks(date);
    final coin = await CoinService.instance.balance();
    final earned = await CoinService.instance.earnedToday(date);
    final notes = await _noteService.notes();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _coin = coin;
      _todayEarned = earned;
      _notes = notes.take(3).toList();
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleTask(StudentTask task) async {
    final ok = await confirmTaskToggle(context, task, todayStr());
    if (!ok || !mounted) return;
    final r = await _taskService.toggleTask(task, todayStr());
    await _reload();
    if (r.total != 0) {
      _showSnack(r.total > 0
          ? '金币 +${r.total}${r.bonus > 0 ? '(含全部完成奖励 🎉)' : ''}'
          : '已收回金币 ${-r.total}');
    }
  }

  Future<void> _saveNote() async {
    final text = _noteCtrl.text;
    if (text.trim().isEmpty) {
      _showSnack('写点什么再保存吧~');
      return;
    }
    await _noteService.addNote(text);
    _noteCtrl.clear();
    await _reload();
    _showSnack('已同步到灵感专区 ✨');
  }

  Future<void> _openCoinCenter() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CoinCenterPage()),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _buildCoinCard(),
                  const SizedBox(height: 16),
                  _buildTodayCard(),
                  const SizedBox(height: 16),
                  _buildNoteCard(),
                  const SizedBox(height: 16),
                  _buildEnglishCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_dateLabel $_week',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMain,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$_greeting,今天也要加油哦!',
                style: const TextStyle(fontSize: 14, color: AppColors.textSub),
              ),
              const SizedBox(height: 4),
              Text(
                '「$_quote」',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: AppColors.primaryDark.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        // 侧边栏菜单入口(设置 / 版本更新等收纳在抽屉里)
        IconButton(
          onPressed: () => Scaffold.of(context).openDrawer(),
          icon: const Icon(Icons.menu_rounded,
              size: 24, color: AppColors.textSub),
          tooltip: '菜单',
        ),
      ],
    );
  }

  Widget _buildCoinCard() {
    return InkWell(
      onTap: _openCoinCenter,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
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
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.stars_rounded,
                  color: Color(0xFFFFB300), size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '金币余额',
                    style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFFE3F4FF),
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$_coin 枚',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '今日已赚 $_todayEarned/${CoinService.dailyCap}',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFFE3F4FF)),
                ),
                const SizedBox(height: 4),
                Text(
                  '心愿兑换 ›',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayCard() {
    final total = _tasks.length;
    final done = _doneCount;
    final progress = total == 0 ? 0.0 : done / total;
    return SectionCard(
      title: '今日任务',
      trailing: TextButton(
        onPressed: widget.onGoPlan,
        child: const Text('查看全部 ›',
            style: TextStyle(fontSize: 13, color: AppColors.primaryDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '已完成 $done/$total',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFFE3F0FA),
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          if (total == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('今天还没有任务,去计划中心添加吧~',
                  style: TextStyle(color: AppColors.textSub)),
            )
          else ...[
            for (final task in _tasks) _taskTile(task),
            if (done == total)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('🎉 今日任务全部完成,太棒了!',
                    style: TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _taskTile(StudentTask task) {
    return InkWell(
      onTap: () => _toggleTask(task),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(
              task.done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: task.done ? AppColors.primary : const Color(0xFFB9CBD9),
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                task.title,
                style: TextStyle(
                  fontSize: 15,
                  color: task.done ? AppColors.textSub : AppColors.textMain,
                  decoration: task.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: categoryColor(task.category).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                task.category,
                style: TextStyle(
                  fontSize: 11,
                  color: categoryColor(task.category),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteCard() {
    return SectionCard(
      title: '灵感速记',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _noteCtrl,
            maxLength: 80,
            decoration: const InputDecoration(
              hintText: '记下一句话灵感…',
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(120, 42),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onPressed: _saveNote,
              child: const Text('保存'),
            ),
          ),
          if (_notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              '✨ 灵感专区',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSub),
            ),
            const SizedBox(height: 4),
            for (final note in _notes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded,
                        size: 18, color: Color(0xFFFFB300)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        note.content,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    Text(
                      timeLabel(note.createdAt),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSub),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildEnglishCard() {
    return SectionCard(
      title: '📖 每日英语一句',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _english.en,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _english.zh,
            style: const TextStyle(fontSize: 13, color: AppColors.textSub),
          ),
        ],
      ),
    );
  }
}
