import 'package:flutter/material.dart';

import 'package:chronos/core/services/settings_service.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/utils/dates.dart';
import 'package:chronos/features/health/services/screen_time_service.dart';

/// 近 7 天娱乐趋势底部弹层:堆叠柱状图 + 点选某天看当日明细。
/// 详细数据按需点开才展示,不占页面默认视图。
///
/// 画法与记账页「近 7 天收支柱状图」同路:纯 Container 手绘,无图表库。
/// 柱:每天一根,按 app 分段堆叠;一周总量前 3 的 app 固定三种蓝(跨天可比),
/// 其余归「其他」灰。浅红横线 = 每日娱乐预算参考。
Future<void> showScreenWeekTrendSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _WeekTrendSheet(),
  );
}

class _WeekTrendSheet extends StatefulWidget {
  const _WeekTrendSheet();

  @override
  State<_WeekTrendSheet> createState() => _WeekTrendSheetState();
}

class _WeekTrendSheetState extends State<_WeekTrendSheet> {
  /// 一周总量前 3 的 app 固定配色(深→浅蓝)。
  static const List<Color> _segColors = [
    Color(0xFF0288D1),
    Color(0xFF29B6F7),
    Color(0xFF81D4FA),
  ];
  static const Color _otherColor = Color(0xFFCFD8DC);
  static const double _chartHeight = 130;

  final ScreenTimeService _service = ScreenTimeService.instance;

  Map<String, List<ScreenAppUsage>> _data = {};
  int _budget = 120; // 分钟
  String _selected = ''; // yyyy-MM-dd
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selected = dateKey(DateTime.now());
    _load();
  }

  Future<void> _load() async {
    final data = await _service.recentEntertainmentByDay(7);
    if (!mounted) return;
    setState(() {
      _data = data;
      _budget = SettingsService.instance.screenBudgetMinutes.value;
      _loading = false;
    });
  }

  /// 近 7 天日期键(旧 → 新)。
  List<String> get _days => [
        for (var i = 6; i >= 0; i--)
          dateKey(DateTime.now().subtract(Duration(days: i))),
      ];

  /// 一周总量前 3 的包名(按总秒数降序)。
  List<String> get _top3 {
    final totals = <String, int>{};
    for (final apps in _data.values) {
      for (final a in apps) {
        totals[a.packageName] = (totals[a.packageName] ?? 0) + a.seconds;
      }
    }
    final keys = totals.keys.toList()
      ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
    return keys.take(3).toList();
  }

  /// 包名 → 显示名(从数据行收集)。
  Map<String, String> get _pkgLabels => {
        for (final apps in _data.values)
          for (final a in apps) a.packageName: a.label,
      };

  bool _hasOther(List<String> top3) => _data.values
      .any((apps) => apps.any((a) => !top3.contains(a.packageName)));

  Color _colorOf(String pkg, List<String> top3) {
    final i = top3.indexOf(pkg);
    return i >= 0 && i < _segColors.length ? _segColors[i] : _otherColor;
  }

  String _dayLabel(String day) {
    if (day == dateKey(DateTime.now())) return '今天';
    final dt = DateTime.tryParse('${day}T00:00:00');
    if (dt == null) return day;
    return '周${'一二三四五六日'[dt.weekday - 1]}';
  }

  String _fullDayLabel(String day) {
    final dt = DateTime.tryParse('${day}T00:00:00');
    if (dt == null) return day;
    return '${dt.month}月${dt.day}日 ${_dayLabel(day)}';
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
      return const SizedBox(
          height: 280, child: Center(child: CircularProgressIndicator()));
    }
    final days = _days;
    final top3 = _top3;
    final pkgLabels = _pkgLabels;
    final dayTotals = {
      for (final d in days)
        d: (_data[d] ?? const <ScreenAppUsage>[])
            .fold<int>(0, (a, b) => a + b.seconds),
    };
    final budgetSec = _budget * 60;
    // 柱高基准:含预算线(超预算的柱会明显越过红线)。
    final chartMax = [...dayTotals.values, budgetSec, 1]
        .reduce((a, b) => a > b ? a : b);
    final selectedApps = _data[_selected] ?? const <ScreenAppUsage>[];
    final selectedTotal = dayTotals[_selected] ?? 0;
    final hasAnyData = _data.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('近7天娱乐趋势',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('预算 ${_fmtMinutes(_budget)}',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textSub)),
                ],
              ),
              const SizedBox(height: 16),
              if (!hasAnyData) ...[
                Container(
                  height: 130,
                  alignment: Alignment.center,
                  child: Text('本周暂无娱乐记录',
                      style:
                          TextStyle(fontSize: 13, color: AppColors.textSub)),
                ),
                const SizedBox(height: 12),
              ] else ...[
                _chart(days, dayTotals, top3, chartMax, budgetSec),
                const SizedBox(height: 12),
                if (top3.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        for (final pkg in top3)
                          _legend(_colorOf(pkg, top3),
                              pkgLabels[pkg] ?? pkg),
                        if (_hasOther(top3)) _legend(_otherColor, '其他'),
                      ],
                    ),
                  ),
                const Divider(height: 28),
                Text(
                  '${_fullDayLabel(_selected)} · ${_fmt(selectedTotal)}'
                  '${selectedTotal > budgetSec ? ' 超预算' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selectedTotal > budgetSec
                        ? const Color(0xFFE53935)
                        : AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 8),
                if (selectedApps.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('这天没有娱乐 app 使用',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSub)),
                  )
                else
                  for (final app in selectedApps)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _colorOf(app.packageName, top3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(app.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Text(
                            '${app.minutes}分钟 · '
                            '${(app.seconds / (selectedTotal == 0 ? 1 : selectedTotal) * 100).round()}%',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSub),
                          ),
                        ],
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSub)),
      ],
    );
  }

  /// 柱状图:预算参考线 + 7 根可点选的堆叠柱 + 底部周几标签。
  Widget _chart(List<String> days, Map<String, int> dayTotals,
      List<String> top3, int chartMax, int budgetSec) {
    final lineTop = _chartHeight - (budgetSec / chartMax) * _chartHeight;
    return Column(
      children: [
        SizedBox(
          height: _chartHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 预算参考线(浅红)
              Positioned(
                top: lineTop,
                left: 0,
                right: 0,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                        child: Container(
                            height: 1, color: const Color(0xFFEF9A9A))),
                    const SizedBox(width: 4),
                    Text('预算',
                        style: TextStyle(
                            fontSize: 9, color: const Color(0xFFEF9A9A))),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in days)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _selected = d),
                        child: SizedBox(
                          height: _chartHeight,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 5),
                              child: _bar(
                                  d, dayTotals[d] ?? 0, top3, chartMax),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final d in days)
              Expanded(
                child: Center(
                  child: Text(
                    _dayLabel(d),
                    style: TextStyle(
                      fontSize: 10,
                      color: d == _selected
                          ? AppColors.primary
                          : AppColors.textSub,
                      fontWeight:
                          d == _selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// 单根堆叠柱:按 app 分段(底部起为当天最大者);无数据画一条浅灰底。
  Widget _bar(String day, int total, List<String> top3, int chartMax) {
    if (total <= 0) {
      return Container(
        height: 3,
        decoration: BoxDecoration(
          color: const Color(0xFFE9F0F7),
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    final apps = _data[day] ?? const <ScreenAppUsage>[];
    // 段高 = app秒数/chartMax × 图高(和 = 当天总高);按秒数降序 → 最大的在最底。
    final segments = <Widget>[
      for (final a in apps)
        Container(
          height: a.seconds / chartMax * _chartHeight,
          color: _colorOf(a.packageName, top3),
        ),
    ];
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: segments,
      ),
    );
  }
}
