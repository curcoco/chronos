import 'package:flutter/material.dart';

import 'package:chronos/core/services/settings_service.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/utils/dates.dart';
import 'package:chronos/features/coins/services/coin_service.dart';
import 'package:chronos/features/health/pages/screen_app_classify_page.dart';
import 'package:chronos/features/health/services/screen_time_service.dart';
import 'package:chronos/features/health/widgets/health_common.dart';
import 'package:chronos/features/health/widgets/screen_week_trend_sheet.dart';
import 'package:chronos/core/widgets/status_views.dart';

/// 健康「屏幕时间」Tab(防沉迷):
/// 权限门 → 今日娱乐/预算卡 → 娱乐热力图(近一年,GitHub 式)→ 今日娱乐排行 → 分类管理入口。
/// 数据在打开时从系统 UsageStats 同步(无常驻后台),逻辑见 [ScreenTimeService]。
class HealthScreenTimeTab extends StatefulWidget {
  const HealthScreenTimeTab({super.key});

  @override
  State<HealthScreenTimeTab> createState() => _HealthScreenTimeTabState();
}

class _HealthScreenTimeTabState extends State<HealthScreenTimeTab>
    with WidgetsBindingObserver {
  final ScreenTimeService _service = ScreenTimeService.instance;
  final ScrollController _heatCtrl = ScrollController();

  bool _loading = true;
  String? _error; // 同步/查询失败时的提示(渲染 ErrorView + 重试,不再静默空白)
  bool _permitted = false;

  int _todayEnt = 0; // 秒
  int _todayTotal = 0; // 秒
  int _yesterdayEnt = 0; // 秒
  bool _yesterdayHasData = false;
  int _yesterdayReward = 0; // 昨日达标今日已入账的金币数
  int _budget = 120; // 分钟
  Map<String, int> _heat = {}; // 天 → 娱乐分钟
  List<ScreenAppUsage> _top = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _budget = SettingsService.instance.screenBudgetMinutes.value;
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heatCtrl.dispose();
    super.dispose();
  }

  /// 从系统设置页授权返回时自动重新检测(无需手动点「重新检测」)。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_permitted && !_loading) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final permitted = await _service.hasPermission();
      if (!permitted) {
        if (!mounted) return;
        setState(() {
          _permitted = false;
          _loading = false;
        });
        return;
      }
      await _service.syncRecent(days: 8);
      final budget = SettingsService.instance.screenBudgetMinutes.value;
      final now = DateTime.now();
      final today = dateKey(now);
      final yesterday = dateKey(now.subtract(const Duration(days: 1)));
      final results = await Future.wait([
        _service.entertainmentSeconds(today),
        _service.totalSeconds(today),
        _service.entertainmentSeconds(yesterday),
        _service.totalSeconds(yesterday),
        _service.entertainmentMinutesByDay(371),
        _service.topApps(today, category: ScreenTimeService.catEntertainment),
        CoinService.instance.earnedOfType(today, 'screen'),
      ]);
      // 昨日达标才尝试发金币(内部查重 + 每日上限;已发过返回 0)。
      final yesterdayEnt = results[2] as int;
      final yesterdayTotal = results[3] as int;
      var granted = 0;
      if (yesterdayTotal > 0 && yesterdayEnt <= budget * 60) {
        granted = await _service.maybeRewardYesterday(budgetMinutes: budget);
      }
      final earned = results[6] as int;
      if (!mounted) return;
      setState(() {
        _permitted = true;
        _budget = budget;
        _todayEnt = results[0] as int;
        _todayTotal = results[1] as int;
        _yesterdayEnt = yesterdayEnt;
        _yesterdayHasData = yesterdayTotal > 0;
        _yesterdayReward = granted > 0 ? granted : earned;
        _heat = results[4] as Map<String, int>;
        _top = results[5] as List<ScreenAppUsage>;
        _loading = false;
      });
      _scrollHeatToEnd();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '屏幕时间数据加载失败,请重试';
      });
    }
  }

  /// 热力图默认滚到最右(最近的一周)。
  void _scrollHeatToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_heatCtrl.hasClients) {
        _heatCtrl.jumpTo(_heatCtrl.position.maxScrollExtent);
      }
    });
  }

  String _fmt(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return m > 0 ? '$h小时$m分' : '$h小时';
    return '$m分钟';
  }

  String _fmtMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return m > 0 ? '$h小时$m分' : '$h小时';
    return '$m分钟';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return _errorView();
    if (!_permitted) return _permissionGate();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        _todayCard(),
        const SizedBox(height: 12),
        _heatCard(),
        const SizedBox(height: 12),
        _topAppsCard(),
        const SizedBox(height: 12),
        _classifyEntry(),
      ],
    );
  }

  // ---------- 权限门 ----------

  Widget _errorView() {
    return ErrorView(
      message: _error!,
      onRetry: _refresh,
    );
  }

  Widget _permissionGate() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              Icon(Icons.privacy_tip_outlined,
                  size: 40, color: AppColors.primary),
              const SizedBox(height: 12),
              const Text('需要「使用情况访问」权限',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                '屏幕时长由系统自动记录,Chronos 只在打开本页时读取汇总,'
                '不会常驻后台监控。请在系统设置中授予 Chronos「使用情况访问」权限。',
                style: TextStyle(fontSize: 12, color: AppColors.textSub),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _service.openPermissionSettings(),
                      child: const Text('去授权'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _refresh,
                      child: const Text('重新检测'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- 今日卡片 ----------

  Widget _todayCard() {
    final over = _todayEnt > _budget * 60;
    final ratio = (_budget * 60) <= 0
        ? 1.0
        : (_todayEnt / (_budget * 60)).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('今日娱乐',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textSub)),
                  const SizedBox(height: 2),
                  Text(
                    _fmt(_todayEnt),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: over ? const Color(0xFFE53935) : AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('预算',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textSub)),
                  Text(_fmtMinutes(_budget),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMain)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              color: over ? const Color(0xFFE53935) : AppColors.primary,
              backgroundColor: const Color(0xFFE9F0F7),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                over
                    ? '已超出 ${_fmt(_todayEnt - _budget * 60)}'
                    : '还剩 ${_fmt(_budget * 60 - _todayEnt)}',
                style: TextStyle(
                  fontSize: 11,
                  color: over ? const Color(0xFFE53935) : AppColors.textSub,
                ),
              ),
              const Spacer(),
              Text('今日总屏幕 ${_fmt(_todayTotal)}',
                  style:
                      TextStyle(fontSize: 11, color: AppColors.textSub)),
            ],
          ),
          const Divider(height: 24),
          _yesterdayRow(),
          const SizedBox(height: 4),
          _budgetRow(),
        ],
      ),
    );
  }

  /// 昨日结果一行:达标发金币 / 超预算 / 无数据。
  Widget _yesterdayRow() {
    String text;
    Color color = AppColors.textSub;
    if (!_yesterdayHasData) {
      text = '昨日无数据(未授权或未同步)';
    } else if (_yesterdayEnt > _budget * 60) {
      text = '昨日娱乐 ${_fmt(_yesterdayEnt)},超预算';
      color = const Color(0xFFE53935);
    } else if (_yesterdayReward > 0) {
      text = '昨日娱乐 ${_fmt(_yesterdayEnt)} 达标,已奖 $_yesterdayReward 金币';
      color = const Color(0xFF43A047);
    } else {
      text = '昨日娱乐 ${_fmt(_yesterdayEnt)} 达标(今日赚币已达上限)';
    }
    return Row(
      children: [
        Icon(Icons.history_rounded, size: 16, color: AppColors.textSub),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, color: color)),
        ),
      ],
    );
  }

  Widget _budgetRow() {
    return Row(
      children: [
        Icon(Icons.tune_rounded, size: 16, color: AppColors.textSub),
        const SizedBox(width: 6),
        Text('每日娱乐预算',
            style: TextStyle(fontSize: 12, color: AppColors.textSub)),
        const Spacer(),
        Text(_fmtMinutes(_budget),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMain)),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _showBudgetDialog,
          icon: Icon(Icons.edit_outlined, size: 16, color: AppColors.textSub),
        ),
      ],
    );
  }

  Future<void> _showBudgetDialog() async {
    var value = _budget;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('每日娱乐预算'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_fmtMinutes(value),
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark)),
              Slider(
                min: 30,
                max: 300,
                divisions: (300 - 30) ~/ 15,
                value: value.toDouble(),
                onChanged: (v) => setDialog(() => value = v.round()),
              ),
              Text('超预算当日变红,昨日达标发 2 金币',
                  style: TextStyle(fontSize: 11, color: AppColors.textSub)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await SettingsService.instance.setScreenBudgetMinutes(value);
    _refresh();
  }

  // ---------- 热力图 ----------

  /// 热力图五档色阶(与运动日历一致的语言:越多越深)。
  Color _heatColor(int minutes) {
    if (minutes <= 0) return const Color(0xFFE9F0F7);
    if (minutes <= 30) return const Color(0xFFB3E5FC);
    if (minutes <= 60) return const Color(0xFF4FC3F7);
    if (minutes <= 120) return const Color(0xFF29B6F6);
    return const Color(0xFF0288D1);
  }

  Widget _heatCard() {
    const cellSize = 12.0;
    const gap = 2.0;
    const weeks = 53;
    final today = DateTime.now();
    // 本周的周日往前推 52 周 = 网格起点(列=周,行=周日~周六)。
    final thisSunday = today.subtract(Duration(days: today.weekday % 7));
    final start =
        DateTime(thisSunday.year, thisSunday.month, thisSunday.day - 7 * 52);

    Widget cell(DateTime date) {
      final future = date.isAfter(today);
      final minutes = _heat[dateKey(date)] ?? 0;
      return Container(
        width: cellSize,
        height: cellSize,
        margin: const EdgeInsets.only(right: gap, bottom: gap),
        decoration: BoxDecoration(
          color: future ? Colors.transparent : _heatColor(minutes),
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }

    // 统计:近 7 天日均 / 近 30 天达标天数(只统计有记录的天)。
    var sum7 = 0, cnt7 = 0, ok30 = 0;
    for (var i = 0; i < 30; i++) {
      final key = dateKey(today.subtract(Duration(days: i)));
      final m = _heat[key];
      if (m == null) continue;
      if (i < 7) {
        sum7 += m;
        cnt7++;
      }
      if (m <= _budget) ok30++;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('娱乐时长热力图',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('近一年', style: TextStyle(fontSize: 10, color: AppColors.textSub)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧周几标注(只标一/三/五,省空间)
              Column(
                children: [
                  const SizedBox(height: 12), // 让出月份标注行
                  for (var i = 0; i < 7; i++)
                    Container(
                      width: cellSize,
                      height: cellSize,
                      margin: const EdgeInsets.only(bottom: gap),
                      alignment: Alignment.center,
                      child: i == 1 || i == 3 || i == 5
                          ? Text('一二三'[i == 1 ? 0 : (i == 3 ? 1 : 2)],
                              style: TextStyle(
                                  fontSize: 8, color: AppColors.textSub))
                          : null,
                    ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _heatCtrl,
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 月份标注行:该周包含 1 号才标
                      Row(
                        children: [
                          for (var w = 0; w < weeks; w++)
                            Builder(builder: (context) {
                              var label = '';
                              for (var d = 0; d < 7; d++) {
                                final date = DateTime(
                                    start.year, start.month, start.day + w * 7 + d);
                                if (date.day == 1 && !date.isAfter(today)) {
                                  label = '${date.month}月';
                                  break;
                                }
                              }
                              return Container(
                                width: cellSize + gap,
                                height: 12,
                                alignment: Alignment.bottomLeft,
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.visible,
                                  softWrap: false,
                                  style: TextStyle(
                                      fontSize: 8, color: AppColors.textSub),
                                ),
                              );
                            }),
                        ],
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var w = 0; w < weeks; w++)
                            Column(
                              children: [
                                for (var d = 0; d < 7; d++)
                                  cell(DateTime(start.year, start.month,
                                      start.day + w * 7 + d)),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('少', style: TextStyle(fontSize: 9, color: AppColors.textSub)),
              const SizedBox(width: 4),
              for (final c in const [
                Color(0xFFE9F0F7),
                Color(0xFFB3E5FC),
                Color(0xFF4FC3F7),
                Color(0xFF29B6F6),
                Color(0xFF0288D1),
              ]) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: c, borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 2),
              ],
              const SizedBox(width: 2),
              Text('多', style: TextStyle(fontSize: 9, color: AppColors.textSub)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              MetricCard(
                  value: '${cnt7 > 0 ? (sum7 / 7).round() : 0}',
                  label: '近7天日均(分)'),
              const SizedBox(width: 10),
              MetricCard(value: '$ok30', label: '近30天达标'),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 今日娱乐排行 ----------

  Widget _topAppsCard() {
    final maxSeconds = _top.isEmpty
        ? 1
        : _top.map((a) => a.seconds).reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('今日娱乐排行',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => showScreenWeekTrendSheet(context),
                icon: Icon(Icons.bar_chart_rounded,
                    size: 14, color: AppColors.primary),
                label: Text('近7天趋势',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.primary)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_top.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('今天还没有娱乐 app 使用',
                  style: TextStyle(fontSize: 12, color: AppColors.textSub)),
            )
          else
            for (final app in _top) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(app.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Text('${app.minutes}分钟',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSub)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: app.seconds / maxSeconds,
                  minHeight: 4,
                  color: AppColors.primary,
                  backgroundColor: const Color(0xFFE9F0F7),
                ),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  // ---------- 分类管理入口 ----------

  Widget _classifyEntry() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: ListTile(
        leading: Icon(Icons.category_outlined, color: AppColors.primary),
        title: const Text('管理 app 分类',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text('标记哪些是娱乐 / 学习 / 工具',
            style: TextStyle(fontSize: 11, color: AppColors.textSub)),
        trailing:
            Icon(Icons.chevron_right_rounded, color: AppColors.textSub),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ScreenAppClassifyPage()));
          _refresh();
        },
      ),
    );
  }
}
