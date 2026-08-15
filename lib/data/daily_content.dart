import 'dart:math';

import '../utils/dates.dart';

/// 每日内容池:夸赞金句 / 每日英语 / 自动生成任务
/// 全部离线内置,按日期确定性选取,同一天结果稳定。
class DailyContent {
  DailyContent._();

  static const List<String> quotes = [
    '今天也要元气满满呀!',
    '你认真学习的样子,真好看。',
    '每一步都算数,加油!',
    '把今天过成自己喜欢的样子。',
    '努力的人,运气都不会太差。',
    '慢慢来,比较快。稳住,我们能赢。',
    '眼里有光,心里有梦,脚下有路。',
    '小坚持,大改变。今天也坚持一点点。',
    '你比你想象中更厉害。',
    '今日份好运,请查收!',
    '不怕慢,就怕站。出发吧!',
    '认真生活的人,自带光芒。',
    '每天进步一点点,未来可期。',
    '心之所向,素履以往。冲鸭!',
  ];

  static const List<({String en, String zh})> english = [
    (en: 'The secret of getting ahead is getting started.', zh: '领先的秘诀,就是开始行动。'),
    (en: 'Small steps every day lead to big results.', zh: '每天一小步,汇成一大步。'),
    (en: 'Knowledge is power.', zh: '知识就是力量。'),
    (en: 'Practice makes perfect.', zh: '熟能生巧。'),
    (en: 'Where there is a will, there is a way.', zh: '有志者事竟成。'),
    (en: 'Never put off till tomorrow what you can do today.', zh: '今日事,今日毕。'),
    (en: 'The best way to predict the future is to create it.', zh: '预测未来最好的方式,就是去创造它。'),
    (en: 'Learning is a treasure that follows its owner everywhere.', zh: '学习是随身携带的财富。'),
    (en: 'A journey of a thousand miles begins with a single step.', zh: '千里之行,始于足下。'),
    (en: 'Success is the sum of small efforts repeated day in and day out.', zh: '成功是日复一日小努力的积累。'),
    (en: 'Stay hungry, stay foolish.', zh: '求知若饥,虚心若愚。'),
    (en: 'Believe you can and you are halfway there.', zh: '相信自己,你就已经成功了一半。'),
    (en: 'The more that you read, the more things you will know.', zh: '读得越多,知道的越多。'),
    (en: 'Genius is one percent inspiration and ninety-nine percent perspiration.', zh: '天才是百分之一的灵感加百分之九十九的汗水。'),
  ];

  static const List<({String title, String category})> autoTasks = [
    (title: '完成今天最难的作业', category: '学习'),
    (title: '复习课堂笔记 20 分钟', category: '学习'),
    (title: '背 10 个英语单词', category: '英语'),
    (title: '阅读课外书 15 页', category: '阅读'),
    (title: '预习明天第一节课', category: '学习'),
    (title: '做 3 道数学题', category: '学习'),
    (title: '整理错题本', category: '学习'),
    (title: '默写一首古诗', category: '语文'),
    (title: '练字一页', category: '学习'),
    (title: '听一集英语听力', category: '英语'),
    (title: '整理书桌和书包', category: '生活'),
    (title: '户外散步 20 分钟', category: '运动'),
    (title: '拉伸放松 10 分钟', category: '运动'),
    (title: '帮忙做一件家务', category: '生活'),
    (title: '喝水打卡 8 杯', category: '生活'),
    (title: '早睡打卡', category: '生活'),
    (title: '给家人打个电话', category: '生活'),
    (title: '写今日复盘一句话', category: '成长'),
  ];

  /// 当日随机夸赞金句(按日期种子,稳定)
  static String quoteFor(String date) =>
      quotes[Random(dateSeed(date)).nextInt(quotes.length)];

  /// 当日英语一句(按天轮换)
  static ({String en, String zh}) englishFor(DateTime now) {
    final idx = daysSinceEpoch(now) % english.length;
    return english[idx];
  }

  /// 按日期随机生成 3 条今日任务
  static List<({String title, String category})> autoTasksFor(String date) {
    final rnd = Random(dateSeed(date));
    final picked = <int>{};
    while (picked.length < 3) {
      picked.add(rnd.nextInt(autoTasks.length));
    }
    return picked.map((i) => autoTasks[i]).toList();
  }

  /// 随机取一条任务(排除已用标题;池子用尽则允许重复)
  static ({String title, String category}) randomAutoTask({
    Set<String> exclude = const {},
  }) {
    final candidates =
        autoTasks.where((t) => !exclude.contains(t.title)).toList();
    final pool = candidates.isEmpty ? autoTasks : candidates;
    return pool[Random().nextInt(pool.length)];
  }
}
