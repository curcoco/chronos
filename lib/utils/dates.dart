/// 日期工具:格式化、周几、确定性种子等
String _two(int v) => v.toString().padLeft(2, '0');

/// 今天日期字符串 yyyy-MM-dd
String todayStr() {
  final n = DateTime.now();
  return '${n.year}-${_two(n.month)}-${_two(n.day)}';
}

/// 由日期字符串得到确定性随机种子
int dateSeed(String date) => int.tryParse(date.replaceAll('-', '')) ?? 0;

/// 星期标签,如「星期六」
String weekdayLabel(DateTime d) => '星期${'一二三四五六日'[d.weekday - 1]}';

/// 距 1970-01-01 的天数(用于按天轮换内容)
int daysSinceEpoch(DateTime d) {
  final dt = DateTime(d.year, d.month, d.day);
  return dt.difference(DateTime(1970, 1, 1)).inDays;
}

/// 「8月15日」格式
String monthDayLabel(DateTime d) => '${d.month}月${d.day}日';

/// 时间戳 → 「14:05」
String timeLabel(int ts) {
  final t = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${_two(t.hour)}:${_two(t.minute)}';
}

/// 时间戳 → 「08-15 14:05」
String dateTimeLabel(int ts) {
  final t = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';
}
