import 'package:flutter/material.dart';

import '../data/cities.dart';
import '../data/daily_content.dart';
import '../models/student_task.dart';
import '../services/coin_service.dart';
import '../services/note_service.dart';
import '../services/settings_service.dart';
import '../services/task_service.dart';
import '../services/weather_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import '../widgets/app_text_field.dart';
import '../widgets/frosted_snack.dart';
import '../widgets/section_card.dart';
import '../widgets/task_confirm_dialog.dart';
import 'coin_center_page.dart';
import 'diary_page.dart';

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
  bool _savingNote = false; // 灵感速记保存去抖
  List<StudentTask> _tasks = [];
  int _coin = 0;
  int _todayEarned = 0;
  String _nickname = '';
  String _quote = '';
  ({String city, String text, String temp})? _weather;
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
      SettingsService.instance.nickname(),
    ]);
    if (!mounted) return;
    setState(() {
      _tasks = results[0] as List<StudentTask>;
      _coin = results[1] as int;
      _todayEarned = results[2] as int;
      _nickname = results[3] as String;
      _quote = DailyContent.quoteFor(date);
      _english = DailyContent.englishFor(now);
      _dateLabel = monthDayLabel(now);
      _week = weekdayLabel(now);
      _loading = false;
    });
    await _loadWeather();
  }

  /// 天气(心知天气;未配置或失败则隐藏)。
  /// [forceRefresh] 为 true 时绕过缓存(切换城市后需要即时刷新)。
  Future<void> _loadWeather({bool forceRefresh = false}) async {
    if (!await WeatherService.instance.isConfigured()) return;
    try {
      final w = await WeatherService.instance.now(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() => _weather = w);
    } catch (_) {
      // 天气失败不打扰用户
    }
  }

  /// 点击天气条:选择城市(应用内可选)
  Future<void> _pickCity() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _CitySheet(),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    await SettingsService.instance.setWeatherCity(picked);
    await _loadWeather(forceRefresh: true);
    _showSnack('已切换城市');
  }

  Future<void> _reload() async {
    final date = todayStr();
    final tasks = await _taskService.todayTasks(date);
    final coin = await CoinService.instance.balance();
    final earned = await CoinService.instance.earnedToday(date);
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _coin = coin;
      _todayEarned = earned;
    });
    await _loadWeather();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  Future<void> _toggleTask(StudentTask task) async {
    final ok = await confirmTaskToggle(context, task, todayStr());
    if (!ok || !mounted) return;
    final r = await _taskService.toggleTask(task, todayStr());
    await _reload();
    if (r.total != 0) {
      _showSnack(r.total > 0
          ? '金币 +${r.total}${r.bonus > 0 ? '(含全部完成奖励)' : ''}'
          : '已收回金币 ${-r.total}');
    }
  }

  Future<void> _saveNote() async {
    if (_savingNote) return; // 去抖:避免「完成」键与换行回调重复触发
    final text = _noteCtrl.text;
    if (text.trim().isEmpty) {
      _showSnack('写点什么再保存吧~');
      return;
    }
    setState(() => _savingNote = true);
    try {
      await _noteService.addNote(text);
      _noteCtrl.clear();
      await _reload();
      _showSnack('已同步到灵感专区');
    } catch (e) {
      _showSnack('保存失败:$e');
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
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
                  if (_weather != null) ...[
                    const SizedBox(height: 12),
                    _buildWeatherStrip(),
                  ],
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
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMain,
                ),
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
        // 用户头像(点击开侧边栏;暂不支持自定义头像)
        GestureDetector(
          onTap: () => Scaffold.of(context).openDrawer(),
          child: CircleAvatar(
            radius: 19,
            backgroundColor: AppColors.primaryLight,
            child: Text(
              _nickname.isEmpty ? '?' : _nickname.substring(0, 1),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 天气条(点击选择城市;下拉刷新也会更新天气)
  Widget _buildWeatherStrip() {
    final w = _weather!;
    return InkWell(
      onTap: _pickCity,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            const Icon(Icons.wb_sunny_rounded,
                size: 18, color: Color(0xFFFFB300)),
            const SizedBox(width: 8),
            Text(w.city, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 10),
            Text(w.text,
                style:
                    TextStyle(fontSize: 13, color: AppColors.textSub)),
            const Spacer(),
            Text(
              '${w.temp}℃',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: AppColors.textSub),
          ],
        ),
      ),
    );
  }

  Widget _buildCoinCard() {
    return InkWell(
      onTap: _openCoinCenter,
      borderRadius: BorderRadius.circular(18),
      child: Container(
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
        child: Text('查看全部 ›',
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
                style: TextStyle(
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
              backgroundColor: AppColors.line,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          if (total == 0)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('今天还没有任务,去计划中心添加吧~',
                  style: TextStyle(color: AppColors.textSub)),
            )
          else ...[
            // 固定展示至多 3 条;溢出时卡片内部可上滑查看全部。
            if (_tasks.length > 3)
              SizedBox(
                height: 120, // 3 行高度,溢出部分卡片内上滑查看
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [for (final task in _tasks) _taskTile(task)],
                ),
              )
            else
              for (final task in _tasks) _taskTile(task),
            if (done == total)
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('今日任务全部完成,太棒了!',
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
    // 已完成的任务不支持任何操作:整行不可点击。
    return InkWell(
      onTap: task.done ? null : () => _toggleTask(task),
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
      trailing: TextButton.icon(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DiaryPage()),
          );
          await _reload();
        },
        icon: Icon(Icons.menu_book_rounded,
            size: 16, color: AppColors.primaryDark),
        label: Text('写日记',
            style: TextStyle(fontSize: 13, color: AppColors.primaryDark)),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '碎片灵感随手记;想写成篇的心情日记点右上角',
            style: TextStyle(fontSize: 11, color: AppColors.textSub),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AppTextField(
                  controller: _noteCtrl,
                  maxLength: 80,
                  hintText: '记下一句话灵感…',
                  onSubmit: _saveNote,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 52,
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(52, 46),
                    shape: const CircleBorder(),
                  ),
                  onPressed: _savingNote ? null : _saveNote,
                  child: _savingNote
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEnglishCard() {
    return SectionCard(
      title: '每日英语一句',
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
            style: TextStyle(fontSize: 13, color: AppColors.textSub),
          ),
        ],
      ),
    );
  }
}

/// 天气城市选择弹层:常用城市 + 自定义拼音输入
class _CitySheet extends StatefulWidget {
  const _CitySheet();

  @override
  State<_CitySheet> createState() => _CitySheetState();
}

class _CitySheetState extends State<_CitySheet> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              '选择城市',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in commonCities)
                InkWell(
                  onTap: () => Navigator.of(context).pop(c.pinyin),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Text(c.name,
                        style: const TextStyle(fontSize: 13)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '或输入城市拼音(心知天气支持,如 hangzhou)',
            style: TextStyle(fontSize: 12, color: AppColors.textSub),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: const InputDecoration(
                    hintText: '城市拼音',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_ctrl.text.trim()),
                child: const Text('确定'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
