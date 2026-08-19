import 'package:flutter/material.dart';

import 'package:student_workbench/core/data/cities.dart';
import 'package:student_workbench/core/data/daily_content.dart';
import 'package:student_workbench/features/tasks/models/student_task.dart';
import 'package:student_workbench/routes.dart';
import 'package:student_workbench/features/coins/services/coin_service.dart';
import 'package:student_workbench/features/notes/services/note_service.dart';
import 'package:student_workbench/core/services/settings_service.dart';
import 'package:student_workbench/features/tasks/services/task_service.dart';
import 'package:student_workbench/core/services/weather_service.dart';
import 'package:student_workbench/core/services/app_log.dart';
import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/core/utils/dates.dart';
import 'package:student_workbench/core/widgets/frosted_snack.dart';
import 'package:student_workbench/features/home/widgets/home_coin_card.dart';
import 'package:student_workbench/features/home/widgets/home_english_card.dart';
import 'package:student_workbench/features/home/widgets/home_header.dart';
import 'package:student_workbench/features/home/widgets/home_note_card.dart';
import 'package:student_workbench/features/home/widgets/home_onboarding_card.dart';
import 'package:student_workbench/features/home/widgets/home_today_card.dart';
import 'package:student_workbench/features/home/widgets/home_weather_strip.dart';
import 'package:student_workbench/features/tasks/widgets/task_confirm_dialog.dart';
import 'package:student_workbench/features/settings/pages/api_settings_page.dart';
import 'package:student_workbench/features/coins/pages/coin_center_page.dart';
import 'package:student_workbench/features/diary/pages/diary_page.dart';
import 'package:student_workbench/features/ledger/services/ledger_service.dart';
import 'package:student_workbench/features/ledger/widgets/ledger_entry_sheet.dart';

/// 首页仪表盘:今日任务概览 / 灵感快捷速记 / 每日英语一句 / 金币入口。
/// 各卡片 UI 拆到 widgets/home/ 下的独立组件,本页只负责状态加载与组装。
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
  bool _showOnboarding = false; // 首次引导卡
  String _avatarPath = ''; // 用户头像本地路径
  List<StudentTask> _tasks = [];
  int _coin = 0;
  int _todayEarned = 0;
  String _nickname = '';
  String _quote = '';
  ({String city, String text, String temp})? _weather;
  String _dateLabel = '';
  String _week = '';
  ({String en, String zh}) _english = (en: '', zh: '');

  @override
  void initState() {
    super.initState();
    _init();
    // 侧边栏更换头像后刷新首页头像。
    SettingsService.instance.avatarVersion.addListener(_onAvatarChanged);
  }

  @override
  void dispose() {
    SettingsService.instance.avatarVersion.removeListener(_onAvatarChanged);
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _onAvatarChanged() async {
    final path = await SettingsService.instance.avatarPath();
    if (!mounted) return;
    setState(() => _avatarPath = path);
  }

  Future<void> _init() async {
    final now = DateTime.now();
    final date = todayStr();
    final results = await Future.wait<Object>([
      _taskService.todayTasks(date),
      CoinService.instance.balance(),
      CoinService.instance.earnedToday(date),
      SettingsService.instance.nickname(),
      SettingsService.instance.isOnboardingDone(),
      SettingsService.instance.avatarPath(),
    ]);
    if (!mounted) return;
    setState(() {
      _tasks = results[0] as List<StudentTask>;
      _coin = results[1] as int;
      _todayEarned = results[2] as int;
      _nickname = results[3] as String;
      _showOnboarding = !(results[4] as bool);
      _avatarPath = results[5] as String;
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
      AppLog.instance.e('首页速记保存失败:$e');
      _showSnack('保存失败:$e');
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  Future<void> _openCoinCenter() async {
    await AppRoutes.push(context, const CoinCenterPage());
    await _reload();
  }

  Future<void> _openDiary() async {
    await AppRoutes.push(context, const DiaryPage());
    await _reload();
  }

  Future<void> _openApiSettings() async {
    await AppRoutes.push(context, const ApiSettingsPage());
  }

  /// 首页「记一笔」快捷入口:直接弹记账弹层,保存后打卡。
  Future<void> _quickLedger() async {
    final result = await showModalBottomSheet<
        ({String type, double amount, String category, String note, String date})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => LedgerEntrySheet(customCats: const []),
    );
    if (result == null || !mounted) return;
    await LedgerService().addTxn(
      type: result.type,
      amount: result.amount,
      category: result.category,
      note: result.note,
      date: result.date,
    );
    // 当天记一笔 → 记账打卡(每日一次,受金币上限约束)
    if (result.date == todayStr()) {
      final coin =
          await CoinService.instance.rewardLedgerCheckin(todayStr());
      if (!mounted) return;
      _showSnack(coin > 0 ? '已记一笔,打卡成功,金币 +$coin' : '已记一笔');
    } else {
      if (!mounted) return;
      _showSnack('已记一笔');
    }
    await _reload();
  }

  Future<void> _closeOnboarding() async {
    await SettingsService.instance.setOnboardingDone();
    if (!mounted) return;
    setState(() => _showOnboarding = false);
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
                  HomeHeader(
                    dateLabel: _dateLabel,
                    week: _week,
                    quote: _quote,
                    nickname: _nickname,
                    avatarPath: _avatarPath,
                    onOpenDrawer: () => Scaffold.of(context).openDrawer(),
                  ),
                  if (_showOnboarding) ...[
                    const SizedBox(height: 12),
                    HomeOnboardingCard(
                      onClose: _closeOnboarding,
                      onOpenApiSettings: _openApiSettings,
                    ),
                  ],
                  if (_weather != null) ...[
                    const SizedBox(height: 12),
                    HomeWeatherStrip(
                      city: _weather!.city,
                      text: _weather!.text,
                      temp: _weather!.temp,
                      onTap: _pickCity,
                    ),
                  ],
                  const SizedBox(height: 16),
                  HomeCoinCard(
                    coin: _coin,
                    todayEarned: _todayEarned,
                    onTap: _openCoinCenter,
                  ),
                  const SizedBox(height: 10),
                  // 记账快捷入口:一键直达「记一笔」弹层,无需进记账页
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        foregroundColor: AppColors.primaryDark,
                        side: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _quickLedger,
                      icon:
                          const Icon(Icons.edit_note_rounded, size: 18),
                      label: const Text('记一笔'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  HomeTodayCard(
                    tasks: _tasks,
                    onGoPlan: widget.onGoPlan,
                    onToggleTask: _toggleTask,
                  ),
                  const SizedBox(height: 16),
                  HomeNoteCard(
                    controller: _noteCtrl,
                    saving: _savingNote,
                    onSubmit: _saveNote,
                    onOpenDiary: _openDiary,
                  ),
                  const SizedBox(height: 16),
                  HomeEnglishCard(en: _english.en, zh: _english.zh),
                ],
              ),
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
