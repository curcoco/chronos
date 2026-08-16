import 'dart:math';

import '../utils/dates.dart';

/// 每日内容池:夸赞金句 / 每日英语 / 自动生成任务
/// 全部离线内置,按日期确定性选取,同一天结果稳定。
class DailyContent {
  DailyContent._();

  static const List<String> quotes = [
    '万物皆有裂痕,那是光照进来的地方。',
    '热爱可抵岁月漫长。',
    '凡是过往,皆为序章。',
    '星光不问赶路人,时光不负有心人。',
    '行到水穷处,坐看云起时。',
    '把日子过成诗,简单而精致。',
    '心有山海,静而无边。',
    '温柔半两,从容一生。',
    '愿你眼里有光,心中有火。',
    '保持热爱,奔赴山海。',
    '生活明朗,万物可爱。',
    '夜色难免黑凉,前行必有曙光。',
    '慢慢来,比较快。稳住,我们能赢。',
    '日子常新,未来可期。',
    '且将新火试新茶,诗酒趁年华。',
    '山高路远,看世界,也找自己。',
    '所有的相遇,都是久别重逢。',
    '愿你千山暮雪,海棠依旧。',
    '心有猛虎,细嗅蔷薇。',
    '此心安处是吾乡。',
    '莫愁前路无知己,天下谁人不识君。',
    '静水流深,智者无言。',
    '一蓑烟雨任平生。',
    '人生如逆旅,我亦是行人。',
    '苔花如米小,也学牡丹开。',
    '守得云开见月明。',
    '心之所向,素履以往。',
    '鲜衣怒马少年时,不负韶华行且知。',
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

  /// 本周计划建议池(title + detail)
  static const List<({String title, String detail})> weekPlans = [
    (title: '完成本周所有学科作业', detail: '按科目分配到每天,避免最后一天赶工'),
    (title: '复习本周课堂笔记', detail: '每天抽 20 分钟回顾当天要点'),
    (title: '背诵 50 个英语单词', detail: '每天 10 个,周末统一复盘'),
    (title: '读完一本课外书的一章', detail: '记录 3 句喜欢的句子'),
    (title: '整理一次错题本', detail: '把本周错题归类、标注原因'),
    (title: '运动三次,每次 30 分钟', detail: '跑步 / 跳绳 / 球类都可'),
    (title: '预习下周新课内容', detail: '列出不懂的问题,课上重点听'),
    (title: '完成一次学习复盘', detail: '总结做得好的与要改进的'),
    (title: '练字 15 分钟 × 5 天', detail: '保持字迹工整'),
    (title: '规律作息,每天 23 点前睡', detail: '睡前不玩手机'),
    (title: '帮家里做三次家务', detail: '洗碗 / 扫地 / 整理房间'),
    (title: '每天喝够 8 杯水', detail: '用打卡提醒自己'),
  ];

  /// 长期目标建议池(title + detail)
  static const List<({String title, String detail})> longTermGoals = [
    (title: '养成每天阅读的习惯', detail: '目标每天至少 20 分钟,坚持一学期'),
    (title: '英语词汇量提升到 3000', detail: '每天积累,配合听力与阅读'),
    (title: '数学成绩提升一个档次', detail: '主攻薄弱章节,建立错题体系'),
    (title: '坚持锻炼身体', detail: '每周运动 3 次以上,增强体质'),
    (title: '学会一项新技能', detail: '如乐器 / 编程 / 绘画,循序渐进'),
    (title: '改掉拖延习惯', detail: '用任务清单和番茄钟管理时间'),
    (title: '培养规律作息', detail: '早睡早起,保证充足睡眠'),
    (title: '读完 10 本好书', detail: '涵盖不同题材,做读书笔记'),
    (title: '提升专注力', detail: '减少分心,单次专注时长逐步拉长'),
    (title: '建立健康的理财意识', detail: '记录零花钱收支,学会储蓄'),
  ];

  /// 随机取一条本周计划(可排除已有标题)
  static ({String title, String detail}) randomWeekPlan({
    Set<String> exclude = const {},
  }) {
    final candidates =
        weekPlans.where((t) => !exclude.contains(t.title)).toList();
    final pool = candidates.isEmpty ? weekPlans : candidates;
    return pool[Random().nextInt(pool.length)];
  }

  /// 随机取一条长期目标(可排除已有标题)
  static ({String title, String detail}) randomLongTermGoal({
    Set<String> exclude = const {},
  }) {
    final candidates =
        longTermGoals.where((t) => !exclude.contains(t.title)).toList();
    final pool = candidates.isEmpty ? longTermGoals : candidates;
    return pool[Random().nextInt(pool.length)];
  }
}
