import 'dart:math';

/// 系统随机心愿池(金币中心「随机心愿」用)
class WishContent {
  WishContent._();

  static const List<({String title, int cost})> wishes = [
    (title: '一杯奶茶', cost: 5),
    (title: '一包零食', cost: 8),
    (title: '一份甜品', cost: 10),
    (title: '电影票一张', cost: 12),
    (title: '买一套文具', cost: 12),
    (title: '买一本新书', cost: 15),
    (title: '看一次展览', cost: 20),
    (title: '周末去郊游', cost: 25),
    (title: '和朋友吃一顿大餐', cost: 30),
    (title: '买喜欢的耳机', cost: 40),
    (title: '给自己买束花', cost: 9),
    (title: '换一个新笔袋', cost: 6),
  ];

  /// 随机取一个心愿(排除已有标题;池子用尽返回 null)
  static ({String title, int cost})? randomWish(Set<String> exclude) {
    final pool =
        wishes.where((w) => !exclude.contains(w.title)).toList();
    if (pool.isEmpty) return null;
    return pool[Random().nextInt(pool.length)];
  }
}
