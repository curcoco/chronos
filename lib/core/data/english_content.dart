import 'dart:math';

import 'package:chronos/core/data/content_store.dart';
import 'package:chronos/core/utils/dates.dart';

/// 英文积累内容池:每日单词 / 每日阅读 / 每日写作提示(全部离线内置,按日期确定性选取)
class EnglishContent {
  EnglishContent._();

  static const List<({String w, String p, String m})> words = [
    (w: 'persevere', p: '/ˌpɜːrsəˈvɪr/', m: 'v. 坚持不懈'),
    (w: 'curiosity', p: '/ˌkjʊriˈɑːsəti/', m: 'n. 好奇心'),
    (w: 'insight', p: '/ˈɪnsaɪt/', m: 'n. 洞察力'),
    (w: 'momentum', p: '/moʊˈmentəm/', m: 'n. 势头'),
    (w: 'discipline', p: '/ˈdɪsəplɪn/', m: 'n. 自律'),
    (w: 'resilient', p: '/rɪˈzɪliənt/', m: 'adj. 有韧性的'),
    (w: 'ambiguous', p: '/æmˈbɪɡjuəs/', m: 'adj. 模棱两可的'),
    (w: 'dedicate', p: '/ˈdedɪkeɪt/', m: 'v. 奉献,致力于'),
    (w: 'consistent', p: '/kənˈsɪstənt/', m: 'adj. 始终如一的'),
    (w: 'efficient', p: '/ɪˈfɪʃnt/', m: 'adj. 高效的'),
    (w: 'obstacle', p: '/ˈɑːbstəkl/', m: 'n. 障碍'),
    (w: 'accumulate', p: '/əˈkjuːmjəleɪt/', m: 'v. 积累'),
    (w: 'priority', p: '/praɪˈɔːrəti/', m: 'n. 优先事项'),
    (w: 'reflect', p: '/rɪˈflekt/', m: 'v. 反思;反射'),
    (w: 'genuine', p: '/ˈdʒenjuɪn/', m: 'adj. 真诚的'),
    (w: 'flexible', p: '/ˈfleksəbl/', m: 'adj. 灵活的'),
    (w: 'gratitude', p: '/ˈɡrætɪtuːd/', m: 'n. 感恩'),
    (w: 'motivate', p: '/ˈmoʊtɪveɪt/', m: 'v. 激励'),
    (w: 'optimistic', p: '/ˌɑːptɪˈmɪstɪk/', m: 'adj. 乐观的'),
    (w: 'practical', p: '/ˈpræktɪkl/', m: 'adj. 实际的,实用的'),
    (w: 'review', p: '/rɪˈvjuː/', m: 'v./n. 复习;回顾'),
    (w: 'schedule', p: '/ˈskedʒuːl/', m: 'n. 日程表'),
    (w: 'summary', p: '/ˈsʌməri/', m: 'n. 总结'),
    (w: 'approach', p: '/əˈproʊtʃ/', m: 'n. 方法;接近'),
    (w: 'balance', p: '/ˈbæləns/', m: 'n. 平衡'),
  ];

  static const List<({String title, String text})> readings = [
    (title: 'A Small Step, Every Day', text: 'Progress is rarely dramatic. It is the sum of small, consistent efforts. Open the book, write one line, walk one more minute — and let the routine carry you forward.'),
    (title: 'The Power of Focus', text: 'In a world full of distractions, focus is a superpower. Decide what matters, protect your attention, and give that one thing your full energy.'),
    (title: 'Learning Never Stops', text: 'School ends, but learning does not. Every conversation, every mistake, every quiet hour of reading adds a little more to who you are becoming.'),
    (title: 'Rest Is Part of Work', text: 'Pushing hard matters, but so does resting. Sleep and breaks are not wasted time — they are how your mind turns practice into progress.'),
    (title: 'Small Habits, Big Change', text: 'You do not rise to the level of your goals; you fall to the level of your systems. Build tiny habits and let them compound over time.'),
    (title: 'Kindness Is Strength', text: 'Being kind is not being weak. It takes courage to understand others, patience to listen, and strength to help without expecting anything back.'),
    (title: 'Start Before You Feel Ready', text: 'Confidence comes after action, not before it. Take the first imperfect step, and let momentum teach you what you still need to learn.'),
    (title: 'The Value of a Plan', text: 'A clear plan turns a vague wish into a path. Write it down, break it into steps, and check off the first one today.'),
  ];

  static const List<String> writings = [
    '用一句话描述「今天最想改变的一个小习惯」,并写下第一步。',
    '假如你给一年后的自己写一封信,你会写什么?',
    '描述一个让你感到平静的场景,试着写出细节。',
    '用 50 词总结今天最有收获的一件事。',
    '写下你最近学到的、最想分享给别人的一个知识点。',
    '如果你今天只能做三件事,你会选哪三件?为什么?',
    '给「坚持」下一个你自己的定义,并举一个例子。',
    '想象你最好的朋友今天有点沮丧,写一段鼓励的话。',
  ];

  /// 按日期确定性取 5 个单词
  static List<({String w, String p, String m})> wordsFor(String date) {
    final pool = ContentStore.words ?? words;
    final rnd = Random(dateSeed(date));
    final picked = <int>{};
    while (picked.length < 5) {
      picked.add(rnd.nextInt(pool.length));
    }
    return picked.map((i) => pool[i]).toList();
  }

  /// 按日期取一篇阅读
  static ({String title, String text}) readingFor(String date) {
    final pool = ContentStore.readings ?? readings;
    return pool[Random(dateSeed(date)).nextInt(pool.length)];
  }

  /// 按日期取一个写作提示
  static String writingFor(String date) {
    final pool = ContentStore.writings ?? writings;
    return pool[Random(dateSeed(date)).nextInt(pool.length)];
  }
}
